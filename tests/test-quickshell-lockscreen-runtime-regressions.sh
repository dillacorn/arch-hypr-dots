#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
SCENE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
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

# The approved wordmark is presentation-only now and is shared by both the
# secure surface and unlocked editor through LockScene.
reject_text "$SCENE_QML" '/fastfetch/ascii/awtarchy.txt' \
    'shared lock scene still loads the Fastfetch ASCII mark'
reject_text "$SCENE_QML" 'id: logoFile' \
    'shared lock scene still owns the removed Fastfetch FileView'
require_text "$SURFACE_QML" 'LockScene {' \
    'secure lock surface does not use the shared presentation scene'

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
    require_text "$SCENE_QML" "$row" \
        'shared lock scene does not use the approved solid-block Awtarchy wordmark'
done

mapfile -t hypr_header < <(head -n 7 "$HYPRLAND_LUA")
[[ ${#hypr_header[@]} -eq ${#WORDMARK_ROWS[@]} ]] \
    || fail 'Hyprland header does not contain all seven Awtarchy wordmark rows'
for i in "${!WORDMARK_ROWS[@]}"; do
    [[ ${hypr_header[$i]} == "-- ${WORDMARK_ROWS[$i]}" ]] \
        || fail 'Hyprland header does not exactly match the approved solid-block Awtarchy wordmark'
done

# The shared scene rasterizes ASCII cells geometrically rather than via font
# glyphs. Integer cell rectangles avoid the seams seen with adjacent text glyphs.
require_text "$SCENE_QML" 'readonly property int wordmarkCellWidth:' \
    'lockscreen wordmark does not use fixed geometric cell widths'
require_text "$SCENE_QML" 'readonly property int wordmarkCellHeight:' \
    'lockscreen wordmark does not use fixed geometric cell heights'
require_text "$SCENE_QML" 'readonly property var wordmarkRows:' \
    'lockscreen wordmark rows are not owned by the geometric renderer'
require_text "$SCENE_QML" 'property string glyph:' \
    'lockscreen wordmark does not map ASCII glyphs to geometric cells'
require_text "$SCENE_QML" 'antialiasing: false' \
    'lockscreen geometric wordmark does not disable rectangle antialiasing'
reject_text "$SCENE_QML" 'fontSizeMode: Text.HorizontalFit' \
    'lockscreen still renders the ASCII wordmark through font glyph fitting'

# Theme accent stays meaningful on the black base and paints both presentation
# and password particles through the same lock theme identity.
require_text "$LOCK_THEME_QML" 'readonly property color lockAccent:' \
    'lock theme does not expose a dedicated lockscreen accent'
lock_accent_uses="$(( $(grep -Fc 'color: root.theme.lockAccent' "$SCENE_QML" || true) + $(grep -Fc 'color: root.theme.lockAccent' "$SURFACE_QML" || true) ))"
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

# Random mode is chosen once by the lock shell so every monitor receives the
# same family for that lock. LockScene maps explicit preferences and randomizes
# paths within the selected family. Off skips only entrance formation.
require_text "$SHELL_QML" 'property int randomFormationMode: Math.floor(Math.random() * 4)' \
    'lock shell does not choose one randomized formation family per lock'
require_text "$SHELL_QML" 'randomFormationMode: root.randomFormationMode' \
    'lock surfaces do not share the shell-owned random formation family'
require_text "$SURFACE_QML" 'required property string animationPreference' \
    'lock surface does not receive the selected animation preference'
require_text "$SURFACE_QML" 'required property int randomFormationMode' \
    'lock surface does not receive the shared random formation family'
for preference in swarm edges center split; do
    require_text "$SCENE_QML" "animationPreference === \"${preference}\"" \
        "shared lock scene is missing the ${preference} formation preference"
done
for mode in 0 1 2 3; do
    require_text "$SCENE_QML" "root.formationMode === ${mode}" \
        "shared lock scene is missing formation family ${mode}"
done
require_text "$SCENE_QML" 'root.animationPreference === "off" ? 1 : 0' \
    'lockscreen off preference does not skip particle formation'
require_text "$SCENE_QML" 'root.animationPreference !== "off"' \
    'lockscreen particle animation still runs when disabled'
require_text "$SCENE_QML" 'Math.random()' \
    'lockscreen wordmark formation is not randomized per lock'
require_text "$SCENE_QML" 'readonly property int formationDelay: Math.floor(Math.random() * 301)' \
    'lockscreen wordmark does not use the approved faster particle stagger'
require_text "$SCENE_QML" 'readonly property int formationDuration: 1700' \
    'lockscreen wordmark does not use the approved faster formation duration'
require_text "$SCENE_QML" '+ Math.floor(Math.random() * 351)' \
    'lockscreen wordmark does not use the approved faster duration variance'
require_text "$SCENE_QML" 'SequentialAnimation on formationProgress' \
    'lockscreen wordmark has no per-particle formation animation'
require_text "$SCENE_QML" 'PauseAnimation {' \
    'lockscreen wordmark particles do not use randomized start delays'
require_text "$SCENE_QML" 'wordmarkCell.formationProgress <= 0 ? 0' \
    'lockscreen exposes stationary particles before formation starts'
require_text "$SURFACE_QML" 'enabled: !auth.busy || auth.responseRequired' \
    'password input was coupled to presentation instead of PAM state'
reject_text "$SCENE_QML" 'readonly property int formationDuration: 2300' \
    'lockscreen still uses the slower previous formation duration'
reject_text "$SCENE_QML" 'readonly property int formationDuration: 3000' \
    'lockscreen still uses the slower original formation duration'

# Password is still security-owned by LockSurface. Optional metadata is now
# independently positioned/rendered by LockScene rather than a forced stack.
reject_text "$SURFACE_QML" 'width: Math.round(250 * root.uiScale)' \
    'lockscreen still renders the password underline'
reject_text "$SCENE_QML" 'text: "── AWTARCHY ──"' \
    'lockscreen still uses the old tiny Awtarchy heading'
require_text "$SURFACE_QML" 'required property bool showTime' \
    'lockscreen does not carry optional time display state'
require_text "$SURFACE_QML" 'required property bool showDate' \
    'lockscreen does not carry optional date display state'
require_text "$SURFACE_QML" 'required property bool showUsername' \
    'lockscreen does not carry optional username display state'
require_text "$SCENE_QML" 'visible: root.showTime' \
    'time metadata is not optional'
require_text "$SCENE_QML" 'visible: root.showDate' \
    'date metadata is not optional'
require_text "$SCENE_QML" 'visible: root.showUsername' \
    'username metadata is not optional'
reject_text "$SURFACE_QML" 'text: "PASSWORD"' \
    'lockscreen still displays a PASSWORD label'
require_text "$SURFACE_QML" 'readonly property int maskedCount: Math.min(password.text.length, 10)' \
    'lockscreen does not cap visible password length'
require_text "$SURFACE_QML" 'readonly property real passwordScale: scene.elementScale("password")' \
    'secure password visuals do not consume the shared bounded password scale'
require_text "$SURFACE_QML" 'width: Math.round(7 * root.uiScale * root.passwordScale)' \
    'password block width does not scale from the shared password anchor'
require_text "$SURFACE_QML" 'height: Math.round(10 * root.uiScale * root.passwordScale)' \
    'password block height does not scale from the shared password anchor'
require_text "$SCENE_QML" 'Math.max(0.50, Math.min(2.00, value))' \
    'shared scene does not bound saved element scale to the editor limits'
reject_text "$SURFACE_QML" 'index % 3' \
    'password blocks still vary in height by index'
reject_text "$SURFACE_QML" 'index % 4' \
    'password blocks still vary in opacity by index'

# The secure session lock remains held while visible content fades. Only after
# the short fade may the shell release WlSessionLock.
require_text "$SURFACE_QML" 'required property bool unlocking' \
    'lock surface does not receive the shared unlock-fade state'
require_text "$SURFACE_QML" 'property bool entered: false' \
    'lock surface has no fade-in entry state'
require_text "$SURFACE_QML" 'opacity: root.unlocking ? 0 : root.entered ? 1 : 0' \
    'secure password content does not fade for lock and unlock transitions'
require_text "$SCENE_QML" 'opacity: root.unlocking ? 0 : root.entered ? 1 : 0' \
    'shared presentation content does not fade for lock and unlock transitions'
require_text "$SURFACE_QML" 'Behavior on opacity' \
    'secure password content has no opacity transition animation'
require_text "$SCENE_QML" 'Behavior on opacity' \
    'shared presentation has no opacity transition animation'
require_text "$SHELL_QML" 'unlocking: root.unlockRequested' \
    'lock surfaces do not receive the shared unlock-fade state'
require_text "$SHELL_QML" 'unlockFadeTimer.restart()' \
    'successful authentication does not start the safe unlock fade'
require_text "$SHELL_QML" 'id: unlockFadeTimer' \
    'lock shell has no unlock fade timer'

printf 'PASS: lockscreen runtime regressions\n'
