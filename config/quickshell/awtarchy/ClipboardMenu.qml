pragma Singleton

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property var entries: []
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string backend: configHome + "/hypr/scripts/quickshell_clipboard.sh"

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function openFocused() {
        const target = focusedScreen();
        if (target)
            clipboardWindow.screen = target;
        clipboardWindow.visible = true;
        listProcess.running = true;
    }

    function close() {
        clipboardWindow.visible = false;
    }

    function toggleFocused() {
        if (clipboardWindow.visible)
            close();
        else
            openFocused();
    }

    function choose(index) {
        selectProcess.exec([backend, "select", String(index)]);
        close();
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggleFocused(); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
    }

    Process {
        id: listProcess
        command: [root.backend, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.entries = JSON.parse(text.trim() || "[]");
                    clipboardList.currentIndex = root.entries.length > 0 ? 0 : -1;
                } catch (error) {
                    console.warn("Awtarchy clipboard list parse failed:", error);
                    root.entries = [];
                }
            }
        }
    }

    Process { id: selectProcess }

    PanelWindow {
        id: clipboardWindow
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
            id: panel
            anchors.centerIn: parent
            implicitWidth: Math.min(880, Math.max(560, clipboardWindow.width * 0.68))
            implicitHeight: Math.min(760, Math.max(420, clipboardWindow.height * 0.72))
            width: implicitWidth
            height: implicitHeight
            color: Theme.popupBackground
            radius: 0

            MouseArea {
                anchors.fill: parent
                onPressed: mouse => mouse.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Clipboard"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                }

                ListView {
                    id: clipboardList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.entries
                    clip: true
                    currentIndex: root.entries.length > 0 ? 0 : -1

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down && count > 0) {
                            currentIndex = Math.min(count - 1, currentIndex + 1);
                            positionViewAtIndex(currentIndex, ListView.Contain);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && count > 0) {
                            currentIndex = Math.max(0, currentIndex - 1);
                            positionViewAtIndex(currentIndex, ListView.Contain);
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && currentIndex >= 0) {
                            root.choose(root.entries[currentIndex].index);
                            event.accepted = true;
                        }
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: modelData.thumb && modelData.thumb.length > 0 ? 116 : 44
                        color: ListView.isCurrentItem ? Theme.focus : (rowMouse.containsMouse ? Theme.subtleHover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12

                            Image {
                                visible: row.modelData.thumb && row.modelData.thumb.length > 0
                                Layout.preferredWidth: visible ? 96 : 0
                                Layout.preferredHeight: visible ? 96 : 0
                                source: visible ? "file://" + row.modelData.thumb : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.label
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                elide: Text.ElideRight
                                maximumLineCount: 3
                                wrapMode: Text.WrapAnywhere
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: clipboardList.currentIndex = row.index
                            onClicked: root.choose(row.modelData.index)
                        }
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => clipboardList.forceActiveFocus());
        }
    }
}
