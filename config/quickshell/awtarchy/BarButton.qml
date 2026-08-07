import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    property string label: ""
    property string tooltip: ""
    property bool vertical: false
    property color foreground: Theme.foreground
    property color normalBackground: "transparent"
    property color hoverBackground: Theme.subtleHover
    property int horizontalPadding: 8
    property int verticalPadding: 0
    property int fixedWidth: 0
    property int fixedHeight: 0
    readonly property bool hovered: pointer.containsMouse

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal wheelUp()
    signal wheelDown()

    implicitWidth: fixedWidth > 0 ? fixedWidth : (vertical ? 36 : textItem.implicitWidth + horizontalPadding * 2)
    implicitHeight: fixedHeight > 0 ? fixedHeight : (vertical ? Math.max(28, textItem.implicitHeight + 12) : 28)
    color: pointer.containsMouse ? hoverBackground : normalBackground

    Text {
        id: textItem
        anchors.centerIn: parent
        text: root.label
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontPixelSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else if (mouse.button === Qt.MiddleButton)
                root.middleClicked();
            else
                root.clicked();
        }
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0)
                root.wheelUp();
            else if (wheel.angleDelta.y < 0)
                root.wheelDown();
        }
    }

    ToolTip.visible: pointer.containsMouse && tooltip.length > 0
    ToolTip.text: tooltip
    ToolTip.delay: 350
}
