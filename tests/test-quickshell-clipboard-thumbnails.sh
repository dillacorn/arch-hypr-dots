#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${ROOT}/config/hypr/scripts/quickshell_clipboard.sh"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "${TMPD}/bin" "${TMPD}/runtime"

cat >"${TMPD}/bin/cliphist" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list)
    printf '300\tnewest text entry\n'
    printf '299\t[[ binary data 8 KiB image/png ]]\n'
    ;;
  decode)
    printf 'decode\n' >>"$AWTARCHY_CLIPBOARD_TEST_LOG"
    printf 'fake image bytes'
    ;;
  *)
    exit 2
    ;;
esac
EOF

cat >"${TMPD}/bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
EOF

cat >"${TMPD}/bin/magick" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'magick\n' >>"$AWTARCHY_CLIPBOARD_TEST_LOG"
printf 'magick-args:%s\n' "$*" >>"$AWTARCHY_CLIPBOARD_TEST_LOG"
if [[ ${AWTARCHY_MAGICK_HANG:-0} == 1 ]]; then
  sleep 5
fi
output="${!#}"
output="${output#png:}"
printf 'fake thumbnail' >"$output"
EOF

chmod 0755 \
  "${TMPD}/bin/cliphist" \
  "${TMPD}/bin/wl-copy" \
  "${TMPD}/bin/magick"

log="${TMPD}/operations.log"
touch "$log"

common_env=(
  PATH="${TMPD}/bin:${PATH}"
  XDG_RUNTIME_DIR="${TMPD}/runtime"
  AWTARCHY_CLIPBOARD_TEST_LOG="$log"
  LIST_LIMIT=10
)

list_output="$(env "${common_env[@]}" "$BACKEND" list)"
[[ "$(wc -l <<<"$list_output")" -eq 2 ]] \
  || fail 'clipboard metadata list did not contain both fixture entries'
jq -s -e \
  '.[1].binary == true and .[1].thumb == ""' \
  <<<"$list_output" >/dev/null \
  || fail 'binary clipboard metadata was not emitted without a thumbnail'
[[ ! -s "$log" ]] \
  || fail 'listing clipboard metadata eagerly decoded an image thumbnail'

first_path="$(env "${common_env[@]}" "$BACKEND" thumb 1)"
[[ -n "$first_path" && -s "$first_path" ]] \
  || fail 'lazy thumbnail request did not produce a readable cached image'

second_path="$(env "${common_env[@]}" "$BACKEND" thumb 1)"
[[ "$second_path" == "$first_path" ]] \
  || fail 'repeated thumbnail request did not reuse the cached path'
[[ "$(grep -c '^decode$' "$log")" -eq 1 ]] \
  || fail 'cached thumbnail was decoded more than once'
[[ "$(grep -c '^magick$' "$log")" -eq 1 ]] \
  || fail 'cached thumbnail was rendered more than once'

# A thumbnail is untrusted decoded clipboard media: bound frame count, memory, mapped cache, disk cache, and wall time.
grep -Eq '^magick-args:.*-limit memory 256MiB.*-limit map 256MiB.*-limit disk 512MiB.*\.tmp\[0\].*png:' "$log" \
  || fail 'ImageMagick thumbnail render is not limited to the first frame with bounded memory/map/disk resources'
grep -Fq 'THUMB_TIMEOUT="${THUMB_TIMEOUT:-2s}"' "$BACKEND" \
  || fail 'clipboard thumbnail rendering has no dedicated timeout'
grep -Fq 'timeout --kill-after=1s "$THUMB_TIMEOUT" magick' "$BACKEND" \
  || fail 'ImageMagick thumbnail rendering is not time bounded'

rm -f -- "$first_path"
set +e
AWTARCHY_MAGICK_HANG=1 THUMB_TIMEOUT=0.05s \
  timeout 1 env "${common_env[@]}" "$BACKEND" thumb 1 >/dev/null 2>&1
hang_rc=$?
set -e
[[ "$hang_rc" -ne 124 ]] \
  || fail 'a hung ImageMagick thumbnail render escaped the backend timeout'

if env "${common_env[@]}" "$BACKEND" thumb 0 >/dev/null 2>&1; then
  fail 'text clipboard entry unexpectedly produced an image thumbnail'
fi

printf '%s\n' 'PASS: clipboard thumbnails load lazily, reuse the cache, and bound ImageMagick work.'
