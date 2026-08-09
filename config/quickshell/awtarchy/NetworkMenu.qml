pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland

Singleton {
    id: root

    property string placement: "center"
    property var pendingWifiNetwork: null
    property string wifiPassword: ""
    property string actionMessage: ""

    readonly property var wifiDevices: devicesOfType(DeviceType.Wifi)
    readonly property var wiredDevices: devicesOfType(DeviceType.Wired)
    readonly property var primaryWifiDevice: wifiDevices.length > 0 ? wifiDevices[0] : null
    readonly property var connectedWifiNetworks: wifiNetworks().filter(network => network.connected)
    readonly property var connectedWiredDevices: wiredDevices.filter(device => device.connected)
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
    readonly property int activeBarSize: {
        const target = networkWindow.screen;
        if (!target || placement === "center")
            return 0;
        return BarState.barSizeFor(target.name, placement === "left" || placement === "right");
    }
    readonly property int targetScreenWidth: networkWindow.screen ? networkWindow.screen.width : 1920
    readonly property int targetScreenHeight: networkWindow.screen ? networkWindow.screen.height : 1080
    readonly property int availablePanelWidth: Math.max(1, targetScreenWidth
        - ((placement === "left" || placement === "right") ? activeBarSize : 0) - 16)
    readonly property int availablePanelHeight: Math.max(1, targetScreenHeight
        - ((placement === "top" || placement === "bottom") ? activeBarSize : 0) - 16)
    readonly property int panelWidth: Math.min(520, availablePanelWidth)
    readonly property int panelHeight: Math.min(600, availablePanelHeight)

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

    function buildBarLabel() {
        const parts = [];
        if (wiredPresent)
            parts.push(wiredConnected ? "󰈀" : "󰈀 ×");
        if (wifiPresent) {
            if (!Networking.wifiHardwareEnabled)
                parts.push(" blocked");
            else if (!Networking.wifiEnabled)
                parts.push(" off");
            else if (wifiConnected)
                parts.push(" " + wifiSignalPercent(connectedWifiNetworks[0]) + "%");
            else
                parts.push(" ×");
        }
        return parts.join("  ");
    }

    function buildVerticalBarLabel() {
        const parts = [];
        if (wiredPresent)
            parts.push(wiredConnected ? "󰈀" : "󰈀×");
        if (wifiPresent) {
            if (!Networking.wifiHardwareEnabled)
                parts.push("!");
            else if (!Networking.wifiEnabled)
                parts.push("off");
            else if (wifiConnected)
                parts.push("" + wifiSignalPercent(connectedWifiNetworks[0]) + "%");
            else
                parts.push("×");
        }
        return parts.join("\n");
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

    function openForScreen(targetScreen) {
        if (!targetScreen || !available)
            return;
        FlyoutManager.claim("network");
        networkWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        actionMessage = "";
        cancelWifiPassword();
        networkWindow.visible = true;
        if (wifiPresent && Networking.wifiEnabled)
            setWifiScanning(true);
    }

    function close() {
        networkWindow.visible = false;
        setWifiScanning(false);
        cancelWifiPassword();
        actionMessage = "";
        FlyoutManager.release("network");
    }

    function toggleForScreen(targetScreen) {
        const currentName = networkWindow.screen ? networkWindow.screen.name : "";
        const targetName = targetScreen ? targetScreen.name : "";
        if (networkWindow.visible && currentName === targetName)
            close();
        else
            openForScreen(targetScreen);
    }

    onAvailableChanged: {
        if (!available && networkWindow.visible)
            close();
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "network" && networkWindow.visible)
                root.close();
        }
    }

    IpcHandler {
        target: "network"
        function available(): bool { return root.available; }
        function toggle(): void { root.toggleForScreen(root.focusedScreen()); }
        function open(): void { root.openForScreen(root.focusedScreen()); }
        function close(): void { root.close(); }
    }

    PanelWindow {
        id: networkWindow
        WlrLayershell.namespace: "awtarchy-network"
        visible: false
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: root.panelWidth
        implicitHeight: root.panelHeight
        anchors.top: root.placement === "top" || root.placement === "center"
        anchors.bottom: root.placement !== "top" && root.placement !== "center"
        anchors.left: root.placement === "left" || root.placement === "center"
        anchors.right: root.placement !== "left" && root.placement !== "center"
        margins {
            top: root.placement === "top" ? root.activeBarSize + 6
                : (root.placement === "center"
                    ? Math.max(6, Math.round((root.targetScreenHeight - root.panelHeight) / 2)) : 0)
            bottom: root.placement === "bottom" ? root.activeBarSize + 6
                : ((root.placement === "left" || root.placement === "right") ? 8 : 0)
            left: root.placement === "left" ? root.activeBarSize + 6
                : (root.placement === "center"
                    ? Math.max(6, Math.round((root.targetScreenWidth - root.panelWidth) / 2)) : 0)
            right: root.placement === "right" ? root.activeBarSize + 6
                : ((root.placement === "top" || root.placement === "bottom") ? 8 : 0)
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
                    Layout.preferredHeight: 38
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
                            font.pixelSize: 14
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.actionMessage.length > 0
                                ? "Network · " + root.actionMessage : "Network"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        SettingsButton {
                            label: "×"
                            textSize: 14
                            onClicked: root.close()
                        }
                    }
                }

                Flickable {
                    id: networkFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                Repeater {
                                    model: ScriptModel { values: root.wiredDevices }

                                    Rectangle {
                                        id: wiredRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 38
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
                                                font.pixelSize: 10
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.wiredConnectionName(wiredRow.modelData)
                                                    color: Theme.foreground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
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
                                                    font.pixelSize: 8
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
                                                textSize: 9
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
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                    SettingsButton {
                                        label: Networking.wifiEnabled ? "On" : "Off"
                                        active: Networking.wifiEnabled
                                        available: Networking.wifiHardwareEnabled
                                        textSize: 9
                                        onClicked: root.toggleWifi()
                                    }
                                    SettingsButton {
                                        label: root.wifiScanning() ? "Scanning…" : "Scan"
                                        active: root.wifiScanning()
                                        available: Networking.wifiEnabled
                                            && Networking.wifiHardwareEnabled
                                        textSize: 9
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
                                    font.pixelSize: 9
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: Networking.wifiEnabled && root.wifiNetworks().length === 0
                                    text: root.wifiScanning()
                                        ? "Scanning for networks…" : "No Wi-Fi networks found"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }

                                Repeater {
                                    model: ScriptModel {
                                        values: Networking.wifiEnabled ? root.wifiNetworks() : []
                                    }

                                    Rectangle {
                                        id: wifiRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
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
                                                font.pixelSize: 11
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: wifiRow.modelData.name || "Hidden network"
                                                    color: Theme.foreground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
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
                                                    font.pixelSize: 8
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            SettingsButton {
                                                label: wifiRow.modelData.stateChanging ? "Working…"
                                                    : (wifiRow.modelData.connected ? "Disconnect" : "Connect")
                                                available: !wifiRow.modelData.stateChanging
                                                active: wifiRow.modelData.connected
                                                textSize: 9
                                                onClicked: root.requestWifiConnection(wifiRow.modelData)
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: visible ? 40 : 0
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
                                            font.pixelSize: 9
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
                                                font.pixelSize: 9
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                onTextEdited: root.wifiPassword = text
                                                Keys.onReturnPressed: root.connectPendingWifi()
                                                Keys.onEscapePressed: root.cancelWifiPassword()
                                            }
                                        }
                                        SettingsButton {
                                            label: "Cancel"
                                            textSize: 9
                                            onClicked: root.cancelWifiPassword()
                                        }
                                        SettingsButton {
                                            label: "Connect"
                                            available: root.wifiPassword.length > 0
                                            textSize: 9
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
