//@ pragma ShellId awtarchy
//@ pragma CacheDir $BASE/awtarchy-quickshell
//@ pragma StateDir $BASE/awtarchy-quickshell
//@ pragma IconTheme Papirus-Dark
//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // Force singleton construction before the control IPC endpoint reports ready.
    readonly property bool notificationsReady: Notifications.dnd || !Notifications.dnd
    readonly property bool launcherReady: Launcher !== null
    readonly property bool clipboardReady: ClipboardMenu !== null
    readonly property bool powerReady: PowerMenu !== null
    readonly property bool themesReady: ThemePicker !== null
    readonly property bool barSettingsReady: BarSettings !== null
    readonly property bool applicationSettingsReady: ApplicationSettings !== null

    Variants {
        model: Quickshell.screens

        Bar {
            id: barInstance

            implicitWidth: vertical ? BarState.barSizeFor(monitorName, true) : 0
            implicitHeight: vertical ? 0 : BarState.barSizeFor(monitorName, false)
            exclusiveZone: BarState.barSizeFor(monitorName, vertical)

            Item {
                id: dragSurface
                parent: barInstance.contentItem
                anchors.fill: parent
                z: 10000
                property string candidateEdge: barInstance.position
                property bool hasCandidate: false

                function updateCandidate(dx, dy) {
                    const distance = Math.max(Math.abs(dx), Math.abs(dy));
                    if (distance < 32) {
                        candidateEdge = barInstance.position;
                        hasCandidate = false;
                        return;
                    }

                    hasCandidate = true;
                    if (Math.abs(dx) > Math.abs(dy))
                        candidateEdge = dx >= 0 ? "right" : "left";
                    else
                        candidateEdge = dy >= 0 ? "bottom" : "top";
                }

                function edgeGlyph(edge) {
                    if (edge === "top") return "↑";
                    if (edge === "bottom") return "↓";
                    if (edge === "left") return "←";
                    return "→";
                }

                Process {
                    id: barMoveWriter
                    onExited: {
                        BarState.refresh();
                        dragRefreshFollowup.restart();
                    }
                }

                Timer {
                    id: dragRefreshFollowup
                    interval: 100
                    repeat: false
                    onTriggered: BarState.refresh()
                }

                MouseArea {
                    id: barDrag
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: false
                    propagateComposedEvents: true
                    property bool dragging: false
                    property real startX: 0
                    property real startY: 0

                    onPressed: mouse => {
                        if (!(mouse.modifiers & Qt.AltModifier)) {
                            mouse.accepted = false;
                            return;
                        }

                        dragging = true;
                        startX = mouse.x;
                        startY = mouse.y;
                        dragSurface.candidateEdge = barInstance.position;
                        dragSurface.hasCandidate = false;
                        mouse.accepted = true;
                    }

                    onPositionChanged: mouse => {
                        if (!dragging)
                            return;
                        dragSurface.updateCandidate(mouse.x - startX, mouse.y - startY);
                    }

                    onReleased: mouse => {
                        if (!dragging)
                            return;

                        dragging = false;
                        if (dragSurface.hasCandidate
                                && dragSurface.candidateEdge !== barInstance.position) {
                            barMoveWriter.exec([
                                (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hypr/scripts/quickshell.sh",
                                "setpos",
                                barInstance.monitorName,
                                dragSurface.candidateEdge
                            ]);
                        }
                        dragSurface.hasCandidate = false;
                        mouse.accepted = true;
                    }

                    onCanceled: {
                        dragging = false;
                        dragSurface.hasCandidate = false;
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: barInstance.vertical ? parent.width : Math.min(150, parent.width)
                    height: barInstance.vertical ? Math.min(90, parent.height) : parent.height
                    color: Theme.focus
                    radius: 0
                    opacity: barDrag.dragging && dragSurface.hasCandidate ? 0.96 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutCubic
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: dragSurface.edgeGlyph(dragSurface.candidateEdge)
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: barInstance.vertical ? 20 : 18
                        font.bold: true
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "control"
        function ping(): string { return "ok"; }
        function reload(): void { Quickshell.reload(false); }
        function hardReload(): void { Quickshell.reload(true); }
        function quit(): void { Qt.quit(); }
    }
}
