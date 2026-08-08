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

                function updateCandidate() {
                    const dx = edgeDrag.activeTranslation.x;
                    const dy = edgeDrag.activeTranslation.y;
                    const distance = Math.max(Math.abs(dx), Math.abs(dy));

                    if (distance < 40) {
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

                Timer {
                    id: dragRefreshQuick
                    interval: 100
                    repeat: false
                    onTriggered: BarState.refresh()
                }

                Timer {
                    id: dragRefreshFollowup
                    interval: 350
                    repeat: false
                    onTriggered: BarState.refresh()
                }

                DragHandler {
                    id: edgeDrag
                    parent: barInstance.contentItem
                    target: null
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.AltModifier
                    dragThreshold: 4
                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                        | PointerHandler.ApprovesTakeOverByAnything

                    onActiveTranslationChanged: dragSurface.updateCandidate()

                    onActiveChanged: {
                        if (active) {
                            dragSurface.candidateEdge = barInstance.position;
                            dragSurface.hasCandidate = false;
                            return;
                        }

                        if (dragSurface.hasCandidate
                                && dragSurface.candidateEdge !== barInstance.position) {
                            Quickshell.execDetached([
                                (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hypr/scripts/quickshell.sh",
                                "setpos",
                                barInstance.monitorName,
                                dragSurface.candidateEdge
                            ]);
                            dragRefreshQuick.restart();
                            dragRefreshFollowup.restart();
                        }

                        dragSurface.hasCandidate = false;
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: barInstance.vertical ? parent.width : Math.min(150, parent.width)
                    height: barInstance.vertical ? Math.min(90, parent.height) : parent.height
                    color: Theme.focus
                    radius: 0
                    opacity: edgeDrag.active && dragSurface.hasCandidate ? 0.96 : 0
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
