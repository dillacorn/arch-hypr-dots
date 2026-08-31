#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHELL = ROOT / "config/quickshell/awtarchy/shell.qml"
PICKER = ROOT / "config/quickshell/awtarchy/ThemePicker.qml"
CI = ROOT / ".github/workflows/validate-awtarchy.yml"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_exact(text: str, old: str, new: str, *, count: int = 1, label: str) -> str:
    found = text.count(old)
    if found != count:
        raise SystemExit(f"{label}: expected {count} match(es), found {found}")
    return text.replace(old, new)


shell = SHELL.read_text(encoding="utf-8")
shell = replace_exact(
    shell,
    '''    function closeActiveFloatingSurface() {
        const surface = String(FlyoutManager.activeSurface || "");
''',
    '''    function closeActiveFloatingSurface() {
        if (ThemePicker.open) {
            ThemePicker.close();
            return;
        }

        const surface = String(FlyoutManager.activeSurface || "");
''',
    label="Theme Picker Escape priority",
)
shell = replace_exact(
    shell,
    '        enabled: String(FlyoutManager.activeSurface || "").length > 0\n',
    '        enabled: ThemePicker.open || String(FlyoutManager.activeSurface || "").length > 0\n',
    label="standalone Theme Picker Escape enablement",
)
SHELL.write_text(shell, encoding="utf-8")

picker = PICKER.read_text(encoding="utf-8")
picker = replace_exact(
    picker,
    '''                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    root.close();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Left) {
''',
    '''                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Left) {
''',
    label="remove duplicate local Theme Picker Escape handler",
)
PICKER.write_text(picker, encoding="utf-8")

ci = CI.read_text(encoding="utf-8")
ci = replace_exact(
    ci,
    '          bash -n tests/test-quickshell-theme-picker.sh\n',
    '          bash -n tests/test-quickshell-theme-picker.sh\n          bash -n tests/test-quickshell-theme-escape-priority.sh\n',
    label="permanent CI Bash syntax coverage",
)
ci = replace_exact(
    ci,
    '            tests/test-quickshell-theme-picker.sh \\\n',
    '            tests/test-quickshell-theme-picker.sh \\\n            tests/test-quickshell-theme-escape-priority.sh \\\n',
    label="permanent CI ShellCheck coverage",
)
ci = replace_exact(
    ci,
    '          bash tests/test-quickshell-theme-picker.sh\n',
    '          bash tests/test-quickshell-theme-picker.sh\n          bash tests/test-quickshell-theme-escape-priority.sh\n',
    label="permanent CI execution coverage",
)
CI.write_text(ci, encoding="utf-8")

history = HISTORY.read_text(encoding="utf-8")
if history and not history.endswith("\n"):
    history += "\n"
for source, rel in (
    (SHELL, ".config/quickshell/awtarchy/shell.qml"),
    (PICKER, ".config/quickshell/awtarchy/ThemePicker.qml"),
):
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    entry = f"{digest}\t{rel}\n"
    if entry not in history:
        history += entry
HISTORY.write_text(history, encoding="utf-8")
