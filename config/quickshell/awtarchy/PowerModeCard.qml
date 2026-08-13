import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100
    property string backendCommand: ""

    readonly property bool isLaptop: UPower.displayDevice.ready
        && UPower.displayDevice.isLaptopBattery
    readonly property bool available: isLaptop && backendCommand.length > 0

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
        if (profile === PowerProfile.PowerSaver)
            return "Power Saver";
        if (profile === PowerProfile.Performance)
            return "Performance";
        return "Balanced";
    }

    function backendLabel() {
        return backendCommand === "tlpctl" ? "TLP" : "power-profiles-daemon";
    }

    function probeBackend() {
        if (!backendProbe.running)
            backendProbe.running = true;
    }

    onActiveChanged: {
        if (active)
            probeBackend();
    }

    Process {
        id: backendProbe
        command: [
            "bash", "-lc",
            "if command -v tlpctl >/dev/null 2>&1 && tlpctl get >/dev/null 2>&1; then printf tlpctl; "
                + "elif command -v powerprofilesctl >/dev/null 2>&1 && powerprofilesctl get >/dev/null 2>&1; then printf powerprofilesctl; fi"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.backendCommand = text.trim()
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.active
        onTriggered: root.probeBackend()
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
                text: "Power Mode · " + root.profileLabel(PowerProfiles.profile)
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
                model: PowerProfiles.hasPerformanceProfile
                    ? [
                        { label: "Power Saver", value: PowerProfile.PowerSaver },
                        { label: "Balanced", value: PowerProfile.Balanced },
                        { label: "Performance", value: PowerProfile.Performance }
                    ]
                    : [
                        { label: "Power Saver", value: PowerProfile.PowerSaver },
                        { label: "Balanced", value: PowerProfile.Balanced }
                    ]

                SettingsButton {
                    required property var modelData
                    label: String(modelData.label)
                    active: PowerProfiles.profile === modelData.value
                    textSize: root.scaledText(9)
                    onClicked: PowerProfiles.profile = modelData.value
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            text: "Performance limited: "
                + PerformanceDegradationReason.toString(PowerProfiles.degradationReason)
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
