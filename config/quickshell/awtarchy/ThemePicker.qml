pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

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

    function filteredThemes() {
        const query = search.text.trim().toLowerCase();
        if (query.length === 0)
            return themes;
        return themes.filter(name => name.toLowerCase().indexOf(query) >= 0);
    }

    function resetSelection() {
        themeList.currentIndex = themeList.count > 0 ? 0 : -1;
        Qt.callLater(() => {
            themeList.currentIndex = themeList.count > 0 ? 0 : -1;
            themeList.positionViewAtBeginning();
        });
    }

    function openForScreen(target) {
        if (target)
            pickerWindow.screen = target;
        search.text = "";
        pickerWindow.visible = true;
        listProcess.running = true;
        resetSelection();
        Qt.callLater(() => search.forceActiveFocus());
    }

    function openFocused() { openForScreen(focusedScreen()); }

    function close() {
        pickerWindow.visible = false;
        search.text = "";
    }

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
        command: ["sh", "-lc", "find '" + root.themeDir + "' -maxdepth 1 -type f ! -name '*.backup*' -printf '%f\\n' 2>/dev/null | LC_ALL=C sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.themes = text.split("\n").filter(value => value.length > 0);
                root.resetSelection();
            }
        }
    }

    Process { id: applyProcess }

    PanelWindow {
        id: pickerWindow
        WlrLayershell.namespace: "awtarchy-theme-picker"
        visible: false
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 420
        implicitHeight: 372
        anchors.top: true
        anchors.left: true
        margins {
            top: Math.max(6, Math.round(((screen ? screen.height : 1080) - implicitHeight) / 2))
            left: Math.max(6, Math.round(((screen ? screen.width : 1920) - implicitWidth) / 2))
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 0
            radius: 0

            MouseArea {
                anchors.fill: parent
                onPressed: mouse => mouse.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: Theme.active
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: "Choose theme:"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }

                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.foreground
                            selectionColor: Theme.focus
                            selectedTextColor: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    root.close();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down) {
                                    if (themeList.count > 0) {
                                        const current = Math.max(0, themeList.currentIndex);
                                        themeList.currentIndex = (current + 1) % themeList.count;
                                        themeList.positionViewAtIndex(themeList.currentIndex, ListView.Contain);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    if (themeList.count > 0) {
                                        const current = Math.max(0, themeList.currentIndex);
                                        themeList.currentIndex = (current - 1 + themeList.count) % themeList.count;
                                        themeList.positionViewAtIndex(themeList.currentIndex, ListView.Contain);
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    const values = root.filteredThemes();
                                    if (themeList.currentIndex >= 0 && themeList.currentIndex < values.length)
                                        root.choose(values[themeList.currentIndex]);
                                    event.accepted = true;
                                }
                            }

                            onTextChanged: root.resetSelection()
                        }
                    }
                }

                ListView {
                    id: themeList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0
                    currentIndex: count > 0 ? 0 : -1

                    model: ScriptModel {
                        values: root.filteredThemes()
                    }

                    delegate: Rectangle {
                        id: row
                        required property string modelData
                        required property int index
                        property string themeName: modelData
                        width: ListView.view.width
                        height: 28
                        color: ListView.isCurrentItem ? Theme.focus : (mouse.containsMouse ? Theme.subtleHover : "transparent")

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            text: row.themeName
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.choose(row.themeName)
                        }
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => search.forceActiveFocus());
        }
    }
}
