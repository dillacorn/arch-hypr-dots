#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
CONTRAST_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_contrast.sh"
DESKTOP_CONTRAST="${ROOT}/config/quickshell/awtarchy/LockscreenContrast.qml"
LOCK_CONTRAST="${ROOT}/config/quickshell/awtarchy-lock/LockContrastCache.qml"
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

require_count_at_least() {
    local file="$1" text="$2" minimum="$3" message="$4"
    local count
    count="$(grep -Fc -- "$text" "$file" || true)"
    (( count >= minimum )) || fail "$message"
}

run_state() {
    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$@"
}

state_file="$TMP/cache/awtarchy/quickshell-state.json"
mkdir -p "$TMP/cache/awtarchy" "$TMP/config" "$TMP/home"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' >"$state_file"

# Layout scale/color are persisted with each element and validated independently of the UI.
require_text "$APP_STATE" 'save-lockscreen-editor)' \
    'state helper has no atomic lockscreen editor save command'
require_text "$APP_STATE" 'scale' \
    'lockscreen layout persistence has no scale field'
require_text "$APP_STATE" 'color' \
    'lockscreen layout persistence has no per-element color field'

valid_layout='{"logo":{"x":0.5,"y":0.34,"scale":1.25,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":0.8,"color":"#ff6600"},"date":{"x":0.5,"y":0.555,"scale":1,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1.1,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1.4,"color":"auto"}}'
valid_visibility='{"logo":true,"time":true,"date":false,"username":true,"weather":false,"password":true}'
run_state save-lockscreen-editor "$valid_layout" "$valid_visibility"
jq -e '
    .lockscreen_layout.logo.scale == 1.25
    and .lockscreen_layout.logo.color == "auto"
    and .lockscreen_layout.time.color == "#ff6600"
    and .lockscreen_layout.password.scale == 1.4
    and .lockscreen_show_logo == true
    and .lockscreen_show_time == true
    and .lockscreen_show_date == false
    and .lockscreen_show_username == true
    and .lockscreen_show_weather == false
' "$state_file" >/dev/null || fail 'atomic editor state did not persist scale, color, and visibility'

state_before="$(sha256sum "$state_file" | awk '{print $1}')"
for invalid_layout in \
    '{"logo":{"x":0.5,"y":0.34,"scale":0.49,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":1,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1,"color":"auto"}}' \
    '{"logo":{"x":0.5,"y":0.34,"scale":1,"color":"banana"},"time":{"x":0.5,"y":0.51,"scale":1,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1,"color":"auto"}}' \
    '{"logo":{"x":0.5,"y":0.34,"scale":1,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":1,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":2.01,"color":"auto"}}'; do
    if run_state save-lockscreen-editor "$invalid_layout" "$valid_visibility" >/dev/null 2>&1; then
        fail "invalid element scale/color was accepted: $invalid_layout"
    fi
done
invalid_visibility='{"logo":true,"time":true,"date":false,"username":true,"weather":false,"password":false}'
if run_state save-lockscreen-editor "$valid_layout" "$invalid_visibility" >/dev/null 2>&1; then
    fail 'editor allowed the password element to be hidden'
fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid editor save partially mutated persistent state'

# Shared production scene owns the live scale/color/visibility result and exposes
# exact visual dimensions needed by the unlocked editor selection frames.
require_text "$SCENE" 'required property bool showLogo' \
    'shared scene has no logo visibility input'
require_text "$SCENE" 'required property color autoAccent' \
    'shared scene has no automatic black/white contrast input'
require_text "$SCENE" 'function elementScale(name)' \
    'shared scene has no normalized element scale reader'
require_text "$SCENE" 'function elementColor(name)' \
    'shared scene has no per-element color reader'
require_text "$SCENE" 'return value === "auto" ? root.autoAccent' \
    'auto element color does not use the wallpaper-derived contrast color'
require_text "$SCENE" 'property bool editorMode: false' \
    'shared scene has no editor-only presentation mode'
require_text "$SCENE" 'property var editorVisibility: ({})' \
    'shared scene has no editor visibility preview state'
require_text "$SCENE" 'function presentationVisible(name, configuredVisible)' \
    'shared scene cannot show hidden elements only inside the editor'
require_text "$SCENE" 'function presentationOpacity(name)' \
    'shared scene cannot visually distinguish hidden editor elements'
require_text "$SCENE" 'function elementVisualWidth(name)' \
    'shared scene does not expose rendered element widths to the editor'
require_text "$SCENE" 'function elementVisualHeight(name)' \
    'shared scene does not expose rendered element heights to the editor'
require_text "$SCENE" 'scale: root.elementScale("logo")' \
    'logo does not consume saved live scale'
require_text "$SCENE" 'root.presentationVisible("logo", root.showLogo)' \
    'logo visibility is not editor-aware while preserving saved state'
for name in time date username weather; do
    require_text "$SCENE" "root.elementScale(\"$name\")" \
        "$name does not consume saved live scale"
    require_text "$SCENE" "root.presentationVisible(\"$name\", root.show" \
        "$name visibility is not editor-aware"
done
require_text "$SCENE" 'root.elementScale("password")' \
    'password visual anchor does not consume saved scale'

# Stock non-logo presentation elements are intentionally much larger than the
# first proof-of-concept defaults so 100% scale is useful on a 1080p desktop.
require_text "$SCENE" 'font.pixelSize: Math.round(64 * root.uiScale)' \
    'stock lockscreen time is still too small'
require_text "$SCENE" 'font.pixelSize: Math.round(22 * root.uiScale)' \
    'stock lockscreen date is still too small'
require_count_at_least "$SCENE" 'font.pixelSize: Math.round(18 * root.uiScale)' 2 \
    'stock username/weather are still too small'
require_text "$SCENE" 'Math.round(420 * uiScale * elementScale("password"))' \
    'stock password interaction width is still too small'
require_text "$SCENE" 'Math.round(58 * uiScale * elementScale("password"))' \
    'stock password interaction height is still too small'

# Time must remain minute-only without forcing a 12/24-hour convention.
require_text "$SCENE" 'function minuteTimeFormat()' \
    'lockscreen has no locale-aware minute-only clock formatter'
require_text "$SCENE" 'timeFormat(Locale.ShortFormat)' \
    'minute-only clock no longer derives the user locale time format'
reject_text "$SCENE" 'Qt.formatTime(now, Locale.ShortFormat)' \
    'lockscreen still delegates directly to a locale format that may contain seconds'

# Editor draft drives the preview immediately and persists only on Save. The
# rendered lockscreen elements themselves are the visual examples; selection
# frames track their actual dimensions instead of generic text-labelled handles.
require_text "$EDITOR" 'property var draftVisibility' \
    'editor has no draft visibility state'
require_text "$EDITOR" 'property string selectedElement' \
    'editor has no selected element for scale/visibility/color editing'
require_text "$EDITOR" 'function setDraftScale(name, scale)' \
    'editor cannot change element scale live'
require_text "$EDITOR" 'function setDraftVisible(name, visible)' \
    'editor cannot change element visibility live'
require_text "$EDITOR" 'function setDraftColor(name, colorValue)' \
    'editor cannot change selected element color live'
require_text "$EDITOR" 'function elementColor(name)' \
    'editor cannot read selected element color'
require_text "$EDITOR" 'label: "Auto"' \
    'editor has no automatic contrast color option'
require_text "$EDITOR" 'label: "White"' \
    'editor has no explicit white color option'
require_text "$EDITOR" 'label: "Black"' \
    'editor has no explicit black color option'
require_text "$EDITOR" 'placeholderText: "#RRGGBB"' \
    'editor has no custom hex color input'
require_text "$EDITOR" 'editorMode: true' \
    'LockscreenEditor does not activate editor-only presentation behavior'
require_text "$EDITOR" 'editorVisibility: root.draftVisibility' \
    'LockscreenEditor does not preview hidden elements as faded visuals'
require_text "$EDITOR" 'previewScene.elementVisualWidth(elementName)' \
    'editor selection frames do not follow rendered element widths'
require_text "$EDITOR" 'previewScene.elementVisualHeight(elementName)' \
    'editor selection frames do not follow rendered element heights'
require_text "$EDITOR" 'weatherText: "72°F · Clear"' \
    'editor does not render a representative weather visual'
reject_text "$EDITOR" 'text: root.elementLabel(parent.elementName)' \
    'editor still covers lockscreen elements with generic text-labelled handles'
reject_text "$EDITOR" ' · Off' \
    'editor still describes hidden elements with generic handle text'
require_text "$EDITOR" 'save-lockscreen-editor' \
    'editor does not atomically save layout and visibility'
reject_text "$EDITOR" 'visible: enabledElement' \
    'disabled element handles disappear and cannot be re-enabled from the live editor'

# Visibility belongs in the visual editor now. Quick Settings keeps global
# effects/background controls but no longer duplicates per-element On/Off rows.
for command in set-lockscreen-show-time set-lockscreen-show-date set-lockscreen-show-username set-lockscreen-show-weather; do
    reject_text "$QUICK_SETTINGS" "\"${command}\"" \
        "Quick Settings still duplicates editor visibility control: $command"
done
require_text "$QUICK_SETTINGS" 'text: "Mouse Interaction"' \
    'global Mouse Interaction control unexpectedly left Quick Settings'
require_text "$QUICK_SETTINGS" 'text: "Audio Reactive"' \
    'global Audio Reactive control unexpectedly left Quick Settings'

# Automatic contrast is computed only while unlocked. The secure lock reads a
# local cache and never runs ImageMagick or wallpaper inspection itself.
[[ -x "$CONTRAST_HELPER" ]] || fail 'unlocked lockscreen contrast helper is missing or not executable'
[[ -f "$DESKTOP_CONTRAST" ]] || fail 'unlocked LockscreenContrast.qml service is missing'
[[ -f "$LOCK_CONTRAST" ]] || fail 'secure LockContrastCache.qml reader is missing'
require_text "$CONTRAST_HELPER" 'magick' \
    'automatic wallpaper contrast does not inspect image luminance'
require_text "$CONTRAST_HELPER" '#000000' \
    'automatic wallpaper contrast cannot choose black'
require_text "$CONTRAST_HELPER" '#ffffff' \
    'automatic wallpaper contrast cannot choose white'
require_text "$DESKTOP_CONTRAST" 'quickshell_lockscreen_contrast.sh' \
    'unlocked contrast service does not use the bounded helper'
require_text "$DESKTOP_CONTRAST" 'backend_state.tsv' \
    'unlocked contrast service does not react to Awtwall selections'
require_text "$LOCK_CONTRAST" 'lockscreen-contrast.txt' \
    'secure contrast reader does not consume the local cache'
for forbidden in Process magick backend_state.tsv; do
    reject_text "$LOCK_CONTRAST" "$forbidden" \
        "secure contrast cache performs unlocked-only work: $forbidden"
done
require_text "$LOCK_SHELL" 'LockContrastCache {' \
    'secure lock shell does not construct the cache-only contrast reader'
require_text "$SURFACE" 'required property color autoAccent' \
    'secure lock surface does not receive automatic contrast color'

require_text "$BAR_STATE" 'function lockscreenShowLogo()' \
    'BarState has no normalized logo visibility reader'
require_text "$LOCK_SHELL" 'property bool lockShowLogo: true' \
    'secure lock shell has no safe logo visibility default'
require_text "$LOCK_SHELL" 'showLogo: root.lockShowLogo' \
    'secure lock surface does not receive saved logo visibility'
require_text "$SURFACE" 'required property bool showLogo' \
    'secure surface does not pass logo visibility to the shared scene'

printf 'PASS: live lockscreen editor scale, color, visibility, and minute-only time contracts\n'
