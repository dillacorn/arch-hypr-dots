#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUICK = ROOT / "config/quickshell/awtarchy/QuickSettings.qml"
BAR_TEST = ROOT / "tests/test-quick-settings-bar-customize-flow.sh"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_exact(text: str, old: str, new: str, *, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new)


quick = QUICK.read_text(encoding="utf-8")
position_block = '''                                        Text {\n                                            Layout.fillWidth: true\n                                            text: "Position: SUPER+Mouse1 / ALT+Mouse1 drag · CTRL+SUPER+B / SUPER+ALT+B change edge"\n                                            color: Theme.muted\n                                            font.family: Theme.fontFamily\n                                            font.pixelSize: root.scaledText(8)\n                                            horizontalAlignment: Text.AlignRight\n                                            wrapMode: Text.Wrap\n                                        }\n'''
theme_block = '''                                        Text {\n                                            Layout.fillWidth: true\n                                            text: "Themes: SUPER+T"\n                                            color: Theme.muted\n                                            font.family: Theme.fontFamily\n                                            font.pixelSize: root.scaledText(8)\n                                            horizontalAlignment: Text.AlignRight\n                                            wrapMode: Text.Wrap\n                                        }\n\n'''
quick = replace_exact(
    quick,
    position_block,
    theme_block + position_block,
    label="Bar Themes shortcut hint",
)
QUICK.write_text(quick, encoding="utf-8")

bar_test = BAR_TEST.read_text(encoding="utf-8")
bar_test = replace_exact(
    bar_test,
    "printf '%s\\n' 'PASS: Quick Settings uses separate Icons/Appearance expansions, toggleable Themes, compact settings, inline copy targets, keybind hints, and complete transient reset.'\n",
    "bash \"$ROOT/tests/test-quick-settings-theme-hint.sh\"\n\nprintf '%s\\n' 'PASS: Quick Settings uses separate Icons/Appearance expansions, toggleable Themes, compact settings, inline copy targets, keybind hints, and complete transient reset.'\n",
    label="permanent Themes hint regression hook",
)
BAR_TEST.write_text(bar_test, encoding="utf-8")

history = HISTORY.read_text(encoding="utf-8")
if history and not history.endswith("\n"):
    history += "\n"
digest = hashlib.sha256(QUICK.read_bytes()).hexdigest()
entry = f"{digest}\t.config/quickshell/awtarchy/QuickSettings.qml"
if entry not in history.splitlines():
    history += entry + "\n"
HISTORY.write_text(history, encoding="utf-8")
