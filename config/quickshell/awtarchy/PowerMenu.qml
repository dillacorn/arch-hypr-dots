pragma Singleton

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    readonly property var actions: [
        { label: "", text: "Lock (L)", key: "l", command: "hyprlock" },
        { label: "", text: "Logout (O)", key: "o", command: "loginctl kill-session \"$XDG_SESSION_ID\"" },
        { label: "", text: "Suspend (Z)", key: "z", command: "hyprlock & sleep 1; systemctl suspend -i" },
        { label: "", text: "Hibernate (H)", key: "h", command: "hyprlock & sleep 1; systemctl hibernate || loginctl hibernate" },
        { label: "", text: "Reboot (R)", key: "r", command: "systemctl reboot" },
        { label: "", text: "Shutdown (S)", key: "s", command: "systemctl poweroff" }
    ]

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function openForScreen(targetScreen) {
        if (targetScreen)
            powerWindow.screen = targetScreen;
        powerWindow.visible = true;
        Qt.callLater(() => keyCatcher.forceActiveFocus());
    }

    function openFocused() { openForScreen(focusedScreen()); }
    function close() { powerWindow.visible = false; }
    function toggleFocused() { powerWindow.visible ? close() : openFocused(); }

    function runAction(action) {
        close();
        Quickshell.execDetached(["sh", "-lc", action.command]);
    }

    IpcHandler {
        target: "powermenu"
        function toggle(): void { root.toggleFocused(); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
    }

    PanelWindow {
        id: powerWindow
        visible: false
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.85)
            border.width: 0
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: powerWindow.visible

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                    return;
                }

                const typed = event.text ? event.text.toLowerCase() : "";
                for (let i = 0; i < root.actions.length; ++i) {
                    if (typed === root.actions[i].key) {
                        root.runAction(root.actions[i]);
                        event.accepted = true;
                        return;
                    }
                }
            }
        }

        GridLayout {
            anchors.centerIn: parent
            columns: 3
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                model: root.actions

                delegate: Rectangle {
                    required property var modelData
                    width: Math.min(220, Math.max(150, powerWindow.width * 0.14))
                    height: Math.min(150, Math.max(110, powerWindow.height * 0.16))
                    radius: 20
                    color: hover.containsMouse ? Theme.popupButtonHover : Theme.popupButton
                    border.width: 0

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 30
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.text
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.runAction(modelData)
                    }
                }
            }
        }
    }
}
