//@ pragma ShellId awtarchy
//@ pragma CacheDir $BASE/awtarchy-quickshell
//@ pragma StateDir $BASE/awtarchy-quickshell
//@ pragma IconTheme Papirus-Dark
//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"
    property bool barDragActive: false
    property string barDragMonitor: ""
    property string barDragCandidate: ""

    // Force singleton construction before the control IPC endpoint reports ready.
    readonly property bool notificationsReady: Notifications.dnd || !Notifications.dnd
    readonly property bool launcherReady: Launcher !== null
    readonly property bool clipboardReady: ClipboardMenu !== null
    readonly property bool powerReady: PowerMenu !== null
    readonly property bool themesReady: ThemePicker !== null

    Process {
        id: runtimeRules
        running: true
        command: [root.runtimeRulesScript]
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event && event.name === "configreloaded")
                runtimeRules.exec([root.runtimeRulesScript]);
        }
    }

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
                    } else {
                        hasCandidate = true;
                        if (Math.abs(dx) > Math.abs(dy))
                            candidateEdge = dx >= 0 ? "right" : "left";
                        else
                            candidateEdge = dy >= 0 ? "bottom" : "top";
                    }

                    root.barDragCandidate = candidateEdge;
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
                    interval: 120
                    repeat: false
                    onTriggered: BarState.refresh()
                }

                MouseArea {
                    id: barDrag
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: false
                    propagateComposedEvents: true
                    preventStealing: dragging
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
                        root.barDragActive = true;
                        root.barDragMonitor = barInstance.monitorName;
                        root.barDragCandidate = barInstance.position;
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

                        const targetEdge = dragSurface.candidateEdge;
                        const shouldMove = dragSurface.hasCandidate
                            && targetEdge !== barInstance.position;

                        dragging = false;
                        dragSurface.hasCandidate = false;
                        root.barDragActive = false;
                        root.barDragMonitor = "";
                        root.barDragCandidate = "";

                        if (shouldMove) {
                            barMoveWriter.exec([
                                root.configHome + "/hypr/scripts/quickshell.sh",
                                "setpos",
                                barInstance.monitorName,
                                targetEdge
                            ]);
                        }
                        mouse.accepted = true;
                    }

                    onCanceled: {
                        dragging = false;
                        dragSurface.hasCandidate = false;
                        root.barDragActive = false;
                        root.barDragMonitor = "";
                        root.barDragCandidate = "";
                    }
                }
            }
        }
    }

    // A non-interactive full-edge ghost shows exactly where the bar will land.
    // The real bar stays in place until ALT + left-click is released.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barDropPreview
            required property var modelData

            screen: modelData
            readonly property string monitorName: modelData ? modelData.name : ""
            readonly property string candidate: root.barDragCandidate
            readonly property bool candidateVertical: candidate === "left" || candidate === "right"
            readonly property int previewSize: BarState.barSizeFor(monitorName, candidateVertical)

            visible: root.barDragActive
                && root.barDragMonitor === monitorName
                && candidate.length > 0
                && candidate !== BarState.positionFor(monitorName)
            color: "transparent"
            focusable: false
            aboveWindows: true
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            mask: Region {}

            implicitWidth: candidateVertical ? previewSize : 0
            implicitHeight: candidateVertical ? 0 : previewSize

            anchors.top: candidate === "top" || candidateVertical
            anchors.bottom: candidate === "bottom" || candidateVertical
            anchors.left: candidate === "left" || !candidateVertical
            anchors.right: candidate === "right" || !candidateVertical

            Rectangle {
                anchors.fill: parent
                color: Theme.focus
                opacity: 0.34

                Text {
                    anchors.centerIn: parent
                    text: barDropPreview.candidate === "top" ? "↑"
                        : barDropPreview.candidate === "bottom" ? "↓"
                        : barDropPreview.candidate === "left" ? "←" : "→"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
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
