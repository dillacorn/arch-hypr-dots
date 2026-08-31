#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path.cwd()


def replace_exact(path: Path, old: str, new: str, expected: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} matches, found {count}")
    path.write_text(text.replace(old, new), encoding="utf-8")


flyout = ROOT / "config/quickshell/awtarchy/FlyoutManager.qml"
replace_exact(
    flyout,
    '    property string activeSurface: ""\n',
    '    property string activeSurface: ""\n    property string overlaySurface: ""\n',
)
replace_exact(
    flyout,
    '    function claim(surface, monitorName) {\n',
    '''    function claimOverlay(surface) {\n        const key = String(surface || "");\n        if (key.length === 0)\n            return;\n        overlaySurface = key;\n    }\n\n    function releaseOverlay(surface) {\n        const key = String(surface || "");\n        if (overlaySurface === key)\n            overlaySurface = "";\n    }\n\n    function claim(surface, monitorName) {\n''',
)

theme = ROOT / "config/quickshell/awtarchy/ThemePicker.qml"
replace_exact(
    theme,
    '''        pickerWindow.visible = true;\n        loadActiveTheme();\n''',
    '''        pickerWindow.visible = true;\n        FlyoutManager.claimOverlay("themes");\n        loadActiveTheme();\n''',
)
replace_exact(
    theme,
    '''    function close() {\n        pickerWindow.visible = false;\n        search.text = "";\n    }\n''',
    '''    function close() {\n        FlyoutManager.releaseOverlay("themes");\n        pickerWindow.visible = false;\n        search.text = "";\n    }\n''',
)
replace_exact(
    theme,
    '''    IpcHandler {\n        target: "themes"\n''',
    '''    Shortcut {\n        sequence: "Escape"\n        context: Qt.ApplicationShortcut\n        enabled: root.open && FlyoutManager.overlaySurface === "themes"\n        autoRepeat: false\n        onActivated: root.close()\n    }\n\n    IpcHandler {\n        target: "themes"\n''',
)

shell = ROOT / "config/quickshell/awtarchy/shell.qml"
replace_exact(
    shell,
    '''    function closeActiveFloatingSurface() {\n        if (ThemePicker.open) {\n            ThemePicker.close();\n            return;\n        }\n\n        const surface = String(FlyoutManager.activeSurface || "");\n''',
    '''    function closeActiveFloatingSurface() {\n        const surface = String(FlyoutManager.activeSurface || "");\n''',
)
replace_exact(
    shell,
    '''        enabled: ThemePicker.open || String(FlyoutManager.activeSurface || "").length > 0\n''',
    '''        enabled: FlyoutManager.overlaySurface.length === 0\n            && String(FlyoutManager.activeSurface || "").length > 0\n''',
)
replace_exact(
    shell,
    '''    // Escape always closes the active Awtarchy flyout regardless of which child\n    // control currently owns focus. Existing per-window handlers remain valid,\n    // but this provides a consistent application-level fallback.\n''',
    '''    // The active flyout owns Escape only when no higher overlay is present.\n    // Overlays such as ThemePicker own their own application-level Escape shortcut.\n''',
)

hypr = ROOT / "config/hypr/hyprland.lua"
old_night = '''hl.bind("SUPER + ALT + CTRL + equal", hl.dsp.exec_cmd(hyprsunset_ctl .. " up"), {})\nhl.bind("SUPER + ALT + CTRL + minus", hl.dsp.exec_cmd(hyprsunset_ctl .. " down"), {})\nhl.bind("SUPER + ALT + CTRL + backspace", hl.dsp.exec_cmd(hyprsunset_ctl .. " toggle"), {})'''
new_night = '''hl.bind("SUPER + ALT + CTRL + bracketright", hl.dsp.exec_cmd(hyprsunset_ctl .. " up"), {})\nhl.bind("SUPER + ALT + CTRL + bracketleft", hl.dsp.exec_cmd(hyprsunset_ctl .. " down"), {})\nhl.bind("SUPER + ALT + CTRL + N", hl.dsp.exec_cmd(hyprsunset_ctl .. " toggle"), {})'''
replace_exact(hypr, old_night, new_night, expected=2)

picker_test = ROOT / "tests/test-quickshell-theme-picker.sh"
text = picker_test.read_text(encoding="utf-8")
start_marker = 'python3 - "$SHELL_QML" <<\'PY\' || fail \'application Escape handler does not close ThemePicker before the active flyout\'\n'
end_marker = "if ! grep -Fq 'ipc call themes toggle' \"$THEME_SELECT\"; then\n"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit("theme picker test: could not locate old shell Escape assertions")
text = text[:start] + 'bash "$ROOT/tests/test-theme-overlay-escape.sh"\n\n' + text[end:]
picker_test.write_text(text, encoding="utf-8")

history = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"
history_lines = history.read_text(encoding="utf-8").splitlines()
for source, rel in (
    (flyout, ".config/quickshell/awtarchy/FlyoutManager.qml"),
    (theme, ".config/quickshell/awtarchy/ThemePicker.qml"),
    (shell, ".config/quickshell/awtarchy/shell.qml"),
):
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    history_lines = [line for line in history_lines if not line.endswith("\t" + rel)]
    history_lines.append(f"{digest}\t{rel}")
history.write_text("\n".join(history_lines) + "\n", encoding="utf-8")
