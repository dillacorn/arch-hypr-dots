pragma ComponentBehavior: Bound

pragma Singleton

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property var entries: []
    property string placement: "center"
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string backend: configHome + "/hypr/scripts/quickshell_clipboard.sh"

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function placementForScreen(targetScreen) {
        if (!targetScreen || !BarState.enabledFor(targetScreen.name))
            return "center";
        return BarState.positionFor(targetScreen.name);
    }

    function openFocused() {
        const target = focusedScreen();
        if (target)
            clipboardWindow.screen = target;
        placement = placementForScreen(target);
        search.text = "";
        clipboardWindow.visible = true;
        listProcess.running = true;
        Qt.callLater(() => search.forceActiveFocus());
    }

    function close() {
        clipboardWindow.visible = false;
        search.text = "";
    }

    function toggleFocused() {
        if (clipboardWindow.visible)
            close();
        else
            openFocused();
    }

    function choose(entry) {
        if (!entry)
            return;
        selectProcess.exec([backend, "select", String(entry.index)]);
        close();
    }

    function fuzzyScore(haystack, query) {
        if (query.length === 0)
            return 0;
        const exact = haystack.indexOf(query);
        if (exact >= 0)
            return 5000 - exact * 4 + (exact === 0 ? 1000 : 0);

        let score = 0;
        let at = 0;
        let previous = -2;
        for (let i = 0; i < query.length; ++i) {
            const found = haystack.indexOf(query[i], at);
            if (found < 0)
                return -1;
            score += 20;
            if (found === previous + 1)
                score += 35;
            if (found === 0 || " -_./".indexOf(haystack[found - 1]) >= 0)
                score += 45;
            score -= Math.min(20, found - at);
            previous = found;
            at = found + 1;
        }
        return score - Math.min(200, haystack.length);
    }

    function filteredEntries() {
        const query = search.text.trim().toLowerCase();
        const scored = entries.map(entry => ({
            entry: entry,
            score: fuzzyScore(String(entry.label || "").toLowerCase(), query)
        })).filter(item => item.score >= 0);

        if (query.length > 0)
            scored.sort((a, b) => b.score - a.score);
        return scored.map(item => item.entry);
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
            implicitWidth: Math.min(880, Math.max(560, clipboardWindow.width * 0.68))
            implicitHeight: Math.min(760, Math.max(420, clipboardWindow.height * 0.72))
            width: implicitWidth
            height: implicitHeight
            x: root.placement === "left"
                ? 8
                : root.placement === "right"
                    ? parent.width - width - 8
                    : Math.round((parent.width - width) / 2)
            y: root.placement === "top"
                ? 8
                : root.placement === "bottom"
                    ? parent.height - height - 8
                    : Math.round((parent.height - height) / 2)
            color: Theme.popupBackground
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
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: "Clipboard"
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
                                } else if (event.key === Qt.Key_Down && clipboardList.count > 0) {
                                    clipboardList.currentIndex = Math.min(clipboardList.count - 1, clipboardList.currentIndex + 1);
                                    clipboardList.positionViewAtIndex(clipboardList.currentIndex, ListView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up && clipboardList.count > 0) {
                                    clipboardList.currentIndex = Math.max(0, clipboardList.currentIndex - 1);
                                    clipboardList.positionViewAtIndex(clipboardList.currentIndex, ListView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    const values = root.filteredEntries();
                                    if (clipboardList.currentIndex >= 0 && clipboardList.currentIndex < values.length)
                                        root.choose(values[clipboardList.currentIndex]);
                                    event.accepted = true;
                                }
                            }

                            onTextChanged: clipboardList.currentIndex = 0
                        }
                    }
                }

                ListView {
                    id: clipboardList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: ScriptModel { values: root.filteredEntries() }
                    clip: true
                    currentIndex: count > 0 ? 0 : -1

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
                            onClicked: root.choose(row.modelData)
                            onWheel: wheel => {
                                const maxY = Math.max(0, clipboardList.contentHeight - clipboardList.height);
                                clipboardList.contentY = Math.max(0, Math.min(maxY, clipboardList.contentY - wheel.angleDelta.y));
                                wheel.accepted = true;
                            }
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
