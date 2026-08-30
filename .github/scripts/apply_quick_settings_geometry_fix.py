#!/usr/bin/env python3
from pathlib import Path
import hashlib

QML = Path("config/quickshell/awtarchy/QuickSettings.qml")
HISTORY = Path("local/share/awtarchy/quickshell-managed-history.sha256")


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one match, found {count}: {old[:80]!r}")
    return text.replace(old, new, 1)


text = QML.read_text()

text = replace_once(
    text,
    '''    readonly property int livePanelHeight: quickSettingsWindow.visible && quickSettingsWindow.height > 0
        ? clampHeight(Math.round(quickSettingsWindow.height)) : configuredPanelHeight
''',
    '''    readonly property int livePanelHeight: quickSettingsWindow.visible && !root.settingsOpen
        && quickSettingsWindow.height > 0
        ? clampHeight(Math.round(quickSettingsWindow.height)) : configuredPanelHeight
    readonly property int settingsModePanelHeight: clampHeight(38
        + (layoutEditorOpen ? layoutEditor.implicitHeight : settingsPanel.implicitHeight) + 12)
''')

text = replace_once(
    text,
    '''                String(panelWidthOverride), String(panelHeightOverride)
            ]);
        }
    }

    function positionWindow() {
''',
    '''                String(panelWidthOverride),
                String(settingsOpen ? settingsModePanelHeight : panelHeightOverride)
            ]);
        }
    }

    function resizeForSettingsMode() {
        if (!quickSettingsWindow.visible || activeMonitorName.length === 0)
            return;
        Quickshell.execDetached([
            positionScript, "quick-settings", activeMonitorName, placement, "resize",
            String(configuredPanelWidth),
            String(settingsOpen ? settingsModePanelHeight : configuredPanelHeight)
        ]);
    }

    function positionWindow() {
''')

text = replace_once(
    text,
    '''    onBottomEdgeLayoutChanged: Qt.callLater(() => alignContentToBar())
''',
    '''    onBottomEdgeLayoutChanged: Qt.callLater(() => alignContentToBar())
    onLayoutEditorOpenChanged: {
        if (settingsOpen)
            Qt.callLater(() => resizeForSettingsMode());
    }
''')

text = replace_once(
    text,
    '''    function toggleSettings() {
        settingsOpen = !settingsOpen;
        layoutEditorOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }
''',
    '''    function toggleSettings() {
        settingsOpen = !settingsOpen;
        layoutEditorOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        Qt.callLater(() => root.resizeForSettingsMode());
    }
''')

text = replace_once(
    text,
    '''        implicitWidth: root.configuredPanelWidth
        implicitHeight: root.configuredPanelHeight
''',
    '''        implicitWidth: root.configuredPanelWidth
        implicitHeight: root.settingsOpen ? root.settingsModePanelHeight : root.configuredPanelHeight
''')

text = replace_once(
    text,
    '''                Rectangle {
                    Layout.row: root.bottomEdgeLayout ? 2 : 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
''',
    '''                Rectangle {
                    id: headerBar
                    Layout.row: root.bottomEdgeLayout ? 2 : 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
''')

text = replace_once(
    text,
    '''                Flickable {
                    id: contentFlick
                    visible: !root.settingsOpen
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.bottomMargin: 0
''',
    '''                Flickable {
                    id: contentFlick
                    visible: !root.settingsOpen
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: !root.settingsOpen
                    Layout.preferredHeight: root.settingsOpen ? 0 : -1
                    Layout.maximumHeight: root.settingsOpen ? 0 : root.maximumPanelHeight
                    Layout.bottomMargin: 0
''')

text = replace_once(
    text,
    '''            Rectangle {
                width: 28
                height: 28
                x: panel.width - width - 6
                y: root.bottomEdgeLayout ? panel.height - height - 5 : 5
                color: closeMouse.containsMouse ? Theme.focus : Theme.active
''',
    '''            Rectangle {
                width: 28
                height: 28
                anchors.right: panel.right
                anchors.rightMargin: 6
                anchors.verticalCenter: headerBar.verticalCenter
                color: closeMouse.containsMouse ? Theme.focus : Theme.active
''')

QML.write_text(text)

managed = ".config/quickshell/awtarchy/QuickSettings.qml"
digest = hashlib.sha256(QML.read_bytes()).hexdigest()
entry = f"{digest}\t{managed}\n"
history = HISTORY.read_text()
if entry not in history:
    with HISTORY.open("a") as handle:
        handle.write(entry)
