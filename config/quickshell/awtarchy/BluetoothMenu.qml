pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property string placement: "center"
    property string actionMessage: ""

    readonly property var adapters: Bluetooth.adapters
        ? [...Bluetooth.adapters.values].filter(item => item !== null) : []
    readonly property var adapter: Bluetooth.defaultAdapter
        || (adapters.length > 0 ? adapters[0] : null)
    readonly property bool available: adapters.length > 0 && adapter !== null
    readonly property var connectedDevices: devices().filter(device => device.connected)
    readonly property string barLabel: buildBarLabel()
    readonly property string verticalBarLabel: connectedDevices.length > 0
        ? "\n" + connectedDevices.length : (adapter && adapter.enabled ? "\n×" : "\noff")
    readonly property string barTooltip: buildBarTooltip()
    readonly property color barForeground: adapter && adapter.enabled
        ? Theme.foreground : Theme.muted
    readonly property int activeBarSize: {
        const target = bluetoothWindow.screen;
        if (!target || placement === "center")
            return 0;
        return BarState.barSizeFor(target.name, placement === "left" || placement === "right");
    }
    readonly property int targetScreenWidth: bluetoothWindow.screen ? bluetoothWindow.screen.width : 1920
    readonly property int targetScreenHeight: bluetoothWindow.screen ? bluetoothWindow.screen.height : 1080
    readonly property int availablePanelWidth: Math.max(1, targetScreenWidth
        - ((placement === "left" || placement === "right") ? activeBarSize : 0) - 16)
    readonly property int availablePanelHeight: Math.max(1, targetScreenHeight
        - ((placement === "top" || placement === "bottom") ? activeBarSize : 0) - 16)
    readonly property int panelWidth: Math.min(500, availablePanelWidth)
    readonly property int panelHeight: Math.min(600, availablePanelHeight)

    function devices() {
        if (!adapter || !adapter.devices)
            return [];
        return [...adapter.devices.values]
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
        if (!adapter || !adapter.enabled)
            return " off";
        if (connectedDevices.length === 0)
            return " ×";
        if (connectedDevices.length === 1)
            return " " + shortDeviceName(connectedDevices[0]);
        return " " + connectedDevices.length;
    }

    function buildBarTooltip() {
        if (!adapter)
            return "Bluetooth adapter unavailable";
        if (!adapter.enabled)
            return "Bluetooth disabled\nClick: Bluetooth devices";
        if (connectedDevices.length === 0)
            return "Bluetooth enabled · no device connected\nClick: Bluetooth devices";
        const lines = connectedDevices.map(device => "Connected: " + deviceName(device)
            + batteryText(device));
        lines.push("Click: Bluetooth devices");
        return lines.join("\n");
    }

    function toggleAdapter() {
        if (!adapter)
            return;
        adapter.enabled = !adapter.enabled;
        if (!adapter.enabled && adapter.discovering)
            adapter.discovering = false;
        actionMessage = adapter.enabled ? "Bluetooth enabled" : "Bluetooth disabled";
    }

    function toggleDiscovery() {
        if (!adapter || !adapter.enabled)
            return;
        adapter.discovering = !adapter.discovering;
        actionMessage = adapter.discovering ? "Scanning for devices…" : "Scan stopped";
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
        if (!targetScreen || !BarState.enabledFor(targetScreen.name))
            return "center";
        return BarState.positionFor(targetScreen.name);
    }

    function openForScreen(targetScreen) {
        if (!targetScreen || !available)
            return;
        FlyoutManager.claim("bluetooth");
        bluetoothWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        actionMessage = "";
        bluetoothWindow.visible = true;
        if (adapter.enabled)
            adapter.discovering = true;
    }

    function close() {
        bluetoothWindow.visible = false;
        if (adapter && adapter.discovering)
            adapter.discovering = false;
        actionMessage = "";
        FlyoutManager.release("bluetooth");
    }

    function toggleForScreen(targetScreen) {
        const currentName = bluetoothWindow.screen ? bluetoothWindow.screen.name : "";
        const targetName = targetScreen ? targetScreen.name : "";
        if (bluetoothWindow.visible && currentName === targetName)
            close();
        else
            openForScreen(targetScreen);
    }

    onAvailableChanged: {
        if (!available && bluetoothWindow.visible)
            close();
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "bluetooth" && bluetoothWindow.visible)
                root.close();
        }
    }

    IpcHandler {
        target: "bluetooth"
        function available(): bool { return root.available; }
        function toggle(): void { root.toggleForScreen(root.focusedScreen()); }
        function open(): void { root.openForScreen(root.focusedScreen()); }
        function close(): void { root.close(); }
    }

    PanelWindow {
        id: bluetoothWindow
        WlrLayershell.namespace: "awtarchy-bluetooth"
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
                            text: ""
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.actionMessage.length > 0
                                ? "Bluetooth · " + root.actionMessage : "Bluetooth"
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
                    id: bluetoothFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: bluetoothColumn.implicitHeight + 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: bluetoothColumn
                        x: 6
                        y: 6
                        width: bluetoothFlick.width - (bluetoothScroll.visible ? 26 : 12)
                        spacing: 8

                        Rectangle {
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
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    SettingsButton {
                                        label: root.adapter && root.adapter.enabled ? "On" : "Off"
                                        active: root.adapter ? root.adapter.enabled : false
                                        available: root.adapter !== null
                                        textSize: 9
                                        onClicked: root.toggleAdapter()
                                    }
                                    SettingsButton {
                                        label: root.adapter && root.adapter.discovering ? "Scanning…" : "Scan"
                                        active: root.adapter ? root.adapter.discovering : false
                                        available: root.adapter !== null && root.adapter.enabled
                                        textSize: 9
                                        onClicked: root.toggleDiscovery()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: root.adapter && !root.adapter.enabled
                                    text: "Bluetooth is disabled"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.adapter && root.adapter.enabled && root.devices().length === 0
                            text: root.adapter.discovering
                                ? "Scanning for Bluetooth devices…" : "No Bluetooth devices found"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        Repeater {
                            model: ScriptModel {
                                values: root.adapter && root.adapter.enabled ? root.devices() : []
                            }

                            Rectangle {
                                id: deviceRow
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
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
                                        font.pixelSize: 11
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.deviceName(deviceRow.modelData)
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
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
                                            font.pixelSize: 8
                                            elide: Text.ElideRight
                                        }
                                    }
                                    SettingsButton {
                                        visible: deviceRow.modelData.paired && !deviceRow.modelData.connected
                                        label: "Forget"
                                        textSize: 8
                                        onClicked: root.forgetDevice(deviceRow.modelData)
                                    }
                                    SettingsButton {
                                        label: deviceRow.modelData.connected ? "Disconnect"
                                            : (deviceRow.modelData.pairing ? "Cancel"
                                                : (deviceRow.modelData.paired ? "Connect" : "Pair"))
                                        active: deviceRow.modelData.connected
                                        textSize: 9
                                        onClicked: root.toggleDevice(deviceRow.modelData)
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
