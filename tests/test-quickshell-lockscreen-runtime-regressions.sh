#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
LOCK_THEME_QML="${ROOT}/config/quickshell/awtarchy-lock/LockTheme.qml"
THEME_APPLY="${ROOT}/config/hypr/scripts/quickshell_theme_apply.sh"
PINK_THEME="${ROOT}/config/hypr/themes/pink"
HYPRLAND_LUA="${ROOT}/config/hypr/hyprland.lua"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

# Runtime regression: the real Quickshell session reported root.auth undefined.
# A LockSurface property named `auth` must not be bound as `auth: auth` from the
# Component body. In QML that self-shadows the outer id and loses LockAuth.
require_text "$SHELL_QML" 'id: lockAuth' \
    'lock shell does not use a non-shadowing authentication id'
require_text "$SHELL_QML" 'auth: lockAuth' \
    'lock surface is not bound to the real LockAuth object'
reject_text "$SHELL_QML" 'auth: auth' \
    'lock surface still self-binds auth and loses the authentication object'

# Approved minimal lockscreen: large Awtarchy ASCII wordmark, no conventional
# lockscreen metadata, and uniform password blocks. The exact seven solid-block
# rows, including their intentional leading spaces, are shared with the Hyprland
# header so both representations remain visually identical.
reject_text "$SURFACE_QML" '/fastfetch/ascii/awtarchy.txt' \
    'lockscreen still loads the Fastfetch ASCII mark'
reject_text "$SURFACE_QML" 'id: logoFile' \
    'lockscreen still owns the removed Fastfetch FileView'

WORDMARK_ROWS=(
    ' ▄▄▄      ██     █ ▄▄▄█████ ▄▄▄      ██▀███  ▄████▄  ██  ██ ██   ██'
    ' ████▄     █  █  █ █  ██  █ ████▄    ██   ██ ██▀ ▀█  ██  ██  ██  ██'
    ' ██  ▀█▄  ██  █  ██   ██    ██  ▀█▄  ██  ▄█  ██    ▄ ██▀▀██   ██ ██'
    ' ██▄▄▄▄██ ██  █  ██   ██    ██▄▄▄▄██ ██▀▀█▄  ██▄ ▄██ ██  ██    ▐██'
    '███    ██  ███████    ██    ██    ██ ██   ██  ████▀  ██  ██    ██'
    '             ███                                              ██'
    '                                                              ██'
)

for row in "${WORDMARK_ROWS[@]}"; do
    require_text "$SURFACE_QML" "$row" \
        'lockscreen does not use the approved solid-block Awtarchy wordmark'
done

mapfile -t hypr_header < <(head -n 7 "$HYPRLAND_LUA")
[[ ${#hypr_header[@]} -eq ${#WORDMARK_ROWS[@]} ]] \
    || fail 'Hyprland header does not contain all seven Awtarchy wordmark rows'
for i in "${!WORDMARK_ROWS[@]}"; do
    [[ ${hypr_header[$i]} == "-- ${WORDMARK_ROWS[$i]}" ]] \
        || fail 'Hyprland header does not exactly match the approved solid-block Awtarchy wordmark'
done

# The lockscreen must rasterize the ASCII cells geometrically rather than via
# font glyphs. Adjacent block glyphs rendered as text showed visible hairline
# seams on the real display; integer cell rectangles remove those font gaps.
require_text "$SURFACE_QML" 'readonly property int wordmarkCellWidth:' \
    'lockscreen wordmark does not use fixed geometric cell widths'
require_text "$SURFACE_QML" 'readonly property int wordmarkCellHeight:' \
    'lockscreen wordmark does not use fixed geometric cell heights'
require_text "$SURFACE_QML" 'readonly property var wordmarkRows:' \
    'lockscreen wordmark rows are not owned by the geometric renderer'
require_text "$SURFACE_QML" 'property string glyph:' \
    'lockscreen wordmark does not map ASCII glyphs to geometric cells'
require_text "$SURFACE_QML" 'antialiasing: false' \
    'lockscreen geometric wordmark does not disable rectangle antialiasing'
reject_text "$SURFACE_QML" 'fontSizeMode: Text.HorizontalFit' \
    'lockscreen still renders the ASCII wordmark through font glyph fitting'

# The lockscreen needs a theme color that remains meaningful on its fixed black
# background. It is generated from each theme's active-border identity instead
# of reusing foreground, which is intentionally dark for the pink theme.
require_text "$LOCK_THEME_QML" 'readonly property color lockAccent:' \
    'lock theme does not expose a dedicated lockscreen accent'
lock_accent_uses="$(grep -Fc 'color: root.theme.lockAccent' "$SURFACE_QML" || true)"
[[ "$lock_accent_uses" -ge 3 ]] \
    || fail 'lockscreen logo and password particles do not use the dedicated lock accent'

mkdir -p "$TMP/config/hypr/themes" "$TMP/state" "$TMP/home" "$TMP/bin"
cp -- "$PINK_THEME" "$TMP/config/hypr/themes/pink"
cat >"$TMP/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod 0755 "$TMP/bin/systemctl"
PATH="$TMP/bin:$PATH" \
HOME="$TMP/home" \
XDG_CONFIG_HOME="$TMP/config" \
XDG_STATE_HOME="$TMP/state" \
    bash "$THEME_APPLY" pink
python3 - "$TMP/config/quickshell/awtarchy/theme.json" <<'PY' \
    || fail 'pink theme did not generate the expected lockscreen accent'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

if data.get("lockAccent") != "#EACDD2":
    raise SystemExit(1)
PY

# Every lock chooses one of four formation families, then randomizes paths inside
# that family. The particles start fully invisible so the first frame is black,
# then reveal only after they begin moving. Formation is intentionally a little
# quicker than the original roughly four-second swarm without gating PAM input.
require_text "$SURFACE_QML" 'readonly property int formationMode: Math.floor(Math.random() * 4)' \
    'lockscreen does not choose a randomized formation family per lock'
for mode in 0 1 2 3; do
    require_text "$SURFACE_QML" "root.formationMode === ${mode}" \
        "lockscreen is missing formation family ${mode}"
done
require_text "$SURFACE_QML" 'property real formationProgress: 0' \
    'lockscreen wordmark cells have no formation progress state'
require_text "$SURFACE_QML" 'Math.random()' \
    'lockscreen wordmark formation is not randomized per lock'
require_text "$SURFACE_QML" 'readonly property int formationDelay: Math.floor(Math.random() * 451)' \
    'lockscreen wordmark does not use the approved shorter particle stagger'
require_text "$SURFACE_QML" 'readonly property int formationDuration: 2300' \
    'lockscreen wordmark does not use the approved quicker formation duration'
require_text "$SURFACE_QML" 'SequentialAnimation on formationProgress' \
    'lockscreen wordmark has no per-particle formation animation'
require_text "$SURFACE_QML" 'PauseAnimation {' \
    'lockscreen wordmark particles do not use randomized start delays'
require_text "$SURFACE_QML" 'wordmarkCell.formationProgress <= 0 ? 0' \
    'lockscreen exposes stationary particles before formation starts'
require_text "$SURFACE_QML" 'enabled: !auth.busy || auth.responseRequired' \
    'password input was coupled to the logo formation instead of PAM state'
reject_text "$SURFACE_QML" 'readonly property int formationDuration: 3000' \
    'lockscreen still uses the slower original formation duration'

# The password row is intentionally minimal. Keep only the blocks/haze and do
# not restore the old focus/error underline.
reject_text "$SURFACE_QML" 'width: Math.round(250 * root.uiScale)' \
    'lockscreen still renders the password underline'
reject_text "$SURFACE_QML" 'text: "── AWTARCHY ──"' \
    'lockscreen still uses the old tiny Awtarchy heading'
reject_text "$SURFACE_QML" 'property string timeText' \
    'lockscreen still owns clock state'
reject_text "$SURFACE_QML" 'property string dateText' \
    'lockscreen still owns date state'
reject_text "$SURFACE_QML" 'Quickshell.env("USER")' \
    'lockscreen still displays the username'
reject_text "$SURFACE_QML" 'text: "PASSWORD"' \
    'lockscreen still displays a PASSWORD label'
require_text "$SURFACE_QML" 'readonly property int maskedCount: Math.min(password.text.length, 10)' \
    'lockscreen does not cap visible password length'
require_text "$SURFACE_QML" 'width: Math.round(7 * root.uiScale)' \
    'password blocks do not use one fixed width'
require_text "$SURFACE_QML" 'height: Math.round(10 * root.uiScale)' \
    'password blocks do not use one fixed height'
reject_text "$SURFACE_QML" 'index % 3' \
    'password blocks still vary in height by index'
reject_text "$SURFACE_QML" 'index % 4' \
    'password blocks still vary in opacity by index'

# The secure session lock must stay held while the visible lockscreen content
# fades out. Only after that short fade may the shell release WlSessionLock.
require_text "$SURFACE_QML" 'required property bool unlocking' \
    'lock surface does not receive the shared unlock-fade state'
require_text "$SURFACE_QML" 'property bool entered: false' \
    'lock surface has no fade-in entry state'
require_text "$SURFACE_QML" 'opacity: root.unlocking ? 0 : root.entered ? 1 : 0' \
    'lockscreen content does not fade for lock and unlock transitions'
require_text "$SURFACE_QML" 'Behavior on opacity' \
    'lockscreen has no opacity transition animation'
require_text "$SHELL_QML" 'unlocking: root.unlockRequested' \
    'lock surfaces do not receive the shared unlock-fade state'
require_text "$SHELL_QML" 'unlockFadeTimer.restart()' \
    'successful authentication does not start the safe unlock fade'
require_text "$SHELL_QML" 'id: unlockFadeTimer' \
    'lock shell has no unlock fade timer'

printf 'PASS: lockscreen runtime regressions\n'
