#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
POSITION="${ROOT}/config/hypr/scripts/quickshell_flyout_position.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$POSITION" ]] || fail 'battery flyout positioning helper is missing or not executable'
command -v jq >/dev/null 2>&1 || fail 'jq is required'

mkdir -p "$TMP/bin" "$TMP/cache/awtarchy" "$TMP/runtime"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_RUNTIME_DIR="$TMP/runtime"
export AWTARCHY_TEST_HYPR_LOG="$TMP/hypr-eval.log"

cat >"$TMP/bin/hyprctl" <<'FAKE_HYPRCTL'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  clients)
    [[ ${2:-} == -j ]] || exit 64
    printf '%s\n' '[{"title":"Awtarchy Battery","address":"0xabc","at":[0,0],"size":[560,560]}]'
    ;;
  monitors)
    [[ ${2:-} == -j ]] || exit 64
    printf '%s\n' '[{"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0}]'
    ;;
  eval)
    printf '%s\n' "${2:-}" >"${AWTARCHY_TEST_HYPR_LOG:?}"
    ;;
  *) exit 64 ;;
esac
FAKE_HYPRCTL
chmod 0755 "$TMP/bin/hyprctl"
export PATH="$TMP/bin:$PATH"

assert_position() {
  local placement="$1" expected_x="$2" expected_y="$3"
  : >"$AWTARCHY_TEST_HYPR_LOG"
  "$POSITION" battery eDP-1 "$placement" spawn
  grep -Fq -- "hl.dispatch(hl.dsp.window.move({ x = ${expected_x}, y = ${expected_y}, relative = false" \
    "$AWTARCHY_TEST_HYPR_LOG" \
    || fail "Battery ${placement} placement did not resolve to ${expected_x},${expected_y}"
  grep -Fq -- 'hl.dispatch(hl.dsp.window.resize({ x = 560, y = 560, relative = false' \
    "$AWTARCHY_TEST_HYPR_LOG" \
    || fail "Battery ${placement} spawn did not apply default 560x560 geometry"
}

assert_position top 1352 28
assert_position bottom 1352 492
assert_position left 36 512
assert_position right 1324 512
assert_position center 680 260

: >"$AWTARCHY_TEST_HYPR_LOG"
"$POSITION" battery eDP-1 top resize 700 500
grep -Fq -- 'hl.dispatch(hl.dsp.window.resize({ x = 700, y = 500, relative = false' \
  "$AWTARCHY_TEST_HYPR_LOG" || fail 'Battery explicit resize did not use 700x500'
grep -Fq -- 'hl.dispatch(hl.dsp.window.move({ x = 1212, y = 28, relative = false' \
  "$AWTARCHY_TEST_HYPR_LOG" || fail 'Battery resized top placement did not stay corner-aligned'

printf '%s\n' 'Battery flyout geometry regression test passed.'
