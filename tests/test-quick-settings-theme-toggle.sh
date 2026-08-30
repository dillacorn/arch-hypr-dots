#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
THEME_PICKER="$ROOT/config/quickshell/awtarchy/ThemePicker.qml"
HISTORY="$ROOT/local/share/awtarchy/quickshell-managed-history.sha256"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

not_contains() {
    if grep -Fq -- "$2" "$1"; then
        fail "$3"
    fi
}

contains "$THEME_PICKER" 'readonly property bool open: pickerWindow.visible' \
    'Theme Picker does not expose its open state'
contains "$THEME_PICKER" 'function toggleForScreen(target)' \
    'Theme Picker cannot toggle itself for a requested display'
contains "$THEME_PICKER" 'function toggleFocused() { toggleForScreen(focusedScreen()); }' \
    'Theme Picker focused toggle does not reuse the screen-aware toggle path'
contains "$QUICK" 'ThemePicker.toggleForScreen(activeScreen);' \
    'Quick Settings Themes action still only opens instead of toggling the Theme Picker'
contains "$QUICK" 'active: ThemePicker.open' \
    'Quick Settings Themes button does not visually reflect an open Theme Picker'
not_contains "$QUICK" 'ThemePicker.openForScreen(activeScreen);' \
    'Quick Settings Themes action still uses the one-way open path'

for rel in \
    .config/quickshell/awtarchy/QuickSettings.qml \
    .config/quickshell/awtarchy/ThemePicker.qml
do
    source_file="$ROOT/config/${rel#.config/}"
    digest="$(sha256sum "$source_file" | awk '{print $1}')"
    grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY" \
        || fail "managed history is missing current hash for $rel"
done

printf '%s\n' 'PASS: Quick Settings Themes button toggles the screen-aware Theme Picker and reflects open state.'
