#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
FLYOUT="$ROOT/config/quickshell/awtarchy/FlyoutSettings.qml"
DISPLAY_SCALE="$ROOT/config/quickshell/awtarchy/DisplayScaleSettings.qml"
BAR_SETTINGS="$ROOT/config/quickshell/awtarchy/BarSettingsSection.qml"
THEME_PICKER="$ROOT/config/quickshell/awtarchy/ThemePicker.qml"
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

contains "$QUICK" 'property bool barIconsOpen: false' \
    'Quick Settings does not own a dedicated Bar Icons expansion state'
contains "$QUICK" 'property bool barAppearanceOpen: false' \
    'Quick Settings does not own a dedicated Bar Appearance expansion state'
not_contains "$QUICK" 'property bool barCustomizeOpen: false' \
    'Quick Settings still owns the old combined Bar Customize expansion state'
contains "$QUICK" 'label: "Icons"' \
    'Bar card does not expose a dedicated Icons action'
contains "$QUICK" 'label: "Appearance"' \
    'Bar card does not expose a dedicated Appearance action'
contains "$QUICK" 'label: "Themes"' \
    'Themes is not promoted to the Bar card header'
contains "$QUICK" 'Position: SUPER+Mouse1 / ALT+Mouse1 drag · CTRL+SUPER+B / SUPER+ALT+B change edge' \
    'Bar position hint does not document mouse drag and keyboard edge changes'
contains "$QUICK" 'Auto-hide: CTRL+SUPER+ALT+B toggle' \
    'Bar auto-hide hint does not document the keyboard toggle'
contains "$QUICK" 'visible: root.barIconsOpen' \
    'Bar icon customization does not collapse behind the Icons action'
contains "$QUICK" 'visible: root.barAppearanceOpen' \
    'Bar appearance customization does not collapse behind the Appearance action'
contains "$QUICK" 'id: barAppearanceSettings' \
    'Quick Settings does not own the embedded Bar appearance settings instance'

python3 - "$QUICK" <<'PY' || fail 'Bar Icons and Appearance buttons are not mutually exclusive'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
icons = text.index('label: "Icons"')
appearance = text.index('label: "Appearance"', icons + 1)
icons_block = text[icons:appearance]
appearance_block = text[appearance:text.index('label: root.barStatus.enabled ? "Visible" : "Hidden"', appearance)]
if 'root.barIconsOpen = !root.barIconsOpen;' not in icons_block:
    raise SystemExit(1)
if 'root.barAppearanceOpen = false;' not in icons_block:
    raise SystemExit(1)
if 'root.barAppearanceOpen = !root.barAppearanceOpen;' not in appearance_block:
    raise SystemExit(1)
if 'root.barIconsOpen = false;' not in appearance_block:
    raise SystemExit(1)
PY

contains "$THEME_PICKER" 'readonly property bool open: pickerWindow.visible' \
    'Theme Picker does not expose its open state to the Quick Settings Themes button'
contains "$THEME_PICKER" 'function toggleForScreen(target)' \
    'Theme Picker cannot toggle itself for the current Quick Settings display'
contains "$THEME_PICKER" 'function toggleFocused() { toggleForScreen(focusedScreen()); }' \
    'Theme Picker focused toggle does not share the screen-aware toggle path'
contains "$QUICK" 'ThemePicker.toggleForScreen(activeScreen);' \
    'Quick Settings Themes action still only opens instead of toggling the Theme Picker'
contains "$QUICK" 'active: ThemePicker.open' \
    'Quick Settings Themes button does not visually reflect an open Theme Picker'
not_contains "$QUICK" 'ThemePicker.openForScreen(activeScreen);' \
    'Quick Settings Themes action still uses the one-way open path'

python3 - "$QUICK" <<'PY' || fail 'closing Quick Settings does not reset all transient customization state'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start = text.index('    function close() {')
end = text.index('\n    }', start) + 6
block = text[start:end]
for needle in (
    'barIconsOpen = false;',
    'barAppearanceOpen = false;',
    'settingsPanel.resetTransientState();',
    'barAppearanceSettings.resetTransientState();',
    'brightnessHoverPercent = -1;',
    'outputVolumeHoverPercent = -1;',
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
contains "$FLYOUT" 'function resetTransientState()' \
    'Quick Settings settings panel has no unified transient reset contract'
contains "$FLYOUT" 'displayScaleSection.resetTransientState();' \
    'Quick Settings settings reset does not collapse the custom Display Scale editor'
contains "$DISPLAY_SCALE" 'function resetTransientState()' \
    'Display Scale custom editor cannot be reset when Quick Settings closes'

contains "$QUICK" 'readonly property int minimumSettingsPanelHeight:' \
    'settings mode does not have a compact minimum independent of the normal panel'
contains "$QUICK" 'function clampSettingsHeight(value)' \
    'settings-mode height is still clamped through the normal 460px minimum'
contains "$QUICK" 'readonly property int settingsModePanelHeight: clampSettingsHeight(' \
    'settings-mode content height does not use the compact clamp'
contains "$POSITION" 'resize-compact' \
    'flyout positioning does not support a compact Quick Settings resize action'

python3 - "$QUICK" <<'PY' || fail 'FloatingWindow still forces the normal 460px minimum while settings mode is open'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start = text.index('    FloatingWindow {\n        id: quickSettingsWindow')
end = text.index('\n        onClosed:', start)
block = text[start:end]
required = (
    'minimumSize: Qt.size(root.minimumPanelWidth,',
    'root.settingsOpen ? root.minimumSettingsPanelHeight : root.minimumPanelHeight',
)
if not all(needle in block for needle in required):
    raise SystemExit(1)
PY

python3 - "$QUICK" <<'PY' || fail 'Quick Settings does not follow an in-session bar edge or visibility change'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start = text.index('    onPlacementChanged:')
end = text.index('\n    }', start) + 6
block = text[start:end]
for needle in (
    'quickSettingsWindow.visible',
    'root.settingsOpen',
    'root.resizeForSettingsMode()',
    'root.positionWindow()',
):
    if needle not in block:
        raise SystemExit(1)
PY

python3 - "$QUICK" <<'PY' || fail 'Customize Layout preserves stale settings sub-panels underneath the editor'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
needle = '                        onLayoutEditorRequested:'
start = text.index(needle)
end = text.index('\n                    }', start)
block = text[start:end]
if 'settingsPanel.resetTransientState();' not in block:
    raise SystemExit(1)
if 'root.layoutEditorOpen = true;' not in block:
    raise SystemExit(1)
PY

bash "$ROOT/tests/test-quick-settings-theme-hint.sh"

printf '%s\n' 'PASS: Quick Settings uses separate Icons/Appearance expansions, toggleable Themes, compact settings, inline copy targets, keybind hints, and complete transient reset.'
