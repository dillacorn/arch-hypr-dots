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

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string terminalLauncher: configHome + "/hypr/scripts/default_terminal.sh"
    readonly property string setupScript: configHome + "/hypr/scripts/quickshell_power_profile_setup.sh"
    readonly property bool isLaptop: UPower.displayDevice.ready
        && UPower.displayDevice.isLaptopBattery
    readonly property bool backendReady: backendCommand === "tlpctl"
        || backendCommand === "powerprofilesctl"
    readonly property bool conflictDetected: backendCommand === "conflict"

    visible: isLaptop
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
        if (backendCommand === "tlpctl")
            return "TLP";
        if (backendCommand === "powerprofilesctl")
            return "power-profiles-daemon";
        if (conflictDetected)
            return "TLP + PPD conflict";
        return "Setup required";
    }

    function probeBackend() {
        if (!backendProbe.running)
            backendProbe.running = true;
    }

    function runSetup() {
        if (setupTerminal.running)
            return;
        setupTerminal.exec([
            terminalLauncher,
            "--class", "awtarchy-power-mode-setup",
            "--", "bash", setupScript
        ]);
    }

    onActiveChanged: {
        if (active)
            probeBackend();
    }

    Process {
        id: backendProbe
        command: [
            "bash", "-lc",
            "if pacman -Qq 2>/dev/null | grep -Fx -- tlp >/dev/null && pacman -Qq 2>/dev/null | grep -Fx -- power-profiles-daemon >/dev/null; then printf conflict; "
                + "elif command -v tlpctl >/dev/null 2>&1 && tlpctl get >/dev/null 2>&1; then printf tlpctl; "
                + "elif command -v powerprofilesctl >/dev/null 2>&1 && powerprofilesctl get >/dev/null 2>&1; then printf powerprofilesctl; fi"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.backendCommand = text.trim()
        }
    }

    Process {
        id: setupTerminal
        onExited: {
            root.backendCommand = "";
            Qt.callLater(() => root.probeBackend());
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
                text: root.backendReady
                    ? "Power Mode · " + root.profileLabel(PowerProfiles.profile)
                    : "Power Mode"
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
            visible: root.backendReady
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

        RowLayout {
            Layout.fillWidth: true
            visible: !root.backendReady
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.conflictDetected
                    ? "TLP and power-profiles-daemon are both installed. Resolve the conflict before switching profiles."
                    : "No Power Profiles backend is available yet. Awtarchy will use TLP's tlp-pd backend when TLP is installed."
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
                wrapMode: Text.Wrap
            }

            SettingsButton {
                label: root.conflictDetected ? "Resolve" : "Set Up"
                textSize: root.scaledText(9)
                onClicked: root.runSetup()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.backendReady
                && PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            text: "Performance mode is currently degraded by the system."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
