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
    readonly property var horizontalParts: vertical
        ? []
        : displayLabel.split(/\s+/).filter(part => part.length > 0)
    readonly property var verticalParts: vertical
        ? displayLabel.split("\n").filter(part => part.length > 0)
        : []
    readonly property bool useHorizontalParts: !vertical && horizontalParts.length > 1
    readonly property bool useVerticalParts: vertical && verticalParts.length > 1

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal wheelUp()
    signal wheelDown()

    function partFontPixelSize(part) {
        if (fontPixelSize > 0)
            return fontPixelSize;

        // Keep the two glyphs the user already identified as correctly sized.
        if (part.indexOf("🖱") >= 0 || part.indexOf("°") >= 0)
            return 14;

        // Numeric/text values remain at 14px. Icons get their own size but are
        // geometrically centered in a fixed-height wrapper below, so mixed
        // Nerd Font metrics cannot drag adjacent values off-axis.
        if (part.indexOf("") >= 0)
            return 19;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 18;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 18;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 18;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 17;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 17;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 16;

        // Workspace/application glyphs. The number beside them stays 14px.
        if (/^[󰀀-󰿿-]$/u.test(part))
            return 18;

        return Theme.fontPixelSize;
    }

    implicitWidth: fixedWidth > 0
        ? fixedWidth
        : (vertical ? 36 : labelContent.implicitWidth + horizontalPadding * 2)
    implicitHeight: fixedHeight > 0
        ? fixedHeight
        : (vertical ? Math.max(28, labelContent.implicitHeight + 12) : 28)
    color: pointer.containsMouse ? hoverBackground : normalBackground

    Item {
        id: labelContent
        anchors.centerIn: parent
        implicitWidth: root.useHorizontalParts
            ? horizontalRow.implicitWidth
            : (root.useVerticalParts ? verticalColumn.implicitWidth : normalText.implicitWidth)
        implicitHeight: root.useHorizontalParts
            ? 28
            : (root.useVerticalParts ? verticalColumn.implicitHeight : normalText.implicitHeight)

        Text {
            id: normalText
            anchors.centerIn: parent
            visible: !root.useHorizontalParts && !root.useVerticalParts
            text: root.displayLabel
            color: root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: root.partFontPixelSize(root.displayLabel)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Row {
            id: horizontalRow
            anchors.centerIn: parent
            height: 28
            spacing: 4
            visible: root.useHorizontalParts

            Repeater {
                model: root.horizontalParts

                delegate: Item {
                    required property var modelData
                    width: tokenText.implicitWidth
                    height: horizontalRow.height

                    Text {
                        id: tokenText
                        anchors.centerIn: parent
                        text: String(parent.modelData)
                        color: root.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: root.partFontPixelSize(String(parent.modelData))
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Column {
            id: verticalColumn
            anchors.centerIn: parent
            spacing: 0
            visible: root.useVerticalParts

            Repeater {
                model: root.verticalParts

                delegate: Item {
                    required property var modelData
                    width: Math.max(20, tokenText.implicitWidth)
                    height: Math.max(16, tokenText.implicitHeight)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        id: tokenText
                        anchors.centerIn: parent
                        text: String(parent.modelData)
                        color: root.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: root.partFontPixelSize(String(parent.modelData))
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
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
