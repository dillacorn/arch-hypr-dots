pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100
    property var profiles: []
    property string actionMessage: ""
    property string publicIp: ""
    property string publicIpError: ""
    property bool publicIpLoading: false

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string homeDir: Quickshell.env("HOME") || "~"
    readonly property string helper: configHome + "/hypr/scripts/quickshell_wireguard.sh"

    implicitHeight: content.implicitHeight + 16
    color: Theme.popupButton
    border.width: 1
    border.color: Theme.active

    function scaledText(baseSize) {
        return Math.max(7, Math.round(baseSize * textScale / 100));
    }

    function scaledIcon(baseSize) {
        return Math.max(8, Math.round(baseSize * iconScale / 100));
    }

    function refreshProfiles() {
        if (!listProcess.running)
            listProcess.running = true;
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

    function checkPublicIp() {
        if (publicIpProcess.running)
            return;
        publicIp = "";
        publicIpError = "";
        publicIpLoading = true;
        publicIpProcess.running = true;
    }

    onActiveChanged: {
        if (active)
            refreshProfiles();
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
        id: actionProcess
        stdout: StdioCollector { }
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message.length > 0)
                    root.actionMessage = message.split("\n")[0];
            }
        }
        onExited: {
            actionRefresh.restart();
        }
    }

    Timer {
        id: actionRefresh
        interval: 400
        repeat: false
        onTriggered: {
            root.actionMessage = "";
            root.refreshProfiles();
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.active
        onTriggered: root.refreshProfiles()
    }

    Process {
        id: publicIpProcess
        command: [root.helper, "public-ip"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.trim();
                if (value.length > 0)
                    root.publicIp = value;
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
            if (root.publicIp.length === 0 && root.publicIpError.length === 0)
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
                text: "󰖂 WireGuard VPN"
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
                onClicked: root.refreshProfiles()
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

        Repeater {
            model: ScriptModel { values: root.profiles }

            Rectangle {
                id: profileRow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(40,
                    root.scaledText(10) + root.scaledText(8) + 16)
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
                    spacing: 0

                    Text {
                        text: "Public IP"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(9)
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.publicIpLoading ? "Checking…"
                            : (root.publicIp.length > 0 ? root.publicIp
                                : (root.publicIpError.length > 0 ? root.publicIpError : "Not checked"))
                        color: root.publicIp.length > 0 ? Theme.foreground : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(8)
                        elide: Text.ElideRight
                    }
                }

                SettingsButton {
                    label: root.publicIp.length > 0 ? "Refresh IP" : "Check IP"
                    available: !root.publicIpLoading
                    textSize: root.scaledText(8)
                    onClicked: root.checkPublicIp()
                }

                SettingsButton {
                    label: "WTFIsMyIP"
                    textSize: root.scaledText(8)
                    onClicked: Quickshell.execDetached([root.helper, "open-ip-site"])
                }
            }
        }
    }
}
