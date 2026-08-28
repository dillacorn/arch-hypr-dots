pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import "FlyoutEdgeLayout.js" as FlyoutEdgeLayout

Singleton {
    id: root

    property string placement: "center"
    readonly property bool bottomEdgeLayout: FlyoutEdgeLayout.isBottom(placement)
    property string actionMessage: ""
    property bool settingsOpen: false
    property int panelWidthOverride: -1
    property int panelHeightOverride: -1
    property int textScaleOverride: -1
    property int iconScaleOverride: -1
    property int captureAllowedOverride: -1
    property int actualAdapterEnabled: -1
    property bool privacyRemapPending: false
    property string settingsMessage: ""
    property var savedView: ({
        width: BarState.defaultBluetoothWidth,
        height: BarState.defaultBluetoothHeight,
        textScale: 100,
        iconScale: 100,
        captureAllowed: false
    })
    property var stateCommandQueue: []
    property bool openPreparing: false
    property bool panelPresented: false
    readonly property int panelFadeDuration: 140
    property var flyoutScreen: null

    readonly property var adapters: Bluetooth.adapters
        ? [...Bluetooth.adapters.values].filter(item => item !== null) : []
    readonly property var adapter: Bluetooth.defaultAdapter
        || (adapters.length > 0 ? adapters[0] : null)
    readonly property bool available: adapters.length > 0 && adapter !== null
    readonly property int adapterState: adapter ? adapter.state : BluetoothAdapterState.Disabled
    readonly property bool adapterEnabled: actualAdapterEnabled >= 0
        ? actualAdapterEnabled === 1 : adapter !== null && adapter.enabled
    readonly property bool adapterDiscovering: adapter !== null && adapter.discovering
    readonly property bool adapterBlocked: adapter !== null
        && adapter.state === BluetoothAdapterState.Blocked
    readonly property var connectedDevices: devices().filter(device => device.connected)
    readonly property string barLabel: buildBarLabel()
    readonly property string verticalBarLabel: connectedDevices.length > 0
        ? "\n" + connectedDevices.length : ""
    readonly property string barTooltip: buildBarTooltip()
    readonly property color barForeground: adapterEnabled ? Theme.foreground : Theme.muted
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_flyout_position.sh"
    readonly property string prepareScript: configHome + "/hypr/scripts/quickshell_flyout_prepare.sh"
    readonly property string bluetoothStateScript: configHome + "/hypr/scripts/quickshell_bluetooth_state.sh"
    readonly property var activeScreen: flyoutScreen || bluetoothWindow.screen
    readonly property string activeMonitorName: activeScreen && activeScreen.name
        ? String(activeScreen.name) : ""
    readonly property int targetScreenWidth: activeScreen ? activeScreen.width : 1920
    readonly property int targetScreenHeight: activeScreen ? activeScreen.height : 1080
    readonly property int maximumPanelWidth: Math.max(1, targetScreenWidth - 20)
    readonly property int maximumPanelHeight: Math.max(1, targetScreenHeight - 20)
    readonly property int minimumPanelWidth: Math.min(360, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(360, maximumPanelHeight)
    readonly property int configuredPanelWidth: clampWidth(panelWidthOverride >= 0
        ? panelWidthOverride : BarState.bluetoothViewFor(activeMonitorName).width)
    readonly property int configuredPanelHeight: clampHeight(panelHeightOverride >= 0
        ? panelHeightOverride : BarState.bluetoothViewFor(activeMonitorName).height)
    readonly property int livePanelWidth: bluetoothWindow.visible && bluetoothWindow.width > 0
        ? clampWidth(Math.round(bluetoothWindow.width)) : configuredPanelWidth
    readonly property int livePanelHeight: bluetoothWindow.visible && bluetoothWindow.height > 0
        ? clampHeight(Math.round(bluetoothWindow.height)) : configuredPanelHeight
    readonly property int effectiveTextScale: textScaleOverride >= 0
        ? textScaleOverride : BarState.bluetoothViewFor(activeMonitorName).textScale
    readonly property int effectiveIconScale: iconScaleOverride >= 0
        ? iconScaleOverride : BarState.bluetoothViewFor(activeMonitorName).iconScale
    readonly property bool captureAllowed: captureAllowedOverride >= 0
        ? captureAllowedOverride === 1 : BarState.captureAllowedFor("bluetooth")
    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed

    onBottomEdgeLayoutChanged: Qt.callLater(() => alignContentToBar())

    function devices() {
        const current = adapter;
        if (!current || !current.devices)
            return [];
        return [...current.devices.values]
            .filter(device => device !== null)
            .sort((left, right) => {
                if (Boolean(left.connected) !== Boolean(right.connected))
                    return left.connected ? -1 : 1;
                if (Boolean(left.paired) !== Boolean(right.paired))
                    return left.paired ? -1 : 1;
                return deviceName(left).localeCompare(deviceName(right));
            });
    }

    function deviceName(device) {
        return String(device && (device.name || device.deviceName || device.address)
            || "Bluetooth device");
    }

    function shortDeviceName(device) {
        const name = deviceName(device);
        return name.length > 18 ? name.slice(0, 17) + "…" : name;
    }

    function batteryText(device) {
        if (!device || !device.batteryAvailable)
            return "";
        return " · " + Math.round(Number(device.battery || 0) * 100) + "%";
    }

    function buildBarLabel() {
        if (connectedDevices.length === 1)
            return " " + shortDeviceName(connectedDevices[0]);
        if (connectedDevices.length > 1)
            return " " + connectedDevices.length;
        return "";
    }

    function buildBarTooltip() {
        if (!adapter)
            return "Bluetooth adapter unavailable";
        if (adapterBlocked)
            return "Bluetooth blocked by rfkill\nClick: Bluetooth devices";
        if (!adapterEnabled)
            return "Bluetooth disabled\nClick: Bluetooth devices";
        if (connectedDevices.length === 0)
            return "Bluetooth enabled · no device connected\nClick: Bluetooth devices";
        const lines = connectedDevices.map(device => "Connected: " + deviceName(device)
            + batteryText(device));
        lines.push("Click: Bluetooth devices");
        return lines.join("\n");
    }

    function refreshActualAdapterPower() {
        if (!bluetoothPowerProbe.running)
            bluetoothPowerProbe.exec([bluetoothStateScript, "actual"]);
    }

    function applyActualAdapterPower(text) {
        const state = String(text || "").trim();
        if (state === "enabled")
            actualAdapterEnabled = 1;
        else if (state === "disabled")
            actualAdapterEnabled = 0;
        else
            actualAdapterEnabled = -1;
    }

    function toggleAdapter() {
        const current = adapter;
        if (!current) {
            actionMessage = "Bluetooth adapter unavailable";
            return;
        }

        const enableRequested = !adapterEnabled
            || current.state === BluetoothAdapterState.Blocked;
        if (enableRequested) {
            actionMessage = "Enabling Bluetooth…";
            bluetoothEnable.exec([bluetoothStateScript, "set", "enabled"]);
            return;
        }

        if (current.discovering)
            current.discovering = false;
        actionMessage = "Disabling Bluetooth…";
        bluetoothDisable.exec([bluetoothStateScript, "set", "disabled"]);
    }

    function retryEnableAfterRfkill() {
        const current = adapter;
        if (!current) {
            actionMessage = "Bluetooth adapter unavailable";
            return;
        }
        if (current.state === BluetoothAdapterState.Blocked) {
            actionMessage = "Bluetooth is still blocked by rfkill";
            return;
        }
        current.enabled = true;
        actualAdapterEnabled = 1;
        refreshActualAdapterPower();
        actionMessage = "Bluetooth enabled";
    }

    function toggleDiscovery() {
        const current = adapter;
        if (!current || !adapterEnabled)
            return;
        const nextDiscovering = !current.discovering;
        current.discovering = nextDiscovering;
        actionMessage = nextDiscovering ? "Scanning for devices…" : "Scan stopped";
    }

    function toggleDevice(device) {
        if (!device)
            return;
        const name = deviceName(device);
        if (device.connected) {
            device.disconnect();
            actionMessage = "Disconnecting " + name + "…";
        } else if (device.paired) {
            device.connect();
            actionMessage = "Connecting " + name + "…";
        } else if (device.pairing) {
            device.cancelPair();
            actionMessage = "Cancelling pairing with " + name + "…";
        } else {
            device.pair();
            actionMessage = "Pairing " + name + "…";
        }
    }

    function forgetDevice(device) {
        if (!device || !device.paired)
            return;
        actionMessage = "Forgetting " + deviceName(device) + "…";
        device.forget();
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0]
            : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function placementForScreen(targetScreen) {
        if (!targetScreen || !FlyoutManager.barVisibleOnMonitor(targetScreen.name))
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
        if (bluetoothWindow.visible && activeMonitorName.length > 0) {
            Quickshell.execDetached([
                positionScript, "bluetooth", activeMonitorName, placement, "resize",
                String(panelWidthOverride), String(panelHeightOverride)
            ]);
        }
    }

    function positionWindow() {
        if (!bluetoothWindow.visible || activeMonitorName.length === 0)
            return;
        Quickshell.execDetached([
            positionScript, "bluetooth", activeMonitorName, placement, "spawn"
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
            "bash", prepareScript, "bluetooth", targetScreen.name, placement,
            String(configuredPanelWidth), String(configuredPanelHeight),
            String(barSize), "-1",
            String(Math.round(targetScreen.width)), String(Math.round(targetScreen.height))
        ]);
    }

    function finishPreparedOpen() {
        if (!openPreparing)
            return;

        const wasVisible = bluetoothWindow.visible;

        openPreparing = false;
        panelPresented = true;
        bluetoothWindow.visible = true;
        if (wasVisible)
            Qt.callLater(() => root.positionWindow());
        const current = adapter;
        if (current && adapterEnabled)
            current.discovering = true;
    }

    function scaledText(baseSize) {
        return Math.max(7, Math.round(baseSize * effectiveTextScale / 100));
    }

    function scaledIcon(baseSize) {
        return Math.max(8, Math.round(baseSize * effectiveIconScale / 100));
    }

    function alignContentToBar() {
        const minimumY = bluetoothFlick.originY;
        const maximumY = Math.max(minimumY,
            minimumY + bluetoothFlick.contentHeight - bluetoothFlick.height);
        bluetoothFlick.contentY = bottomEdgeLayout ? maximumY : minimumY;
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
        const persisted = BarState.bluetoothViewFor(targetScreen.name);
        panelWidthOverride = clampWidth(persisted.width);
        panelHeightOverride = clampHeight(persisted.height);
        textScaleOverride = persisted.textScale;
        iconScaleOverride = persisted.iconScale;
        captureAllowedOverride = BarState.captureAllowedFor("bluetooth") ? 1 : 0;
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
            "save-flyout", "bluetooth", activeMonitorName,
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            captureAllowed ? "true" : "false"
        ]);
        panelWidthOverride = livePanelWidth;
        panelHeightOverride = livePanelHeight;
        acceptDraftAsSaved();
        settingsMessage = "Saved Bluetooth settings for " + activeMonitorName;
    }

    function resetDisplaySettings() {
        if (activeMonitorName.length === 0)
            return;
        const wasCaptureAllowed = captureAllowed;
        textScaleOverride = 100;
        iconScaleOverride = 100;
        captureAllowedOverride = 0;
        applyWindowSize(BarState.defaultBluetoothWidth, BarState.defaultBluetoothHeight);
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: 100,
            iconScale: 100,
            captureAllowed: false
        });
        privacyRemapPending = wasCaptureAllowed;
        queueStateCommand(["reset-flyout", "bluetooth", activeMonitorName]);
        settingsMessage = "Bluetooth defaults restored for " + activeMonitorName;
    }

    function copyDisplaySettings(targets) {
        if (!targets || targets.length === 0)
            return;
        queueStateCommand([
            "copy-flyout", "bluetooth",
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            ...targets
        ]);
        settingsMessage = "Copied Bluetooth settings to " + targets.length
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
        queueStateCommand(["set-capture", "bluetooth", next ? "true" : "false"]);
        settingsMessage = next
            ? "Bluetooth is visible in captures" : "Bluetooth capture protection enabled";
    }

    function toggleSettings() {
        settingsOpen = !settingsOpen;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function openForScreen(targetScreen) {
        if (!targetScreen || !available)
            return;
        refreshActualAdapterPower();
        FlyoutManager.claim("bluetooth", targetScreen.name);
        flyoutScreen = targetScreen;
        if (!bluetoothWindow.visible)
            bluetoothWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        actionMessage = adapterBlocked ? "Bluetooth is blocked by rfkill" : "";
        settingsOpen = false;
        settingsMessage = "";
        settingsPanel.resetCopySelection();
        loadSavedView(targetScreen);
        prepareWindowOpen(targetScreen);
    }

    function close() {
        openPreparing = false;
        if (prepareProcess.running)
            prepareProcess.running = false;
        if (settingsDirty)
            discardDraft();
        bluetoothWindow.visible = false;
        panelPresented = false;
        const current = adapter;
        if (current && current.discovering)
            current.discovering = false;
        actionMessage = "";
        settingsOpen = false;
        settingsMessage = "";
        settingsPanel.resetCopySelection();
        FlyoutManager.release("bluetooth");
    }

    function toggleForScreen(targetScreen) {
        if (!FlyoutManager.acceptToggle("bluetooth"))
            return;
        const currentName = activeMonitorName;
        const targetName = targetScreen ? targetScreen.name : "";
        if ((bluetoothWindow.visible || openPreparing) && currentName === targetName)
            close();
        else
            openForScreen(targetScreen);
    }

    onAvailableChanged: {
        if (!available && (bluetoothWindow.visible || openPreparing))
            close();
        if (available)
            refreshActualAdapterPower();
    }

    Component.onCompleted: bluetoothRestore.exec([bluetoothStateScript, "restore"])

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "bluetooth"
                && (bluetoothWindow.visible || root.openPreparing))
                root.close();
        }
    }

    Connections {
        target: root.adapter
        function onStateChanged() { root.refreshActualAdapterPower(); }
    }

    Process {
        id: prepareProcess
        onExited: root.finishPreparedOpen()
    }

    Process {
        id: bluetoothEnable
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.actionMessage = "Failed to enable Bluetooth";
                root.refreshActualAdapterPower();
                return;
            }
            root.actualAdapterEnabled = 1;
            rfkillRetry.restart();
        }
    }

    Process {
        id: bluetoothDisable
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.actualAdapterEnabled = 0;
            root.actionMessage = exitCode === 0
                ? "Bluetooth disabled" : "Failed to disable Bluetooth";
            root.refreshActualAdapterPower();
        }
    }

    Process {
        id: bluetoothRestore
        onExited: root.refreshActualAdapterPower()
    }

    Process {
        id: bluetoothPowerProbe
        stdout: StdioCollector {
            onStreamFinished: root.applyActualAdapterPower(text)
        }
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
            if (!bluetoothWindow.visible)
                return;
            bluetoothWindow.visible = false;
            Qt.callLater(() => {
                bluetoothWindow.visible = true;
                root.positionWindow();
            });
        }
    }

    Timer {
        id: rfkillRetry
        interval: 300
        repeat: false
        onTriggered: root.retryEnableAfterRfkill()
    }

    IpcHandler {
        target: "bluetooth"
        function available(): bool { return root.available; }
        function toggle(): void { root.toggleForScreen(root.focusedScreen()); }
        function open(): void { root.openForScreen(root.focusedScreen()); }
        function close(): void { root.close(); }
    }


    FloatingWindow {
        id: bluetoothWindow
        visible: false
        title: "Awtarchy Bluetooth"
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
                            text: ""
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledIcon(14)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.actionMessage.length > 0
                                ? "Bluetooth · " + root.actionMessage : "Bluetooth"
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
                        surfaceLabel: "Bluetooth"
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

                Flickable {
                    id: bluetoothFlick
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: Math.max(height, bluetoothColumn.implicitHeight + 12)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    GridLayout {
                        id: bluetoothColumn
                        columns: 1
                        x: 6
                        y: root.bottomEdgeLayout
                            ? Math.max(6, bluetoothFlick.contentHeight - implicitHeight - 6) : 6
                        width: bluetoothFlick.width - (bluetoothScroll.visible ? 26 : 12)
                        rowSpacing: 8
                        columnSpacing: 0

                        Rectangle {
                            Layout.row: FlyoutEdgeLayout.sectionRow(root.bottomEdgeLayout, 0, 2)
                            Layout.fillWidth: true
                            Layout.preferredHeight: adapterContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: adapterContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 7

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: root.adapter
                                            ? (root.adapter.name || root.adapter.adapterId || "Bluetooth adapter")
                                            : "Bluetooth adapter"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    SettingsButton {
                                        label: root.adapterEnabled ? "On" : "Off"
                                        active: root.adapterEnabled
                                        available: root.adapter !== null
                                        textSize: root.scaledText(9)
                                        onClicked: root.toggleAdapter()
                                    }
                                    SettingsButton {
                                        label: root.adapterDiscovering ? "Scanning…" : "Scan"
                                        active: root.adapterDiscovering
                                        available: root.adapterEnabled
                                        textSize: root.scaledText(9)
                                        onClicked: root.toggleDiscovery()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: root.adapter !== null && !root.adapterEnabled
                                    text: root.adapterBlocked
                                        ? "Bluetooth is blocked by rfkill"
                                        : "Bluetooth is disabled"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.row: FlyoutEdgeLayout.sectionRow(root.bottomEdgeLayout, 1, 2)
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                visible: root.adapterEnabled && root.devices().length === 0
                                text: root.adapterDiscovering
                                    ? "Scanning for Bluetooth devices…" : "No Bluetooth devices found"
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: root.scaledText(9)
                            }

                            Repeater {
                                model: ScriptModel {
                                    values: root.adapterEnabled
                                        ? (root.bottomEdgeLayout ? root.devices().slice().reverse() : root.devices())
                                        : []
                                }

                                Rectangle {
                                    id: deviceRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.max(48,
                                        root.scaledText(10) + root.scaledText(8) + 20)
                                    color: modelData.connected ? Theme.active : Theme.popupButton
                                    border.width: 1
                                    border.color: modelData.connected ? Theme.focus : Theme.active

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 7
                                        anchors.rightMargin: 5
                                        spacing: 7

                                    Text {
                                        text: deviceRow.modelData.connected ? "●" : ""
                                        color: deviceRow.modelData.connected ? Theme.focus : Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledIcon(11)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.deviceName(deviceRow.modelData)
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(10)
                                            font.bold: deviceRow.modelData.connected
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (deviceRow.modelData.connected ? "connected"
                                                : (deviceRow.modelData.pairing ? "pairing"
                                                    : (deviceRow.modelData.paired ? "paired" : "available")))
                                                + root.batteryText(deviceRow.modelData)
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            elide: Text.ElideRight
                                        }
                                    }
                                    SettingsButton {
                                        visible: deviceRow.modelData.paired && !deviceRow.modelData.connected
                                        label: "Forget"
                                        textSize: root.scaledText(8)
                                        onClicked: root.forgetDevice(deviceRow.modelData)
                                    }
                                        SettingsButton {
                                            label: deviceRow.modelData.connected ? "Disconnect"
                                                : (deviceRow.modelData.pairing ? "Cancel"
                                                    : (deviceRow.modelData.paired ? "Connect" : "Pair"))
                                            active: deviceRow.modelData.connected
                                            textSize: root.scaledText(9)
                                            onClicked: root.toggleDevice(deviceRow.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ListScrollBar {
                        id: bluetoothScroll
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        flickable: bluetoothFlick
                        z: 10
                    }
                }
            }
        }
    }
}
