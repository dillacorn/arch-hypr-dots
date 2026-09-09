#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR_QML="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
PREVIEW_WALLPAPER="${ROOT}/config/quickshell/awtarchy/LockPreviewWallpaperState.qml"
LOCK_SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
LOCK_WALLPAPER="${ROOT}/config/quickshell/awtarchy-lock/LockWallpaperState.qml"

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

require_file "$EDITOR_QML" 'unlocked LockscreenEditor.qml is missing'
require_file "$LOCK_SCENE" 'secure lock presentation scene is missing'
require_file "$LOCK_WALLPAPER" 'secure lock wallpaper state is missing'

reject_text "$EDITOR_QML" 'import "../awtarchy-lock"' \
    'desktop editor crosses the Quickshell configuration boundary into awtarchy-lock'
require_text "$EDITOR_QML" 'LockPreviewScene {' \
    'desktop editor does not use its config-local lock preview scene'
require_text "$EDITOR_QML" 'LockPreviewWallpaperState {' \
    'desktop editor does not use its config-local wallpaper preview state'

require_file "$PREVIEW_SCENE" 'desktop editor preview scene is missing'
require_file "$PREVIEW_WALLPAPER" 'desktop editor wallpaper preview state is missing'
cmp -s "$LOCK_SCENE" "$PREVIEW_SCENE" \
    || fail 'desktop preview scene drifted from the secure lock presentation scene'
cmp -s "$LOCK_WALLPAPER" "$PREVIEW_WALLPAPER" \
    || fail 'desktop wallpaper preview state drifted from the secure lock wallpaper state'

for forbidden in WlSessionLock LockAuth auth.submit; do
    reject_text "$PREVIEW_SCENE" "$forbidden" \
        "desktop preview scene crosses the secure lock boundary: $forbidden"
done

printf 'PASS: lockscreen editor Quickshell config boundary\n'
