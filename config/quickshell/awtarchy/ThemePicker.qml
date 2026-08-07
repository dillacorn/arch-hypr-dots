pragma Singleton

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property var themes: []
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string themeDir: configHome + "/hypr/themes"
    readonly property string applyBackend: configHome + "/hypr/scripts/quickshell_theme_apply.sh"

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function openFocused() {
        const target = focusedScreen();
        if (target)
            pickerWindow.screen = target;
        pickerWindow.visible = true;
        listProcess.running = true;
    }

    function close() { pickerWindow.visible = false; }
    function toggleFocused() { pickerWindow.visible ? close() : openFocused(); }

    function choose(name) {
        close();
        applyProcess.exec([applyBackend, name]);
    }

    IpcHandler {
        target: "themes"
        function toggle(): void { root.toggleFocused(); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
    }

    Process {
        id: listProcess
        command: ["sh", "-lc", "find '" + root.themeDir + "' -maxdepth 1 -type f -executable -printf '%f\\n' 2>/dev/null | LC_ALL=C sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.themes = text.split("\n").filter(value => value.length > 0);
                themeList.currentIndex = root.themes.length > 0 ? 0 : -1;
            }
        }
    }

    Process { id: applyProcess }

    PanelWindow {
        id: pickerWindow
        visible: false
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(520, Math.max(360, pickerWindow.width * 0.36))
            height: Math.min(620, Math.max(320, pickerWindow.height * 0.60))
            color: Theme.popupBackground

            MouseArea { anchors.fill: parent; onPressed: mouse => mouse.accepted = true }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Choose theme"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                }

                ListView {
                    id: themeList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.themes
                    clip: true

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down && count > 0) {
                            currentIndex = Math.min(count - 1, currentIndex + 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && count > 0) {
                            currentIndex = Math.max(0, currentIndex - 1);
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && currentIndex >= 0) {
                            root.choose(root.themes[currentIndex]);
                            event.accepted = true;
                        }
                    }

                    delegate: Rectangle {
                        id: row
                        required property string modelData
                        required property int index
                        width: ListView.view.width
                        height: 42
                        color: ListView.isCurrentItem ? Theme.focus : (mouse.containsMouse ? Theme.subtleHover : "transparent")

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            text: row.modelData
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: themeList.currentIndex = row.index
                            onClicked: root.choose(row.modelData)
                        }
                    }
                }
            }
        }

        onVisibleChanged: if (visible) Qt.callLater(() => themeList.forceActiveFocus())
    }
}
