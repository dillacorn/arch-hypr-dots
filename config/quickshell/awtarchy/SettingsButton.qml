import QtQuick

Rectangle {
    id: root

    property string label: ""
    property bool active: false
    property bool available: true
    property int textSize: 10
    property int horizontalPadding: 14
    signal clicked()

    implicitWidth: Math.max(28, buttonLabel.implicitWidth + horizontalPadding)
    implicitHeight: 26
    color: active ? Theme.focus
        : (buttonMouse.containsMouse && available ? Theme.subtleHover : "transparent")
    opacity: available ? 1 : 0.4
    border.width: 1
    border.color: active ? Theme.focus : Theme.muted
    radius: 0

    Text {
        id: buttonLabel
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 8)
        text: root.label
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        enabled: root.available
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
