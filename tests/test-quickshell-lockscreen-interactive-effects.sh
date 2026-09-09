#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
SCENE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
AUDIO_QML="${ROOT}/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"
WEATHER_QML="${ROOT}/config/quickshell/awtarchy-lock/LockWeatherCache.qml"
CAVA_CONFIG="${ROOT}/config/quickshell/awtarchy-lock/cava.conf"
AUDIO_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_audio.sh"
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

mkdir -p "$TMP/cache/awtarchy" "$TMP/home" "$TMP/config"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' \
    >"$TMP/cache/awtarchy/quickshell-state.json"

check_bool_setting() {
    local command="$1" field="$2"

    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$command" true
    jq -e --arg field "$field" '.[$field] == true' \
        "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
        || fail "$command did not persist true to $field"

    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$command" false
    jq -e --arg field "$field" '.[$field] == false' \
        "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
        || fail "$command did not persist false to $field"

    if XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$command" maybe >/dev/null 2>&1; then
        fail "$command accepted an invalid boolean"
    fi
}

check_bool_setting set-lockscreen-audio-reactive lockscreen_audio_reactive
check_bool_setting set-lockscreen-mouse-interactive lockscreen_mouse_interactive
check_bool_setting set-lockscreen-show-time lockscreen_show_time
check_bool_setting set-lockscreen-show-date lockscreen_show_date
check_bool_setting set-lockscreen-show-username lockscreen_show_username
check_bool_setting set-lockscreen-show-weather lockscreen_show_weather

# Interactive effects are visible for evaluation by default. Optional information
# overlays remain stock-off so the lockscreen stays minimal unless requested.
require_text "$BAR_STATE" 'lockscreen_audio_reactive: true' \
    'BarState stock audio-reactive default is not enabled'
require_text "$BAR_STATE" 'lockscreen_mouse_interactive: true' \
    'BarState stock mouse-interactive default is not enabled'
require_text "$BAR_STATE" 'lockscreen_show_time: false' \
    'BarState stock time default is not disabled'
require_text "$BAR_STATE" 'lockscreen_show_date: false' \
    'BarState stock date default is not disabled'
require_text "$BAR_STATE" 'lockscreen_show_username: false' \
    'BarState stock username default is not disabled'
require_text "$BAR_STATE" 'lockscreen_show_weather: false' \
    'BarState stock weather default is not disabled'
require_text "$BAR_STATE" 'function lockscreenAudioReactiveEnabled()' \
    'BarState does not expose normalized audio-reactive state'
require_text "$BAR_STATE" 'function lockscreenMouseInteractiveEnabled()' \
    'BarState does not expose normalized mouse-interactive state'
require_text "$BAR_STATE" 'function lockscreenShowTime()' \
    'BarState does not expose normalized time state'
require_text "$BAR_STATE" 'function lockscreenShowDate()' \
    'BarState does not expose normalized date state'
require_text "$BAR_STATE" 'function lockscreenShowUsername()' \
    'BarState does not expose normalized username state'
require_text "$BAR_STATE" 'function lockscreenShowWeather()' \
    'BarState does not expose normalized weather state'

# Controls stay in the existing Awtarchy card and persist immediately.
require_text "$QUICK_SETTINGS" 'text: "Audio Reactive"' \
    'Quick Settings has no Audio Reactive lockscreen toggle'
require_text "$QUICK_SETTINGS" 'text: "Mouse Interaction"' \
    'Quick Settings has no Mouse Interaction lockscreen toggle'
require_text "$QUICK_SETTINGS" 'text: "Time"' \
    'Quick Settings has no Time lockscreen toggle'
require_text "$QUICK_SETTINGS" 'text: "Date"' \
    'Quick Settings has no Date lockscreen toggle'
require_text "$QUICK_SETTINGS" 'text: "Username"' \
    'Quick Settings has no Username lockscreen toggle'
require_text "$QUICK_SETTINGS" 'text: "Weather"' \
    'Quick Settings has no Weather lockscreen toggle'
for command in \
    set-lockscreen-audio-reactive \
    set-lockscreen-mouse-interactive \
    set-lockscreen-show-time \
    set-lockscreen-show-date \
    set-lockscreen-show-username \
    set-lockscreen-show-weather; do
    require_text "$QUICK_SETTINGS" "\"${command}\"" \
        "Quick Settings does not persist ${command}"
done
reject_text "$QUICK_SETTINGS" 'BarState.lockscreenAnimationPreference() !== "off"' \
    'Quick Settings still treats formation Off as an effects master switch'

# The dedicated lock process loads shared preferences once and owns one analyzer
# plus one local weather-cache reader shared by every lock surface.
require_text "$SHELL_QML" 'property bool lockAudioReactive: true' \
    'lock shell has no stock-enabled audio-reactive preference'
require_text "$SHELL_QML" 'property bool lockMouseInteractive: true' \
    'lock shell has no stock-enabled mouse-interactive preference'
require_text "$SHELL_QML" 'property bool lockShowTime: false' \
    'lock shell has no stock-disabled time preference'
require_text "$SHELL_QML" 'property bool lockShowDate: false' \
    'lock shell has no stock-disabled date preference'
require_text "$SHELL_QML" 'property bool lockShowUsername: false' \
    'lock shell has no stock-disabled username preference'
require_text "$SHELL_QML" 'property bool lockShowWeather: false' \
    'lock shell has no stock-disabled weather preference'
require_text "$SHELL_QML" 'LockAudioAnalyzer {' \
    'lock shell does not own the audio analyzer'
require_text "$SHELL_QML" 'id: lockAudioAnalyzer' \
    'lock shell audio analyzer has no single root owner'
require_text "$SHELL_QML" 'enabled: root.lockAudioReactive' \
    'audio analyzer is not controlled independently by Audio Reactive'
reject_text "$SHELL_QML" 'root.lockAudioReactive && root.lockAnimationPreference !== "off"' \
    'audio analyzer is still coupled to the formation preference'
require_text "$SHELL_QML" 'LockWeatherCache {' \
    'lock shell does not own the weather cache reader'
require_text "$SHELL_QML" 'enabled: root.lockShowWeather' \
    'weather cache reader is not gated by the Weather preference'
require_text "$SHELL_QML" 'audioLow: lockAudioAnalyzer.low' \
    'lock surfaces do not receive low-band audio state'
require_text "$SHELL_QML" 'mouseInteractive: root.lockMouseInteractive' \
    'lock surfaces do not receive mouse-interaction state'
require_text "$SHELL_QML" 'showTime: root.lockShowTime' \
    'lock surfaces do not receive time visibility state'
require_text "$SHELL_QML" 'showDate: root.lockShowDate' \
    'lock surfaces do not receive date visibility state'
require_text "$SHELL_QML" 'showUsername: root.lockShowUsername' \
    'lock surfaces do not receive username visibility state'
require_text "$SHELL_QML" 'showWeather: root.lockShowWeather' \
    'lock surfaces do not receive weather visibility state'
require_text "$SHELL_QML" 'weatherText: lockWeatherCache.summary' \
    'lock surfaces do not receive cached weather text'

# Real cursor stays hidden on the secure surface. Replacement visuals and
# displacement physics are presentation-only and live in the shared scene.
require_text "$SURFACE_QML" 'cursorShape: Qt.BlankCursor' \
    'lockscreen exposes the real pointer'
require_text "$SCENE_QML" 'readonly property int ghostTrailLength: 6' \
    'ghost cursor does not use the fixed six-sample trail'
require_text "$SCENE_QML" 'readonly property int pointerUpdateIntervalMs: 16' \
    'pointer interaction is not throttled near one 60 Hz update'
require_text "$SCENE_QML" 'readonly property int cursorFadeDelayMs: 180' \
    'ghost cursor fade does not begin at the approved idle delay'
require_text "$SCENE_QML" 'readonly property int cursorFadeDurationMs: 320' \
    'ghost cursor fade does not finish near 500 ms total idle time'
require_text "$SCENE_QML" 'readonly property real pointerInfluenceRadius: 72 * uiScale' \
    'pointer influence radius is not explicitly bounded'
require_text "$SCENE_QML" 'readonly property real pointerDisplacementCap: 24 * uiScale' \
    'pointer displacement is not explicitly bounded'
require_text "$SCENE_QML" 'readonly property real clickInfluenceRadius: 110 * uiScale' \
    'click influence radius is not explicitly stronger than pointer motion'
require_text "$SCENE_QML" 'readonly property real clickDisplacementCap: 38 * uiScale' \
    'click displacement cap is not explicitly stronger than pointer motion'
require_text "$SCENE_QML" 'readonly property real audioDisplacementCap: 6 * uiScale' \
    'audio displacement is not explicitly bounded'
require_text "$SURFACE_QML" 'required property bool mouseInteractive' \
    'lock surface has no independent mouse-interaction input'
require_text "$SCENE_QML" 'readonly property bool pointerEffectsEnabled: mouseInteractive && pointerActive' \
    'pointer effects do not obey the independent Mouse Interaction toggle'
require_text "$SCENE_QML" 'readonly property bool audioEffectsEnabled: audioReactive && audioLevel > audioSilenceThreshold' \
    'audio effects do not obey the independent Audio Reactive toggle'
reject_text "$SCENE_QML" 'readonly property bool interactiveEffectsEnabled: root.animationPreference !== "off"' \
    'Lockscreen Animation Off still acts as the pointer/audio master switch'
require_text "$SCENE_QML" 'property real pointerOffsetX: 0' \
    'wordmark cells have no pointer displacement state'
require_text "$SCENE_QML" 'property real pointerOffsetY: 0' \
    'wordmark cells have no pointer displacement state'
require_text "$SCENE_QML" 'readonly property real audioOffsetX:' \
    'wordmark cells have no audio displacement state'
require_text "$SCENE_QML" 'readonly property real audioOffsetY:' \
    'wordmark cells have no audio displacement state'
require_text "$SCENE_QML" 'function applyClickImpulse(x, y)' \
    'shared scene has no distinct click impulse path'
require_text "$SCENE_QML" 'function handlePointerClick(x, y)' \
    'shared scene does not turn a click into an interaction event'
require_text "$SURFACE_QML" 'scene.handlePointerClick(mouse.x, mouse.y)' \
    'secure lock surface still drops pointer clicks before logo physics'
require_text "$SURFACE_QML" 'password.forceActiveFocus()' \
    'click interaction no longer preserves password focus'
require_text "$SCENE_QML" 'NumberAnimation on pointerOffsetX' \
    'pointer X displacement has no return-to-rest animation'
require_text "$SCENE_QML" 'NumberAnimation on pointerOffsetY' \
    'pointer Y displacement has no return-to-rest animation'

# Optional metadata remains independent from animation/effect preferences.
# LockSurface carries the normalized visibility inputs; LockScene renders them.
require_text "$SURFACE_QML" 'required property bool showTime' \
    'lock surface has no optional time property'
require_text "$SURFACE_QML" 'required property bool showDate' \
    'lock surface has no optional date property'
require_text "$SURFACE_QML" 'required property bool showUsername' \
    'lock surface has no optional username property'
require_text "$SURFACE_QML" 'required property bool showWeather' \
    'lock surface has no optional weather property'
require_text "$SURFACE_QML" 'required property string weatherText' \
    'lock surface has no cached weather text input'
require_text "$SCENE_QML" 'root.showWeather && root.weatherText.length > 0' \
    'weather metadata does not fail closed when the local cache is empty'
require_text "$SCENE_QML" 'Quickshell.env("USER")' \
    'optional username does not read the current local session user'

# Weather is cache-only inside the lock process. It never performs geolocation or
# a network request while the session is locked.
require_file "$WEATHER_QML" 'lockscreen weather cache reader QML is missing'
require_text "$WEATHER_QML" 'lockscreen-weather.json' \
    'weather cache reader does not use the dedicated local cache'
require_text "$WEATHER_QML" 'FileView {' \
    'weather cache reader is not file-backed'
reject_text "$WEATHER_QML" 'curl' \
    'lockscreen weather cache reader performs a network request'
reject_text "$WEATHER_QML" 'http://' \
    'lockscreen weather cache reader contains a network URL'
reject_text "$WEATHER_QML" 'https://' \
    'lockscreen weather cache reader contains a network URL'
reject_text "$WEATHER_QML" 'geolocation' \
    'lockscreen weather cache reader contains location inference'

# Audio must come from a real output analyzer and fail closed to static visuals.
require_file "$AUDIO_QML" 'lockscreen audio analyzer QML is missing'
require_file "$CAVA_CONFIG" 'lockscreen CAVA configuration is missing'
require_file "$AUDIO_HELPER" 'lockscreen audio helper is missing'
require_text "$AUDIO_QML" 'property real low: 0' \
    'audio analyzer does not expose normalized low energy'
require_text "$AUDIO_QML" 'property real mid: 0' \
    'audio analyzer does not expose normalized mid energy'
require_text "$AUDIO_QML" 'property real high: 0' \
    'audio analyzer does not expose normalized high energy'
require_text "$AUDIO_QML" 'property real overall: 0' \
    'audio analyzer does not expose normalized overall energy'
require_text "$AUDIO_QML" 'command: [root.helper]' \
    'audio analyzer does not use the dedicated helper'
require_text "$AUDIO_QML" 'stdout: SplitParser {' \
    'audio analyzer does not consume streaming spectrum frames'
require_text "$AUDIO_HELPER" 'command -v cava >/dev/null 2>&1 || exit 0' \
    'audio helper does not safely tolerate missing CAVA'
reject_text "$AUDIO_HELPER" 'microphone' \
    'audio helper contains microphone capture behavior'
require_text "$CAVA_CONFIG" 'method = pipewire' \
    'CAVA config does not use PipeWire input'
require_text "$CAVA_CONFIG" 'source = auto' \
    'CAVA config does not monitor the automatic/default output source'
require_text "$CAVA_CONFIG" 'bars = 8' \
    'CAVA config does not cap spectrum to eight bands'
require_text "$CAVA_CONFIG" 'framerate = 30' \
    'CAVA config does not cap analysis near 30 FPS'
require_text "$CAVA_CONFIG" 'method = raw' \
    'CAVA config does not use raw analyzer output'
require_text "$CAVA_CONFIG" 'data_format = ascii' \
    'CAVA config does not use parseable ASCII frames'
require_text "$CAVA_CONFIG" 'channels = mono' \
    'CAVA config is not reduced to one averaged channel'

# Lock authentication remains isolated from all optional state.
for token in audioLow LockAudioAnalyzer LockWeatherCache weatherText mouseInteractive; do
    reject_text "${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml" "$token" \
        "authentication owner was coupled to optional lockscreen state: $token"
done

printf 'PASS: lockscreen interactive effects contracts\n'
