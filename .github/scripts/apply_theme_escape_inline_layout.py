#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUICK = ROOT / "config/quickshell/awtarchy/QuickSettings.qml"
FLYOUT = ROOT / "config/quickshell/awtarchy/FlyoutSettings.qml"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_exact(text: str, old: str, new: str, *, label: str, count: int = 1) -> str:
    found = text.count(old)
    if found != count:
        raise SystemExit(f"{label}: expected {count} match(es), found {found}")
    return text.replace(old, new)


quick = QUICK.read_text(encoding="utf-8")
quick = replace_exact(
    quick,
    '''            focus: true
            Keys.onEscapePressed: root.close()

            MouseArea {
''',
    '''            focus: true
            Keys.onEscapePressed: event => {
                if (ThemePicker.open)
                    ThemePicker.close();
                else
                    root.close();
                event.accepted = true;
            }

            MouseArea {
''',
    label="Quick Settings Escape priority",
)
quick = replace_exact(
    quick,
    '''                        message: root.settingsMessage
                        otherMonitorNames: root.otherMonitorNames()

                        onResetRequested: root.resetDisplaySettings()
''',
    '''                        message: root.settingsMessage
                        otherMonitorNames: root.otherMonitorNames()
                        quickSettingsOrder: root.layoutOrderDraft
                        quickSettingsHidden: root.layoutHiddenDraft

                        onResetRequested: root.resetDisplaySettings()
''',
    label="Quick Settings inline layout state",
)
quick = replace_exact(
    quick,
    '''                        onCopyRequested: monitorNames => root.copyDisplaySettings(monitorNames)
                        onThemePickerRequested: root.openThemeMenu()
                        onLayoutEditorRequested: {
''',
    '''                        onCopyRequested: monitorNames => root.copyDisplaySettings(monitorNames)
                        onThemePickerRequested: root.openThemeMenu()
                        onQuickSettingsVisibilityRequested: (sectionId, visible) =>
                            root.setQuickSettingsSectionVisible(sectionId, visible)
                        onQuickSettingsLayoutResetRequested: root.resetQuickSettingsLayoutDraft()
                        onLayoutEditorRequested: {
''',
    label="Quick Settings inline layout actions",
)
QUICK.write_text(quick, encoding="utf-8")

flyout = FLYOUT.read_text(encoding="utf-8")
flyout = replace_exact(
    flyout,
    '''    property string message: ""
    property var otherMonitorNames: []
    property bool copyOpen: false
''',
    '''    property string message: ""
    property var otherMonitorNames: []
    property var quickSettingsOrder: []
    property var quickSettingsHidden: []
    property bool copyOpen: false
''',
    label="FlyoutSettings inline layout properties",
)
flyout = replace_exact(
    flyout,
    '''    signal copyRequested(var monitorNames)
    signal themePickerRequested()
    signal layoutEditorRequested()

    implicitHeight: inlineCopy
        ? 139 + displayScaleSection.implicitHeight + 37 + (copyOpen ? 31 : 0)
        : (copyOpen ? 104 : 139)

    function targetSelected(name) {
''',
    '''    signal copyRequested(var monitorNames)
    signal themePickerRequested()
    signal layoutEditorRequested()
    signal quickSettingsVisibilityRequested(string sectionId, bool visible)
    signal quickSettingsLayoutResetRequested()

    implicitHeight: inlineCopy
        ? 139 + displayScaleSection.implicitHeight
            + quickSettingsSectionControls.implicitHeight + 3 + (copyOpen ? 31 : 0)
        : (copyOpen ? 104 : 139)

    function quickSettingsSectionLabel(sectionId) {
        const labels = {
            "brightness": "Brightness",
            "output-volume": "Max Volume",
            "bar": "Bar",
            "display-effects": "Night + Vibrance",
            "submap": "Submap",
            "wallpaper": "Wallpaper",
            "awtarchy": "Awtarchy",
            "smtty": "smtty",
            "scheduler": "sched-ext",
            "numlock": "Num Lock",
            "title-bars": "Title Bars"
        };
        return labels[sectionId] || sectionId;
    }

    function quickSettingsSectionVisible(sectionId) {
        return (quickSettingsHidden || []).indexOf(sectionId) < 0;
    }

    function quickSettingsVisibleCount() {
        let count = 0;
        for (const sectionId of quickSettingsOrder || []) {
            if (quickSettingsSectionVisible(String(sectionId)))
                count++;
        }
        return count;
    }

    function targetSelected(name) {
''',
    label="FlyoutSettings inline layout contract",
)
flyout = replace_exact(
    flyout,
    '''        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 6
            visible: root.surfaceLabel === "Quick Settings"

            SettingsButton {
                label: "Customize Layout…"
                textSize: 9
                onClicked: root.layoutEditorRequested()
            }

            Text {
                Layout.fillWidth: true
                text: "Show, hide, and reorder sections for this display"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
''',
    '''        ColumnLayout {
            id: quickSettingsSectionControls
            Layout.fillWidth: true
            visible: root.surfaceLabel === "Quick Settings"
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 5

                Text {
                    Layout.fillWidth: true
                    text: "Quick Settings sections"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                SettingsButton {
                    label: "Reorder…"
                    textSize: 8
                    onClicked: root.layoutEditorRequested()
                }

                SettingsButton {
                    label: "Stock Layout"
                    textSize: 8
                    onClicked: root.quickSettingsLayoutResetRequested()
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 5

                Repeater {
                    model: root.quickSettingsOrder

                    SettingsButton {
                        required property var modelData
                        readonly property string sectionId: String(modelData)
                        readonly property bool shown: root.quickSettingsSectionVisible(sectionId)

                        label: root.quickSettingsSectionLabel(String(modelData))
                        active: root.quickSettingsSectionVisible(String(modelData))
                        available: !shown || root.quickSettingsVisibleCount() > 1
                        textSize: 8
                        horizontalPadding: 9
                        onClicked: root.quickSettingsVisibilityRequested(sectionId, !shown)
                    }
                }
            }
        }
''',
    label="FlyoutSettings inline section controls",
)
FLYOUT.write_text(flyout, encoding="utf-8")

history = HISTORY.read_text(encoding="utf-8")
for path, rel in (
    (QUICK, ".config/quickshell/awtarchy/QuickSettings.qml"),
    (FLYOUT, ".config/quickshell/awtarchy/FlyoutSettings.qml"),
):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    entry = f"{digest}\t{rel}\n"
    if entry not in history:
        if history and not history.endswith("\n"):
            history += "\n"
        history += entry
HISTORY.write_text(history, encoding="utf-8")
