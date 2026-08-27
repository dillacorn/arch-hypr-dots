#!/usr/bin/env bash
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

if env "${common_env[@]}" "$BACKEND" thumb 0 >/dev/null 2>&1; then
  fail 'text clipboard entry unexpectedly produced an image thumbnail'
fi

printf '%s\n' 'PASS: clipboard thumbnails load lazily and reuse the cache.'
