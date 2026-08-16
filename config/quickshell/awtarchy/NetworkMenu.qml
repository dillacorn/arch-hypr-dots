pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking

Singleton {
    id: root

    property string placement: "center"
    property var pendingWifiNetwork: null
    property string wifiPassword: ""
    property string actionMessage: ""
    property bool settingsOpen: false
    property bool vpnOpen: false
    property bool vpnPrivacyOpening: false
    property bool vpnPrivacyUnlockPending: false
    property string vpnPrivacyAction: ""
    property int panelWidthOverride: -1
    property int panelHeightOverride: -1
    property int textScaleOverride: -1
    property int iconScaleOverride: -1
    property int captureAllowedOverride: -1
    property bool privacyRemapPending: false
    property string settingsMessage: ""
    property var savedView: ({
        width: BarState.defaultNetworkWidth,
        height: BarState.defaultNetworkHeight,
        textScale: 100,
        iconScale: 100,
        captureAllowed: false
    })
    property var stateCommandQueue: []
    property bool openPreparing: false
    property var flyoutScreen: null

    readonly property var wifiDevices: devicesOfType(DeviceType.Wifi)
    readonly property var wiredDevices: devicesOfType(DeviceType.Wired)
    readonly property var primaryWifiDevice: wifiDevices.length > 0 ? wifiDevices[0] : null
    readonly property var connectedWifiNetworks: wifiNetworks().filter(network => network.connected)
    readonly property var connectedWiredDevices: wiredDevices.filter(device => device && device.network && device.network.connected)
    readonly property bool wifiPresent: wifiDevices.length > 0
    readonly property bool wiredPresent: wiredDevices.length > 0
    readonly property bool available: wifiPresent || wiredPresent
    readonly property bool wifiConnected: connectedWifiNetworks.length > 0
    readonly property bool wiredConnected: connectedWiredDevices.length > 0
    readonly property string barLabel: buildBarLabel()
    readonly property string verticalBarLabel: buildVerticalBarLabel()
    readonly property string barTooltip: buildBarTooltip()
    readonly property color barForeground: wifiConnected || wiredConnected
        ? Theme.foreground : Theme.muted
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"
    readonly property string sensitiveCaptureScript: configHome + "/hypr/scripts/quickshell_sensitive_capture.sh"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_flyout_position.sh"
    readonly property string prepareScript: configHome + "/hypr/scripts/quickshell_flyout_prepare.sh"
    readonly property var activeScreen: flyoutScreen || networkWindow.screen
    readonly property string activeMonitorName: activeScreen && activeScreen.name
        ? String(activeScreen.name) : ""
    readonly property int targetScreenWidth: activeScreen ? activeScreen.width : 1920
    readonly property int targetScreenHeight: activeScreen ? activeScreen.height : 1080
    readonly property int maximumPanelWidth: Math.max(1, targetScreenWidth - 20)
    readonly property int maximumPanelHeight: Math.max(1, targetScreenHeight - 20)
    readonly property int minimumPanelWidth: Math.min(360, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(360, maximumPanelHeight)
    readonly property int configuredPanelWidth: clampWidth(panelWidthOverride >= 0
        ? panelWidthOverride : BarState.networkViewFor(activeMonitorName).width)
    readonly property int configuredPanelHeight: clampHeight(panelHeightOverride >= 0
        ? panelHeightOverride : BarState.networkViewFor(activeMonitorName).height)
    readonly property int livePanelWidth: networkWindow.visible && networkWindow.width > 0
        ? clampWidth(Math.round(networkWindow.width)) : configuredPanelWidth
    readonly property int livePanelHeight: networkWindow.visible && networkWindow.height > 0
        ? clampHeight(Math.round(networkWindow.height)) : configuredPanelHeight
    readonly property int effectiveTextScale: textScaleOverride >= 0
        ? textScaleOverride : BarState.networkViewFor(activeMonitorName).textScale
    readonly property int effectiveIconScale: iconScaleOverride >= 0
        ? iconScaleOverride : BarState.networkViewFor(activeMonitorName).iconScale
    readonly property bool captureAllowed: captureAllowedOverride >= 0
        ? captureAllowedOverride === 1 : BarState.captureAllowedFor("network")
    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed

    function devicesOfType(type) {
        const devices = Networking.devices ? Networking.devices.values : [];
        return [...devices].filter(device => device && device.type === type);
    }

    function wifiNetworks() {
        const networks = [];
        for (const device of wifiDevices) {
            if (!device || !device.networks)
                continue;
            for (const network of device.networks.values) {
                if (network)
                    networks.push(network);
            }
        }
        return networks.sort((left, right) => {
            if (Boolean(left.connected) !== Boolean(right.connected))
                return left.connected ? -1 : 1;
            if (Boolean(left.known) !== Boolean(right.known))
                return left.known ? -1 : 1;
            return Number(right.signalStrength || 0) - Number(left.signalStrength || 0);
        });
    }

    function wifiSignalPercent(network) {
        return Math.max(0, Math.min(100,
            Math.round(Number(network && network.signalStrength || 0) * 100)));
    }

    function wifiSignalIcon(network) {
        const percent = wifiSignalPercent(network);
        if (percent >= 75)
            return "󰤨";
        if (percent >= 50)
            return "󰤥";
        if (percent >= 25)
            return "󰤢";
        if (percent > 0)
            return "󰤟";
        return "󰤯";
    }

    function buildBarLabel() {
    if (wifiConnected)
        return wifiSignalIcon(connectedWifiNetworks[0]);
    if (wiredConnected)
        return "󰈀";
    if (wifiPresent)
        return "󰤯";
    if (wiredPresent)
        return "󰈂";
    return "";
}

    function buildVerticalBarLabel() {
    if (wifiConnected)
        return wifiSignalIcon(connectedWifiNetworks[0]);
    if (wiredConnected)
        return "󰈀";
    if (wifiPresent)
        return "󰤯";
    if (wiredPresent)
        return "󰈂";
    return "";
}

    function wiredConnectionName(device) {
        if (!device)
            return "Ethernet";
        const network = device.network;
        return network && network.name ? network.name : (device.name || "Ethernet");
    }

    function toggleWiredConnection(device) {
        const network = device ? device.network : null;
        if (!network)
            return;
        if (network.connected) {
            network.disconnect();
            actionMessage = "Disconnecting " + wiredConnectionName(device) + "…";
        } else {
            network.connect();
            actionMessage = "Connecting " + wiredConnectionName(device) + "…";
        }
    }

    function buildBarTooltip() {
        const lines = [];
        for (const device of connectedWiredDevices) {
            let line = "Ethernet: " + wiredConnectionName(device);
            if (Number(device.linkSpeed || 0) > 0)
                line += " · " + device.linkSpeed + " Mb/s";
            lines.push(line);
        }
        for (const network of connectedWifiNetworks) {
            lines.push("Wi-Fi: " + (network.name || "Hidden network")
                + " · " + wifiSignalPercent(network) + "%");
        }
        if (lines.length === 0) {
            if (wifiPresent && !Networking.wifiHardwareEnabled)
                lines.push("Wi-Fi blocked by hardware switch");
            else if (wifiPresent && !Networking.wifiEnabled)
                lines.push("Wi-Fi disabled");
            if (wiredPresent)
                lines.push("Ethernet disconnected");
            if (wifiPresent && Networking.wifiEnabled)
                lines.push("Wi-Fi disconnected");
        }
        lines.push("Click: network connections");
        return lines.join("\n");
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
            actionMessage = "Disconnecting " + (network.name || "Wi-Fi") + "…";
            return;
        }
        if (!wifiNeedsPassword(network)) {
            network.connect();
            actionMessage = "Connecting to " + (network.name || "Wi-Fi") + "…";
            return;
        }
        pendingWifiNetwork = network;
        wifiPassword = "";
        actionMessage = "Password required for " + (network.name || "Wi-Fi");
        Qt.callLater(() => wifiPasswordInput.forceActiveFocus());
    }

    function connectPendingWifi() {
        if (!pendingWifiNetwork || wifiPassword.length === 0)
            return;
        const network = pendingWifiNetwork;
        network.connectWithPsk(wifiPassword);
        actionMessage = "Connecting to " + (network.name || "Wi-Fi") + "…";
        wifiPassword = "";
        pendingWifiNetwork = null;
    }

    function cancelWifiPassword() {
        wifiPassword = "";
        pendingWifiNetwork = null;
    }

    function setWifiScanning(enabled) {
        for (const device of wifiDevices) {
            if (device)
                device.scannerEnabled = Boolean(enabled) && Networking.wifiEnabled;
        }
    }

    function wifiScanning() {
        return wifiDevices.some(device => device && device.scannerEnabled);
    }

    function toggleWifi() {
        if (!wifiPresent || !Networking.wifiHardwareEnabled)
            return;
        Networking.wifiEnabled = !Networking.wifiEnabled;
        if (Networking.wifiEnabled)
            setWifiScanning(true);
        else {
            setWifiScanning(false);
            cancelWifiPassword();
        }
        actionMessage = Networking.wifiEnabled ? "Wi-Fi enabled" : "Wi-Fi disabled";
    }

    function toggleWifiScanning() {
        if (!wifiPresent || !Networking.wifiEnabled)
            return;
        setWifiScanning(!wifiScanning());
        actionMessage = wifiScanning() ? "Scanning for Wi-Fi networks…" : "Wi-Fi scan stopped";
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

    function applyWindowSize(width, height) {
        panelWidthOverride = clampWidth(width);
        panelHeightOverride = clampHeight(height);
        if (networkWindow.visible && activeMonitorName.length > 0) {
            Quickshell.execDetached([
                positionScript, "network", activeMonitorName, placement, "resize",
                String(panelWidthOverride), String(panelHeightOverride)
            ]);
        }
    }

    function positionWindow() {
        if (!networkWindow.visible || activeMonitorName.length === 0)
            return;
        Quickshell.execDetached([
            positionScript, "network", activeMonitorName, placement, "spawn"
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
            "bash", prepareScript, "network", targetScreen.name, placement,
            String(configuredPanelWidth), String(configuredPanelHeight),
            String(barSize), "-1",
            String(Math.round(targetScreen.width)), String(Math.round(targetScreen.height))
        ]);
    }

    function finishPreparedOpen() {
        if (!openPreparing)
            return;

        const wasVisible = networkWindow.visible;

        openPreparing = false;
        networkWindow.visible = true;
        if (wasVisible)
            Qt.callLater(() => root.positionWindow());
        if (wifiPresent && Networking.wifiEnabled)
            setWifiScanning(true);
    }

    function scaledText(baseSize) {
        return Math.max(7, Math.round(baseSize * effectiveTextScale / 100));
    }

    function scaledIcon(baseSize) {
        return Math.max(8, Math.round(baseSize * effectiveIconScale / 100));
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
        const persisted = BarState.networkViewFor(targetScreen.name);
        panelWidthOverride = clampWidth(persisted.width);
        panelHeightOverride = clampHeight(persisted.height);
        textScaleOverride = persisted.textScale;
        iconScaleOverride = persisted.iconScale;
        captureAllowedOverride = BarState.captureAllowedFor("network") ? 1 : 0;
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
            "save-flyout", "network", activeMonitorName,
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            captureAllowed ? "true" : "false"
        ]);
        panelWidthOverride = livePanelWidth;
        panelHeightOverride = livePanelHeight;
        acceptDraftAsSaved();
        settingsMessage = "Saved Network settings for " + activeMonitorName;
    }

    function resetDisplaySettings() {
        if (activeMonitorName.length === 0)
            return;
        const wasCaptureAllowed = captureAllowed;
        textScaleOverride = 100;
        iconScaleOverride = 100;
        captureAllowedOverride = 0;
        applyWindowSize(BarState.defaultNetworkWidth, BarState.defaultNetworkHeight);
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: 100,
            iconScale: 100,
            captureAllowed: false
        });
        privacyRemapPending = wasCaptureAllowed;
        queueStateCommand(["reset-flyout", "network", activeMonitorName]);
        settingsMessage = "Network defaults restored for " + activeMonitorName;
    }

    function copyDisplaySettings(targets) {
        if (!targets || targets.length === 0)
            return;
        queueStateCommand([
            "copy-flyout", "network",
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            ...targets
        ]);
        settingsMessage = "Copied Network settings to " + targets.length
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
        if (vpnOpen || vpnPrivacyOpening)
            return;
        const next = !captureAllowed;
        captureAllowedOverride = next ? 1 : 0;
        savedView = Object.assign({}, savedView, { captureAllowed: next });
        privacyRemapPending = true;
        queueStateCommand(["set-capture", "network", next ? "true" : "false"]);
        settingsMessage = next
            ? "Network is visible in captures" : "Network capture protection enabled";
    }

    function startVpnUnlock() {
        if (vpnPrivacyProcess.running) {
            vpnPrivacyUnlockPending = true;
            return;
        }
        vpnPrivacyUnlockPending = false;
        vpnPrivacyAction = "unlock";
        vpnPrivacyProcess.exec([root.sensitiveCaptureScript, "network", "unlock"]);
    }

    function openVpnView() {
        if (vpnOpen || vpnPrivacyOpening)
            return;
        if (vpnPrivacyProcess.running) {
            actionMessage = "VPN privacy protection is still initializing";
            return;
        }
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        cancelWifiPassword();
        vpnPrivacyUnlockPending = false;
        vpnPrivacyOpening = true;
        vpnPrivacyAction = "lock";
        vpnPrivacyProcess.exec([root.sensitiveCaptureScript, "network", "lock"]);
    }

    function closeVpnView() {
        const wasSensitive = vpnOpen || vpnPrivacyOpening;
        vpnOpen = false;
        vpnPrivacyOpening = false;
        if (wasSensitive)
            startVpnUnlock();
    }

    function showVpnAfterPrivacyLock() {
        networkWindow.visible = false;
        vpnPrivacyOpening = false;
        vpnOpen = true;
        Qt.callLater(() => {
            if (FlyoutManager.activeSurface !== "network" || !root.vpnOpen)
                return;
            networkWindow.visible = true;
            root.positionWindow();
        });
    }

    function remapNetworkAfterVpnUnlock() {
        if (!networkWindow.visible || vpnOpen || vpnPrivacyOpening)
            return;
        networkWindow.visible = false;
        Qt.callLater(() => {
            if (FlyoutManager.activeSurface !== "network"
                || root.vpnOpen || root.vpnPrivacyOpening)
                return;
            networkWindow.visible = true;
            root.positionWindow();
        });
    }

    function toggleSettings() {
        if (vpnOpen || vpnPrivacyOpening)
            closeVpnView();
        settingsOpen = !settingsOpen;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }
    function toggleVpn() {
        if (vpnOpen || vpnPrivacyOpening)
            closeVpnView();
        else
            openVpnView();
    }
    function openForScreen(targetScreen) {
        if (!targetScreen || !available)
            return;
        FlyoutManager.claim("network", targetScreen.name);
        flyoutScreen = targetScreen;
        if (!networkWindow.visible)
            networkWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        actionMessage = "";
        settingsOpen = false;
        if (vpnOpen || vpnPrivacyOpening)
            closeVpnView();
        settingsMessage = "";
        settingsPanel.resetCopySelection();
        cancelWifiPassword();
        loadSavedView(targetScreen);
        prepareWindowOpen(targetScreen);
    }

    function close() {
        openPreparing = false;
        if (prepareProcess.running)
            prepareProcess.running = false;
        if (settingsDirty)
            discardDraft();
        networkWindow.visible = false;
        if (vpnOpen || vpnPrivacyOpening)
            closeVpnView();
        setWifiScanning(false);
        cancelWifiPassword();
        actionMessage = "";
        settingsOpen = false;
        settingsMessage = "";
        settingsPanel.resetCopySelection();
        FlyoutManager.release("network");
    }

    function toggleForScreen(targetScreen) {
        if (!FlyoutManager.acceptToggle("network"))
            return;
        const currentName = activeMonitorName;
        const targetName = targetScreen ? targetScreen.name : "";
        if ((networkWindow.visible || openPreparing) && currentName === targetName)
            close();
        else
            openForScreen(targetScreen);
    }

    onAvailableChanged: {
        if (!available && (networkWindow.visible || openPreparing))
            close();
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "network"
                && (networkWindow.visible || root.openPreparing))
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
            if (!networkWindow.visible || root.vpnOpen || root.vpnPrivacyOpening)
                return;
            networkWindow.visible = false;
            Qt.callLater(() => {
                networkWindow.visible = true;
                root.positionWindow();
            });
        }
    }

    Process {
        id: vpnPrivacyProcess
        onExited: (exitCode, exitStatus) => {
            const completedAction = root.vpnPrivacyAction;
            root.vpnPrivacyAction = "";

            if (completedAction === "lock") {
                if (exitCode !== 0) {
                    root.vpnPrivacyOpening = false;
                    root.vpnOpen = false;
                    root.actionMessage = "VPN capture protection unavailable";
                    root.vpnPrivacyUnlockPending = false;
                    Qt.callLater(() => root.startVpnUnlock());
                    return;
                }
                if (root.vpnPrivacyUnlockPending) {
                    root.vpnPrivacyOpening = false;
                    root.vpnOpen = false;
                    root.vpnPrivacyUnlockPending = false;
                    Qt.callLater(() => root.startVpnUnlock());
                    return;
                }
                root.showVpnAfterPrivacyLock();
                return;
            }

            if (completedAction === "unlock") {
                root.vpnPrivacyUnlockPending = false;
                if (exitCode === 0)
                    root.remapNetworkAfterVpnUnlock();
            }
        }
    }

    Component.onCompleted: {
        networkWindow.visible = false;
        root.vpnPrivacyAction = "unlock";
        vpnPrivacyProcess.exec([root.sensitiveCaptureScript, "network", "unlock"]);
    }

    IpcHandler {
        target: "network"
        function available(): bool { return root.available; }
        function toggle(): void { root.toggleForScreen(root.focusedScreen()); }
        function open(): void { root.openForScreen(root.focusedScreen()); }
        function close(): void { root.close(); }
    }

    FloatingWindow {
        id: networkWindow
        visible: false
        title: "Awtarchy Network"
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: root.configuredPanelWidth
        implicitHeight: root.configuredPanelHeight
        minimumSize: Qt.size(root.minimumPanelWidth, root.minimumPanelHeight)
        maximumSize: Qt.size(root.maximumPanelWidth, root.maximumPanelHeight)

        onClosed: root.close()
        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => root.positionWindow());
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 0
            focus: true
            Keys.onEscapePressed: root.close()

            MouseArea {
                anchors.fill: parent
                onPressed: mouse => mouse.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
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
                            text: ""
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledIcon(14)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.actionMessage.length > 0
                                ? "Network · " + root.actionMessage : "Network"
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
                            captureAllowed: root.captureAllowed && !root.vpnOpen && !root.vpnPrivacyOpening
                            locked: root.vpnOpen || root.vpnPrivacyOpening
                            textSize: root.scaledIcon(12)
                            onClicked: root.toggleCaptureAllowed()
                        }

                        SettingsButton {
                            label: "󰒃"
                            active: root.vpnOpen || root.vpnPrivacyOpening
                            textSize: root.scaledIcon(12)
                            horizontalPadding: 10
                            onClicked: root.toggleVpn()
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
                        surfaceLabel: "Network"
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

                NetworkVpnSection {
                    id: vpnSection
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 6
                    visible: root.vpnOpen
                    standalone: true
                    active: visible && networkWindow.visible
                    textScale: root.effectiveTextScale
                    iconScale: root.effectiveIconScale
                }

                Flickable {
                    id: networkFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.vpnOpen
                    contentWidth: width
                    contentHeight: networkColumn.implicitHeight + 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: networkColumn
                        x: 6
                        y: 6
                        width: networkFlick.width - (networkScroll.visible ? 26 : 12)
                        spacing: 8

                        Rectangle {
                            visible: root.wiredPresent
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? wiredContent.implicitHeight + 16 : 0
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: wiredContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5

                                Text {
                                    text: "󰈀 Ethernet"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(12)
                                    font.bold: true
                                }

                                Repeater {
                                    model: ScriptModel { values: root.wiredDevices }

                                    Rectangle {
                                        id: wiredRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.max(38,
                                            root.scaledText(10) + root.scaledText(8) + 16)
                                        color: modelData.connected ? Theme.active : "transparent"
                                        border.width: 0

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 8
                                            Text {
                                                text: wiredRow.modelData.connected ? "●" : "○"
                                                color: wiredRow.modelData.connected ? Theme.focus : Theme.muted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledIcon(10)
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.wiredConnectionName(wiredRow.modelData)
                                                    color: Theme.foreground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root.scaledText(10)
                                                    font.bold: wiredRow.modelData.connected
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: wiredRow.modelData.connected
                                                        ? "Connected · " + (wiredRow.modelData.name || "Ethernet")
                                                            + (Number(wiredRow.modelData.linkSpeed || 0) > 0
                                                                ? " · " + wiredRow.modelData.linkSpeed + " Mb/s" : "")
                                                        : (wiredRow.modelData.hasLink ? "Cable connected" : "Cable unplugged")
                                                    color: Theme.muted
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root.scaledText(8)
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            SettingsButton {
                                                readonly property var wiredNetwork: wiredRow.modelData.network
                                                visible: Boolean(wiredNetwork)
                                                label: wiredNetwork && wiredNetwork.stateChanging ? "Working…"
                                                    : (wiredNetwork && wiredNetwork.connected ? "Disconnect" : "Connect")
                                                available: Boolean(wiredNetwork) && !wiredNetwork.stateChanging
                                                active: wiredNetwork ? wiredNetwork.connected : false
                                                textSize: root.scaledText(9)
                                                onClicked: root.toggleWiredConnection(wiredRow.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: root.wifiPresent
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? wifiContent.implicitHeight + 16 : 0
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: wifiContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: " Wi-Fi"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                    }
                                    SettingsButton {
                                        label: Networking.wifiEnabled ? "On" : "Off"
                                        active: Networking.wifiEnabled
                                        available: Networking.wifiHardwareEnabled
                                        textSize: root.scaledText(9)
                                        onClicked: root.toggleWifi()
                                    }
                                    SettingsButton {
                                        label: root.wifiScanning() ? "Scanning…" : "Scan"
                                        active: root.wifiScanning()
                                        available: Networking.wifiEnabled
                                            && Networking.wifiHardwareEnabled
                                        textSize: root.scaledText(9)
                                        onClicked: root.toggleWifiScanning()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !Networking.wifiHardwareEnabled || !Networking.wifiEnabled
                                    text: !Networking.wifiHardwareEnabled
                                        ? "Wi-Fi is blocked by a hardware switch"
                                        : "Wi-Fi is disabled"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: Networking.wifiEnabled && root.wifiNetworks().length === 0
                                    text: root.wifiScanning()
                                        ? "Scanning for networks…" : "No Wi-Fi networks found"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                }

                                Repeater {
                                    model: ScriptModel {
                                        values: Networking.wifiEnabled ? root.wifiNetworks() : []
                                    }

                                    Rectangle {
                                        id: wifiRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.max(40,
                                            root.scaledText(10) + root.scaledText(8) + 16)
                                        color: modelData.connected ? Theme.active : "transparent"
                                        border.width: 0

                                        Connections {
                                            target: wifiRow.modelData
                                            function onConnectionFailed(reason) {
                                                root.actionMessage = "Could not connect to "
                                                    + (wifiRow.modelData.name || "Wi-Fi")
                                                    + ": " + String(reason);
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
                                                    text: root.wifiSignalPercent(wifiRow.modelData)
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
                                    Layout.preferredHeight: visible ? Math.max(40, root.scaledText(9) + 20) : 0
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
                                            border.color: wifiPasswordInput.activeFocus
                                                ? Theme.focus : Theme.muted
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
                    }

                    ListScrollBar {
                        id: networkScroll
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        flickable: networkFlick
                        z: 10
                    }
                }
            }
        }
    }
}
