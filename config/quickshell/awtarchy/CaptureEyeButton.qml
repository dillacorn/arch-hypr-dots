pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: root

    property bool captureAllowed: false
    property bool locked: false
    property int textSize: 13

    signal clicked()

    implicitWidth: 30
    implicitHeight: 26
    color: root.locked ? "transparent"
        : (root.captureAllowed
            ? Theme.focus
            : (captureMouse.containsMouse ? Theme.subtleHover : "transparent"))
    opacity: root.locked ? 0.5 : 1
    border.width: 1
    border.color: root.captureAllowed && !root.locked ? Theme.focus : Theme.muted

    Text {
        anchors.centerIn: parent
        text: root.captureAllowed ? "" : ""
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize
    }

    MouseArea {
        id: captureMouse
        anchors.fill: parent
        enabled: !root.locked
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
