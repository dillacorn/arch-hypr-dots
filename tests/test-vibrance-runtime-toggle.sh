#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/config/hypr/scripts/vibrance_shader.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

HOME_DIR="$TMP/home"
BIN_DIR="$TMP/bin"
LUA="$HOME_DIR/.config/hypr/hyprland.lua"
SHADER="$HOME_DIR/.config/hypr/shaders/vibrance"
LOG="$TMP/hyprctl.log"
mkdir -p -- "$HOME_DIR/.config/hypr/shaders" "$BIN_DIR"

cat >"$LUA" <<EOF
hl.config({ decoration = { screen_shader = "$SHADER" } })
EOF
cat >"$SHADER" <<'EOF'
#define VIBRANCE 0.45
void main() {}
EOF

cat >"$BIN_DIR/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
{
    printf 'argc=%d' "$#"
    for arg in "$@"; do
        printf '|%s' "$arg"
    done
    printf '\n'
} >>"$HYPRCTL_TEST_LOG"
EOF
chmod +x "$BIN_DIR/hyprctl"

run_toggle() {
    PATH="$BIN_DIR:$PATH" \
    HOME="$HOME_DIR" \
    HYPRLAND_LUA="$LUA" \
    VIBRANCE_SHADER_FILE="$SHADER" \
    HYPRCTL_TEST_LOG="$LOG" \
    "$SCRIPT" toggle >/dev/null
}

: >"$LOG"
run_toggle

grep -Fq -- "-- hl.config({ decoration = { screen_shader = \"$SHADER\" } })" "$LUA" \
    || fail 'toggle off did not persist the disabled vibrance config state'
grep -Fq -- 'argc=3|keyword|decoration:screen_shader|' "$LOG" \
    || fail 'toggle off did not explicitly clear the live Hyprland screen shader'

: >"$LOG"
run_toggle

grep -Fq -- "hl.config({ decoration = { screen_shader = \"$SHADER\" } })" "$LUA" \
    || fail 'toggle on did not persist the enabled vibrance config state'
if grep -Fq -- "-- hl.config({ decoration = { screen_shader = \"$SHADER\" } })" "$LUA"; then
    fail 'toggle on left the vibrance config commented out'
fi
grep -Fq -- "argc=3|keyword|decoration:screen_shader|$SHADER" "$LOG" \
    || fail 'toggle on did not explicitly apply the live vibrance shader path'

printf '%s\n' 'PASS: vibrance toggle persists config state and explicitly updates the live Hyprland screen shader.'
