#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
HYPRLAND_LUA="${ROOT}/config/hypr/hyprland.lua"

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
# lockscreen metadata, and uniform password blocks. The seven solid-block rows
# are shared with the Hyprland header so both representations stay identical.
reject_text "$SURFACE_QML" '/fastfetch/ascii/awtarchy.txt' \
    'lockscreen still loads the Fastfetch ASCII mark'
reject_text "$SURFACE_QML" 'id: logoFile' \
    'lockscreen still owns the removed Fastfetch FileView'

WORDMARK_ROWS=(
    '▄▄▄      ██     █ ▄▄▄█████ ▄▄▄      ██▀███  ▄████▄  ██  ██ ██   ██'
    '████▄     █  █  █ █  ██  █ ████▄    ██   ██ ██▀ ▀█  ██  ██  ██  ██'
    '██  ▀█▄  ██  █  ██   ██    ██  ▀█▄  ██  ▄█  ██    ▄ ██▀▀██   ██ ██'
    '██▄▄▄▄██ ██  █  ██   ██    ██▄▄▄▄██ ██▀▀█▄  ██▄ ▄██ ██  ██    ▐██'
    '███    ██  ███████    ██    ██    ██ ██   ██  ████▀  ██  ██    ██'
    '             ███                                              ██'
    '                                                              ██'
)

for row in "${WORDMARK_ROWS[@]}"; do
    require_text "$SURFACE_QML" "$row" \
        'lockscreen does not use the approved solid-block Awtarchy wordmark'
    require_text "$HYPRLAND_LUA" "$row" \
        'Hyprland header does not match the approved solid-block Awtarchy wordmark'
done

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
