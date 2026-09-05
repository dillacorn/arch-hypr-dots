import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    required property Item anchorItem
    property string text: ""
    property bool hovered: false
    property bool vertical: false
    property int delay: 350
    property bool popupHovered: false
    readonly property bool idleControl: ["", "", ""].indexOf(
        String(anchorItem ? anchorItem.label : "")) >= 0
    readonly property string barPosition: {
        const item = anchorItem;
        const monitorName = item && item.monitorName ? String(item.monitorName) : "";
        return monitorName.length > 0 ? BarState.positionFor(monitorName) : "";
    }
    readonly property bool keepAwakeFirst: idleControl && barPosition === "top"

    implicitWidth: 0
    implicitHeight: 0
    visible: false

    onHoveredChanged: {
        if (hovered && text.length > 0) {
            hideTimer.stop();
            showTimer.restart();
        } else {
            showTimer.stop();
            if (!popupHovered)
                hideTimer.restart();
        }
    }

    onPopupHoveredChanged: {
        if (popupHovered) {
            hideTimer.stop();
        } else if (!hovered) {
            hideTimer.restart();
        }
    }

    onTextChanged: {
        if (text.length === 0) {
            showTimer.stop();
            popup.visible = false;
        }
    }

    Timer {
        id: showTimer
        interval: root.delay
        repeat: false
        onTriggered: {
            if (root.hovered && root.text.length > 0) {
                popup.anchor.updateAnchor();
                popup.visible = true;
            }
        }
    }

    Timer {
        id: hideTimer
        interval: root.idleControl ? 260 : 40
        repeat: false
        onTriggered: popup.visible = false
    }

    PopupWindow {
        id: popup
        visible: false
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: root.idleControl
            ? 340
            : Math.min(360, Math.max(72, tooltipText.implicitWidth + 18))
        implicitHeight: root.idleControl
            ? 166
            : Math.max(28, tooltipText.implicitHeight + 10)

        // Normal tooltips remain visual-only and click-through. The idle-eye
        // hover card alone accepts pointer input for its explicit stronger mode.
        mask: Region {
            width: root.idleControl ? popup.width : 0
            height: root.idleControl ? popup.height : 0
        }

        anchor.item: root.anchorItem
        anchor.edges: root.vertical
            ? Edges.Top | Edges.Right
            : Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.All

        onVisibleChanged: {
            if (!visible)
                root.popupHovered = false;
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.width: root.idleControl ? 1 : 0
            border.color: Theme.active
            radius: 0

            Text {
                id: tooltipText
                anchors.centerIn: parent
                visible: !root.idleControl
                text: root.text
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
                id: idleHoverArea
                anchors.fill: parent
                visible: root.idleControl
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onContainsMouseChanged: root.popupHovered = containsMouse

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    columns: 1
                    rowSpacing: 5
                    columnSpacing: 0

                    ColumnLayout {
                        Layout.row: root.keepAwakeFirst ? 2 : 0
                        Layout.fillWidth: true
                        spacing: 5

                        Text {
                            Layout.fillWidth: true
                            text: "Always Awake"
                            color: Theme.urgent
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Keeps the session unlocked and displays on after 4 hours idle."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            wrapMode: Text.Wrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            color: alwaysAwakeMouse.containsMouse
                                ? Theme.strongHover
                                : (SystemState.idleMode === "always-awake"
                                    ? Theme.subtleActive : Theme.subtleHover)
                            radius: 0

                            Text {
                                anchors.centerIn: parent
                                text: SystemState.idleMode === "always-awake" ? "Disable Always Awake" : "Enable Always Awake (Not Recommended)"
                                color: SystemState.idleMode === "always-awake" ? Theme.foreground : Theme.urgent
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                id: alwaysAwakeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                onClicked: SystemState.setIdleMode(
                                    SystemState.idleMode === "always-awake" ? "off" : "always-awake")
                            }
                        }
                    }

                    Rectangle {
                        Layout.row: 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.active
                    }

                    ColumnLayout {
                        Layout.row: root.keepAwakeFirst ? 0 : 2
                        Layout.fillWidth: true
                        spacing: 5

                        Text {
                            Layout.fillWidth: true
                            text: SystemState.idleMode === "keep-awake" ? "Keep Awake: On" : "Keep Awake: Off"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: SystemState.idleMode === "always-awake"
                                ? "Recommended: click the eye to disable Always Awake. Click again for normal Keep Awake."
                                : "Recommended: click the eye to toggle Keep Awake. The 4-hour safety stays active."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
