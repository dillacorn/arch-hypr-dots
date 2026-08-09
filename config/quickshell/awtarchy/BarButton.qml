import QtQuick
import QtQuick.Window

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

    // Bar.qml supplies these explicitly. Window.window is not reliable for
    // children of every Quickshell proxy window, so keep it only as a fallback
    // for BarButton users outside the main bar.
    readonly property var containingWindow: Window.window
    property string monitorName: containingWindow && containingWindow.screen ? containingWindow.screen.name : ""
    property real iconScale: BarState.iconScaleFor(monitorName)
    property int barThickness: BarState.barSizeFor(monitorName, vertical)

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
    readonly property string effectiveTooltip: tooltip === "Audio volume"
        ? SystemState.audioOutputName
        : (tooltip.indexOf("Memory usage: ") === 0 ? SystemState.memoryTooltip : tooltip)

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

    function scaledIconSize(baseSize) {
        const scaled = Math.round(baseSize * iconScale);
        const maxForBar = Math.max(8, barThickness - 2);
        return Math.max(8, Math.min(maxForBar, scaled));
    }

    function partFontPixelSize(part) {
        if (fontPixelSize > 0)
            return scaledIconSize(fontPixelSize);

        if (part.indexOf("🖱") >= 0 || part.indexOf("°") >= 0 || /^[↑↓←→]$/.test(part))
            return scaledIconSize(14);

        // Workspace numbers remain normal text while the approved workspace
        // glyph size scales with the rest of the bar icons.
        if (workspaceLabel && (isBmpIconPart(part) || isSupplementaryIconPart(part)))
            return scaledIconSize(20);

        if (part.indexOf("") >= 0)
            return scaledIconSize(20);
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return scaledIconSize(19);

        // Preserve the tuned relative sizes for the idle-inhibitor glyphs.
        if (part.indexOf("") >= 0)
            return scaledIconSize(25);
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return scaledIconSize(23);

        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return scaledIconSize(20);
        if (part.indexOf("") >= 0)
            return scaledIconSize(18);
        if (part.indexOf("") >= 0)
            return scaledIconSize(18);
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return scaledIconSize(18);
        if (part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0 || part.indexOf("") >= 0)
            return scaledIconSize(17);

        if (isBmpIconPart(part) || isSupplementaryIconPart(part))
            return scaledIconSize(18);

        return Theme.fontPixelSize;
    }

    implicitWidth: vertical
        ? barThickness
        : (fixedWidth > 0 ? fixedWidth : labelContent.implicitWidth + horizontalPadding * 2)
    implicitHeight: vertical
        ? (fixedHeight > 0 ? fixedHeight : Math.max(28, labelContent.implicitHeight + 12))
        : (fixedHeight > 0 ? fixedHeight : barThickness)
    color: pointer.containsMouse ? hoverBackground : normalBackground

    Item {
        id: labelContent
        anchors.centerIn: parent
        implicitWidth: root.useHorizontalParts
            ? horizontalRow.implicitWidth
            : (root.useVerticalParts ? verticalColumn.implicitWidth : normalText.implicitWidth)
        implicitHeight: root.useHorizontalParts
            ? root.barThickness
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
            height: root.barThickness
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
                    anchors.horizontalCenter: verticalColumn.horizontalCenter

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
        text: root.effectiveTooltip
        hovered: pointer.containsMouse
        vertical: root.vertical
    }
}
