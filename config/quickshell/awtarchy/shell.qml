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

    Variants {
        model: Quickshell.screens

        Bar {
            id: barInstance

            implicitWidth: vertical ? BarState.barSizeFor(monitorName, true) : 0
            implicitHeight: vertical ? 0 : BarState.barSizeFor(monitorName, false)
            exclusiveZone: BarState.barSizeFor(monitorName, vertical)

            Item {
                id: dragSurface
                anchors.fill: parent
                z: 10000
                property string candidateEdge: barInstance.position

                function updateCandidate() {
                    const dx = edgeDrag.activeTranslation.x;
                    const dy = edgeDrag.activeTranslation.y;
                    if (Math.abs(dx) < 10 && Math.abs(dy) < 10) {
                        candidateEdge = barInstance.position;
                    } else if (Math.abs(dx) > Math.abs(dy)) {
                        candidateEdge = dx >= 0 ? "right" : "left";
                    } else {
                        candidateEdge = dy >= 0 ? "bottom" : "top";
                    }
                }

                function edgeGlyph(edge) {
                    if (edge === "top") return "↑";
                    if (edge === "bottom") return "↓";
                    if (edge === "left") return "←";
                    return "→";
                }

                DragHandler {
                    id: edgeDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.AltModifier
                    dragThreshold: 4

                    xAxis.onActiveValueChanged: dragSurface.updateCandidate()
                    yAxis.onActiveValueChanged: dragSurface.updateCandidate()

                    onActiveChanged: {
                        if (active) {
                            dragSurface.candidateEdge = barInstance.position;
                            return;
                        }

                        if (dragSurface.candidateEdge !== barInstance.position) {
                            Quickshell.execDetached([
                                (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hypr/scripts/quickshell.sh",
                                "setpos",
                                barInstance.monitorName,
                                dragSurface.candidateEdge
                            ]);
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: barInstance.vertical ? parent.width : Math.min(150, parent.width)
                    height: barInstance.vertical ? Math.min(90, parent.height) : parent.height
                    color: Theme.focus
                    radius: 0
                    opacity: edgeDrag.active ? 0.96 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 100
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
