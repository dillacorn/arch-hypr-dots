#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_QML="$ROOT/config/quickshell/awtarchy/shell.qml"
THEME_PICKER="$ROOT/config/quickshell/awtarchy/ThemePicker.qml"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

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

if grep -Fq 'event.key === Qt.Key_Escape' "$THEME_PICKER"; then
    fail 'ThemePicker still owns a duplicate local Escape close path'
fi

if ! grep -Fq 'ThemePicker.toggleForScreen(activeScreen)' "$QUICK_SETTINGS"; then
    fail 'Quick Settings Themes button no longer uses the screen-aware ThemePicker toggle'
fi

printf '%s\n' 'PASS: Escape closes ThemePicker first, then the underlying Quick Settings flyout on the next press.'
