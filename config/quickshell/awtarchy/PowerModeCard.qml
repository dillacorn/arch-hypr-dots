import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100
    property var statusData: ({
        is_laptop: false,
        available: false,
        backend: "",
        active: "",
        profiles: []
    })
    property string actionError: ""

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string backendScript: configHome + "/hypr/scripts/quickshell_power_profiles.sh"
    readonly property bool available: Boolean(statusData.is_laptop)
        && Boolean(statusData.available)
        && (statusData.profiles || []).length > 0

    visible: available
    Layout.fillWidth: true
    Layout.preferredHeight: visible ? content.implicitHeight + 16 : 0
    color: Theme.popupButton
    border.width: 1
    border.color: Theme.active

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * textScale / 100));
    }

    function profileLabel(profile) {
        const value = String(profile || "");
        if (value === "power-saver")
            return "Power Saver";
        if (value === "balanced")
            return "Balanced";
        if (value === "performance")
            return "Performance";
        return value;
    }

    function backendLabel() {
        if (String(statusData.backend) === "tlpctl")
            return "TLP";
        if (String(statusData.backend) === "powerprofilesctl")
            return "power-profiles-daemon";
        return "";
    }

    function refresh() {
        if (statusReader.running)
            return;
        statusReader.exec(["bash", backendScript, "status"]);
    }

    function setProfile(profile) {
        if (profileWriter.running)
            return;
        actionError = "";
        profileWriter.exec(["bash", backendScript, "set", String(profile)]);
    }

    onActiveChanged: {
        if (active)
            refresh();
    }

    Process {
        id: statusReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "{}");
                    root.statusData = parsed && typeof parsed === "object"
                        ? parsed : root.statusData;
                } catch (error) {
                    console.warn("Awtarchy power profile status parse failed:", error);
                }
            }
        }
    }

    Process {
        id: profileWriter
        stderr: StdioCollector {
            onStreamFinished: root.actionError = text.trim().split("\n")[0] || ""
        }
        onExited: root.refresh()
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "Power Mode · " + root.profileLabel(root.statusData.active)
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(12)
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                text: root.backendLabel()
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            spacing: 5

            Repeater {
                model: root.statusData.profiles || []

                SettingsButton {
                    required property var modelData
                    label: root.profileLabel(modelData)
                    active: String(root.statusData.active) === String(modelData)
                    textSize: root.scaledText(9)
                    onClicked: root.setProfile(modelData)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.actionError.length > 0
            text: root.actionError
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
