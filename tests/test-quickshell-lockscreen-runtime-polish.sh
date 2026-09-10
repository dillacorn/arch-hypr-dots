#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
COLOR_PICKER="${ROOT}/config/quickshell/awtarchy/InlineColorPicker.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
PICKER_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
CONTRAST_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_contrast.sh"
LOCK_WALLPAPER="${ROOT}/config/quickshell/awtarchy-lock/LockWallpaperState.qml"
PREVIEW_WALLPAPER="${ROOT}/config/quickshell/awtarchy/LockPreviewWallpaperState.qml"
LOCK_CONTRAST="${ROOT}/config/quickshell/awtarchy-lock/LockContrastCache.qml"
LOCK_SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
LOCK_AUTH="${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml"
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

# Dedicated state: lockscreen wallpaper must never follow desktop Awtwall state.
require_text "$APP_STATE" 'LOCKSCREEN_BACKGROUNDS_JSON=' \
    'state helper has no lockscreen background allowlist'
require_text "$APP_STATE" '"black","wallpaper","color"' \
    'custom solid-color background mode is not allowed'
require_text "$APP_STATE" 'lockscreen_background_color' \
    'state helper does not persist a custom background color'
require_text "$APP_STATE" 'lockscreen_wallpaper_path' \
    'state helper does not persist a dedicated lockscreen wallpaper path'
require_text "$APP_STATE" 'set-lockscreen-background-color)' \
    'state helper has no custom background-color command'
require_text "$APP_STATE" 'set-lockscreen-wallpaper)' \
    'state helper has no atomic dedicated lockscreen wallpaper command'

run_state set-lockscreen-background color
jq -e '.lockscreen_background == "color"' "$state_file" >/dev/null \
    || fail 'custom color background mode did not persist'
run_state set-lockscreen-background-color '#336699'
jq -e '.lockscreen_background_color == "#336699"' "$state_file" >/dev/null \
    || fail 'custom background color did not persist'
color_before="$(sha256sum "$state_file" | awk '{print $1}')"
if run_state set-lockscreen-background-color 'red' >/dev/null 2>&1; then
    fail 'invalid background color was accepted'
fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$color_before" ]] \
    || fail 'invalid background color changed persistent state'

wallpaper="$TMP/home/lockscreen image.png"
printf 'not-an-image-but-a-real-local-file\n' >"$wallpaper"
run_state set-lockscreen-wallpaper "$wallpaper"
jq -e --arg wallpaper "$wallpaper" \
    '.lockscreen_background == "wallpaper" and .lockscreen_wallpaper_path == $wallpaper' \
    "$state_file" >/dev/null || fail 'dedicated lockscreen wallpaper did not persist atomically'
wallpaper_before="$(sha256sum "$state_file" | awk '{print $1}')"
if run_state set-lockscreen-wallpaper '../relative.png' >/dev/null 2>&1; then
    fail 'relative lockscreen wallpaper path was accepted'
fi
if run_state set-lockscreen-wallpaper "$TMP/home/missing.png" >/dev/null 2>&1; then
    fail 'missing lockscreen wallpaper path was accepted'
fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$wallpaper_before" ]] \
    || fail 'invalid lockscreen wallpaper changed persistent state'

require_text "$BAR_STATE" 'lockscreen_background_color: "#000000"' \
    'BarState has no stock custom background color'
require_text "$BAR_STATE" 'lockscreen_wallpaper_path: ""' \
    'BarState has no dedicated lockscreen wallpaper default'
require_text "$BAR_STATE" 'function lockscreenBackgroundColor()' \
    'BarState has no validated custom background-color reader'
require_text "$BAR_STATE" 'function lockscreenWallpaperPath()' \
    'BarState has no validated dedicated wallpaper reader'

require_file "$LOCK_WALLPAPER" 'secure lock wallpaper reader is missing'
require_file "$PREVIEW_WALLPAPER" 'desktop preview wallpaper reader is missing'
reject_text "$LOCK_WALLPAPER" 'backend_state.tsv' \
    'secure lock wallpaper still follows desktop Awtwall backend state'
require_text "$LOCK_WALLPAPER" 'property string path:' \
    'secure lock wallpaper reader has no dedicated path input'
cmp -s "$LOCK_WALLPAPER" "$PREVIEW_WALLPAPER" \
    || fail 'secure and preview wallpaper readers diverge'

# Awtwall integration must be selection-only and return the exact draft path.
require_file "$PICKER_HELPER" 'selection-only lockscreen wallpaper picker helper is missing'
bash -n "$PICKER_HELPER" || fail 'selection-only wallpaper picker helper has invalid Bash syntax'
require_text "$PICKER_HELPER" '--select-only' \
    'lockscreen wallpaper picker does not use Awtwall selection-only mode'
require_text "$PICKER_HELPER" '--type' \
    'lockscreen wallpaper picker does not filter to images'
require_text "$PICKER_HELPER" 'images' \
    'lockscreen wallpaper picker does not request image media'
require_text "$PICKER_HELPER" '--select-result' \
    'lockscreen wallpaper picker has no detached result path'
require_text "$PICKER_HELPER" '--help' \
    'lockscreen wallpaper picker does not verify Awtwall selection-only capability'
reject_text "$PICKER_HELPER" 'set-lockscreen-wallpaper' \
    'wallpaper picker helper persists state instead of returning an editor draft'
require_text "$EDITOR" 'wallpaperPickerProcess' \
    'editor has no selection-only wallpaper picker process'
require_text "$EDITOR" 'stdout: SplitParser {' \
    'editor does not consume the selected wallpaper result'
require_text "$EDITOR" 'draftWallpaperPath' \
    'editor has no lockscreen-specific wallpaper draft'
require_text "$EDITOR" 'draftBackgroundMode' \
    'editor has no background-mode draft'
require_text "$EDITOR" 'draftBackgroundColor' \
    'editor has no custom background-color draft'
require_text "$EDITOR" 'quickshell_lockscreen_wallpaper_picker.sh' \
    'editor does not launch the selection-only wallpaper helper'
reject_text "$QUICK_SETTINGS" 'label: "Choose with Awtwall"' \
    'Quick Settings still duplicates lockscreen wallpaper selection outside the editor'

# Element/editor controls.
require_text "$EDITOR" 'function resetElementPosition(name)' \
    'editor has no per-element Reset Position action'
require_text "$EDITOR" 'label: "Reset Position"' \
    'editor does not expose per-element Reset Position'
require_text "$EDITOR" 'label: "Auto All"' \
    'editor has no global Auto All contrast action'
require_text "$EDITOR" 'label: "White All"' \
    'editor has no global White All contrast action'
require_text "$EDITOR" 'label: "Black All"' \
    'editor has no global Black All contrast action'
require_text "$EDITOR" 'function setAllDraftColors(' \
    'editor has no global element-color setter'
require_text "$EDITOR" 'selectedElement === "logo"' \
    'editor does not make Logo visibility explicit when Logo is selected'
require_text "$EDITOR" 'Password cannot be hidden' \
    'editor no longer communicates the password visibility invariant'

require_file "$COLOR_PICKER" 'reusable inline lockscreen color picker is missing'
require_text "$COLOR_PICKER" 'property real hue:' \
    'inline color picker has no hue control state'
require_text "$COLOR_PICKER" 'property real saturation:' \
    'inline color picker has no saturation control state'
require_text "$COLOR_PICKER" 'property real value:' \
    'inline color picker has no value/brightness control state'
require_text "$COLOR_PICKER" 'MouseArea {' \
    'inline color picker has no draggable palette interaction'
require_text "$COLOR_PICKER" '#RRGGBB' \
    'inline color picker has no editable hex path'
require_text "$EDITOR" 'InlineColorPicker {' \
    'editor does not use the reusable color picker'
require_text "$EDITOR" 'backgroundColorPicker' \
    'editor has no expandable custom background palette'
require_text "$EDITOR" 'elementColorPicker' \
    'editor has no expandable per-element custom palette'

# Secure presentation accepts custom backgrounds and per-element cached Auto colors.
require_text "$LOCK_SCENE" 'required property color backgroundColor' \
    'LockScene has no custom solid background color input'
require_text "$LOCK_SCENE" 'required property var autoAccents' \
    'LockScene has no per-element Auto contrast input map'
require_text "$LOCK_SCENE" 'root.autoAccents[name]' \
    'LockScene does not resolve Auto color per element'
require_text "$LOCK_SCENE" 'root.backgroundMode === "color" ? root.backgroundColor : "#000000"' \
    'LockScene does not render custom solid backgrounds with black fallback'
cmp -s "$LOCK_SCENE" "$PREVIEW_SCENE" \
    || fail 'secure and preview presentation scenes diverge'

require_file "$LOCK_CONTRAST" 'secure lock contrast cache reader is missing'
require_text "$LOCK_CONTRAST" 'function colorFor(name)' \
    'contrast cache does not expose per-element colors'
require_text "$LOCK_CONTRAST" 'colors' \
    'contrast cache does not parse a per-element color map'
for forbidden in 'curl' 'http://' 'https://' 'magick '; do
    reject_text "$LOCK_CONTRAST" "$forbidden" \
        "secure contrast reader performs unlocked-only work: $forbidden"
done

require_file "$CONTRAST_HELPER" 'unlocked contrast helper is missing'
bash -n "$CONTRAST_HELPER" || fail 'contrast helper has invalid Bash syntax'
require_text "$CONTRAST_HELPER" 'lockscreen_wallpaper_path' \
    'contrast helper does not use dedicated lockscreen wallpaper state'
require_text "$CONTRAST_HELPER" 'lockscreen_background_color' \
    'contrast helper does not account for custom solid background color'
require_text "$CONTRAST_HELPER" 'lockscreen_layout' \
    'contrast helper does not sample at saved element positions'
require_text "$CONTRAST_HELPER" 'logo time date username weather password' \
    'contrast helper does not calculate every lockscreen subject independently'
require_text "$CONTRAST_HELPER" 'colors' \
    'contrast helper does not write per-element contrast JSON'
require_text "$CONTRAST_HELPER" 'magick' \
    'contrast helper does not sample wallpaper regions in unlocked mode'

# Security boundary is unchanged.
require_text "$LOCK_SHELL" 'WlSessionLock {' \
    'secure shell no longer owns WlSessionLock'
require_text "$LOCK_SHELL" 'LockAuth {' \
    'secure shell no longer constructs LockAuth'
for token in lockscreen_wallpaper_path lockscreen_background_color InlineColorPicker wallpaperPickerProcess; do
    reject_text "$LOCK_AUTH" "$token" \
        "LockAuth was coupled to presentation state: $token"
done

printf 'PASS: lockscreen runtime polish contracts\n'
