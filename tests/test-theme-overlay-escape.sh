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

python3 - "$PICKER" <<'PY' || fail 'Theme Picker does not exclusively own Escape while its overlay is visible'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = '    Shortcut {\n        sequence: "Escape"'
start = text.index(needle)
end = text.index('\n    }', start) + 6
block = text[start:end]
required = (
    'context: Qt.ApplicationShortcut',
    'enabled: root.open && FlyoutManager.overlaySurface === "themes"',
    'onActivated: root.close()',
)
if not all(item in block for item in required):
    raise SystemExit(1)
PY

python3 - "$SHELL" <<'PY' || fail 'normal flyout Escape remains enabled underneath a Theme Picker overlay'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = '    Shortcut {\n        sequence: "Escape"'
start = text.index(needle)
end = text.index('\n    }', start) + 6
block = text[start:end]
if 'FlyoutManager.overlaySurface.length === 0' not in block:
    raise SystemExit(1)
if 'String(FlyoutManager.activeSurface || "").length > 0' not in block:
    raise SystemExit(1)
if 'onActivated: root.closeActiveFloatingSurface()' not in block:
    raise SystemExit(1)
PY

not_contains "$SHELL" 'if (ThemePicker.open)' \
    'shell Escape still special-cases Theme Picker instead of respecting overlay ownership'

printf '%s\n' 'PASS: Theme Picker owns Escape as an explicit overlay above the active flyout.'
