pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "FlyoutEdgeLayout.js" as FlyoutEdgeLayout

Singleton {
    id: root

    property string placement: "center"
    readonly property bool bottomEdgeLayout: FlyoutEdgeLayout.isBottom(placement)
    property bool settingsOpen: false
    property int panelWidthOverride: -1
    property int panelHeightOverride: -1
    property int textScaleOverride: -1
    property int iconScaleOverride: -1
    property int captureAllowedOverride: -1
    property bool privacyRemapPending: false
    property string settingsMessage: ""
    property var savedView: ({
        width: BarState.defaultBatteryWidth,
        height: BarState.defaultBatteryHeight,
        textScale: 100,
        iconScale: 100,
        captureAllowed: false
    })
    property var stateCommandQueue: []
    property bool openPreparing: false
    property bool panelPresented: false
    readonly property bool available: BatteryState.available
    readonly property int panelFadeDuration: 140
    property var flyoutScreen: null

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_flyout_position.sh"
    readonly property string prepareScript: configHome + "/hypr/scripts/quickshell_flyout_prepare.sh"
    readonly property var activeScreen: flyoutScreen || batteryWindow.screen
    readonly property string activeMonitorName: activeScreen && activeScreen.name
        ? String(activeScreen.name) : ""
    readonly property int targetScreenWidth: activeScreen ? activeScreen.width : 1920
    readonly property int targetScreenHeight: activeScreen ? activeScreen.height : 1080
    readonly property int maximumPanelWidth: Math.max(1, targetScreenWidth - 20)
    readonly property int maximumPanelHeight: Math.max(1, targetScreenHeight - 20)
    readonly property int minimumPanelWidth: Math.min(420, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(360, maximumPanelHeight)
    readonly property int configuredPanelWidth: clampWidth(panelWidthOverride >= 0
        ? panelWidthOverride : BarState.batteryViewFor(activeMonitorName).width)
    readonly property int configuredPanelHeight: clampHeight(panelHeightOverride >= 0
        ? panelHeightOverride : BarState.batteryViewFor(activeMonitorName).height)
    readonly property int livePanelWidth: batteryWindow.visible && batteryWindow.width > 0
        ? clampWidth(Math.round(batteryWindow.width)) : configuredPanelWidth
    readonly property int livePanelHeight: batteryWindow.visible && batteryWindow.height > 0
        ? clampHeight(Math.round(batteryWindow.height)) : configuredPanelHeight
    readonly property int effectiveTextScale: textScaleOverride >= 0
        ? textScaleOverride : BarState.batteryViewFor(activeMonitorName).textScale
    readonly property int effectiveIconScale: iconScaleOverride >= 0
        ? iconScaleOverride : BarState.batteryViewFor(activeMonitorName).iconScale
    readonly property bool captureAllowed: captureAllowedOverride >= 0
        ? captureAllowedOverride === 1 : BarState.captureAllowedFor("battery")
    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed

    onBottomEdgeLayoutChanged: Qt.callLater(() => alignContentToBar())

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0]
            : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function placementForScreen(targetScreen) {
        if (!targetScreen || !BarState.enabledFor(targetScreen.name))
            return "center";
        return BarState.positionFor(targetScreen.name);
    }

    function clampWidth(value) {
        return Math.max(minimumPanelWidth, Math.min(maximumPanelWidth, Math.round(value)));
    }

    function clampHeight(value) {
        return Math.max(minimumPanelHeight, Math.min(maximumPanelHeight, Math.round(value)));
    }

    function applyWindowSize(width, height) {
        panelWidthOverride = clampWidth(width);
        panelHeightOverride = clampHeight(height);
        if (batteryWindow.visible && activeMonitorName.length > 0) {
            Quickshell.execDetached([
                positionScript, "battery", activeMonitorName, placement, "resize",
                String(panelWidthOverride), String(panelHeightOverride)
            ]);
        }
    }

    function positionWindow() {
        if (!batteryWindow.visible || activeMonitorName.length === 0)
            return;
        Quickshell.execDetached([
            positionScript, "battery", activeMonitorName, placement, "spawn"
        ]);
    }

    function prepareWindowOpen(targetScreen) {
        if (!targetScreen)
            return;
        const vertical = placement === "left" || placement === "right";
        const barSize = placement === "center"
            ? 0 : BarState.barSizeFor(targetScreen.name, vertical);
        openPreparing = true;
        prepareProcess.exec([
            "bash", prepareScript, "battery", targetScreen.name, placement,
            String(configuredPanelWidth), String(configuredPanelHeight),
            String(barSize), "-1",
            String(Math.round(targetScreen.width)), String(Math.round(targetScreen.height))
        ]);
    }

    function finishPreparedOpen() {
        if (!openPreparing)
            return;

        const wasVisible = batteryWindow.visible;
        openPreparing = false;
        panelPresented = true;
        batteryWindow.visible = true;
        if (wasVisible)
            Qt.callLater(() => root.positionWindow());
    }

    function scaledText(baseSize) {
        return Math.max(7, Math.round(baseSize * effectiveTextScale / 100));
    }

    function scaledIcon(baseSize) {
        return Math.max(8, Math.round(baseSize * effectiveIconScale / 100));
    }

    function alignContentToBar() {
        const minimumY = contentFlick.originY;
        const maximumY = Math.max(minimumY,
            minimumY + contentFlick.contentHeight - contentFlick.height);
        contentFlick.contentY = bottomEdgeLayout ? maximumY : minimumY;
    }

    function batteryIcon(percent) {
        if (percent >= 90) return "";
        if (percent >= 65) return "";
        if (percent >= 40) return "";
        if (percent >= 15) return "";
        return "";
    }

    function batteryDetailText() {
        const lines = BatteryState.barTooltip.split("\n");
        if (lines.length > 1)
            return lines.slice(1).join("\n");
        return BatteryState.pluggedIn ? "Plugged in" : "Battery status unavailable";
    }

    function otherMonitorNames() {
        return Quickshell.screens
            .map(target => target ? target.name : "")
            .filter(name => name.length > 0 && name !== activeMonitorName);
    }

    function loadSavedView(targetScreen) {
        if (!targetScreen)
            return;
        BarState.refresh();
        const persisted = BarState.batteryViewFor(targetScreen.name);
        panelWidthOverride = clampWidth(persisted.width);
        panelHeightOverride = clampHeight(persisted.height);
        textScaleOverride = persisted.textScale;
        iconScaleOverride = persisted.iconScale;
        captureAllowedOverride = BarState.captureAllowedFor("battery") ? 1 : 0;
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: textScaleOverride,
            iconScale: iconScaleOverride,
            captureAllowed: captureAllowed
        });
    }

    function acceptDraftAsSaved() {
        savedView = ({
            width: livePanelWidth,
            height: livePanelHeight,
            textScale: effectiveTextScale,
            iconScale: effectiveIconScale,
            captureAllowed: captureAllowed
        });
    }

    function discardDraft() {
        const width = savedView.width;
        const height = savedView.height;
        textScaleOverride = savedView.textScale;
        iconScaleOverride = savedView.iconScale;
        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;
        applyWindowSize(width, height);
    }

    function queueStateCommand(commandArgs) {
        const nextQueue = stateCommandQueue.slice();
        nextQueue.push(commandArgs);
        stateCommandQueue = nextQueue;
        runNextStateCommand();
    }

    function runNextStateCommand() {
        if (stateWriter.running || stateCommandQueue.length === 0)
            return;
        const nextCommand = stateCommandQueue[0];
        stateCommandQueue = stateCommandQueue.slice(1);
        stateWriter.exec([stateScript, ...nextCommand]);
    }

    function saveDisplaySettings() {
        if (activeMonitorName.length === 0 || !settingsDirty)
            return;
        queueStateCommand([
            "save-flyout", "battery", activeMonitorName,
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            captureAllowed ? "true" : "false"
        ]);
        panelWidthOverride = livePanelWidth;
        panelHeightOverride = livePanelHeight;
        acceptDraftAsSaved();
        settingsMessage = "Saved Battery settings for " + activeMonitorName;
    }

    function resetDisplaySettings() {
        if (activeMonitorName.length === 0)
            return;
        const wasCaptureAllowed = captureAllowed;
        textScaleOverride = 100;
        iconScaleOverride = 100;
        captureAllowedOverride = 0;
        applyWindowSize(BarState.defaultBatteryWidth, BarState.defaultBatteryHeight);
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: 100,
            iconScale: 100,
            captureAllowed: false
        });
        privacyRemapPending = wasCaptureAllowed;
        queueStateCommand(["reset-flyout", "battery", activeMonitorName]);
        settingsMessage = "Battery defaults restored for " + activeMonitorName;
    }

    function copyDisplaySettings(targets) {
        if (!targets || targets.length === 0)
            return;
        queueStateCommand([
            "copy-flyout", "battery",
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            ...targets
        ]);
        settingsMessage = "Copied Battery settings to " + targets.length
            + (targets.length === 1 ? " display" : " displays");
    }

    function adjustPanelWidth(delta) {
        applyWindowSize(livePanelWidth + delta, livePanelHeight);
        settingsMessage = "Width " + panelWidthOverride + " px";
    }

    function adjustPanelHeight(delta) {
        applyWindowSize(livePanelWidth, livePanelHeight + delta);
        settingsMessage = "Height " + panelHeightOverride + " px";
    }

    function adjustTextScale(delta) {
        textScaleOverride = Math.max(50, Math.min(200, effectiveTextScale + delta));
        settingsMessage = "Text size " + textScaleOverride + "%";
    }

    function adjustIconScale(delta) {
        iconScaleOverride = Math.max(50, Math.min(200, effectiveIconScale + delta));
        settingsMessage = "Icon size " + iconScaleOverride + "%";
    }

    function toggleCaptureAllowed() {
        const next = !captureAllowed;
        captureAllowedOverride = next ? 1 : 0;
        savedView = Object.assign({}, savedView, { captureAllowed: next });
        privacyRemapPending = true;
        queueStateCommand(["set-capture", "battery", next ? "true" : "false"]);
        settingsMessage = next
            ? "Battery is visible in captures" : "Battery capture protection enabled";
    }

    function toggleSettings() {
        settingsOpen = !settingsOpen;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function openForScreen(targetScreen) {
        if (!targetScreen || !available)
            return;
        FlyoutManager.claim("battery", targetScreen.name);
        flyoutScreen = targetScreen;
        if (!batteryWindow.visible)
            batteryWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        loadSavedView(targetScreen);
        prepareWindowOpen(targetScreen);
    }

    function openFocused() {
        openForScreen(focusedScreen());
    }

    function close() {
        openPreparing = false;
        if (prepareProcess.running)
            prepareProcess.running = false;
        if (settingsDirty)
            discardDraft();
        batteryWindow.visible = false;
        panelPresented = false;
        FlyoutManager.release("battery");
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function toggleForScreen(targetScreen) {
        if (!FlyoutManager.acceptToggle("battery"))
            return;
        const currentName = activeMonitorName;
        const targetName = targetScreen ? targetScreen.name : "";
        if ((batteryWindow.visible || openPreparing)
            && currentName.length > 0 && currentName === targetName)
            close();
        else
            openForScreen(targetScreen);
    }

    onAvailableChanged: {
        if (!available && (batteryWindow.visible || openPreparing))
            close();
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "battery"
                && (batteryWindow.visible || root.openPreparing))
                root.close();
        }
    }

    Process {
        id: prepareProcess
        onExited: root.finishPreparedOpen()
    }

    Process {
        id: stateWriter
        onExited: {
            BarState.refresh();
            privacyRuleUpdater.exec([root.runtimeRulesScript]);
            Qt.callLater(() => root.runNextStateCommand());
        }
    }

    Process {
        id: privacyRuleUpdater
        onExited: {
            if (!root.privacyRemapPending)
                return;
            root.privacyRemapPending = false;
            if (!batteryWindow.visible)
                return;
            batteryWindow.visible = false;
            Qt.callLater(() => {
                if (FlyoutManager.activeSurface !== "battery")
                    return;
                batteryWindow.visible = true;
                root.positionWindow();
            });
        }
    }

    IpcHandler {
        target: "battery"
        function available(): bool { return root.available; }
        function toggle(): void { root.toggleForScreen(root.focusedScreen()); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
    }

    FloatingWindow {
        id: batteryWindow
        visible: false
        title: "Awtarchy Battery"
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: root.configuredPanelWidth
        implicitHeight: root.configuredPanelHeight
        minimumSize: Qt.size(root.minimumPanelWidth, root.minimumPanelHeight)
        maximumSize: Qt.size(root.maximumPanelWidth, root.maximumPanelHeight)

        onClosed: root.close()
        onVisibleChanged: {
            if (visible) {
                Qt.callLater(() => root.positionWindow());
                Qt.callLater(() => root.alignContentToBar());
            }
        }

        Rectangle {
            id: panel
            opacity: root.panelPresented ? 1 : 0

            Behavior on opacity {
                enabled: FlyoutManager.animationsEnabled
                NumberAnimation {
                    duration: root.panelFadeDuration
                    easing.type: Easing.OutCubic
                }
            }

            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 0
            focus: true
            Keys.onEscapePressed: root.close()

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: mouse => mouse.accepted = true
            }

            GridLayout {
                anchors.fill: parent
                columns: 1
                rowSpacing: 0
                columnSpacing: 0

                Rectangle {
                    Layout.row: root.bottomEdgeLayout ? 2 : 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(38, root.scaledText(13) + 18)
                    color: Theme.active
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 7
                        spacing: 7

                        Text {
                            text: root.batteryIcon(BatteryState.percentage)
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledIcon(14)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Battery · " + BatteryState.percentage + "%"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledText(13)
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        SettingsButton {
                            label: ""
                            available: root.settingsDirty
                            textSize: root.scaledIcon(12)
                            horizontalPadding: 10
                            onClicked: root.saveDisplaySettings()
                        }

                        CaptureEyeButton {
                            captureAllowed: root.captureAllowed
                            textSize: root.scaledIcon(12)
                            onClicked: root.toggleCaptureAllowed()
                        }

                        SettingsButton {
                            label: ""
                            active: root.settingsOpen
                            textSize: root.scaledIcon(12)
                            horizontalPadding: 10
                            onClicked: root.toggleSettings()
                        }

                        SettingsButton {
                            label: "×"
                            textSize: root.scaledIcon(14)
                            horizontalPadding: 10
                            onClicked: root.close()
                        }
                    }
                }

                Rectangle {
                    Layout.row: 1
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.settingsOpen ? settingsPanel.implicitHeight + 12 : 0
                    visible: root.settingsOpen
                    color: Theme.popupButton
                    border.width: 0
                    clip: true

                    FlyoutSettings {
                        id: settingsPanel
                        anchors.fill: parent
                        anchors.margins: 6
                        surfaceLabel: "Battery"
                        monitorName: root.activeMonitorName
                        panelWidth: root.livePanelWidth
                        panelHeight: root.livePanelHeight
                        minimumWidth: root.minimumPanelWidth
                        maximumWidth: root.maximumPanelWidth
                        minimumHeight: root.minimumPanelHeight
                        maximumHeight: root.maximumPanelHeight
                        textScale: root.effectiveTextScale
                        iconScale: root.effectiveIconScale
                        captureAllowed: false
                        showCaptureControl: false
                        message: root.settingsMessage
                        otherMonitorNames: root.otherMonitorNames()

                        onResetRequested: root.resetDisplaySettings()
                        onWidthAdjustmentRequested: delta => root.adjustPanelWidth(delta)
                        onHeightAdjustmentRequested: delta => root.adjustPanelHeight(delta)
                        onTextScaleAdjustmentRequested: delta => root.adjustTextScale(delta)
                        onIconScaleAdjustmentRequested: delta => root.adjustIconScale(delta)
                        onCopyRequested: monitorNames => root.copyDisplaySettings(monitorNames)
                    }
                }

                Item {
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: contentFlick
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        anchors.rightMargin: contentScrollBar.visible ? 19 : 6
                        contentWidth: width
                        contentHeight: Math.max(height, contentColumn.implicitHeight)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        GridLayout {
                            id: contentColumn
                            columns: 1
                            y: root.bottomEdgeLayout
                                ? Math.max(0, contentFlick.contentHeight - implicitHeight) : 0
                            width: contentFlick.width
                            rowSpacing: 8
                            columnSpacing: 0

                            Rectangle {
                                Layout.row: FlyoutEdgeLayout.sectionRow(root.bottomEdgeLayout, 0, 2)
                                Layout.fillWidth: true
                                Layout.preferredHeight: batteryContent.implicitHeight + 18
                                color: Theme.popupButton
                                border.width: 1
                                border.color: Theme.active

                                ColumnLayout {
                                    id: batteryContent
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: root.batteryIcon(BatteryState.percentage)
                                            color: BatteryState.percentage <= 15 && BatteryState.discharging
                                                ? Theme.critical : Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledIcon(24)
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                Layout.fillWidth: true
                                                text: BatteryState.percentage + "%"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(21)
                                                font.bold: true
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: root.batteryDetailText()
                                                color: Theme.muted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(10)
                                                wrapMode: Text.Wrap
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 18
                                        color: Theme.active
                                        border.width: 0

                                        Rectangle {
                                            width: parent.width * BatteryState.percentage / 100
                                            height: parent.height
                                            color: BatteryState.percentage <= 15 && BatteryState.discharging
                                                ? Theme.critical : Theme.focus
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: BatteryState.healthSupported

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Battery health"
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(9)
                                        }

                                        Text {
                                            text: BatteryState.healthPercentage + "%"
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(9)
                                            font.bold: true
                                        }
                                    }
                                }
                            }

                            PowerModeCard {
                                Layout.row: FlyoutEdgeLayout.sectionRow(root.bottomEdgeLayout, 1, 2)
                                presentationEnabled: true
                                active: batteryWindow.visible
                                textScale: root.effectiveTextScale
                                iconScale: root.effectiveIconScale
                            }
                        }
                    }

                    ListScrollBar {
                        id: contentScrollBar
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        flickable: contentFlick
                    }
                }
            }
        }
    }
}
