pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland

Singleton {
    id: root

    property var statusData: emptyStatus()
    property bool statusLoading: false
    property bool refreshPending: false
    property string actionMessage: ""
    property string actionError: ""
    property var actionQueue: []
    property string placement: "center"
    property string brightnessTarget: ""
    property string selectedSchedulerName: ""
    property bool schedulerEditorOpen: false
    property string schedulerArgsDraft: ""
    property bool schedulerArgsDirty: false
    property var pendingWifiNetwork: null
    property string wifiPassword: ""
    property bool settingsOpen: false
    property int panelWidthOverride: -1
    property int panelHeightOverride: -1
    property int textScaleOverride: -1
    property int iconScaleOverride: -1
    property int captureAllowedOverride: -1
    property string settingsMessage: ""
    property var savedView: ({
        width: BarState.defaultQuickSettingsWidth,
        height: BarState.defaultQuickSettingsHeight,
        textScale: 100,
        iconScale: 100,
        captureAllowed: false
    })
    property var stateCommandQueue: []

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string backend: configHome + "/hypr/scripts/hypr_quicksettings.sh"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string activeMonitorName: quickSettingsWindow.screen ? quickSettingsWindow.screen.name : ""
    readonly property int activeBarSize: {
        const target = quickSettingsWindow.screen;
        if (!target || placement === "center")
            return 0;
        return BarState.barSizeFor(target.name, placement === "left" || placement === "right");
    }
    readonly property int maximumPanelWidth: Math.max(1, quickSettingsWindow.width
        - ((placement === "left" || placement === "right") ? activeBarSize : 0) - 20)
    readonly property int maximumPanelHeight: Math.max(1, quickSettingsWindow.height
        - ((placement === "top" || placement === "bottom") ? activeBarSize : 0) - 20)
    readonly property int minimumPanelWidth: Math.min(520, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(460, maximumPanelHeight)
    readonly property int livePanelWidth: clampWidth(panelWidthOverride >= 0
        ? panelWidthOverride : BarState.quickSettingsViewFor(activeMonitorName).width)
    readonly property int livePanelHeight: clampHeight(panelHeightOverride >= 0
        ? panelHeightOverride : BarState.quickSettingsViewFor(activeMonitorName).height)
    readonly property int effectiveTextScale: textScaleOverride >= 0
        ? textScaleOverride : BarState.quickSettingsViewFor(activeMonitorName).textScale
    readonly property int effectiveIconScale: iconScaleOverride >= 0
        ? iconScaleOverride : BarState.quickSettingsViewFor(activeMonitorName).iconScale
    readonly property bool captureAllowed: captureAllowedOverride >= 0
        ? captureAllowedOverride === 1 : BarState.captureAllowedFor("quick_settings")
    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed
    readonly property var brightnessStatus: statusData.brightness || ({})
    readonly property var barStatus: statusData.bar || ({})
    readonly property var nightLightStatus: statusData.night_light || ({})
    readonly property var vibranceStatus: statusData.vibrance || ({})
    readonly property var schedulerStatus: statusData.sched_ext || ({ schedulers: [] })
    readonly property var wifiDevice: firstWifiDevice()
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property int brightnessPercent: {
        const current = Number(brightnessStatus.current);
        const maximum = Number(brightnessStatus.max);
        if (!Number.isFinite(current) || !Number.isFinite(maximum) || maximum <= 0)
            return -1;
        return Math.max(0, Math.min(100, Math.round(current * 100 / maximum)));
    }

    function emptyStatus() {
        return ({
            monitors: [],
            brightness: { target: "", connector: "", current: null, max: null },
            bar: { monitor: "", position: "top", enabled: true },
            night_light: { temperature: null, identity: "unknown", enabled: false },
            vibrance: { value: null, enabled: false },
            submap: "reset",
            sched_ext: {
                running: "off",
                mode: "",
                enabled: false,
                available: false,
                authorized: false,
                schedulers: []
            }
        });
    }

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

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * effectiveTextScale / 100));
    }

    function scaledIcon(baseSize) {
        return Math.max(9, Math.round(baseSize * effectiveIconScale / 100));
    }

    function monitorNames() {
        const values = statusData.monitors || [];
        return values.map(monitor => String(monitor.name || "")).filter(name => name.length > 0);
    }

    function firstWifiDevice() {
        const devices = Networking.devices ? Networking.devices.values : [];
        for (const device of devices) {
            if (device && device.type === DeviceType.Wifi)
                return device;
        }
        return null;
    }

    function wiredDevices() {
        const devices = Networking.devices ? Networking.devices.values : [];
        return [...devices].filter(device => device && device.type === DeviceType.Wired);
    }

    function wifiNetworks() {
        if (!wifiDevice || !wifiDevice.networks)
            return [];
        return [...wifiDevice.networks.values].sort((left, right) => {
            if (Boolean(left.connected) !== Boolean(right.connected))
                return left.connected ? -1 : 1;
            if (Boolean(left.known) !== Boolean(right.known))
                return left.known ? -1 : 1;
            return Number(right.signalStrength || 0) - Number(left.signalStrength || 0);
        });
    }

    function bluetoothDevices() {
        if (!bluetoothAdapter || !bluetoothAdapter.devices)
            return [];
        return [...bluetoothAdapter.devices.values].sort((left, right) => {
            if (Boolean(left.connected) !== Boolean(right.connected))
                return left.connected ? -1 : 1;
            if (Boolean(left.paired) !== Boolean(right.paired))
                return left.paired ? -1 : 1;
            return String(left.name || left.deviceName || "")
                .localeCompare(String(right.name || right.deviceName || ""));
        });
    }

    function wifiNeedsPassword(network) {
        if (!network || network.known)
            return false;
        return network.security === WifiSecurityType.WpaPsk
            || network.security === WifiSecurityType.Wpa2Psk
            || network.security === WifiSecurityType.Sae;
    }

    function wifiSecurityLabel(network) {
        if (!network)
            return "";
        if (network.security === WifiSecurityType.Open)
            return "Open";
        return WifiSecurityType.toString(network.security);
    }

    function requestWifiConnection(network) {
        if (!network)
            return;
        if (network.connected) {
            network.disconnect();
            actionMessage = "Disconnecting from " + network.name + "…";
            return;
        }
        if (!wifiNeedsPassword(network)) {
            network.connect();
            actionMessage = "Connecting to " + network.name + "…";
            return;
        }
        pendingWifiNetwork = network;
        wifiPassword = "";
        actionMessage = "Enter the password for " + network.name;
        Qt.callLater(() => wifiPasswordInput.forceActiveFocus());
    }

    function connectPendingWifi() {
        if (!pendingWifiNetwork || wifiPassword.length === 0)
            return;
        const network = pendingWifiNetwork;
        network.connectWithPsk(wifiPassword);
        actionMessage = "Connecting to " + network.name + "…";
        wifiPassword = "";
        pendingWifiNetwork = null;
    }

    function cancelWifiPassword() {
        wifiPassword = "";
        pendingWifiNetwork = null;
    }

    function toggleBluetoothDevice(device) {
        if (!device)
            return;
        if (device.connected) {
            device.disconnect();
            actionMessage = "Disconnecting " + (device.name || device.deviceName) + "…";
        } else if (device.paired) {
            device.connect();
            actionMessage = "Connecting " + (device.name || device.deviceName) + "…";
        } else if (device.pairing) {
            device.cancelPair();
            actionMessage = "Cancelling Bluetooth pairing…";
        } else {
            device.pair();
            actionMessage = "Pairing " + (device.name || device.deviceName) + "…";
        }
    }

    function otherMonitorNames() {
        return Quickshell.screens
            .map(target => target ? target.name : "")
            .filter(name => name.length > 0 && name !== activeMonitorName);
    }

    function schedulerByName(name) {
        const schedulers = schedulerStatus.schedulers || [];
        for (const scheduler of schedulers) {
            if (String(scheduler.name || "") === name)
                return scheduler;
        }
        return null;
    }

    function selectedScheduler() {
        return schedulerByName(selectedSchedulerName);
    }

    function syncSelectedScheduler() {
        const schedulers = schedulerStatus.schedulers || [];
        if (schedulers.length === 0) {
            selectedSchedulerName = "";
            schedulerArgsDraft = "";
            schedulerArgsDirty = false;
            return;
        }

        let selected = schedulerByName(selectedSchedulerName);
        if (!selected) {
            selected = schedulerByName(String(schedulerStatus.running || "")) || schedulers[0];
            selectedSchedulerName = String(selected.name || "");
            schedulerArgsDirty = false;
        }
        if (!schedulerArgsDirty)
            schedulerArgsDraft = String(selected.custom_args || "");
    }

    function selectScheduler(name) {
        selectedSchedulerName = name;
        const selected = schedulerByName(name);
        schedulerArgsDraft = selected ? String(selected.custom_args || "") : "";
        schedulerArgsDirty = false;
        schedulerEditorOpen = true;
    }

    function refreshStatus() {
        if (!quickSettingsWindow.visible)
            return;
        if (statusReader.running) {
            refreshPending = true;
            return;
        }
        statusLoading = true;
        refreshPending = false;
        statusReader.exec([
            backend,
            "--status-json",
            activeMonitorName,
            brightnessTarget.length > 0 ? brightnessTarget : activeMonitorName
        ]);
    }

    function queueAction(commandArgs, message) {
        const nextQueue = actionQueue.slice();
        nextQueue.push({ args: commandArgs, message: message || "" });
        actionQueue = nextQueue;
        runNextAction();
    }

    function runNextAction() {
        if (actionRunner.running || actionQueue.length === 0)
            return;
        const next = actionQueue[0];
        actionQueue = actionQueue.slice(1);
        actionMessage = next.message;
        actionError = "";
        actionRunner.exec([backend, "--action", ...next.args]);
    }

    function adjustBrightness(delta) {
        const target = brightnessTarget.length > 0 ? brightnessTarget : activeMonitorName;
        queueAction(["brightness-adjust", target, String(delta)],
            "Adjusting brightness on " + target + "…");
    }

    function setBrightnessPercent(percent) {
        const target = brightnessTarget.length > 0 ? brightnessTarget : activeMonitorName;
        queueAction(["brightness-percent", target,
            String(Math.max(0, Math.min(100, Math.round(percent))))],
            "Setting brightness on " + target + "…");
    }

    function loadSavedView(targetScreen) {
        if (!targetScreen)
            return;
        BarState.refresh();
        const persisted = BarState.quickSettingsViewFor(targetScreen.name);
        panelWidthOverride = clampWidth(persisted.width);
        panelHeightOverride = clampHeight(persisted.height);
        textScaleOverride = persisted.textScale;
        iconScaleOverride = persisted.iconScale;
        captureAllowedOverride = BarState.captureAllowedFor("quick_settings") ? 1 : 0;
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
        panelWidthOverride = savedView.width;
        panelHeightOverride = savedView.height;
        textScaleOverride = savedView.textScale;
        iconScaleOverride = savedView.iconScale;
        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;
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
        if (activeMonitorName.length === 0)
            return;
        queueStateCommand([
            "save-flyout", "quick-settings", activeMonitorName,
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            captureAllowed ? "true" : "false"
        ]);
        acceptDraftAsSaved();
        settingsMessage = "Saved Quick Settings for " + activeMonitorName;
    }

    function resetDisplaySettings() {
        if (activeMonitorName.length === 0)
            return;
        panelWidthOverride = clampWidth(BarState.defaultQuickSettingsWidth);
        panelHeightOverride = clampHeight(BarState.defaultQuickSettingsHeight);
        textScaleOverride = 100;
        iconScaleOverride = 100;
        captureAllowedOverride = 0;
        queueStateCommand(["reset-flyout", "quick-settings", activeMonitorName]);
        acceptDraftAsSaved();
        settingsMessage = "Reset " + activeMonitorName + " to Quick Settings defaults";
    }

    function copyDisplaySettings(targets) {
        if (!targets || targets.length === 0)
            return;
        queueStateCommand([
            "copy-flyout", "quick-settings",
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            ...targets
        ]);
        settingsMessage = "Copied Quick Settings to " + targets.length
            + (targets.length === 1 ? " display" : " displays");
    }

    function adjustPanelWidth(delta) {
        panelWidthOverride = clampWidth(livePanelWidth + delta);
        settingsMessage = "Width " + panelWidthOverride + " px";
    }

    function adjustPanelHeight(delta) {
        panelHeightOverride = clampHeight(livePanelHeight + delta);
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
        captureAllowedOverride = captureAllowed ? 0 : 1;
        settingsMessage = captureAllowed
            ? "Quick Settings may appear in captures after Save"
            : "Quick Settings will be hidden from captures after Save";
    }

    function toggleSettings() {
        if (settingsOpen && settingsDirty)
            discardDraft();
        settingsOpen = !settingsOpen;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function openForScreen(targetScreen) {
        if (!targetScreen)
            return;
        FlyoutManager.claim("quick-settings");
        quickSettingsWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        brightnessTarget = targetScreen.name;
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        schedulerEditorOpen = false;
        schedulerArgsDirty = false;
        pendingWifiNetwork = null;
        wifiPassword = "";
        loadSavedView(targetScreen);
        quickSettingsWindow.visible = true;
        if (wifiDevice && Networking.wifiEnabled)
            wifiDevice.scannerEnabled = true;
        refreshStatus();
    }

    function openFocused() { openForScreen(focusedScreen()); }

    function close() {
        quickSettingsWindow.visible = false;
        FlyoutManager.release("quick-settings");
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        schedulerEditorOpen = false;
        pendingWifiNetwork = null;
        wifiPassword = "";
        if (wifiDevice)
            wifiDevice.scannerEnabled = false;
        if (bluetoothAdapter && bluetoothAdapter.discovering)
            bluetoothAdapter.discovering = false;
    }

    function toggleForScreen(targetScreen) {
        const currentName = quickSettingsWindow.screen ? quickSettingsWindow.screen.name : "";
        const targetName = targetScreen ? targetScreen.name : "";
        if (quickSettingsWindow.visible && currentName.length > 0 && currentName === targetName)
            close();
        else
            openForScreen(targetScreen);
    }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void { root.toggleForScreen(root.focusedScreen()); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
        function refresh(): void { root.refreshStatus(); }
    }

    Process {
        id: statusReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "{}");
                    root.statusData = parsed && typeof parsed === "object"
                        ? parsed : root.emptyStatus();
                    const nextPlacement = String((root.statusData.bar || ({})).position || "");
                    if (!Boolean((root.statusData.bar || ({})).enabled))
                        root.placement = "center";
                    else if (["top", "bottom", "left", "right"].indexOf(nextPlacement) >= 0)
                        root.placement = nextPlacement;
                    root.syncSelectedScheduler();
                } catch (error) {
                    console.warn("Awtarchy Quick Settings status parse failed:", error);
                    root.actionMessage = "Quick Settings status unavailable";
                }
            }
        }
        onExited: {
            root.statusLoading = false;
            if (root.refreshPending)
                Qt.callLater(() => root.refreshStatus());
        }
    }

    Process {
        id: actionRunner
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.actionError = errorText.split("\n")[0];
            }
        }
        onExited: {
            if (root.actionError.length > 0)
                root.actionMessage = root.actionError;
            else
                root.actionMessage = "Updated";
            root.refreshStatus();
            Qt.callLater(() => root.runNextAction());
        }
    }

    Process {
        id: stateWriter
        onExited: {
            BarState.refresh();
            privacyRuleUpdater.exec([root.configHome + "/hypr/scripts/quickshell_runtime_rules.sh"]);
            Qt.callLater(() => root.runNextStateCommand());
        }
    }

    Process { id: privacyRuleUpdater }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "quick-settings" && quickSettingsWindow.visible)
                root.close();
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: quickSettingsWindow.visible
        onTriggered: root.refreshStatus()
    }

    PanelWindow {
        id: quickSettingsWindow
        WlrLayershell.namespace: "awtarchy-quick-settings"
        visible: false
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: panel
            width: root.livePanelWidth
            height: root.livePanelHeight
            x: root.placement === "left"
                ? root.activeBarSize
                : root.placement === "right"
                    ? parent.width - width - root.activeBarSize
                    : Math.round((parent.width - width) / 2)
            y: root.placement === "top"
                ? root.activeBarSize
                : root.placement === "bottom"
                    ? parent.height - height - root.activeBarSize
                    : Math.round((parent.height - height) / 2)
            color: Theme.popupBackground
            radius: 0

            MouseArea {
                anchors.fill: parent
                onPressed: mouse => mouse.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: Theme.active
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.placement === "right" ? 40 : 8
                        anchors.rightMargin: root.placement !== "right" && root.placement !== "top" ? 40 : 8
                        spacing: 6

                        Text {
                            text: ""
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledIcon(14)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.actionMessage.length > 0
                                ? "Quick Settings · " + root.actionMessage
                                : "Quick Settings"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledText(13)
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        SettingsButton {
                            label: root.statusLoading ? "…" : "↻"
                            textSize: root.scaledText(11)
                            onClicked: root.refreshStatus()
                        }

                        Text {
                            visible: root.settingsDirty
                            text: "● Unsaved"
                            color: Theme.focus
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        SettingsButton {
                            label: " Save"
                            available: root.settingsDirty
                            textSize: root.scaledText(9)
                            onClicked: root.saveDisplaySettings()
                        }

                        SettingsButton {
                            label: ""
                            active: root.settingsOpen
                            textSize: root.scaledIcon(11)
                            onClicked: root.toggleSettings()
                        }
                    }
                }

                Rectangle {
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
                        surfaceLabel: "Quick Settings"
                        monitorName: root.activeMonitorName
                        panelWidth: root.livePanelWidth
                        panelHeight: root.livePanelHeight
                        minimumWidth: root.minimumPanelWidth
                        maximumWidth: root.maximumPanelWidth
                        minimumHeight: root.minimumPanelHeight
                        maximumHeight: root.maximumPanelHeight
                        textScale: root.effectiveTextScale
                        iconScale: root.effectiveIconScale
                        captureAllowed: root.captureAllowed
                        message: root.settingsMessage
                        otherMonitorNames: root.otherMonitorNames()

                        onResetRequested: root.resetDisplaySettings()
                        onWidthAdjustmentRequested: delta => root.adjustPanelWidth(delta)
                        onHeightAdjustmentRequested: delta => root.adjustPanelHeight(delta)
                        onTextScaleAdjustmentRequested: delta => root.adjustTextScale(delta)
                        onIconScaleAdjustmentRequested: delta => root.adjustIconScale(delta)
                        onCaptureToggleRequested: root.toggleCaptureAllowed()
                        onCopyRequested: monitorNames => root.copyDisplaySettings(monitorNames)
                    }
                }

                Flickable {
                    id: contentFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.bottomMargin: root.placement === "top" ? 34 : 0
                    contentWidth: width
                    contentHeight: settingsColumn.implicitHeight + 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: settingsColumn
                        x: 6
                        y: 6
                        width: contentFlick.width - (contentScrollBar.visible ? 26 : 12)
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: networkContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: networkContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: " Network"
                                            + (root.wiredDevices().some(device => device.connected)
                                                ? " · wired connected" : "")
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    SettingsButton {
                                        label: Networking.wifiEnabled ? "Wi-Fi On" : "Wi-Fi Off"
                                        active: Networking.wifiEnabled
                                        available: Networking.wifiHardwareEnabled
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            Networking.wifiEnabled = !Networking.wifiEnabled;
                                            if (root.wifiDevice && Networking.wifiEnabled)
                                                root.wifiDevice.scannerEnabled = true;
                                            root.actionMessage = Networking.wifiEnabled
                                                ? "Wi-Fi enabled" : "Wi-Fi disabled";
                                        }
                                    }
                                    SettingsButton {
                                        label: root.wifiDevice && root.wifiDevice.scannerEnabled ? "Scanning…" : "Scan"
                                        active: root.wifiDevice ? root.wifiDevice.scannerEnabled : false
                                        available: root.wifiDevice !== null && Networking.wifiEnabled
                                        textSize: root.scaledText(9)
                                        onClicked: root.wifiDevice.scannerEnabled = !root.wifiDevice.scannerEnabled
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !Networking.wifiHardwareEnabled || root.wifiDevice === null
                                    text: !Networking.wifiHardwareEnabled
                                        ? "Wi-Fi is blocked by a hardware switch"
                                        : "No NetworkManager Wi-Fi device is available"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                    wrapMode: Text.Wrap
                                }

                                Repeater {
                                    model: ScriptModel { values: root.wifiNetworks() }

                                    Rectangle {
                                        id: wifiRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36
                                        color: modelData.connected ? Theme.active : "transparent"
                                        border.width: 0

                                        Connections {
                                            target: wifiRow.modelData
                                            function onConnectionFailed(reason) {
                                                root.actionMessage = "Could not connect to "
                                                    + wifiRow.modelData.name + ": " + String(reason);
                                            }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 4
                                            spacing: 7
                                            Text {
                                                text: wifiRow.modelData.connected ? "●" : ""
                                                color: wifiRow.modelData.connected ? Theme.focus : Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledIcon(11)
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: wifiRow.modelData.name || "Hidden network"
                                                    color: Theme.foreground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root.scaledText(10)
                                                    font.bold: wifiRow.modelData.connected
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: Math.round(Number(wifiRow.modelData.signalStrength || 0) * 100)
                                                        + "% · " + root.wifiSecurityLabel(wifiRow.modelData)
                                                        + (wifiRow.modelData.known ? " · saved" : "")
                                                    color: Theme.muted
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root.scaledText(8)
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            SettingsButton {
                                                label: wifiRow.modelData.stateChanging ? "Working…"
                                                    : (wifiRow.modelData.connected ? "Disconnect" : "Connect")
                                                available: !wifiRow.modelData.stateChanging
                                                active: wifiRow.modelData.connected
                                                textSize: root.scaledText(9)
                                                onClicked: root.requestWifiConnection(wifiRow.modelData)
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: visible ? 38 : 0
                                    visible: root.pendingWifiNetwork !== null
                                    color: Theme.active
                                    border.width: 1
                                    border.color: Theme.focus

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        spacing: 6
                                        Text {
                                            text: "Password"
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(9)
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            color: Theme.popupBackground
                                            border.width: 1
                                            border.color: wifiPasswordInput.activeFocus ? Theme.focus : Theme.muted
                                            TextInput {
                                                id: wifiPasswordInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 7
                                                anchors.rightMargin: 7
                                                text: root.wifiPassword
                                                echoMode: TextInput.Password
                                                color: Theme.foreground
                                                selectionColor: Theme.focus
                                                selectedTextColor: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(9)
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                onTextEdited: root.wifiPassword = text
                                                Keys.onReturnPressed: root.connectPendingWifi()
                                                Keys.onEscapePressed: root.cancelWifiPassword()
                                            }
                                        }
                                        SettingsButton {
                                            label: "Cancel"
                                            textSize: root.scaledText(9)
                                            onClicked: root.cancelWifiPassword()
                                        }
                                        SettingsButton {
                                            label: "Connect"
                                            available: root.wifiPassword.length > 0
                                            textSize: root.scaledText(9)
                                            onClicked: root.connectPendingWifi()
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: bluetoothContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: bluetoothContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: " Bluetooth"
                                            + (root.bluetoothAdapter
                                                ? " · " + (root.bluetoothAdapter.name
                                                    || root.bluetoothAdapter.adapterId) : "")
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    SettingsButton {
                                        label: root.bluetoothAdapter && root.bluetoothAdapter.enabled
                                            ? "Bluetooth On" : "Bluetooth Off"
                                        active: root.bluetoothAdapter ? root.bluetoothAdapter.enabled : false
                                        available: root.bluetoothAdapter !== null
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.bluetoothAdapter.enabled = !root.bluetoothAdapter.enabled;
                                            root.actionMessage = root.bluetoothAdapter.enabled
                                                ? "Bluetooth enabled" : "Bluetooth disabled";
                                        }
                                    }
                                    SettingsButton {
                                        label: root.bluetoothAdapter && root.bluetoothAdapter.discovering
                                            ? "Scanning…" : "Scan"
                                        active: root.bluetoothAdapter ? root.bluetoothAdapter.discovering : false
                                        available: root.bluetoothAdapter !== null
                                            && root.bluetoothAdapter.enabled
                                        textSize: root.scaledText(9)
                                        onClicked: root.bluetoothAdapter.discovering
                                            = !root.bluetoothAdapter.discovering
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: root.bluetoothAdapter === null
                                    text: "No BlueZ Bluetooth adapter is available"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                }

                                Repeater {
                                    model: ScriptModel { values: root.bluetoothDevices() }

                                    Rectangle {
                                        id: bluetoothRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36
                                        color: modelData.connected ? Theme.active : "transparent"
                                        border.width: 0

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 4
                                            spacing: 7
                                            Text {
                                                text: bluetoothRow.modelData.connected ? "●" : ""
                                                color: bluetoothRow.modelData.connected ? Theme.focus : Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledIcon(11)
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: bluetoothRow.modelData.name
                                                        || bluetoothRow.modelData.deviceName
                                                        || bluetoothRow.modelData.address
                                                    color: Theme.foreground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root.scaledText(10)
                                                    font.bold: bluetoothRow.modelData.connected
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: (bluetoothRow.modelData.connected ? "connected"
                                                        : (bluetoothRow.modelData.pairing ? "pairing"
                                                            : (bluetoothRow.modelData.paired ? "paired" : "available")))
                                                        + (bluetoothRow.modelData.batteryAvailable
                                                            ? " · " + Math.round(bluetoothRow.modelData.battery * 100) + "%"
                                                            : "")
                                                    color: Theme.muted
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root.scaledText(8)
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            SettingsButton {
                                                label: bluetoothRow.modelData.connected ? "Disconnect"
                                                    : (bluetoothRow.modelData.pairing ? "Cancel"
                                                        : (bluetoothRow.modelData.paired ? "Connect" : "Pair"))
                                                active: bluetoothRow.modelData.connected
                                                textSize: root.scaledText(9)
                                                onClicked: root.toggleBluetoothDevice(bluetoothRow.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: brightnessContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: brightnessContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Brightness · " + (root.brightnessTarget || root.activeMonitorName)
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: root.brightnessPercent >= 0
                                            ? root.brightnessPercent + "%  (" + root.brightnessStatus.current
                                                + "/" + root.brightnessStatus.max + ")"
                                            : "DDC unavailable"
                                        color: root.brightnessPercent >= 0 ? Theme.foreground : Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5

                                    Repeater {
                                        model: root.monitorNames()
                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData)
                                            active: root.brightnessTarget === String(modelData)
                                            textSize: root.scaledText(9)
                                            onClicked: {
                                                root.brightnessTarget = String(modelData);
                                                root.refreshStatus();
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    SettingsButton {
                                        label: "−5"
                                        available: root.brightnessPercent >= 0
                                        textSize: root.scaledText(10)
                                        onClicked: root.adjustBrightness(-5)
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        color: Theme.active
                                        border.width: 0

                                        Rectangle {
                                            width: root.brightnessPercent >= 0
                                                ? parent.width * root.brightnessPercent / 100 : 0
                                            height: parent.height
                                            color: Theme.focus
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: root.brightnessPercent >= 0
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onPressed: mouse => root.setBrightnessPercent(mouse.x * 100 / width)
                                            onWheel: wheel => {
                                                root.adjustBrightness(wheel.angleDelta.y > 0 ? 5 : -5);
                                                wheel.accepted = true;
                                            }
                                        }
                                    }

                                    SettingsButton {
                                        label: "+5"
                                        available: root.brightnessPercent >= 0
                                        textSize: root.scaledText(10)
                                        onClicked: root.adjustBrightness(5)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: barContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: barContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Bar · " + root.activeMonitorName
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                    }
                                    SettingsButton {
                                        label: root.barStatus.enabled ? "Visible" : "Hidden"
                                        active: Boolean(root.barStatus.enabled)
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction([
                                            "bar-enabled", root.activeMonitorName,
                                            root.barStatus.enabled ? "false" : "true"
                                        ], "Updating bar visibility…")
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5
                                    Repeater {
                                        model: ["top", "bottom", "left", "right"]
                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData)
                                            active: String(root.barStatus.position) === String(modelData)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction([
                                                "bar-position", root.activeMonitorName, String(modelData)
                                            ], "Moving bar to " + String(modelData) + "…")
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: nightContent.implicitHeight + 16
                                color: Theme.popupButton
                                border.width: 1
                                border.color: Theme.active

                                ColumnLayout {
                                    id: nightContent
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Night Light · "
                                            + (root.nightLightStatus.temperature === null
                                                || root.nightLightStatus.temperature === undefined
                                                ? "N/A" : root.nightLightStatus.temperature + "K")
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(11)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    RowLayout {
                                        SettingsButton {
                                            label: "Warmer"
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction(["night-light", "down"], "Making display warmer…")
                                        }
                                        SettingsButton {
                                            label: root.nightLightStatus.enabled ? "On" : "Off"
                                            active: Boolean(root.nightLightStatus.enabled)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction(["night-light", "toggle"], "Toggling Night Light…")
                                        }
                                        SettingsButton {
                                            label: "Cooler"
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction(["night-light", "up"], "Making display cooler…")
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: vibranceContent.implicitHeight + 16
                                color: Theme.popupButton
                                border.width: 1
                                border.color: Theme.active

                                ColumnLayout {
                                    id: vibranceContent
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Vibrance · "
                                            + (root.vibranceStatus.value === null
                                                || root.vibranceStatus.value === undefined
                                                ? "N/A" : Number(root.vibranceStatus.value).toFixed(2))
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(11)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    RowLayout {
                                        SettingsButton {
                                            label: "−"
                                            textSize: root.scaledText(10)
                                            onClicked: root.queueAction(["vibrance", "down"], "Reducing vibrance…")
                                        }
                                        SettingsButton {
                                            label: root.vibranceStatus.enabled ? "On" : "Off"
                                            active: Boolean(root.vibranceStatus.enabled)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction(["vibrance", "toggle"], "Toggling vibrance…")
                                        }
                                        SettingsButton {
                                            label: "+"
                                            textSize: root.scaledText(10)
                                            onClicked: root.queueAction(["vibrance", "up"], "Increasing vibrance…")
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: submapContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: submapContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6
                                Text {
                                    text: "Hyprland Submap"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(11)
                                    font.bold: true
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5
                                    Repeater {
                                        model: [
                                            { value: "reset", label: "Off / Normal" },
                                            { value: "noalt", label: "noalt" },
                                            { value: "mouse", label: "mouse" },
                                            { value: "vm", label: "VM" }
                                        ]
                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData.label)
                                            active: String(root.statusData.submap || "reset") === String(modelData.value)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction([
                                                "submap", String(modelData.value)
                                            ], "Switching submap…")
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: wallpaperContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            RowLayout {
                                id: wallpaperContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                Text {
                                    Layout.fillWidth: true
                                    text: "Wallpaper Picker"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(11)
                                    font.bold: true
                                }
                                SettingsButton {
                                    label: "Open awtwall"
                                    textSize: root.scaledText(9)
                                    onClicked: {
                                        root.queueAction(["wallpaper"], "Opening wallpaper picker…");
                                        root.close();
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: schedulerContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: schedulerContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "sched-ext · " + (root.schedulerStatus.enabled
                                            ? root.schedulerStatus.running
                                                + (root.schedulerStatus.mode
                                                    ? " (" + root.schedulerStatus.mode + ")" : "")
                                            : "off")
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    SettingsButton {
                                        label: root.schedulerEditorOpen ? "Hide Editor" : "Edit"
                                        available: (root.schedulerStatus.schedulers || []).length > 0
                                        active: root.schedulerEditorOpen
                                        textSize: root.scaledText(9)
                                        onClicked: root.schedulerEditorOpen = !root.schedulerEditorOpen
                                    }
                                    SettingsButton {
                                        label: "Start / Switch"
                                        available: Boolean(root.schedulerStatus.available)
                                            && root.selectedSchedulerName.length > 0
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction([
                                            "scheduler-start", root.selectedSchedulerName
                                        ], "Starting " + root.selectedSchedulerName + "…")
                                    }
                                    SettingsButton {
                                        label: "Stop"
                                        available: Boolean(root.schedulerStatus.enabled)
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction(["scheduler-stop"], "Stopping sched-ext…")
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !root.schedulerStatus.available || !root.schedulerStatus.authorized
                                    text: !root.schedulerStatus.available
                                        ? "scxctl is unavailable"
                                        : "Starting sched-ext needs the existing one-time scxctl authorization"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                    wrapMode: Text.Wrap
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5
                                    Repeater {
                                        model: root.schedulerStatus.schedulers || []
                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData.name).replace(/^scx_/, "")
                                                + (String(root.schedulerStatus.running) === String(modelData.name)
                                                    ? " ●" : "")
                                            active: root.selectedSchedulerName === String(modelData.name)
                                            textSize: root.scaledText(9)
                                            onClicked: root.selectScheduler(String(modelData.name))
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.schedulerEditorOpen && root.selectedScheduler() !== null
                                    spacing: 6

                                    Text {
                                        text: root.selectedSchedulerName + " configuration"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                        font.bold: true
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: childrenRect.height
                                        spacing: 5
                                        Repeater {
                                            model: root.selectedScheduler()
                                                ? root.selectedScheduler().profiles || [] : []
                                            SettingsButton {
                                                required property var modelData
                                                label: String(modelData)
                                                active: root.selectedScheduler()
                                                    && String(root.selectedScheduler().profile) === String(modelData)
                                                textSize: root.scaledText(9)
                                                onClicked: root.queueAction([
                                                    "scheduler-profile", root.selectedSchedulerName, String(modelData)
                                                ], "Saving scheduler profile…")
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: "Custom args"
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(9)
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            color: Theme.active
                                            border.width: 1
                                            border.color: schedulerArgsInput.activeFocus ? Theme.focus : Theme.muted
                                            TextInput {
                                                id: schedulerArgsInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 7
                                                anchors.rightMargin: 7
                                                text: root.schedulerArgsDraft
                                                color: Theme.foreground
                                                selectionColor: Theme.focus
                                                selectedTextColor: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(9)
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                onTextEdited: {
                                                    root.schedulerArgsDraft = text;
                                                    root.schedulerArgsDirty = true;
                                                }
                                            }
                                        }
                                        SettingsButton {
                                            label: "Save Args"
                                            available: root.schedulerArgsDirty
                                            textSize: root.scaledText(9)
                                            onClicked: {
                                                root.queueAction([
                                                    "scheduler-args", root.selectedSchedulerName,
                                                    root.schedulerArgsDraft
                                                ], "Saving scheduler arguments…");
                                                root.schedulerArgsDirty = false;
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        SettingsButton {
                                            visible: root.selectedSchedulerName === "scx_lavd"
                                            label: root.selectedScheduler() && root.selectedScheduler().autopower
                                                ? "Autopower On" : "Autopower Off"
                                            active: root.selectedScheduler()
                                                ? Boolean(root.selectedScheduler().autopower) : false
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction([
                                                "scheduler-autopower", "scx_lavd",
                                                root.selectedScheduler() && root.selectedScheduler().autopower
                                                    ? "false" : "true"
                                            ], "Updating LAVD autopower…")
                                        }
                                        Item { Layout.fillWidth: true }
                                        SettingsButton {
                                            label: "Reset Config"
                                            textSize: root.scaledText(9)
                                            onClicked: {
                                                root.queueAction([
                                                    "scheduler-reset", root.selectedSchedulerName
                                                ], "Resetting scheduler configuration…");
                                                root.schedulerArgsDirty = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ListScrollBar {
                        id: contentScrollBar
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        flickable: contentFlick
                        z: 10
                    }
                }
            }

            Rectangle {
                width: 28
                height: 28
                x: root.placement === "right" ? 6 : panel.width - width - 6
                y: root.placement === "top" ? panel.height - height - 6 : 5
                color: closeMouse.containsMouse ? Theme.focus : Theme.active
                border.width: 0
                z: 20

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledIcon(15)
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }
    }
}
