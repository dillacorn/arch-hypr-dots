#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUICK = ROOT / "config/quickshell/awtarchy/QuickSettings.qml"
TEST = ROOT / "tests/test-quickshell-theme-picker.sh"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"

quick = QUICK.read_text(encoding="utf-8")
old_handler = '''            Keys.onEscapePressed: event => {
                if (ThemePicker.open)
                    ThemePicker.close();
                else
                    root.close();
                event.accepted = true;
            }

'''
if quick.count(old_handler) != 1:
    raise SystemExit(f"expected exactly one Quick Settings panel Escape handler, found {quick.count(old_handler)}")
quick = quick.replace(old_handler, "", 1)
QUICK.write_text(quick, encoding="utf-8")

test = TEST.read_text(encoding="utf-8")
start_marker = '''python3 - "$QUICK_SETTINGS" <<'PY' || fail 'Quick Settings local Escape handler can close Quick Settings underneath ThemePicker'\n'''
end_marker = '''python3 - "$SHELL_QML" <<'PY' || fail 'application Escape handler does not close ThemePicker before the active flyout'\n'''
start = test.index(start_marker)
end = test.index(end_marker, start)
replacement = '''python3 - "$QUICK_SETTINGS" <<'PY' || fail 'Quick Settings main panel still owns Escape instead of deferring to the application escape stack'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("        Rectangle {\\n            id: panel")
end = text.index("\\n            MouseArea {", start)
block = text[start:end]
if "Keys.onEscapePressed:" in block:
    raise SystemExit(1)
PY

'''
test = test[:start] + replacement + test[end:]
TEST.write_text(test, encoding="utf-8")

digest = hashlib.sha256(QUICK.read_bytes()).hexdigest()
entry = f"{digest}\t.config/quickshell/awtarchy/QuickSettings.qml"
history = HISTORY.read_text(encoding="utf-8")
if entry not in history.splitlines():
    if history and not history.endswith("\n"):
        history += "\n"
    history += entry + "\n"
    HISTORY.write_text(history, encoding="utf-8")
