#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PICKER="${ROOT}/config/quickshell/awtarchy/ThemePicker.qml"
CATALOG="${ROOT}/config/hypr/scripts/quickshell_theme_catalog.sh"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
THEME_SELECT="${ROOT}/config/hypr/scripts/theme_select.sh"
MANAGED_HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_picker() {
    local needle="$1" message="$2"
    grep -Fq -- "$needle" "$PICKER" || fail "$message"
}

require_managed_hash() {
    local file="$1" rel="$2" hash entry
    hash="$(sha256sum "$file" | awk '{print $1}')"
    entry="${hash}"$'\t'"${rel}"
    grep -Fxq -- "$entry" "$MANAGED_HISTORY" \
        || fail "managed history missing ${rel}: ${hash}"
}

require_picker 'quickshell_theme_catalog.sh' 'ThemePicker does not use the theme catalog helper'
require_picker 'active-theme' 'ThemePicker does not read active-theme identity'
require_picker 'GridView {' 'ThemePicker is not a visual grid browser'
require_picker 'function applySelectedTheme()' 'ThemePicker has no explicit selected-theme apply function'
require_picker 'applyProcess.exec([root.applyBackend, selected.name])' 'ThemePicker does not delegate apply to the existing helper'
require_picker 'text: "Apply Theme"' 'ThemePicker has no explicit Apply Theme control'
require_picker 'text: "Cancel"' 'ThemePicker has no explicit Cancel control'
require_picker 'Qt.Key_Left' 'ThemePicker lacks left grid navigation'
require_picker 'Qt.Key_Right' 'ThemePicker lacks right grid navigation'
require_picker 'Qt.Key_Up' 'ThemePicker lacks up grid navigation'
require_picker 'Qt.Key_Down' 'ThemePicker lacks down grid navigation'
require_picker 'Qt.Key_Home' 'ThemePicker lacks Home navigation'
require_picker 'Qt.Key_End' 'ThemePicker lacks End navigation'
require_picker 'Qt.Key_Escape' 'ThemePicker lacks Escape cancellation'
require_picker 'Qt.Key_Return' 'ThemePicker lacks Enter apply behavior'
require_picker 'target: "themes"' 'ThemePicker themes IPC target was removed'
require_picker 'text: "Active"' 'ThemePicker does not mark the active theme'
require_picker 'palette.background' 'Theme cards do not use catalog preview colors'
require_picker 'palette.foreground' 'Theme cards do not preview foreground color'
require_picker 'palette.focus' 'Theme cards do not preview focus color'
require_picker 'palette.urgent' 'Theme cards do not preview urgent color'
require_picker 'palette.charging' 'Theme cards do not preview charging color'
require_picker 'palette.muted' 'Theme cards do not preview muted color'
require_picker 'onClicked: root.selectIndex(card.index)' 'Theme card click no longer owns selection'

if grep -Fq "find '" "$PICKER"; then
    fail 'ThemePicker still uses the old filename find command'
fi

if grep -Fq 'themeGrid.currentIndex = card.index' "$PICKER"; then
    fail 'Theme card hover directly overwrites GridView.currentIndex and breaks selected-index binding'
fi

apply_calls="$(grep -Fc 'applyProcess.exec(' "$PICKER" || true)"
[[ "$apply_calls" == 1 ]] || fail "ThemePicker must have exactly one applyProcess.exec call, found ${apply_calls}"

python3 - "$PICKER" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.find("function applySelectedTheme()")
if start < 0:
    raise SystemExit("missing applySelectedTheme")
next_function = text.find("\n    function ", start + 1)
block = text[start:] if next_function < 0 else text[start:next_function]
if "applyProcess.exec([root.applyBackend, selected.name])" not in block:
    raise SystemExit("apply call exists outside applySelectedTheme")
PY

if ! grep -Fq 'ThemePicker.openForScreen(activeScreen)' "$QUICK_SETTINGS"; then
    fail 'Quick Settings no longer opens ThemePicker for its active screen'
fi

if ! grep -Fq 'ipc call themes toggle' "$THEME_SELECT"; then
    fail 'theme_select.sh no longer uses the themes toggle IPC entrypoint'
fi

require_managed_hash "$PICKER" '.config/quickshell/awtarchy/ThemePicker.qml'
require_managed_hash "$CATALOG" '.config/hypr/scripts/quickshell_theme_catalog.sh'

printf '%s\n' 'Quickshell visual theme picker contract test passed.'
