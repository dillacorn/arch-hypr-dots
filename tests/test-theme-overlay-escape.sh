#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FLYOUT="$ROOT/config/quickshell/awtarchy/FlyoutManager.qml"
PICKER="$ROOT/config/quickshell/awtarchy/ThemePicker.qml"
SHELL="$ROOT/config/quickshell/awtarchy/shell.qml"

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

contains "$FLYOUT" 'property string overlaySurface: ""' \
    'FlyoutManager does not model an overlay above the active flyout'
contains "$FLYOUT" 'function claimOverlay(surface)' \
    'FlyoutManager cannot claim an overlay surface'
contains "$FLYOUT" 'function releaseOverlay(surface)' \
    'FlyoutManager cannot release an overlay surface'

contains "$PICKER" 'FlyoutManager.claimOverlay("themes");' \
    'Theme Picker does not claim the themes overlay when opened'
contains "$PICKER" 'FlyoutManager.releaseOverlay("themes");' \
    'Theme Picker does not release the themes overlay when closed'
contains "$PICKER" 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive' \
    'Theme Picker does not take exclusive keyboard focus while visually above Quick Settings'
not_contains "$PICKER" 'focusable: true' \
    'Theme Picker still relies on ambiguous on-demand PanelWindow focus'
not_contains "$PICKER" 'Keys.onEscapePressed:' \
    'Theme Picker still has a local Escape handler that can double-handle one keypress'
not_contains "$PICKER" 'sequence: "Escape"' \
    'Theme Picker still has its own application-level Escape shortcut'

python3 - "$SHELL" <<'PY' || fail 'application Escape does not close the topmost Theme Picker before the underlying flyout'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

route_start = text.index('    function closeTopFloatingSurface() {')
route_end = text.index('\n    }', route_start) + 6
route = text[route_start:route_end]
for required in (
    'if (ThemePicker.open)',
    'ThemePicker.close();',
    'return;',
    'closeActiveFloatingSurface();',
):
    if required not in route:
        raise SystemExit(1)

needle = '    Shortcut {\n        sequence: "Escape"'
start = text.index(needle)
end = text.index('\n    }', start) + 6
block = text[start:end]
if 'ThemePicker.open' not in block:
    raise SystemExit(1)
if 'String(FlyoutManager.activeSurface || "").length > 0' not in block:
    raise SystemExit(1)
if 'onActivated: root.closeTopFloatingSurface()' not in block:
    raise SystemExit(1)
if 'FlyoutManager.overlaySurface.length === 0' in block:
    raise SystemExit(1)
PY

printf '%s\n' 'PASS: one application-level Escape owner closes Theme Picker first and leaves the underlying flyout for the next keypress.'
