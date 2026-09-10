#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
DESKTOP_SHELL="${ROOT}/config/quickshell/awtarchy/shell.qml"
EDITOR_QML="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
DESKTOP_WEATHER="${ROOT}/config/quickshell/awtarchy/LockscreenWeather.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
PREVIEW_WALLPAPER="${ROOT}/config/quickshell/awtarchy/LockPreviewWallpaperState.qml"
LOCK_SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
LOCK_SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
LOCK_AUTH="${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml"
WEATHER_CACHE="${ROOT}/config/quickshell/awtarchy-lock/LockWeatherCache.qml"
WEATHER_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_weather.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "$2"
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
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' \
    >"$state_file"

require_file "$LOCK_SCENE" 'shared LockScene.qml is missing'
require_file "$EDITOR_QML" 'unlocked LockscreenEditor.qml is missing'
require_file "$PREVIEW_SCENE" 'unlocked LockPreviewScene.qml is missing'
require_file "$PREVIEW_WALLPAPER" 'unlocked LockPreviewWallpaperState.qml is missing'
require_file "$DESKTOP_WEATHER" 'unlocked LockscreenWeather.qml is missing'

reject_text "$LOCK_SCENE" 'WlSessionLock' \
    'shared LockScene owns or imports session-lock authority'
reject_text "$LOCK_SCENE" 'LockAuth' \
    'shared LockScene references PAM authentication owner'
reject_text "$LOCK_SCENE" 'auth.submit' \
    'shared LockScene can submit authentication'
reject_text "$LOCK_SCENE" 'TextInput {' \
    'shared LockScene owns a real password TextInput'
require_text "$LOCK_SURFACE" 'WlSessionLockSurface {' \
    'secure LockSurface no longer owns the session-lock surface'
require_text "$LOCK_SURFACE" 'LockScene {' \
    'secure LockSurface does not embed the shared LockScene'
require_text "$LOCK_SURFACE" 'TextInput {' \
    'secure LockSurface no longer owns the real password input'
require_text "$LOCK_SURFACE" 'auth.submit(response)' \
    'secure LockSurface no longer submits through LockAuth'
require_text "$LOCK_SURFACE" 'cursorShape: Qt.BlankCursor' \
    'secure LockSurface exposes the real pointer'

reject_text "$EDITOR_QML" 'import "../awtarchy-lock"' \
    'LockscreenEditor crosses the Quickshell configuration boundary into awtarchy-lock'
require_text "$EDITOR_QML" 'LockPreviewScene {' \
    'LockscreenEditor does not render its config-local lock preview scene'
require_text "$EDITOR_QML" 'LockPreviewWallpaperState {' \
    'LockscreenEditor does not use its config-local wallpaper preview state'
cmp -s "$LOCK_SCENE" "$PREVIEW_SCENE" \
    || fail 'LockPreviewScene drifted from the secure lock presentation scene'
require_text "$EDITOR_QML" 'function save()' \
    'LockscreenEditor has no explicit Save path'
require_text "$EDITOR_QML" 'function close()' \
    'LockscreenEditor has no Cancel/close path'
require_text "$EDITOR_QML" 'function resetDraft()' \
    'LockscreenEditor has no Restore Defaults draft path'
require_text "$EDITOR_QML" 'save-lockscreen-editor' \
    'LockscreenEditor does not atomically persist layout and visibility'
require_text "$EDITOR_QML" 'label: "Save"' \
    'LockscreenEditor has no Save control'
require_text "$EDITOR_QML" 'label: "Cancel"' \
    'LockscreenEditor has no Cancel control'
require_text "$EDITOR_QML" 'label: "Restore Defaults"' \
    'LockscreenEditor has no Restore Defaults control'
for forbidden in WlSessionLock LockAuth auth.submit sessionLock unlockRequested; do
    reject_text "$EDITOR_QML" "$forbidden" \
        "LockscreenEditor crosses the secure lock boundary: $forbidden"
done

require_text "$APP_STATE" 'save-lockscreen-layout)' \
    'state helper has no explicit save-lockscreen-layout command'
require_text "$APP_STATE" 'save-lockscreen-editor)' \
    'state helper has no atomic lockscreen editor save command'
require_text "$APP_STATE" 'set-lockscreen-background)' \
    'state helper has no explicit lockscreen background command'
require_text "$APP_STATE" 'set-lockscreen-weather-location)' \
    'state helper has no explicit lockscreen weather location command'
require_text "$APP_STATE" 'reset-lockscreen-presentation)' \
    'state helper has no scoped lockscreen presentation reset command'

run_state set-lockscreen-background black
jq -e '.lockscreen_background == "black"' "$state_file" >/dev/null \
    || fail 'black lockscreen background did not persist'
run_state set-lockscreen-background wallpaper
jq -e '.lockscreen_background == "wallpaper"' "$state_file" >/dev/null \
    || fail 'wallpaper lockscreen background did not persist'
background_before="$(sha256sum "$state_file" | awk '{print $1}')"
if run_state set-lockscreen-background remote >/dev/null 2>&1; then
    fail 'invalid lockscreen background was accepted'
fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$background_before" ]] \
    || fail 'invalid background changed persistent state'

valid_layout='{"logo":{"x":0.5,"y":0.34},"time":{"x":0.5,"y":0.51},"date":{"x":0.5,"y":0.555},"username":{"x":0.5,"y":0.595},"weather":{"x":0.5,"y":0.635},"password":{"x":0.5,"y":0.7}}'
run_state save-lockscreen-layout "$valid_layout"
jq -e '.lockscreen_layout.password.x == 0.5 and .lockscreen_layout.password.y == 0.7' \
    "$state_file" >/dev/null || fail 'valid normalized lockscreen layout did not persist'

layout_before="$(sha256sum "$state_file" | awk '{print $1}')"
for invalid_layout in \
    '{"logo":{"x":0.5,"y":0.34}}' \
    '{"logo":{"x":"bad","y":0.34},"time":{"x":0.5,"y":0.51},"date":{"x":0.5,"y":0.555},"username":{"x":0.5,"y":0.595},"weather":{"x":0.5,"y":0.635},"password":{"x":0.5,"y":0.7}}' \
    '{"logo":{"x":0.5,"y":0.34},"time":{"x":0.5,"y":0.51},"date":{"x":0.5,"y":0.555},"username":{"x":0.5,"y":0.595},"weather":{"x":0.5,"y":0.635},"password":{"x":0.95,"y":0.7}}' \
    '{"logo":{"x":0.5,"y":0.34},"time":{"x":0.5,"y":0.51},"date":{"x":0.5,"y":0.555},"username":{"x":0.5,"y":0.595},"weather":{"x":0.5,"y":0.635},"password":{"x":0.5,"y":0.95}}'; do
    if run_state save-lockscreen-layout "$invalid_layout" >/dev/null 2>&1; then
        fail "invalid lockscreen layout was accepted: $invalid_layout"
    fi
done
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$layout_before" ]] \
    || fail 'invalid layout partially changed persistent state'

run_state set-lockscreen-weather-location 'Pittsburgh, PA'
jq -e '.lockscreen_weather_location == "Pittsburgh, PA"' "$state_file" >/dev/null \
    || fail 'explicit lockscreen weather location did not persist'
run_state set-lockscreen-weather-location ''
jq -e '.lockscreen_weather_location == ""' "$state_file" >/dev/null \
    || fail 'blank automatic lockscreen weather location did not persist'
location_before="$(sha256sum "$state_file" | awk '{print $1}')"
if run_state set-lockscreen-weather-location $'Pittsburgh\nPA' >/dev/null 2>&1; then
    fail 'weather location accepted a newline'
fi
long_location="$(printf 'x%.0s' {1..97})"
if run_state set-lockscreen-weather-location "$long_location" >/dev/null 2>&1; then
    fail 'weather location accepted more than 96 characters'
fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$location_before" ]] \
    || fail 'invalid weather location changed persistent state'

require_text "$BAR_STATE" 'lockscreen_background: "black"' \
    'BarState has no stock black lockscreen background'
require_text "$BAR_STATE" 'lockscreen_weather_location: ""' \
    'BarState has no blank automatic-location default'
require_text "$BAR_STATE" 'lockscreen_layout:' \
    'BarState has no stock normalized lockscreen layout'
require_text "$BAR_STATE" 'function lockscreenBackground()' \
    'BarState has no normalized lockscreen background reader'
require_text "$BAR_STATE" 'function lockscreenWeatherLocation()' \
    'BarState has no normalized lockscreen weather-location reader'
require_text "$BAR_STATE" 'function lockscreenLayout()' \
    'BarState has no normalized lockscreen layout reader'

require_text "$QUICK_SETTINGS" 'text: "Lockscreen"' \
    'Quick Settings has no expandable Lockscreen section title'
require_text "$QUICK_SETTINGS" 'lockscreenSectionExpanded' \
    'Quick Settings Lockscreen section has no collapsed/expanded state'
require_text "$QUICK_SETTINGS" 'label: "Edit Layout"' \
    'Quick Settings has no Edit Layout action'
require_text "$QUICK_SETTINGS" 'LockscreenEditor.openForScreen' \
    'Quick Settings does not launch the dedicated lockscreen editor'
reject_text "$QUICK_SETTINGS" 'label: "Choose with Awtwall"' \
    'Quick Settings still duplicates lockscreen wallpaper selection outside the editor'
require_text "$EDITOR_QML" 'quickshell_lockscreen_wallpaper_picker.sh' \
    'LockscreenEditor does not own the dedicated selection-only wallpaper flow'
require_text "$QUICK_SETTINGS" 'text: "Location override (optional)"' \
    'Quick Settings does not make automatic weather the simple default path'
require_text "$QUICK_SETTINGS" 'Automatic location uses your approximate public-IP location' \
    'Quick Settings does not explain automatic weather location behavior'
require_text "$QUICK_SETTINGS" 'ipwho.is' \
    'Quick Settings does not disclose the automatic IP-geolocation provider'
require_text "$QUICK_SETTINGS" 'Open-Meteo' \
    'Quick Settings does not disclose the weather provider'
require_text "$QUICK_SETTINGS" 'set-lockscreen-background' \
    'Quick Settings does not persist the lockscreen background mode'
require_text "$QUICK_SETTINGS" 'reset-lockscreen-presentation' \
    'Quick Settings has no scoped Restore Awtarchy Defaults path'

require_text "$DESKTOP_SHELL" 'LockscreenEditor' \
    'desktop Awtarchy shell does not construct/reference LockscreenEditor'
reject_text "$LOCK_SHELL" 'LockscreenEditor' \
    'secure lock process loads the unlocked editor'

require_text "$LOCK_SCENE" 'required property string backgroundMode' \
    'LockScene has no explicit background mode input'
require_text "$LOCK_SCENE" 'required property string wallpaperSource' \
    'LockScene has no local wallpaper source input'
require_text "$LOCK_SCENE" 'root.backgroundMode === "color" ? root.backgroundColor : "#000000"' \
    'LockScene does not keep a black fallback under wallpaper rendering'
require_text "$LOCK_SCENE" 'fillMode: Image.PreserveAspectCrop' \
    'LockScene wallpaper is not aspect-filled'

require_text "$WEATHER_CACHE" 'expires_at' \
    'lock weather cache does not validate expiry metadata'
require_text "$WEATHER_CACHE" 'Date.now()' \
    'lock weather cache does not compare expiry against current time'
for forbidden in 'curl' 'http://' 'https://'; do
    reject_text "$WEATHER_CACHE" "$forbidden" \
        "lock weather cache performs/contains network behavior: $forbidden"
    reject_text "$LOCK_SHELL" "$forbidden" \
        "secure lock shell performs/contains weather network behavior: $forbidden"
done
reject_text "$LOCK_SHELL" 'open-meteo' \
    'secure lock shell contains weather-provider network behavior'
reject_text "$LOCK_SHELL" 'ipwho.is' \
    'secure lock shell contains automatic geolocation network behavior'
require_text "$WEATHER_CACHE" 'provider !== "open-meteo"' \
    'lock weather cache does not validate the expected cache provider'

require_file "$WEATHER_HELPER" 'unlocked lockscreen weather helper is missing'
require_text "$WEATHER_HELPER" 'https://ipwho.is/' \
    'unlocked weather helper does not support automatic public-IP geolocation'
require_text "$WEATHER_HELPER" 'geocoding-api.open-meteo.com' \
    'weather helper does not preserve explicit-location Open-Meteo geocoding'
require_text "$WEATHER_HELPER" 'api.open-meteo.com' \
    'weather helper does not use Open-Meteo current weather'
require_text "$WEATHER_HELPER" '--connect-timeout' \
    'weather helper has no bounded connection timeout'
require_text "$WEATHER_HELPER" '--max-time' \
    'weather helper has no bounded request timeout'
require_text "$WEATHER_HELPER" 'expires_at' \
    'weather helper does not write explicit cache expiry metadata'

require_text "$DESKTOP_WEATHER" 'BarState.lockscreenShowWeather()' \
    'unlocked weather refresh service is not gated by the Weather toggle'
reject_text "$DESKTOP_WEATHER" '&& configuredLocation.length > 0' \
    'unlocked weather refresh still requires manual location configuration'
require_text "$DESKTOP_WEATHER" 'refreshProcess.exec([root.weatherHelper, "refresh", location])' \
    'unlocked weather refresh does not pass blank location through for automatic mode'

for token in LockScene LockscreenEditor lockscreen_layout lockscreen_background \
    lockscreen_weather_location wallpaperSource weatherLocation; do
    reject_text "$LOCK_AUTH" "$token" \
        "LockAuth was coupled to presentation/editor state: $token"
done

printf 'PASS: lockscreen customization editor contracts\n'
