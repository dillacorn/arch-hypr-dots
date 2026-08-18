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
        if (hyprbarsState === "not-loaded")
            return "Enabled · Not loaded";
        if (hyprbarsState === "disabled")
            return "Disabled";
        if (hyprbarsState === "disabled-pending")
            return "On now · Off next login";
        if (hyprbarsState === "unavailable")
            return "Not set up";
        return "Checking…";
    }

    function buttonLabel() {
        if (hyprbarsState === "enabled")
            return "Disable";
        if (hyprbarsState === "not-loaded")
            return "Load";
        if (hyprbarsState === "disabled" || hyprbarsState === "disabled-pending"
                || hyprbarsState === "unavailable")
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
        actionOutput = "";
        pendingAction = hyprbarsState === "enabled"
            ? "hyprbars-disable" : "hyprbars-enable";
        message = pendingAction === "hyprbars-enable" && hyprbarsState === "unavailable"
            ? "First-time setup updates Hyprland plugin headers and builds the official plugin repository, so it can take a while."
            : (pendingAction === "hyprbars-enable" && hyprbarsState === "not-loaded"
                ? "Title Bars are enabled in hyprpm but not loaded. Enter your sudo password to load them into Hyprland."
                : "Enter your sudo password to update the Hyprland plugin state.");
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
            errorMessage = "No Hyprland plugin action is pending";
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
        message = "Authenticating with sudo…";
        actionOutput = "";
        actionRunner.exec([root.trustedHelper, root.pendingAction]);
    }

    function handleActionLine(rawLine) {
        const line = String(rawLine).trim();
        if (line.length === 0)
            return;

        const stagePrefix = "AWTARCHY_STAGE\t";
        const resultPrefix = "AWTARCHY_RESULT\t";
        const errorPrefix = "AWTARCHY_ERROR\t";

        if (line.startsWith(stagePrefix)) {
            message = line.substring(stagePrefix.length);
            return;
        }
        if (line.startsWith(resultPrefix)) {
            actionOutput = line.substring(resultPrefix.length);
            return;
        }
        if (line.startsWith(errorPrefix)) {
            const detail = line.substring(errorPrefix.length);
            if (detail.indexOf("Authentication failed") !== -1)
                errorMessage = "Authentication failed. sudo rejected the password.";
            else
                errorMessage = detail;
        }
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
                root.hyprbarsState = state === "enabled" || state === "not-loaded"
                    || state === "disabled" || state === "disabled-pending"
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
        stdout: SplitParser {
            onRead: data => root.handleActionLine(data)
        }
        stderr: SplitParser {
            onRead: data => {
                const detail = String(data).trim();
                if (detail.length > 0 && root.errorMessage.length === 0)
                    root.errorMessage = detail;
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
                    root.hyprbarsState = "disabled-pending";
                    root.message = "Title Bars are still active now and are configured to turn off next login.";
                } else if (root.actionOutput === "disabled") {
                    root.hyprbarsState = "disabled";
                    root.message = "Title Bars disabled.";
                } else {
                    root.hyprbarsState = "enabled";
                    root.message = "Title Bars enabled.";
                }
                return;
            }

            root.message = "";
            if (root.errorMessage.length === 0) {
                root.errorMessage = exitCode === 77
                    ? "Authentication failed. sudo rejected the password."
                    : "Hyprland plugin update failed. No detailed error was returned.";
            }
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
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Hyprland Plugin"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(12)
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "Title Bars (hyprbars)"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                }
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
                        ? "Enable once to install and activate the official Hyprland Title Bars plugin."
                        : (root.hyprbarsState === "not-loaded"
                            ? "Title Bars are enabled in hyprpm but not loaded in this Hyprland session."
                            : (root.hyprbarsState === "disabled-pending"
                                ? "Title Bars are loaded in this session, but hyprpm is configured to leave them off next login."
                                : "Managed through Hyprland's plugin manager and synchronized with SUPER+ALT+T."))))
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
                    : root.message
                color: root.errorMessage.length > 0 ? Theme.urgent : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                visible: !root.operationBusy
                    && root.pendingAction === "hyprbars-enable"
                    && root.hyprbarsState === "unavailable"
                text: "Updating Hyprland plugin headers and building the official plugin repository is normal on first setup and may take a while. Progress will appear here."
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                visible: !root.operationBusy
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
                    visible: !root.operationBusy
                    enabled: !root.operationBusy
                    onClicked: root.cancelAuthorization()
                }

                SettingsButton {
                    label: root.operationBusy ? "Running…" : "Authorize"
                    textSize: root.scaledText(9)
                    enabled: !root.operationBusy
                    onClicked: root.submitAuthorization()
                }
            }
        }
    }
}
