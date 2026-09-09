#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

managed_files=(
    'config/hypr/scripts/quickshell_application_state.sh:.config/hypr/scripts/quickshell_application_state.sh'
    'config/hypr/scripts/quickshell_lockscreen_audio.sh:.config/hypr/scripts/quickshell_lockscreen_audio.sh'
    'config/hypr/scripts/quickshell_lockscreen_weather.sh:.config/hypr/scripts/quickshell_lockscreen_weather.sh'
    'config/quickshell/awtarchy/shell.qml:.config/quickshell/awtarchy/shell.qml'
    'config/quickshell/awtarchy/BarState.qml:.config/quickshell/awtarchy/BarState.qml'
    'config/quickshell/awtarchy/QuickSettings.qml:.config/quickshell/awtarchy/QuickSettings.qml'
    'config/quickshell/awtarchy/LockscreenEditor.qml:.config/quickshell/awtarchy/LockscreenEditor.qml'
    'config/quickshell/awtarchy/LockscreenWeather.qml:.config/quickshell/awtarchy/LockscreenWeather.qml'
    'config/quickshell/awtarchy-lock/shell.qml:.config/quickshell/awtarchy-lock/shell.qml'
    'config/quickshell/awtarchy-lock/LockSurface.qml:.config/quickshell/awtarchy-lock/LockSurface.qml'
    'config/quickshell/awtarchy-lock/LockScene.qml:.config/quickshell/awtarchy-lock/LockScene.qml'
    'config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml:.config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml'
    'config/quickshell/awtarchy-lock/LockWeatherCache.qml:.config/quickshell/awtarchy-lock/LockWeatherCache.qml'
    'config/quickshell/awtarchy-lock/LockWallpaperState.qml:.config/quickshell/awtarchy-lock/LockWallpaperState.qml'
    'config/quickshell/awtarchy-lock/cava.conf:.config/quickshell/awtarchy-lock/cava.conf'
)

missing=0
for entry in "${managed_files[@]}"; do
    source_path="${entry%%:*}"
    installed_path="${entry#*:}"
    [[ -f "${ROOT}/${source_path}" ]] || fail "managed source is missing: ${source_path}"
    digest="$(sha256sum "${ROOT}/${source_path}" | awk '{print $1}')"
    history_entry="${digest}"$'\t'"${installed_path}"
    if ! grep -Fqx -- "$history_entry" "$HISTORY"; then
        printf 'MISSING_MANAGED_HASH %s\n' "$history_entry" >&2
        missing=1
    fi
done

(( missing == 0 )) || fail 'managed history is missing current lockscreen customization/editor stock hashes'

printf 'PASS: lockscreen customization/editor managed history\n'
