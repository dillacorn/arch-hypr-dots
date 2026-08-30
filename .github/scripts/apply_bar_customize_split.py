#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUICK = ROOT / "config/quickshell/awtarchy/QuickSettings.qml"
THEME_PICKER = ROOT / "config/quickshell/awtarchy/ThemePicker.qml"
FLOATING = ROOT / "config/hypr/scripts/quickshell_floating_windows.sh"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_exact(text: str, old: str, new: str, *, count: int = 1, label: str) -> str:
    found = text.count(old)
    if found != count:
        raise SystemExit(f"{label}: expected {count} match(es), found {found}")
    return text.replace(old, new)


quick = QUICK.read_text()
quick = replace_exact(
    quick,
    "    property bool barCustomizeOpen: false\n",
    "    property bool barIconsOpen: false\n    property bool barAppearanceOpen: false\n",
    label="Bar expansion properties",
)
quick = replace_exact(
    quick,
    "            barCustomizeOpen = false;\n",
    "            barIconsOpen = false;\n            barAppearanceOpen = false;\n",
    count=3,
    label="Bar lifecycle resets",
)
quick = replace_exact(
    quick,
    "    function openThemeMenu() {\n        ThemePicker.openForScreen(activeScreen);\n    }\n",
    "    function openThemeMenu() {\n        ThemePicker.toggleForScreen(activeScreen);\n    }\n",
    label="Theme menu toggle",
)

old_header = '''                                    SettingsButton {
                                        label: "Themes"
                                        textSize: root.scaledText(9)
                                        onClicked: root.openThemeMenu()
                                    }

                                    SettingsButton {
                                        label: "Customize…"
                                        active: root.barCustomizeOpen
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.barCustomizeOpen = !root.barCustomizeOpen;
                                            if (!root.barCustomizeOpen)
                                                barAppearanceSettings.resetTransientState();
                                            if (root.bottomEdgeLayout)
                                                Qt.callLater(() => root.alignContentToBar());
                                        }
                                    }
'''
new_header = '''                                    SettingsButton {
                                        label: "Themes"
                                        active: ThemePicker.open
                                        textSize: root.scaledText(9)
                                        onClicked: root.openThemeMenu()
                                    }

                                    SettingsButton {
                                        label: "Icons"
                                        active: root.barIconsOpen
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.barIconsOpen = !root.barIconsOpen;
                                            root.barAppearanceOpen = false;
                                            barAppearanceSettings.resetTransientState();
                                            if (root.bottomEdgeLayout)
                                                Qt.callLater(() => root.alignContentToBar());
                                        }
                                    }

                                    SettingsButton {
                                        label: "Appearance"
                                        active: root.barAppearanceOpen
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.barAppearanceOpen = !root.barAppearanceOpen;
                                            root.barIconsOpen = false;
                                            if (!root.barAppearanceOpen)
                                                barAppearanceSettings.resetTransientState();
                                            if (root.bottomEdgeLayout)
                                                Qt.callLater(() => root.alignContentToBar());
                                        }
                                    }
'''
quick = replace_exact(quick, old_header, new_header, label="Bar header controls")

old_combined = '''                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.barCustomizeOpen
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Icons"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                        font.bold: true
                                    }

                                    BarIconSettings {
                                        Layout.fillWidth: true
                                        visible: root.barCustomizeOpen
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Appearance"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                        font.bold: true
                                    }

                                    BarSettingsSection {
                                        id: barAppearanceSettings
                                        Layout.fillWidth: true
                                        active: quickSettingsWindow.visible
                                            && root.quickSettingsSectionVisible("bar")
                                            && root.barCustomizeOpen
                                        monitorName: root.activeMonitorName
                                        monitorNames: [root.activeMonitorName]
                                            .concat(root.otherMonitorNames())
                                    }
                                }
'''
new_split = '''                                BarIconSettings {
                                    Layout.fillWidth: true
                                    visible: root.barIconsOpen
                                }

                                BarSettingsSection {
                                    id: barAppearanceSettings
                                    Layout.fillWidth: true
                                    visible: root.barAppearanceOpen
                                    active: quickSettingsWindow.visible
                                        && root.quickSettingsSectionVisible("bar")
                                        && root.barAppearanceOpen
                                    monitorName: root.activeMonitorName
                                    monitorNames: [root.activeMonitorName]
                                        .concat(root.otherMonitorNames())
                                }
'''
quick = replace_exact(quick, old_combined, new_split, label="Split Bar customization panels")

if "barCustomizeOpen" in quick:
    raise SystemExit("old barCustomizeOpen state remains after split")
QUICK.write_text(quick)

theme = THEME_PICKER.read_text()
theme = replace_exact(
    theme,
    '    property string catalogError: ""\n',
    '    property string catalogError: ""\n    readonly property bool open: pickerWindow.visible\n',
    label="Theme Picker open state",
)
theme = replace_exact(
    theme,
    "    function toggleFocused() { pickerWindow.visible ? close() : openFocused(); }\n",
    "    function toggleForScreen(target) {\n"
    "        if (pickerWindow.visible) {\n"
    "            close();\n"
    "            return;\n"
    "        }\n"
    "        openForScreen(target);\n"
    "    }\n\n"
    "    function toggleFocused() { toggleForScreen(focusedScreen()); }\n",
    label="Theme Picker screen-aware toggle",
)
THEME_PICKER.write_text(theme)

floating = FLOATING.read_text()
floating = replace_exact(
    floating,
    '        "$NOTIFY_SEND" -a Awtarchy -t 1500 "Floating windows" "$state" >/dev/null 2>&1 || true\n',
    '        "$NOTIFY_SEND" -a Hyprland -t 1000 "Floating windows" "$state" >/dev/null 2>&1 || true\n',
    label="Floating notification identity and timeout",
)
FLOATING.write_text(floating)

history = HISTORY.read_text()
if history and not history.endswith("\n"):
    history += "\n"
for source, rel in (
    (QUICK, ".config/quickshell/awtarchy/QuickSettings.qml"),
    (THEME_PICKER, ".config/quickshell/awtarchy/ThemePicker.qml"),
):
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    line = f"{digest}\t{rel}\n"
    if line not in history:
        history += line
HISTORY.write_text(history)
