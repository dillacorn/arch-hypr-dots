#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
AUDIO_QML="${ROOT}/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"
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
check_bool_setting set-lockscreen-show-time lockscreen_show_time
check_bool_setting set-lockscreen-show-date lockscreen_show_date
check_bool_setting set-lockscreen-show-username lockscreen_show_username

# Stock state is minimal except for audio response, which is enabled by default.
require_text "$BAR_STATE" 'lockscreen_audio_reactive: true' \
    'BarState stock audio-reactive default is not enabled'
require_text "$BAR_STATE" 'lockscreen_show_time: false' \
    'BarState stock time default is not disabled'
require_text "$BAR_STATE" 'lockscreen_show_date: false' \
    'BarState stock date default is not disabled'
require_text "$BAR_STATE" 'lockscreen_show_username: false' \
    'BarState stock username default is not disabled'
require_text "$BAR_STATE" 'function lockscreenAudioReactiveEnabled()' \
    'BarState does not expose normalized audio-reactive state'
require_text "$BAR_STATE" 'function lockscreenShowTime()' \
    'BarState does not expose normalized time state'
require_text "$BAR_STATE" 'function lockscreenShowDate()' \
    'BarState does not expose normalized date state'
require_text "$BAR_STATE" 'function lockscreenShowUsername()' \
    'BarState does not expose normalized username state'

# Controls stay in the existing Lockscreen Animation area and persist immediately.
require_text "$QUICK_SETTINGS" 'text: "Audio Reactive"' \
    'Quick Settings has no Audio Reactive lockscreen toggle'
require_text "$QUICK_SETTINGS" 'text: "Time"' \
    'Quick Settings has no Time lockscreen toggle'
require_text "$QUICK_SETTINGS" 'text: "Date"' \
    'Quick Settings has no Date lockscreen toggle'
require_text "$QUICK_SETTINGS" 'text: "Username"' \
    'Quick Settings has no Username lockscreen toggle'
for command in \
    set-lockscreen-audio-reactive \
    set-lockscreen-show-time \
    set-lockscreen-show-date \
    set-lockscreen-show-username; do
    require_text "$QUICK_SETTINGS" "\"${command}\"" \
        "Quick Settings does not persist ${command}"
done
require_text "$QUICK_SETTINGS" 'BarState.lockscreenAnimationPreference() !== "off"' \
    'Audio Reactive control is not visually suppressed by the animation master switch'

# The dedicated lock process loads the shared preferences once and owns one analyzer.
require_text "$SHELL_QML" 'property bool lockAudioReactive: true' \
    'lock shell has no stock-enabled audio-reactive preference'
require_text "$SHELL_QML" 'property bool lockShowTime: false' \
    'lock shell has no stock-disabled time preference'
require_text "$SHELL_QML" 'property bool lockShowDate: false' \
    'lock shell has no stock-disabled date preference'
require_text "$SHELL_QML" 'property bool lockShowUsername: false' \
    'lock shell has no stock-disabled username preference'
require_text "$SHELL_QML" 'LockAudioAnalyzer {' \
    'lock shell does not own the audio analyzer'
require_text "$SHELL_QML" 'id: lockAudioAnalyzer' \
    'lock shell audio analyzer has no single root owner'
require_text "$SHELL_QML" 'enabled: root.lockAudioReactive && root.lockAnimationPreference !== "off"' \
    'audio analyzer does not obey Audio Reactive plus animation master state'
require_text "$SHELL_QML" 'audioLow: lockAudioAnalyzer.low' \
    'lock surfaces do not receive low-band audio state'
require_text "$SHELL_QML" 'showTime: root.lockShowTime' \
    'lock surfaces do not receive time visibility state'
require_text "$SHELL_QML" 'showDate: root.lockShowDate' \
    'lock surfaces do not receive date visibility state'
require_text "$SHELL_QML" 'showUsername: root.lockShowUsername' \
    'lock surfaces do not receive username visibility state'

# Real cursor stays hidden. The replacement visual is bounded and surface-local.
require_text "$SURFACE_QML" 'cursorShape: Qt.BlankCursor' \
    'lockscreen exposes the real pointer'
require_text "$SURFACE_QML" 'readonly property int ghostTrailLength: 6' \
    'ghost cursor does not use the fixed six-sample trail'
require_text "$SURFACE_QML" 'readonly property int pointerUpdateIntervalMs: 16' \
    'pointer interaction is not throttled near one 60 Hz update'
require_text "$SURFACE_QML" 'readonly property int cursorFadeDelayMs: 180' \
    'ghost cursor fade does not begin at the approved idle delay'
require_text "$SURFACE_QML" 'readonly property int cursorFadeDurationMs: 320' \
    'ghost cursor fade does not finish near 500 ms total idle time'
require_text "$SURFACE_QML" 'readonly property real pointerInfluenceRadius: 72 * root.uiScale' \
    'pointer influence radius is not explicitly bounded'
require_text "$SURFACE_QML" 'readonly property real pointerDisplacementCap: 24 * root.uiScale' \
    'pointer displacement is not explicitly bounded'
require_text "$SURFACE_QML" 'readonly property real audioDisplacementCap: 6 * root.uiScale' \
    'audio displacement is not explicitly bounded'
require_text "$SURFACE_QML" 'readonly property bool interactiveEffectsEnabled: root.animationPreference !== "off"' \
    'Lockscreen Animation Off is not the pointer/audio master switch'
require_text "$SURFACE_QML" 'property real pointerOffsetX: 0' \
    'wordmark cells have no pointer displacement state'
require_text "$SURFACE_QML" 'property real pointerOffsetY: 0' \
    'wordmark cells have no pointer displacement state'
require_text "$SURFACE_QML" 'readonly property real audioOffsetX:' \
    'wordmark cells have no audio displacement state'
require_text "$SURFACE_QML" 'readonly property real audioOffsetY:' \
    'wordmark cells have no audio displacement state'
require_text "$SURFACE_QML" 'NumberAnimation on pointerOffsetX' \
    'pointer X displacement has no return-to-rest animation'
require_text "$SURFACE_QML" 'NumberAnimation on pointerOffsetY' \
    'pointer Y displacement has no return-to-rest animation'

# Optional metadata must exist but remain independent of the animation master.
require_text "$SURFACE_QML" 'required property bool showTime' \
    'lock surface has no optional time property'
require_text "$SURFACE_QML" 'required property bool showDate' \
    'lock surface has no optional date property'
require_text "$SURFACE_QML" 'required property bool showUsername' \
    'lock surface has no optional username property'
require_text "$SURFACE_QML" 'readonly property bool metadataVisible: root.showTime || root.showDate || root.showUsername' \
    'metadata stack does not collapse when all options are disabled'
require_text "$SURFACE_QML" 'Quickshell.env("USER")' \
    'optional username does not read the current local session user'
reject_text "$SURFACE_QML" 'weather' \
    'interactive-effects slice introduced weather/network behavior'

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

# Lock authentication remains isolated from all analyzer state.
reject_text "${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml" 'audioLow' \
    'authentication owner was coupled to audio state'
reject_text "${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml" 'LockAudioAnalyzer' \
    'authentication owner was coupled to analyzer lifecycle'

printf 'PASS: lockscreen interactive effects contracts\n'
