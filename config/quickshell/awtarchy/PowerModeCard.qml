import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

ColumnLayout {
    id: root

    property bool active: false
    property bool presentationEnabled: false
    property int textScale: 100
    property int iconScale: 100
    property string backendCommand: ""
    property bool setupAuthOpen: false
    property bool setupAuthBusy: false
    property string setupAuthError: ""
    property string setupAuthMessage: ""
    property string setupAuthPendingPassword: ""

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string quickshellManager: configHome + "/hypr/scripts/quickshell.sh"
    readonly property bool isLaptop: UPower.displayDevice.ready
        && UPower.displayDevice.isLaptopBattery
    readonly property bool backendReady: backendCommand === "tlp-pd"
        || backendCommand === "power-profiles-daemon"
    readonly property bool conflictDetected: backendCommand === "conflict"

    visible: root.presentationEnabled
    Layout.fillWidth: true
    spacing: 8

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
        if (backendCommand === "tlp-pd")
            return "TLP";
        if (backendCommand === "power-profiles-daemon")
            return "power-profiles-daemon";
        if (conflictDetected)
            return "TLP + PPD conflict";
        return "Setup required";
    }

    function probeBackend() {
        if (presentationEnabled && isLaptop && !backendProbe.running)
            backendProbe.running = true;
    }

    function openSetupAuthorization() {
        if (setupAuthBusy)
            return;
        setupAuthError = "";
        setupAuthMessage = conflictDetected
            ? "Authorize removal of the conflicting power-profiles-daemon package."
            : "Authorize Power Mode backend setup.";
        setupAuthOpen = true;
        Qt.callLater(() => setupPasswordInput.forceActiveFocus());
    }

    function cancelSetupAuthorization() {
        if (setupAuthBusy)
            return;
        setupAuthPendingPassword = "";
        setupPasswordInput.text = "";
        setupAuthError = "";
        setupAuthMessage = "";
        setupAuthOpen = false;
    }

    function submitSetupAuthorization() {
        if (setupAuthBusy)
            return;
        if (setupPasswordInput.text.length === 0) {
            setupAuthError = "Enter your sudo password";
            setupPasswordInput.forceActiveFocus();
            return;
        }

        setupAuthPendingPassword = setupPasswordInput.text;
        setupPasswordInput.text = "";
        setupAuthError = "";
        setupAuthMessage = "Applying Power Mode backend setup…";
        setupAuthBusy = true;

        const action = root.conflictDetected ? "resolve-tlp-conflict" : "setup";
        setupAuthRunner.exec([
            "/usr/bin/sudo", "-S", "-p", "",
            "/usr/local/libexec/awtarchy/power-profile-helper",
            action
        ]);
    }

    onActiveChanged: {
        if (active && presentationEnabled && isLaptop)
            probeBackend();
    }

    onPresentationEnabledChanged: {
        if (presentationEnabled && active && isLaptop)
            probeBackend();
    }

    Process {
        id: backendProbe
        command: [
            "/usr/bin/bash", "-c",
            "if /usr/bin/pacman -Qq 2>/dev/null | /usr/bin/grep -Fx -- tlp >/dev/null && /usr/bin/pacman -Qq 2>/dev/null | /usr/bin/grep -Fx -- power-profiles-daemon >/dev/null; then printf conflict; "
                + "elif /usr/bin/busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile >/dev/null 2>&1; then "
                + "if /usr/bin/pacman -Qq 2>/dev/null | /usr/bin/grep -Fx -- tlp >/dev/null; then printf tlp-pd; else printf power-profiles-daemon; fi; fi"
        ]
        running: root.presentationEnabled && root.isLaptop
        stdout: StdioCollector {
            onStreamFinished: root.backendCommand = text.trim()
        }
    }

    Process {
        id: setupAuthRunner
        stdinEnabled: true
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.setupAuthError = errorText.split("\n")[0];
            }
        }
        onStarted: {
            // sudo may request another attempt after a bad password. Blank
            // responses force a prompt failure instead of leaving a hidden
            // stdin-backed process waiting forever.
            setupAuthRunner.write(root.setupAuthPendingPassword + "\n\n\n");
            root.setupAuthPendingPassword = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.setupAuthPendingPassword = "";
            root.setupAuthBusy = false;
            if (exitCode === 0) {
                root.setupAuthOpen = false;
                root.setupAuthError = "";
                root.setupAuthMessage = "Power Mode backend ready. Refreshing Awtarchy…";
                root.backendCommand = "";
                Quickshell.execDetached([root.quickshellManager, "restart"]);
                return;
            }

            if (root.setupAuthError.length === 0)
                root.setupAuthError = "Power Mode setup failed";
            root.setupAuthMessage = "";
            Qt.callLater(() => setupPasswordInput.forceActiveFocus());
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.presentationEnabled && root.active && root.isLaptop && !root.setupAuthBusy
        onTriggered: root.probeBackend()
    }

    Rectangle {
        id: powerCard
        visible: root.presentationEnabled && root.isLaptop
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? content.implicitHeight + 16 : 0
        color: Theme.popupButton
        border.width: 1
        border.color: Theme.active

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
                visible: !root.backendReady && !root.setupAuthOpen
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.conflictDetected
                        ? "TLP and power-profiles-daemon are both installed. Resolve the conflict before switching profiles."
                        : "No Power Profiles D-Bus backend is available. Awtarchy uses TLP's tlp-pd backend on laptops."
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                    wrapMode: Text.Wrap
                }

                SettingsButton {
                    label: root.conflictDetected ? "Resolve" : "Set Up"
                    textSize: root.scaledText(9)
                    enabled: !root.setupAuthBusy
                    onClicked: root.openSetupAuthorization()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.backendReady && root.setupAuthOpen
                spacing: 5

                Text {
                    Layout.fillWidth: true
                    text: root.setupAuthMessage
                    visible: text.length > 0
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    color: Theme.active
                    border.width: 1
                    border.color: setupPasswordInput.activeFocus ? Theme.focus : Theme.subtleHover

                    TextInput {
                        id: setupPasswordInput
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.foreground
                        selectionColor: Theme.focus
                        selectedTextColor: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(9)
                        echoMode: TextInput.Password
                        enabled: !root.setupAuthBusy
                        clip: true
                        onAccepted: root.submitSetupAuthorization()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: root.setupAuthError
                        visible: text.length > 0
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: root.scaledText(8)
                        elide: Text.ElideRight
                    }

                    SettingsButton {
                        label: "Cancel"
                        textSize: root.scaledText(9)
                        enabled: !root.setupAuthBusy
                        onClicked: root.cancelSetupAuthorization()
                    }

                    SettingsButton {
                        label: root.setupAuthBusy ? "Working…" : "Authorize"
                        textSize: root.scaledText(9)
                        enabled: !root.setupAuthBusy
                        onClicked: root.submitSetupAuthorization()
                    }
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
}
