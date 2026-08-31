#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PICKER="${ROOT}/config/quickshell/awtarchy/ThemePicker.qml"
CATALOG="${ROOT}/config/hypr/scripts/quickshell_theme_catalog.sh"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
SHELL_QML="${ROOT}/config/quickshell/awtarchy/shell.qml"
THEME_SELECT="${ROOT}/config/hypr/scripts/theme_select.sh"
MANAGED_HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"
PERMANENT_CI="${ROOT}/.github/workflows/validate-awtarchy.yml"
managed_history_missing=0

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
    if ! grep -Fxq -- "$entry" "$MANAGED_HISTORY"; then
        printf 'FAIL: managed history missing %s: %s\n' "$rel" "$hash" >&2
        managed_history_missing=1
    fi
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
require_picker 'Qt.Key_Return' 'ThemePicker lacks Enter apply behavior'
require_picker 'target: "themes"' 'ThemePicker themes IPC target was removed'
require_picker 'text: "Active"' 'ThemePicker does not mark the active theme'
require_picker 'palette.background' 'Theme cards do not use catalog preview colors'
require_picker 'palette.foreground' 'Theme cards do not preview foreground color'
require_picker 'palette.focus' 'Theme cards do not preview focus color'
require_picker 'palette.urgent' 'Theme cards do not preview urgent color'
require_picker 'palette.charging' 'Theme cards do not preview charging color'
require_picker 'palette.muted' 'Theme cards do not preview muted color'
require_picker 'function activateThemeCard(index)' 'ThemePicker has no selected-card activation helper'
require_picker 'if (selectedIndex === index)' 'ThemePicker does not apply an already-selected theme card'
require_picker 'onClicked: root.activateThemeCard(card.index)' 'Theme card click does not use selected-card activation'
require_picker '"Active theme: " + root.activeThemeName' 'ThemePicker header does not render active theme as one inline label'

if grep -Fq "find '" "$PICKER"; then
    fail 'ThemePicker still uses the old filename find command'
fi

if grep -Fq 'themeGrid.currentIndex = card.index' "$PICKER"; then
    fail 'Theme card hover directly overwrites GridView.currentIndex and breaks selected-index binding'
fi

if grep -Fq 'text: "Active theme"' "$PICKER"; then
    fail 'ThemePicker still uses the overlapping two-line active-theme header block'
fi

if grep -Fq 'event.key === Qt.Key_Escape' "$PICKER"; then
    fail 'ThemePicker still owns a duplicate local Escape close path'
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

if ! grep -Fq 'ThemePicker.toggleForScreen(activeScreen)' "$QUICK_SETTINGS"; then
    fail 'Quick Settings no longer toggles ThemePicker for its active screen'
fi

python3 - "$QUICK_SETTINGS" <<'PY' || fail 'Quick Settings main panel still owns Escape instead of deferring to the application escape stack'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("        Rectangle {\n            id: panel")
end = text.index("\n            MouseArea {", start)
block = text[start:end]
if "Keys.onEscapePressed:" in block:
    raise SystemExit(1)
PY

python3 - "$SHELL_QML" <<'PY' || fail 'application Escape handler does not close ThemePicker before the active flyout'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("    function closeActiveFloatingSurface() {")
end = text.index("\n    function flyoutWidth", start)
block = text[start:end]
theme_guard = block.find("if (ThemePicker.open)")
theme_close = block.find("ThemePicker.close();")
active_surface = block.find("const surface = String(FlyoutManager.activeSurface")
if min(theme_guard, theme_close, active_surface) < 0:
    raise SystemExit(1)
if not (theme_guard < theme_close < active_surface):
    raise SystemExit(1)
PY

python3 - "$SHELL_QML" <<'PY' || fail 'application Escape shortcut is disabled when ThemePicker is open standalone'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index('    Shortcut {\n        sequence: "Escape"')
end = text.index("\n    }", start) + 6
block = text[start:end]
if "ThemePicker.open" not in block:
    raise SystemExit(1)
if 'String(FlyoutManager.activeSurface || "").length > 0' not in block:
    raise SystemExit(1)
if "onActivated: root.closeActiveFloatingSurface()" not in block:
    raise SystemExit(1)
PY

if ! grep -Fq 'ipc call themes toggle' "$THEME_SELECT"; then
    fail 'theme_select.sh no longer uses the themes toggle IPC entrypoint'
fi

require_managed_hash "$PICKER" '.config/quickshell/awtarchy/ThemePicker.qml'
require_managed_hash "$CATALOG" '.config/hypr/scripts/quickshell_theme_catalog.sh'
require_managed_hash "$SHELL_QML" '.config/quickshell/awtarchy/shell.qml'
(( managed_history_missing == 0 )) || exit 1

catalog_ci_count="$(grep -Fc 'tests/test-quickshell-theme-catalog.sh' "$PERMANENT_CI" || true)"
picker_ci_count="$(grep -Fc 'tests/test-quickshell-theme-picker.sh' "$PERMANENT_CI" || true)"
catalog_helper_ci_count="$(grep -Fc 'config/hypr/scripts/quickshell_theme_catalog.sh' "$PERMANENT_CI" || true)"
[[ "$catalog_ci_count" -ge 3 ]] || fail 'Validate Awtarchy does not cover theme catalog syntax, ShellCheck, and execution'
[[ "$picker_ci_count" -ge 3 ]] || fail 'Validate Awtarchy does not cover theme picker syntax, ShellCheck, and execution'
[[ "$catalog_helper_ci_count" -ge 2 ]] || fail 'Validate Awtarchy does not syntax-check and ShellCheck the theme catalog helper'

printf '%s\n' 'Quickshell visual theme picker contract test passed.'
