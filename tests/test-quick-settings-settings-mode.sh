#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
FLYOUT_SETTINGS="$ROOT/config/quickshell/awtarchy/FlyoutSettings.qml"
BAR_SETTINGS="$ROOT/config/quickshell/awtarchy/BarSettingsSection.qml"
MANAGER="$ROOT/config/hypr/scripts/quickshell.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

contains "$QUICK_SETTINGS" 'visible: !root.settingsOpen' \
    'normal Quick Settings content is not hidden while settings mode is open'
contains "$FLYOUT_SETTINGS" 'text: root.surfaceLabel === "Quick Settings" ? "Copy Quick Settings…" : "Copy to Displays…"' \
    'generic Quick Settings copy action is not clearly scoped'
contains "$BAR_SETTINGS" 'label: "Copy Bar Settings…"' \
    'Bar Settings has no dedicated copy action'
contains "$BAR_SETTINGS" 'copy-bar-settings' \
    'Bar Settings copy action is not persisted through the existing manager'
contains "$MANAGER" 'copy-bar-settings)' \
    'quickshell manager has no copy-bar-settings command'
contains "$MANAGER" 'bar_transparency' \
    'bar-settings copy does not include transparency state'
contains "$MANAGER" 'show_cpu' \
    'bar-settings copy does not include system-stat visibility'

if grep -A80 -F 'copy_bar_settings()' "$MANAGER" | grep -Fq 'display_scale'; then
    fail 'bar-settings copy must not copy display scale'
fi

printf '%s\n' 'PASS: Quick Settings settings mode is isolated and copy actions have explicit scopes.'
