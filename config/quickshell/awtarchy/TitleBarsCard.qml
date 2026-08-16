import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100
    property string hyprbarsState: "checking"
    property string toggleOutput: ""
    property string message: ""
    property string errorMessage: ""
    property bool authOpen: false
    property bool authBusy: false
    property string pendingPassword: ""

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string hyprbarsScript: configHome + "/hypr/scripts/hyprbars_toggle.sh"
    readonly property bool operationBusy: statusRunner.running || toggleRunner.running
        || authRunner.running || setupRunner.running

    Layout.fillWidth: true
    Layout.preferredHeight: content.implicitHeight + 16
    color: Theme.popupButton
    border.width: 1
    border.color: Theme.active

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * textScale / 100));
    }

    function statusLabel() {
        if (hyprbarsState === "enabled")
            return "Enabled";
        if (hyprbarsState === "disabled")
            return "Disabled";
        if (hyprbarsState === "unavailable")
            return "Not set up";
        return "Checking…";
    }

    function buttonLabel() {
        if (hyprbarsState === "enabled")
            return "Disable";
        if (hyprbarsState === "disabled")
            return "Enable";
        if (hyprbarsState === "unavailable")
            return "Enable";
        return "Checking…";
    }

    function probeStatus() {
        if (!active || operationBusy)
            return;
        statusRunner.exec([root.hyprbarsScript, "--status"]);
    }

    function toggleTitleBars() {
        if (operationBusy)
            return;

        errorMessage = "";
        message = "";

        if (hyprbarsState === "unavailable") {
            authOpen = true;
            Qt.callLater(() => passwordInput.forceActiveFocus());
            return;
        }

        toggleOutput = "";
        message = "Updating title bars…";
        toggleRunner.exec([root.hyprbarsScript, "--toggle"]);
    }

    function cancelAuthorization() {
        if (authBusy)
            return;
        pendingPassword = "";
        passwordInput.text = "";
        errorMessage = "";
        message = "";
        authOpen = false;
    }

    function submitAuthorization() {
        if (authBusy)
            return;
        if (passwordInput.text.length === 0) {
            errorMessage = "Enter your sudo password";
            passwordInput.forceActiveFocus();
            return;
        }

        pendingPassword = passwordInput.text;
        passwordInput.text = "";
        errorMessage = "";
        message = "Authorizing Hyprland plugin setup…";
        authBusy = true;
        authRunner.exec(["/usr/bin/sudo", "-S", "-p", "", "-v"]);
    }

    onActiveChanged: {
        if (active)
            Qt.callLater(() => root.probeStatus());
    }

    Process {
        id: statusRunner
        stdout: StdioCollector {
            onStreamFinished: {
                const state = text.trim();
                root.hyprbarsState = state === "enabled" || state === "disabled"
                    || state === "unavailable" ? state : "unavailable";
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.hyprbarsState = "unavailable";
        }
    }

    Process {
        id: toggleRunner
        stdout: StdioCollector {
            onStreamFinished: root.toggleOutput = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.errorMessage = errorText.split("\n")[0];
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.errorMessage = "";
                if (root.toggleOutput === "disabled-pending")
                    root.message = "Disabled for next login; not hot-unloaded.";
                else if (root.toggleOutput === "disabled")
                    root.message = "Title bars disabled.";
                else
                    root.message = "Title bars enabled.";
                Qt.callLater(() => root.probeStatus());
                return;
            }

            if (exitCode === 3) {
                root.hyprbarsState = "unavailable";
                root.message = "";
                root.authOpen = true;
                Qt.callLater(() => passwordInput.forceActiveFocus());
            } else {
                root.message = "";
                if (root.errorMessage.length === 0)
                    root.errorMessage = "Title bar update failed";
            }
        }
    }

    Process {
        id: authRunner
        stdinEnabled: true
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.errorMessage = errorText.split("\n")[0];
            }
        }
        onStarted: {
            authRunner.write(root.pendingPassword + "\n\n\n");
            root.pendingPassword = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.pendingPassword = "";
            if (exitCode !== 0) {
                root.authBusy = false;
                root.message = "";
                if (root.errorMessage.length === 0)
                    root.errorMessage = "Authorization failed";
                Qt.callLater(() => passwordInput.forceActiveFocus());
                return;
            }

            root.errorMessage = "";
            root.message = "Setting up and enabling Hyprland title bars…";
            setupRunner.exec([root.hyprbarsScript, "--setup-enable"]);
        }
    }

    Process {
        id: setupRunner
        stdout: StdioCollector {
            onStreamFinished: root.toggleOutput = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.errorMessage = errorText.split("\n")[0];
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.authBusy = false;
            if (exitCode === 0) {
                root.authOpen = false;
                root.errorMessage = "";
                root.hyprbarsState = "enabled";
                root.message = "Title bars enabled.";
                Qt.callLater(() => root.probeStatus());
                return;
            }

            root.message = "";
            if (root.errorMessage.length === 0)
                root.errorMessage = "Title bar setup failed";
            Qt.callLater(() => passwordInput.forceActiveFocus());
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.active && !root.operationBusy
        onTriggered: root.probeStatus()
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
                text: "Title Bars"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(12)
                font.bold: true
            }

            Text {
                text: root.statusLabel()
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
            }

            SettingsButton {
                label: root.buttonLabel()
                active: root.hyprbarsState === "enabled"
                textSize: root.scaledText(9)
                enabled: root.hyprbarsState !== "checking" && !root.operationBusy
                onClicked: root.toggleTitleBars()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !root.authOpen
            text: root.errorMessage.length > 0 ? root.errorMessage
                : (root.message.length > 0 ? root.message
                    : (root.hyprbarsState === "unavailable"
                        ? "Enable once to install and activate the official Hyprland hyprbars plugin."
                        : "Disabling loaded title bars takes effect after the next login to avoid a Hyprland crash."))
            color: root.errorMessage.length > 0 ? Theme.urgent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.authOpen
            spacing: 5

            Text {
                Layout.fillWidth: true
                text: root.errorMessage.length > 0
                    ? root.errorMessage
                    : (root.message.length > 0 ? root.message
                        : "Enter your sudo password to set up the official Hyprland plugins repository and enable title bars.")
                color: root.errorMessage.length > 0 ? Theme.urgent : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                color: Theme.active
                border.width: 1
                border.color: passwordInput.activeFocus ? Theme.focus : Theme.subtleHover

                TextInput {
                    id: passwordInput
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
                    enabled: !root.authBusy
                    clip: true
                    onAccepted: root.submitAuthorization()
                    Keys.onEscapePressed: root.cancelAuthorization()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Item { Layout.fillWidth: true }

                SettingsButton {
                    label: "Cancel"
                    textSize: root.scaledText(9)
                    enabled: !root.authBusy
                    onClicked: root.cancelAuthorization()
                }

                SettingsButton {
                    label: root.authBusy ? "Working…" : "Authorize & Enable"
                    textSize: root.scaledText(9)
                    enabled: !root.authBusy
                    onClicked: root.submitAuthorization()
                }
            }
        }
    }
}
