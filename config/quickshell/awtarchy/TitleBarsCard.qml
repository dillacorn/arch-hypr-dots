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
    property string actionOutput: ""
    property string message: ""
    property string errorMessage: ""
    property bool authOpen: false
    property string pendingAction: ""
    property string pendingPassword: ""

    readonly property string trustedHelper: "/usr/local/libexec/awtarchy/scxctl-helper"
    readonly property bool operationBusy: statusRunner.running || actionRunner.running

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
        if (hyprbarsState === "disabled" || hyprbarsState === "unavailable")
            return "Enable";
        return "Checking…";
    }

    function probeStatus() {
        if (!active || operationBusy || authOpen)
            return;
        statusRunner.exec([root.trustedHelper, "hyprbars-status"]);
    }

    function requestToggle() {
        if (operationBusy)
            return;

        errorMessage = "";
        message = "";
        pendingAction = hyprbarsState === "enabled"
            ? "hyprbars-disable" : "hyprbars-enable";
        authOpen = true;
        Qt.callLater(() => passwordInput.forceActiveFocus());
    }

    function cancelAuthorization() {
        if (operationBusy)
            return;
        pendingAction = "";
        pendingPassword = "";
        passwordInput.text = "";
        errorMessage = "";
        message = "";
        authOpen = false;
    }

    function submitAuthorization() {
        if (operationBusy)
            return;
        if (pendingAction !== "hyprbars-enable" && pendingAction !== "hyprbars-disable") {
            errorMessage = "No title bar action is pending";
            return;
        }
        if (passwordInput.text.length === 0) {
            errorMessage = "Enter your sudo password";
            passwordInput.forceActiveFocus();
            return;
        }

        pendingPassword = passwordInput.text;
        passwordInput.text = "";
        errorMessage = "";
        message = pendingAction === "hyprbars-enable"
            ? "Setting up and enabling title bars…"
            : "Disabling title bars…";
        actionOutput = "";
        actionRunner.exec([root.trustedHelper, root.pendingAction]);
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
        id: actionRunner
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: root.actionOutput = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.errorMessage = errorText.split("\n")[0];
            }
        }
        onStarted: {
            actionRunner.write(root.pendingPassword + "\n");
            root.pendingPassword = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.pendingPassword = "";
            if (exitCode === 0) {
                root.authOpen = false;
                root.errorMessage = "";
                root.pendingAction = "";

                if (root.actionOutput === "disabled-pending") {
                    root.hyprbarsState = "disabled";
                    root.message = "Disabled for next login; not hot-unloaded.";
                } else if (root.actionOutput === "disabled") {
                    root.hyprbarsState = "disabled";
                    root.message = "Title bars disabled.";
                } else {
                    root.hyprbarsState = "enabled";
                    root.message = "Title bars enabled.";
                }
                return;
            }

            root.message = "";
            if (root.errorMessage.length === 0)
                root.errorMessage = "Title bar update failed";
            Qt.callLater(() => passwordInput.forceActiveFocus());
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.active && !root.operationBusy && !root.authOpen
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
                onClicked: root.requestToggle()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !root.authOpen
            text: root.errorMessage.length > 0 ? root.errorMessage
                : (root.message.length > 0 ? root.message
                    : (root.hyprbarsState === "unavailable"
                        ? "Enable once to install and activate the official Hyprland hyprbars plugin."
                        : "Changes use Hyprland's plugin manager. Disabling a loaded title bar is left staged for the next login."))
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
                        : (root.pendingAction === "hyprbars-disable"
                            ? "Enter your sudo password to disable title bars."
                            : "Enter your sudo password to set up the official Hyprland plugins repository if needed and enable title bars."))
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
                    enabled: !root.operationBusy
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
                    enabled: !root.operationBusy
                    onClicked: root.cancelAuthorization()
                }

                SettingsButton {
                    label: root.operationBusy ? "Working…" : "Authorize"
                    textSize: root.scaledText(9)
                    enabled: !root.operationBusy
                    onClicked: root.submitAuthorization()
                }
            }
        }
    }
}
