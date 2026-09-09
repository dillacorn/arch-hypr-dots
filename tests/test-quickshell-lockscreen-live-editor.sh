#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
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

run_state() {
    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$@"
}

state_file="$TMP/cache/awtarchy/quickshell-state.json"
mkdir -p "$TMP/cache/awtarchy" "$TMP/config" "$TMP/home"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' >"$state_file"

# Layout scale is persisted with each element and validated independently of the UI.
require_text "$APP_STATE" 'save-lockscreen-editor)' \
    'state helper has no atomic lockscreen editor save command'
require_text "$APP_STATE" 'scale' \
    'lockscreen layout persistence has no scale field'

valid_layout='{"logo":{"x":0.5,"y":0.34,"scale":1.25},"time":{"x":0.5,"y":0.51,"scale":0.8},"date":{"x":0.5,"y":0.555,"scale":1},"username":{"x":0.5,"y":0.595,"scale":1},"weather":{"x":0.5,"y":0.635,"scale":1.1},"password":{"x":0.5,"y":0.7,"scale":1.4}}'
valid_visibility='{"logo":true,"time":true,"date":false,"username":true,"weather":false,"password":true}'
run_state save-lockscreen-editor "$valid_layout" "$valid_visibility"
jq -e '
    .lockscreen_layout.logo.scale == 1.25
    and .lockscreen_layout.password.scale == 1.4
    and .lockscreen_show_logo == true
    and .lockscreen_show_time == true
    and .lockscreen_show_date == false
    and .lockscreen_show_username == true
    and .lockscreen_show_weather == false
' "$state_file" >/dev/null || fail 'atomic editor state did not persist scale and visibility'

state_before="$(sha256sum "$state_file" | awk '{print $1}')"
for invalid_layout in \
    '{"logo":{"x":0.5,"y":0.34,"scale":0.49},"time":{"x":0.5,"y":0.51,"scale":1},"date":{"x":0.5,"y":0.555,"scale":1},"username":{"x":0.5,"y":0.595,"scale":1},"weather":{"x":0.5,"y":0.635,"scale":1},"password":{"x":0.5,"y":0.7,"scale":1}}' \
    '{"logo":{"x":0.5,"y":0.34,"scale":1},"time":{"x":0.5,"y":0.51,"scale":1},"date":{"x":0.5,"y":0.555,"scale":1},"username":{"x":0.5,"y":0.595,"scale":1},"weather":{"x":0.5,"y":0.635,"scale":1},"password":{"x":0.5,"y":0.7,"scale":2.01}}'; do
    if run_state save-lockscreen-editor "$invalid_layout" "$valid_visibility" >/dev/null 2>&1; then
        fail "out-of-range element scale was accepted: $invalid_layout"
    fi
done
invalid_visibility='{"logo":true,"time":true,"date":false,"username":true,"weather":false,"password":false}'
if run_state save-lockscreen-editor "$valid_layout" "$invalid_visibility" >/dev/null 2>&1; then
    fail 'editor allowed the password element to be hidden'
fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid editor save partially mutated persistent state'

# Shared production scene owns the live scale/visibility result.
require_text "$SCENE" 'required property bool showLogo' \
    'shared scene has no logo visibility input'
require_text "$SCENE" 'function elementScale(name)' \
    'shared scene has no normalized element scale reader'
require_text "$SCENE" 'scale: root.elementScale("logo")' \
    'logo does not consume saved live scale'
require_text "$SCENE" 'visible: root.showLogo' \
    'logo does not consume saved visibility'
for name in time date username weather; do
    require_text "$SCENE" "root.elementScale(\"$name\")" \
        "$name does not consume saved live scale"
done
require_text "$SCENE" 'root.elementScale("password")' \
    'password visual anchor does not consume saved scale'

# Time must remain minute-only without forcing a 12/24-hour convention.
require_text "$SCENE" 'function minuteTimeFormat()' \
    'lockscreen has no locale-aware minute-only clock formatter'
require_text "$SCENE" 'timeFormat(Locale.ShortFormat)' \
    'minute-only clock no longer derives the user locale time format'
reject_text "$SCENE" 'Qt.formatTime(now, Locale.ShortFormat)' \
    'lockscreen still delegates directly to a locale format that may contain seconds'

# Editor draft drives the preview immediately and persists only on Save.
require_text "$EDITOR" 'property var draftVisibility' \
    'editor has no draft visibility state'
require_text "$EDITOR" 'property string selectedElement' \
    'editor has no selected element for scale/visibility editing'
require_text "$EDITOR" 'function setDraftScale(name, scale)' \
    'editor cannot change element scale live'
require_text "$EDITOR" 'function setDraftVisible(name, visible)' \
    'editor cannot change element visibility live'
require_text "$EDITOR" 'function elementCanHide(name)' \
    'editor does not protect mandatory elements from hiding'
require_text "$EDITOR" 'return name !== "password"' \
    'password is not explicitly mandatory-visible in the editor'
require_text "$EDITOR" 'showLogo: root.draftVisibility.logo' \
    'preview logo visibility is not driven by the live draft'
require_text "$EDITOR" 'showTime: root.draftVisibility.time' \
    'preview time visibility is not driven by the live draft'
require_text "$EDITOR" 'showDate: root.draftVisibility.date' \
    'preview date visibility is not driven by the live draft'
require_text "$EDITOR" 'showUsername: root.draftVisibility.username' \
    'preview username visibility is not driven by the live draft'
require_text "$EDITOR" 'showWeather: root.draftVisibility.weather' \
    'preview weather visibility is not driven by the live draft'
require_text "$EDITOR" 'save-lockscreen-editor' \
    'editor does not atomically save layout and visibility'
reject_text "$EDITOR" 'visible: enabledElement' \
    'disabled element handles disappear and cannot be re-enabled from the live editor'

require_text "$BAR_STATE" 'function lockscreenShowLogo()' \
    'BarState has no normalized logo visibility reader'
require_text "$LOCK_SHELL" 'property bool lockShowLogo: true' \
    'secure lock shell has no safe logo visibility default'
require_text "$LOCK_SHELL" 'showLogo: root.lockShowLogo' \
    'secure lock surface does not receive saved logo visibility'
require_text "$SURFACE" 'required property bool showLogo' \
    'secure surface does not pass logo visibility to the shared scene'

printf 'PASS: live lockscreen editor scale, visibility, and minute-only time contracts\n'
