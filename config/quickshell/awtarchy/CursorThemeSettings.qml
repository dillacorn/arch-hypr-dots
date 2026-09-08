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

    readonly property var supportedVariants: [
        "ice", "classic", "amber",
        "ice-sharp", "classic-sharp", "amber-sharp",
        "ice-right", "classic-right", "amber-right",
        "ice-sharp-right", "classic-sharp-right", "amber-sharp-right"
    ]
    readonly property string cursorColor: cursorVariant.startsWith("classic")
        ? "classic"
        : (cursorVariant.startsWith("amber") ? "amber" : "ice")
    readonly property bool cursorSharp: cursorVariant.indexOf("-sharp") >= 0
    readonly property bool cursorRightHand: cursorVariant.endsWith("-right")

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string cursorScript: configHome
        + "/hypr/scripts/quickshell_cursor_theme.sh"

    implicitHeight: active ? controls.implicitHeight + 12 : 0

    function composeVariant(color, sharp, rightHand) {
        let variant = color;
        if (sharp)
            variant += "-sharp";
        if (rightHand)
            variant += "-right";
        return variant;
    }

    function setColor(color) {
        setVariant(composeVariant(color, cursorSharp, cursorRightHand));
    }

    function setShape(sharp) {
        setVariant(composeVariant(cursorColor, sharp, cursorRightHand));
    }

    function setHandedness(rightHand) {
        setVariant(composeVariant(cursorColor, cursorSharp, rightHand));
    }

    function refresh() {
        if (!active || statusRunner.running || writer.running)
            return;
        statusRunner.exec(["bash", root.cursorScript, "status"]);
    }

    function setVariant(variant) {
        if (writer.running || variant === cursorVariant
                || supportedVariants.indexOf(variant) < 0)
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
                if (root.supportedVariants.indexOf(value) >= 0)
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
                root.message = "Bibata cursor applied";
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
                    text: "Cursor Color"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                SettingsButton {
                    label: "Ice / White"
                    textSize: 9
                    horizontalPadding: 8
                    active: root.cursorColor === "ice"
                    available: !writer.running
                    onClicked: root.setColor("ice")
                }

                SettingsButton {
                    label: "Classic / Black"
                    textSize: 9
                    horizontalPadding: 8
                    active: root.cursorColor === "classic"
                    available: !writer.running
                    onClicked: root.setColor("classic")
                }

                SettingsButton {
                    label: "Amber"
                    textSize: 9
                    horizontalPadding: 8
                    active: root.cursorColor === "amber"
                    available: !writer.running
                    onClicked: root.setColor("amber")
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Cursor Shape"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                SettingsButton {
                    label: "Rounded"
                    textSize: 9
                    horizontalPadding: 10
                    active: !root.cursorSharp
                    available: !writer.running
                    onClicked: root.setShape(false)
                }

                SettingsButton {
                    label: "Sharp"
                    textSize: 9
                    horizontalPadding: 10
                    active: root.cursorSharp
                    available: !writer.running
                    onClicked: root.setShape(true)
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Cursor Hand"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                SettingsButton {
                    label: "Normal"
                    textSize: 9
                    horizontalPadding: 10
                    active: !root.cursorRightHand
                    available: !writer.running
                    onClicked: root.setHandedness(false)
                }

                SettingsButton {
                    label: "Right Hand"
                    textSize: 9
                    horizontalPadding: 10
                    active: root.cursorRightHand
                    available: !writer.running
                    onClicked: root.setHandedness(true)
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
