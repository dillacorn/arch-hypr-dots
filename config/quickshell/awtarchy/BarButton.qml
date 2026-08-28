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
    property bool workspaceButton: false
    property int workspaceGlyphSize: 0
    property int workspaceGlyphYOffset: 0
    property bool hovered: false
    property int wheelActivationDelay: 0
    property bool wheelReady: wheelActivationDelay <= 0
    // Mouse wheels normally report 120-unit angle steps. Precision touchpads
    // report many smaller pixel deltas, so collect those before emitting one
    // bounded bar action instead of treating every gesture event as a step.
    property real wheelAngleRemainder: 0
    property real wheelPixelRemainder: 0
    readonly property real wheelAngleStep: 120
    readonly property real wheelPixelStep: 24

    // Bar.qml supplies these explicitly. Window.window is not reliable for
    // children of every Quickshell proxy window, so keep it only as a fallback
    // for BarButton users outside the main bar.
    readonly property var containingWindow: Window.window
    property string monitorName: containingWindow && containingWindow.screen ? containingWindow.screen.name : ""
    property real iconScale: BarState.iconScaleFor(monitorName)
    property real textScale: {
        const state = BarState.monitorState(monitorName) || ({});
        const percent = Number(state.text_scale === undefined ? 100 : state.text_scale);
        if (!Number.isFinite(percent))
            return 1.0;
        return Math.max(50, Math.min(200, percent)) / 100.0;
    }
    property int barThickness: BarState.barSizeFor(monitorName, vertical)

    // The legacy Waybar clipboard codepoint renders as an unrelated glyph in
    // the Nerd Font used by Quickshell. Translate it to the well-supported
    // Font Awesome paste/clipboard glyph while keeping callers unchanged.
    readonly property string displayLabel: label.replace("", "").replace(/ {2,}/g, " ")
    readonly property var workspaceParts: workspaceButton
        ? displayLabel.split(/\s+/).filter(part => part.length > 0)
        : []
    readonly property var horizontalParts: vertical || workspaceButton
        ? []
        : displayLabel.split(/\s+/).filter(part => part.length > 0)
    readonly property var verticalParts: vertical && !workspaceButton
        ? displayLabel.split("\n").filter(part => part.length > 0)
        : []
    readonly property bool useWorkspaceParts: workspaceButton && workspaceParts.length > 1
    readonly property bool useHorizontalParts: !workspaceButton && !vertical && horizontalParts.length > 1
    readonly property bool useVerticalParts: !workspaceButton && vertical && verticalParts.length > 1
    readonly property bool workspaceLabel: workspaceButton
    readonly property string effectiveTooltip: tooltip === "Audio volume"
        ? SystemState.audioOutputName
        : (tooltip.indexOf("Memory usage: ") === 0 ? SystemState.memoryTooltip : tooltip)

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal wheelUp()
    signal wheelDown()

    function resetWheelAccumulator() {
        wheelAngleRemainder = 0;
        wheelPixelRemainder = 0;
        wheelReset.stop();
    }

    function dispatchWheelStep(direction) {
        if (direction > 0)
            wheelUp();
        else if (direction < 0)
            wheelDown();
    }

    function handleWheel(wheel) {
        if (!wheelReady) {
            resetWheelAccumulator();
            wheel.accepted = true;
            return;
        }

        const rawPixelDelta = Number(wheel.pixelDelta.y);
        if (Number.isFinite(rawPixelDelta) && rawPixelDelta !== 0) {
            // Qt/Wayland does not reliably expose Hyprland's natural-scroll
            // state through WheelEvent.inverted. Pixel deltas are the smooth
            // touchpad path here, so reverse them directly to match the mouse
            // wheel-up-increases, wheel-down-decreases control direction.
            const pixelDelta = -rawPixelDelta;
            wheelAngleRemainder = 0;
            wheelPixelRemainder += pixelDelta;
            wheelReset.restart();

            if (Math.abs(wheelPixelRemainder) >= wheelPixelStep) {
                const direction = wheelPixelRemainder > 0 ? 1 : -1;
                dispatchWheelStep(direction);
                wheelPixelRemainder -= direction * wheelPixelStep;
            }

            wheel.accepted = true;
            return;
        }

        const angleDelta = Number(wheel.angleDelta.y);
        if (Number.isFinite(angleDelta) && angleDelta !== 0) {
            wheelPixelRemainder = 0;
            wheelAngleRemainder += angleDelta;
            wheelReset.restart();

            if (Math.abs(wheelAngleRemainder) >= wheelAngleStep) {
                const direction = wheelAngleRemainder > 0 ? 1 : -1;
                dispatchWheelStep(direction);
                wheelAngleRemainder -= direction * wheelAngleStep;
            }

            wheel.accepted = true;
            return;
        }

        wheel.accepted = false;
    }

    function isBmpIconPart(part) {
        return /^[\uF000-\uF8FF]$/u.test(part);
    }

    function isSupplementaryIconPart(part) {
        return /^[\u{F0000}-\u{FFFFF}]$/u.test(part);
    }

    function partFontFamily(part) {
        return Theme.fontFamily;
    }

    function workspacePartYOffset(part) {
        return workspaceButton && !/^\d+$/.test(String(part))
            ? workspaceGlyphYOffset : 0;
    }

    function scaledIconSize(baseSize) {
        const scaled = Math.round(baseSize * iconScale);
        const maxForBar = Math.max(8, barThickness - 2);
        return Math.max(8, Math.min(maxForBar, scaled));
    }

    function scaledTextSize(baseSize) {
        const scaled = Math.round(baseSize * textScale);
        const maxForBar = Math.max(8, barThickness - 2);
        return Math.max(8, Math.min(maxForBar, scaled));
    }

    function partFontPixelSize(part) {
        if (workspaceButton) {
            const token = String(part);
            if (/^\d+$/.test(token))
                return scaledTextSize(Theme.fontPixelSize);
            return scaledIconSize(workspaceGlyphSize > 0 ? workspaceGlyphSize : 18);
        }

        if (fontPixelSize > 0)
            return scaledIconSize(fontPixelSize);

        if (part.indexOf("󰍽") >= 0 || /^[↑↓←→]$/.test(part))
            return scaledIconSize(14);

        // Workspace numbers remain independently text-scaled while the
        // workspace glyph follows the bar icon scale.
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

        return scaledTextSize(Theme.fontPixelSize);
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
        implicitWidth: root.useWorkspaceParts
            ? workspaceRow.implicitWidth
            : (root.useHorizontalParts
                ? horizontalRow.implicitWidth
                : (root.useVerticalParts ? verticalColumn.implicitWidth : normalText.implicitWidth))
        implicitHeight: root.useWorkspaceParts
            ? root.barThickness
            : (root.useHorizontalParts
                ? root.barThickness
                : (root.useVerticalParts ? verticalColumn.implicitHeight : normalText.implicitHeight))

        Text {
            id: normalText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.workspacePartYOffset(root.displayLabel)
            visible: !root.useWorkspaceParts && !root.useHorizontalParts && !root.useVerticalParts
            text: root.displayLabel
            color: root.foreground
            font.family: root.partFontFamily(root.displayLabel)
            font.pixelSize: root.partFontPixelSize(root.displayLabel)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Row {
            id: workspaceRow
            anchors.centerIn: parent
            height: root.barThickness
            spacing: 3
            visible: root.useWorkspaceParts

            Repeater {
                model: root.workspaceParts

                delegate: Item {
                    required property var modelData
                    width: tokenText.implicitWidth
                    height: workspaceRow.height

                    Text {
                        id: tokenText
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: root.workspacePartYOffset(String(parent.modelData))
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

    Timer {
        id: wheelDwell
        interval: Math.max(1, root.wheelActivationDelay)
        repeat: false
        onTriggered: root.wheelReady = true
    }

    Timer {
        id: wheelReset
        interval: 250
        repeat: false
        onTriggered: root.resetWheelAccumulator()
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        scrollGestureEnabled: true

        onContainsMouseChanged: {
            root.resetWheelAccumulator();
            if (containsMouse) {
                hoverRelease.stop();
                root.hovered = true;
                root.wheelReady = root.wheelActivationDelay <= 0;
                if (!root.wheelReady)
                    wheelDwell.restart();
            } else {
                hoverRelease.restart();
                wheelDwell.stop();
                root.wheelReady = root.wheelActivationDelay <= 0;
            }
        }

        onClicked: mouse => {
            // Record the bar that received the click before emitting its action.
            // Floating flyouts use this short-lived value instead of trusting the
            // compositor-selected screen of a window that has already mapped.
            FlyoutManager.armBar(root.monitorName);

            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else if (mouse.button === Qt.MiddleButton)
                root.middleClicked();
            else
                root.clicked();
        }

        onWheel: wheel => root.handleWheel(wheel)
    }

    BarTooltip {
        anchorItem: root
        text: root.effectiveTooltip
        hovered: pointer.containsMouse
        vertical: root.vertical
    }
}
