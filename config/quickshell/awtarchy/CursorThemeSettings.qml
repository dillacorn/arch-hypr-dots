pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool active: false
    property string cursorVariant: "ice"
    property string pendingVariant: "ice"
    property string message: ""
    property string runnerError: ""

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string cursorScript: configHome
        + "/hypr/scripts/quickshell_cursor_theme.sh"

    implicitHeight: active ? controls.implicitHeight + 12 : 0

    function refresh() {
        if (!active || statusRunner.running || writer.running)
            return;
        statusRunner.exec(["bash", root.cursorScript, "status"]);
    }

    function setVariant(variant) {
        if (writer.running || variant === cursorVariant)
            return;
        pendingVariant = variant;
        runnerError = "";
        writer.exec(["bash", root.cursorScript, "set", variant]);
    }

    onActiveChanged: {
        if (active)
            refresh();
    }

    Process {
        id: statusRunner
        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.trim();
                if (value === "ice" || value === "classic")
                    root.cursorVariant = value;
            }
        }
    }

    Process {
        id: writer
        stderr: StdioCollector {
            onStreamFinished: root.runnerError = text.trim()
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.cursorVariant = root.pendingVariant;
                root.message = root.cursorVariant === "ice"
                    ? "Bibata Ice cursor applied"
                    : "Bibata Classic cursor applied";
            } else {
                root.message = root.runnerError.length > 0
                    ? root.runnerError.split("\n")[0]
                    : "Cursor theme change failed";
            }
            root.refresh();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.active
        border.width: 1
        border.color: Theme.focus

        ColumnLayout {
            id: controls
            anchors.fill: parent
            anchors.margins: 6
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Cursor"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                SettingsButton {
                    label: "Ice / White"
                    textSize: 9
                    horizontalPadding: 10
                    active: root.cursorVariant === "ice"
                    available: !writer.running
                    onClicked: root.setVariant("ice")
                }

                SettingsButton {
                    label: "Classic / Black"
                    textSize: 9
                    horizontalPadding: 10
                    active: root.cursorVariant === "classic"
                    available: !writer.running
                    onClicked: root.setVariant("classic")
                }

                Item { Layout.fillWidth: true }
            }

            Text {
                Layout.fillWidth: true
                visible: root.message.length > 0
                Layout.preferredHeight: visible ? 18 : 0
                text: root.message
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}
