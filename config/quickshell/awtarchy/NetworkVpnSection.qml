pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property bool active: false
    property bool standalone: false
    property int textScale: 100
    property int iconScale: 100
    property var profiles: []
    property string actionMessage: ""
    property string interfaceName: ""
    property string connectionType: ""
    property string localIpv4: ""
    property string gateway: ""
    property string publicIpv4: ""
    property string publicIpv6: ""
    property string publicIpError: ""
    property bool publicIpLoading: false
    property bool publicIpChecked: false

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string homeDir: Quickshell.env("HOME") || "~"
    readonly property string helper: configHome + "/hypr/scripts/quickshell_wireguard.sh"
    readonly property int profileRowHeight: Math.max(40,
        scaledText(10) + scaledText(8) + 16)
    readonly property int profileListHeight: profiles.length === 0 ? 0
        : Math.min(176, profiles.length * profileRowHeight)

    implicitHeight: standalone ? content.implicitHeight + 16 : 0
    opacity: standalone ? 1 : 0
    enabled: standalone
    color: Theme.popupButton
    border.width: standalone ? 1 : 0
    border.color: Theme.active

    function scaledText(baseSize) {
        return Math.max(7, Math.round(baseSize * textScale / 100));
    }

    function scaledIcon(baseSize) {
        return Math.max(8, Math.round(baseSize * iconScale / 100));
    }

    function refreshProfiles() {
        if (standalone && !listProcess.running)
            listProcess.running = true;
    }

    function refreshLocalInfo() {
        if (standalone && !localInfoProcess.running)
            localInfoProcess.running = true;
    }

    function toggleProfile(profile) {
        if (!profile || actionProcess.running)
            return;
        actionMessage = (profile.active ? "Disconnecting " : "Connecting ") + profile.name + "…";
        actionProcess.exec([helper, profile.active ? "down" : "up", profile.name]);
    }

    function editProfile(profile) {
        if (!profile)
            return;
        Quickshell.execDetached([helper, "edit", profile.name]);
    }

    function openVpnFolder() {
        Quickshell.execDetached([helper, "open-dir"]);
    }

    function checkPublicIps() {
        if (!standalone || publicIpProcess.running)
            return;
        publicIpv4 = "";
        publicIpv6 = "";
        publicIpError = "";
        publicIpChecked = false;
        publicIpLoading = true;
        publicIpProcess.running = true;
    }

    onActiveChanged: {
        if (standalone && active) {
            refreshProfiles();
            refreshLocalInfo();
        }
    }

    Process {
        id: listProcess
        command: [root.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.profiles = JSON.parse(text.trim() || "[]");
                } catch (error) {
                    root.profiles = [];
                    root.actionMessage = "Could not read WireGuard profiles";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message.length > 0)
                    root.actionMessage = message.split("\n")[0];
            }
        }
    }

    Process {
        id: localInfoProcess
        command: [root.helper, "local-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(text.trim() || "{}");
                    root.interfaceName = String(info.interface || "");
                    root.connectionType = String(info.connectionType || "");
                    root.localIpv4 = String(info.localIpv4 || "");
                    root.gateway = String(info.gateway || "");
                } catch (error) {
                    root.interfaceName = "";
                    root.connectionType = "";
                    root.localIpv4 = "";
                    root.gateway = "";
                }
            }
        }
    }

    Process {
        id: actionProcess
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message.length > 0)
                    root.actionMessage = message.split("\n")[0];
            }
        }
        onExited: actionRefresh.restart()
    }

    Timer {
        id: actionRefresh
        interval: 400
        repeat: false
        onTriggered: {
            root.actionMessage = "";
            root.refreshProfiles();
            root.refreshLocalInfo();
            if (root.publicIpChecked)
                root.checkPublicIps();
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.standalone && root.active
        onTriggered: {
            root.refreshProfiles();
            root.refreshLocalInfo();
        }
    }

    Process {
        id: publicIpProcess
        command: [root.helper, "public-ips"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(text.trim() || "{}");
                    root.publicIpv4 = String(info.ipv4 || "");
                    root.publicIpv6 = String(info.ipv6 || "");
                } catch (error) {
                    root.publicIpv4 = "";
                    root.publicIpv6 = "";
                    root.publicIpError = "Could not parse public IP response";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message.length > 0)
                    root.publicIpError = message.split("\n")[0];
            }
        }
        onExited: {
            root.publicIpLoading = false;
            root.publicIpChecked = true;
            if (root.publicIpv4.length === 0 && root.publicIpv6.length === 0
                && root.publicIpError.length === 0)
                root.publicIpError = "Public IP unavailable";
        }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: "󰒃 WireGuard VPN"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(12)
                font.bold: true
            }

            SettingsButton {
                label: "Open ~/vpn"
                textSize: root.scaledText(8)
                onClicked: root.openVpnFolder()
            }

            SettingsButton {
                label: "Refresh"
                textSize: root.scaledText(8)
                onClicked: {
                    root.refreshProfiles();
                    root.refreshLocalInfo();
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Drop wg-quick .conf files into " + root.homeDir + "/vpn"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            elide: Text.ElideMiddle
        }

        Text {
            Layout.fillWidth: true
            visible: root.profiles.length === 0
            text: "No WireGuard profiles found"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(9)
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.profileListHeight
            visible: root.profiles.length > 0

            Flickable {
                id: profileFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: profileColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: profileColumn
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: ScriptModel { values: root.profiles }

                        Rectangle {
                            id: profileRow
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.profileRowHeight
                            color: modelData.active ? Theme.active : "transparent"
                            border.width: 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 4
                                spacing: 7

                                Text {
                                    text: profileRow.modelData.active ? "●" : "○"
                                    color: profileRow.modelData.active ? Theme.focus : Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledIcon(10)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: profileRow.modelData.name
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                        font.bold: profileRow.modelData.active
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: profileRow.modelData.active ? "wg-quick active" : "wg-quick inactive"
                                        color: Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(8)
                                    }
                                }

                                SettingsButton {
                                    label: "Edit"
                                    available: !actionProcess.running
                                    textSize: root.scaledText(8)
                                    onClicked: root.editProfile(profileRow.modelData)
                                }

                                SettingsButton {
                                    label: profileRow.modelData.active ? "Disconnect" : "Connect"
                                    active: profileRow.modelData.active
                                    available: !actionProcess.running
                                    textSize: root.scaledText(8)
                                    onClicked: root.toggleProfile(profileRow.modelData)
                                }
                            }
                        }
                    }
                }
            }

            ListScrollBar {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                flickable: profileFlick
                z: 10
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.actionMessage.length > 0
            text: root.actionMessage
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: localInfoContent.implicitHeight + 12
            color: "transparent"
            border.width: 1
            border.color: Theme.active

            ColumnLayout {
                id: localInfoContent
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: "Local network"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(9)
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "Connection: " + (root.interfaceName.length > 0
                        ? ((root.connectionType.length > 0 ? root.connectionType + " · " : "")
                            + root.interfaceName)
                        : "Unavailable")
                    color: root.interfaceName.length > 0 ? Theme.foreground : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                    elide: Text.ElideMiddle
                }

                Text {
                    Layout.fillWidth: true
                    text: "Local IPv4: " + (root.localIpv4.length > 0 ? root.localIpv4 : "Unavailable")
                    color: root.localIpv4.length > 0 ? Theme.foreground : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                    elide: Text.ElideMiddle
                }

                Text {
                    Layout.fillWidth: true
                    text: "Router gateway: " + (root.gateway.length > 0 ? root.gateway : "Unavailable")
                    color: root.gateway.length > 0 ? Theme.foreground : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                    elide: Text.ElideMiddle
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: publicIpContent.implicitHeight + 12
            color: "transparent"
            border.width: 1
            border.color: Theme.active

            RowLayout {
                id: publicIpContent
                anchors.fill: parent
                anchors.margins: 6
                spacing: 6

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Public IP"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(9)
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.publicIpLoading ? "Public IPv4: Checking…"
                            : "Public IPv4: " + (root.publicIpv4.length > 0
                                ? root.publicIpv4
                                : (root.publicIpChecked ? "Unavailable" : "Not checked"))
                        color: root.publicIpv4.length > 0 ? Theme.foreground : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(8)
                        elide: Text.ElideMiddle
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.publicIpLoading ? "Public IPv6: Checking…"
                            : "Public IPv6: " + (root.publicIpv6.length > 0
                                ? root.publicIpv6
                                : (root.publicIpChecked ? "Unavailable" : "Not checked"))
                        color: root.publicIpv6.length > 0 ? Theme.foreground : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(8)
                        elide: Text.ElideMiddle
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.publicIpError.length > 0
                        text: root.publicIpError
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(7)
                        elide: Text.ElideRight
                    }
                }

                SettingsButton {
                    label: root.publicIpChecked ? "Refresh IPs" : "Check IPs"
                    available: !root.publicIpLoading
                    textSize: root.scaledText(8)
                    onClicked: root.checkPublicIps()
                }

                SettingsButton {
                    label: "myip.wtf"
                    textSize: root.scaledText(8)
                    onClicked: Quickshell.execDetached([root.helper, "open-ip-site"])
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "myip.wtf opens in your normal Firefox session outside this protected VPN panel. It can show your public IP, hostname, location, ISP, browser headers, and XML/YAML/JSON/plain-text output."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(7)
            wrapMode: Text.WordWrap
        }
    }
}
