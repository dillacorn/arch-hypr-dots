#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${ROOT}/config/hypr/scripts/quickshell_clipboard.sh"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"
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

# ImageMagick can spill pixel-cache work from RAM/map into disk, so all three resource classes are bounded.
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

final_hash="$(sha256sum "$BACKEND" | awk '{print $1}')"
grep -Fq "${final_hash}"$'\t''.config/hypr/scripts/quickshell_clipboard.sh' "$HISTORY" \
  || fail 'clipboard hardening final hash is missing from managed history'

grep -Fq 'repair_v355_clipboard_thumbnail_repo()' "$RUNTIME" \
  || fail 'runtime has no v3.5.5 clipboard thumbnail delivery repair'
grep -Fq '[[ "$tag" == "v3.5.5" ]] || return 0' "$RUNTIME" \
  || fail 'v3.5.5 clipboard thumbnail repair is not tag scoped'
grep -Fq 'repair_v355_clipboard_thumbnail_repo "$repo_dir" "$tag"' "$RUNTIME" \
  || fail 'stable update path does not repair the v3.5.5 clipboard source'
repair_line="$(grep -nF 'repair_v355_clipboard_thumbnail_repo "$repo_dir" "$tag"' "$RUNTIME" | tail -n1 | cut -d: -f1)"
build_line="$(grep -nF 'build_target_home "$repo_dir" "$target_home"' "$RUNTIME" | tail -n1 | cut -d: -f1)"
[[ "$repair_line" =~ ^[0-9]+$ && "$build_line" =~ ^[0-9]+$ && "$repair_line" -lt "$build_line" ]] \
  || fail 'v3.5.5 clipboard repair does not run before the stable target is built'

fixture_repo="${TMPD}/v355-repo"
fixture_backend="${fixture_repo}/config/hypr/scripts/quickshell_clipboard.sh"
fixture_history="${fixture_repo}/local/share/awtarchy/quickshell-managed-history.sha256"
mkdir -p -- "$(dirname -- "$fixture_backend")" "$(dirname -- "$fixture_history")"
cat >"$fixture_backend" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
THUMB_SIZE="${THUMB_SIZE:-512}"
DECODE_TIMEOUT="${DECODE_TIMEOUT:-0.70s}"
LIST_PRODUCER_PID=""
make_thumb() {
    local raw="$1" png tmp
    if timeout "$DECODE_TIMEOUT" cliphist decode <<<"$raw" >"$tmp" 2>/dev/null \
        && [[ -s "$tmp" ]] \
        && magick "$tmp" -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}>" "png:$png" >/dev/null 2>&1; then
        :
    fi
}
EOF
printf '%s\n' 'existing-history-entry' >"$fixture_history"

repair_runner="${TMPD}/repair-runner.sh"
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
  printf '%s\n' 'die() { printf "FAIL: %s\\n" "$*" >&2; exit 1; }' 'log() { :; }'
  sed -n '/^repair_v355_clipboard_thumbnail_repo() {/,/^}/p' "$RUNTIME"
  printf '%s\n' 'repair_v355_clipboard_thumbnail_repo "$1" "$2"'
} >"$repair_runner"
chmod 0755 "$repair_runner"
"$repair_runner" "$fixture_repo" v3.5.5

grep -Fq 'THUMB_TIMEOUT="${THUMB_TIMEOUT:-2s}"' "$fixture_backend" \
  || fail 'v3.5.5 repair did not add the thumbnail timeout to release source'
grep -Fq -- '-limit memory 256MiB -limit map 256MiB -limit disk 512MiB' "$fixture_backend" \
  || fail 'v3.5.5 repair did not add ImageMagick resource bounds'
grep -Fq '"${tmp}[0]" -thumbnail' "$fixture_backend" \
  || fail 'v3.5.5 repair did not limit release rendering to the first frame'
grep -Fq $'ab73a9056ecd3cd692112cf218464c9abe1de5792b0fdaad1f6401b063a0d967\t.config/hypr/scripts/quickshell_clipboard.sh' "$fixture_history" \
  || fail 'v3.5.5 repair did not add the final clipboard hash to release managed history'

printf '%s\n' 'PASS: clipboard thumbnails load lazily, reuse the cache, bound ImageMagick work, and deliver safely to v3.5.5.'
