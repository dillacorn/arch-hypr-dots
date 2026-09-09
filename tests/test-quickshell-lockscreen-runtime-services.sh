#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_SHELL="${ROOT}/config/quickshell/awtarchy/shell.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
WEATHER="${ROOT}/config/quickshell/awtarchy/LockscreenWeather.qml"
WALLPAPER="${ROOT}/config/quickshell/awtarchy-lock/LockWallpaperState.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
LOCK_SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"

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

# RED gate: unlocked weather refresh ownership and local Awtwall wallpaper state
# must exist as explicit components rather than placeholders.
require_file "$WEATHER" 'unlocked LockscreenWeather singleton is missing'
require_file "$WALLPAPER" 'local LockWallpaperState reader is missing'

# Unlocked weather refresh is rate-limited and only uses the dedicated helper.
require_text "$WEATHER" 'pragma Singleton' \
    'LockscreenWeather is not an unlocked-session singleton'
require_text "$WEATHER" 'quickshell_lockscreen_weather.sh' \
    'LockscreenWeather does not use the dedicated weather helper'
require_text "$WEATHER" 'BarState.lockscreenShowWeather()' \
    'LockscreenWeather does not honor the saved Weather toggle'
require_text "$WEATHER" 'BarState.lockscreenWeatherLocation()' \
    'LockscreenWeather does not use the explicit saved location'
require_text "$WEATHER" 'interval: 1200000' \
    'LockscreenWeather refresh cadence is more frequent than the 20-minute floor'
require_text "$WEATHER" 'Connections {' \
    'LockscreenWeather does not react to saved state changes'
require_text "$WEATHER" 'target: BarState' \
    'LockscreenWeather does not watch BarState changes'
reject_text "$WEATHER" 'WlSessionLock' \
    'unlocked weather refresh component owns lock authority'
reject_text "$WEATHER" 'LockAuth' \
    'unlocked weather refresh component references PAM'
require_text "$DESKTOP_SHELL" 'LockscreenWeather !== null' \
    'desktop shell does not force weather singleton construction'
reject_text "$LOCK_SHELL" 'quickshell_lockscreen_weather.sh' \
    'secure lock shell launches the network weather helper'

# Wallpaper source is strictly local Awtwall state. It must never accept a URL
# from the state file and the scene must retain its black-first fallback.
require_text "$WALLPAPER" '/.config/awtwall/backend_state.tsv' \
    'LockWallpaperState does not read Awtwall backend state'
require_text "$WALLPAPER" 'FileView {' \
    'LockWallpaperState is not file-backed'
require_text "$WALLPAPER" 'startsWith("/")' \
    'LockWallpaperState does not require an absolute local path'
require_text "$WALLPAPER" 'indexOf("://")' \
    'LockWallpaperState does not explicitly reject URL-style sources'
require_text "$WALLPAPER" 'encodeURI("file://" + path)' \
    'LockWallpaperState does not convert local paths to file URLs safely'
for forbidden in curl wget http:// https://; do
    reject_text "$WALLPAPER" "$forbidden" \
        "LockWallpaperState contains network behavior: $forbidden"
done
require_text "$LOCK_SHELL" 'LockWallpaperState {' \
    'secure lock shell does not own a local wallpaper-state reader'
require_text "$LOCK_SHELL" 'wallpaperSource: lockWallpaperState.source' \
    'secure lock surfaces do not receive the local wallpaper source'
require_text "$EDITOR" 'LockUi.LockWallpaperState {' \
    'lockscreen editor does not use the same local wallpaper-state reader'
require_text "$EDITOR" 'wallpaperSource: wallpaperState.source' \
    'lockscreen editor preview does not receive the local wallpaper source'
require_text "$LOCK_SCENE" 'color: "#000000"' \
    'shared scene no longer has a black wallpaper fallback'

printf 'PASS: lockscreen runtime service contracts\n'
