import QtQuick

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
    property int fontPixelSize: 0
    property bool hovered: false

    readonly property string displayLabel: label.replace(/ {2,}/g, " ")
    readonly property int resolvedFontPixelSize: fontPixelSize > 0 ? fontPixelSize : suggestedFontPixelSize()

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal wheelUp()
    signal wheelDown()

    function suggestedFontPixelSize() {
        // Keep the two glyphs the user already identified as correctly sized.
        if (label.indexOf("🖱") >= 0 || label.indexOf("°") >= 0)
            return 14;

        // Larger control/status glyphs better match the visual weight of the
        // existing Waybar while leaving tray icons and temperature unchanged.
        if (label.indexOf("") >= 0)
            return 18;
        if (label.indexOf("") >= 0 || label.indexOf("") >= 0)
            return 17;
        if (label.indexOf("") >= 0 || label.indexOf("") >= 0 || label.indexOf("") >= 0)
            return 17;
        if (label.indexOf("") >= 0 || label.indexOf("") >= 0 || label.indexOf("") >= 0 || label.indexOf("") >= 0)
            return 17;
        if (label.indexOf("") >= 0 || label.indexOf("") >= 0)
            return 16;
        if (label.indexOf("") >= 0 || label.indexOf("") >= 0 || label.indexOf("") >= 0)
            return 15;
        if (label.indexOf("") >= 0 || label.indexOf("") >= 0 || label.indexOf("") >= 0 || label.indexOf("") >= 0 || label.indexOf("") >= 0 || label.indexOf("") >= 0)
            return 15;
        if (/^\d+/.test(label))
            return 15;

        return Theme.fontPixelSize;
    }

    implicitWidth: fixedWidth > 0 ? fixedWidth : (vertical ? 36 : textItem.implicitWidth + horizontalPadding * 2)
    implicitHeight: fixedHeight > 0 ? fixedHeight : (vertical ? Math.max(28, textItem.implicitHeight + 12) : 28)
    color: pointer.containsMouse ? hoverBackground : normalBackground

    Text {
        id: textItem
        anchors.centerIn: parent
        text: root.displayLabel
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: root.resolvedFontPixelSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Timer {
        id: hoverRelease
        interval: 650
        repeat: false
        onTriggered: root.hovered = false
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true

        onContainsMouseChanged: {
            if (containsMouse) {
                hoverRelease.stop();
                root.hovered = true;
            } else {
                hoverRelease.restart();
            }
        }

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

    BarTooltip {
        anchorItem: root
        text: root.tooltip
        hovered: pointer.containsMouse
        vertical: root.vertical
    }
}
