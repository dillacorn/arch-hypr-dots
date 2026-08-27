import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100
    property string floatingState: "checking"
    property string message: ""
    property string errorMessage: ""

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string helper: configHome + "/hypr/scripts/quickshell_floating_windows.sh"
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
        if (floatingState === "enabled")
            return "Enabled";
        if (floatingState === "disabled")
            return "Disabled";
        if (floatingState === "unavailable")
            return "Unavailable";
        return "Checking…";
    }

    function probeStatus() {
        if (!active || operationBusy)
            return;
        statusRunner.exec([root.helper, "status"]);
    }

    function requestToggle() {
        if (operationBusy)
            return;
        errorMessage = "";
        message = floatingState === "enabled"
            ? "Restoring tiled windows as the default…"
            : "Making new windows float by default…";
        actionRunner.exec([
            root.helper,
            "set",
            floatingState === "enabled" ? "off" : "on"
        ]);
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
                root.floatingState = state === "enabled" || state === "disabled"
                    ? state : "unavailable";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const detail = text.trim();
                if (detail.length > 0)
                    root.errorMessage = detail.split("\n")[0];
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.floatingState = "unavailable";
        }
    }

    Process {
        id: actionRunner
        stdout: StdioCollector {
            onStreamFinished: {
                const state = text.trim();
                if (state === "enabled" || state === "disabled")
                    root.floatingState = state;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const detail = text.trim();
                if (detail.length > 0)
                    root.errorMessage = detail.split("\n")[0];
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.errorMessage = "";
                root.message = root.floatingState === "enabled"
                    ? "Floating Windows enabled."
                    : "Floating Windows disabled.";
            } else {
                root.message = "";
                if (root.errorMessage.length === 0)
                    root.errorMessage = "Could not update the Floating Windows preference.";
            }
            Qt.callLater(() => root.probeStatus());
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
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Window Behavior"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(12)
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "Floating Windows"
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
                label: root.floatingState === "enabled" ? "Disable" : "Enable"
                active: root.floatingState === "enabled"
                textSize: root.scaledText(9)
                enabled: (root.floatingState === "enabled" || root.floatingState === "disabled")
                    && !root.operationBusy
                onClicked: root.requestToggle()
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.errorMessage.length > 0
                ? root.errorMessage
                : (root.message.length > 0
                    ? root.message
                    : (root.floatingState === "enabled"
                        ? "New windows open floating by default. Existing windows keep their current state. Use SUPER+F to tile or float the focused window."
                        : "New windows use Awtarchy's normal tiling behavior. Existing windows keep their current state."))
            color: root.errorMessage.length > 0 ? Theme.urgent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
