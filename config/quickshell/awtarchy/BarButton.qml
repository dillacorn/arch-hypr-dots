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

    // The legacy Waybar clipboard codepoint renders as an unrelated glyph in
    // the Nerd Font used by Quickshell. Translate it to the well-supported
    // Font Awesome paste/clipboard glyph while keeping callers unchanged.
    readonly property string displayLabel: label.replace("", "").replace(/ {2,}/g, " ")
    readonly property var horizontalParts: vertical
        ? []
        : displayLabel.split(/\s+/).filter(part => part.length > 0)
    readonly property var verticalParts: vertical
        ? displayLabel.split("\n").filter(part => part.length > 0)
        : []
    readonly property bool useHorizontalParts: !vertical && horizontalParts.length > 1
    readonly property bool useVerticalParts: vertical && verticalParts.length > 1
    readonly property bool workspaceLabel: /^\d+\s/.test(displayLabel)

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal wheelUp()
    signal wheelDown()

    function isBmpIconPart(part) {
        return /^[\uF000-\uF8FF]$/u.test(part);
    }

    function isSupplementaryIconPart(part) {
        return /^[\u{F0000}-\u{FFFFF}]$/u.test(part);
    }

    function partFontFamily(part) {
        return Theme.fontFamily;
    }

    function partFontPixelSize(part) {
        if (fontPixelSize > 0)
            return fontPixelSize;

        // Keep the two glyphs the user already identified as correctly sized.
        if (part.indexOf("🖱") >= 0 || part.indexOf("°") >= 0)
            return 14;

        // Workspace numbers remain 14px. Their current 20px glyph size is the
        // approved visual target and should not move with other icon tuning.
        if (workspaceLabel && (isBmpIconPart(part) || isSupplementaryIconPart(part)))
            return 20;

        if (part.indexOf("") >= 0)
            return 20;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 19;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 22;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 20;
        if (part.indexOf("") >= 0)
            return 18;
        if (part.indexOf("") >= 0)
            return 18;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 18;
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return 17;

        if (isBmpIconPart(part) || isSupplementaryIconPart(part))
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
            font.family: root.partFontFamily(root.displayLabel)
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
                        font.family: root.partFontFamily(String(parent.modelData))
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
                        font.family: root.partFontFamily(String(parent.modelData))
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
