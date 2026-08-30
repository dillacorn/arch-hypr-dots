#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
FLYOUT="$ROOT/config/quickshell/awtarchy/FlyoutSettings.qml"
BAR_SETTINGS="$ROOT/config/quickshell/awtarchy/BarSettingsSection.qml"
POSITION="$ROOT/config/hypr/scripts/quickshell_flyout_position.sh"

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

contains "$QUICK" 'property bool barCustomizeOpen: false' \
    'Quick Settings does not own one unified Bar Customize expansion state'
contains "$QUICK" 'label: "Customize…"' \
    'Bar card does not expose the unified Customize action'
contains "$QUICK" 'label: "Themes"' \
    'Themes is not promoted to the Bar card header'
contains "$QUICK" 'Tip: drag the bar with SUPER+Mouse1 or ALT+Mouse1.' \
    'Bar position controls do not explain the mouse-drag shortcut'
contains "$QUICK" 'visible: root.barCustomizeOpen' \
    'Bar customization does not collapse behind the unified Customize action'
contains "$QUICK" 'id: barAppearanceSettings' \
    'Quick Settings does not own the embedded Bar appearance settings instance'

python3 - "$QUICK" <<'PY' || fail 'closing Quick Settings does not reset transient customization state'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start = text.index('    function close() {')
end = text.index('\n    }', start) + 6
block = text[start:end]
for needle in (
    'barCustomizeOpen = false;',
    'settingsPanel.resetCopySelection();',
    'barAppearanceSettings.resetTransientState();',
):
    if needle not in block:
        raise SystemExit(1)
PY

contains "$BAR_SETTINGS" 'function resetTransientState()' \
    'Bar appearance settings cannot reset copy/target transient state when the flyout closes'
not_contains "$BAR_SETTINGS" 'text: "Bar Appearance"' \
    'Bar appearance still renders a redundant nested Bar Appearance heading'
not_contains "$BAR_SETTINGS" 'label: "Themes"' \
    'Themes is still buried inside the Bar appearance expansion'
contains "$BAR_SETTINGS" 'label: "Reset"' \
    'Bar appearance Reset is missing from the advanced customization area'
contains "$BAR_SETTINGS" 'label: "Copy Bar Settings…"' \
    'Bar appearance lost its scoped copy action'

not_contains "$FLYOUT" 'implicitHeight: copyOpen ? 104' \
    'Copy Quick Settings still replaces the settings panel instead of expanding inline'
contains "$FLYOUT" 'text: "Copy to:"' \
    'inline Quick Settings copy selector has no Copy to label'
contains "$FLYOUT" 'visible: root.copyOpen' \
    'inline copy target row is not conditionally expanded'
contains "$FLYOUT" 'root.copyRequested(targets);' \
    'inline Quick Settings copy selector does not apply the selected targets'

contains "$QUICK" 'readonly property int minimumSettingsPanelHeight:' \
    'settings mode does not have a compact minimum independent of the normal panel'
contains "$QUICK" 'function clampSettingsHeight(value)' \
    'settings-mode height is still clamped through the normal 460px minimum'
contains "$QUICK" 'readonly property int settingsModePanelHeight: clampSettingsHeight(' \
    'settings-mode content height does not use the compact clamp'
contains "$POSITION" 'resize-compact' \
    'flyout positioning does not support a compact Quick Settings resize action'

printf '%s\n' 'PASS: Quick Settings uses compact edge-attached settings, inline copy targets, and one transient Bar customization flow.'
