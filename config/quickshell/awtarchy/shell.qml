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
    readonly property string flyoutGuardScript: configHome + "/hypr/scripts/quickshell_flyout_guard.sh"
    property bool barDragActive: false
    property string barDragMonitor: ""
    property string barDragCandidate: ""

    function validBarEdge(edge) {
        return ["top", "bottom", "left", "right"].indexOf(edge) >= 0;
    }

    function beginBarDrag(monitor) {
        if (!monitor || monitor.length === 0)
            return;
        barDragActive = true;
        barDragMonitor = monitor;
        barDragCandidate = BarState.positionFor(monitor);
    }

    function previewBarDrag(monitor, candidate) {
        if (!barDragActive || barDragMonitor !== monitor)
            return;
        barDragCandidate = validBarEdge(candidate)
            ? candidate
            : BarState.positionFor(monitor);
    }

    function cancelBarDrag() {
        barDragActive = false;
        barDragMonitor = "";
        barDragCandidate = "";
    }

    function finishBarDrag(monitor, candidate) {
        const active = barDragActive && barDragMonitor === monitor;
        const current = BarState.positionFor(monitor);
        const shouldMove = active && validBarEdge(candidate) && candidate !== current;
        cancelBarDrag();

        if (shouldMove) {
            barMoveWriter.exec([
                configHome + "/hypr/scripts/quickshell.sh",
                "setpos",
                monitor,
                candidate
            ]);
        }
    }

    function flyoutByName(surface) {
        if (surface === "clipboard")
            return ClipboardMenu;
        if (surface === "notifications")
            return Notifications;
        if (surface === "quicksettings")
            return QuickSettings;
        if (surface === "network")
            return NetworkMenu;
        if (surface === "bluetooth")
            return BluetoothMenu;
        return null;
    }

    function flyoutWidth(surface) {
        const flyout = flyoutByName(surface);
        return flyout ? flyout.livePanelWidth : -1;
    }

    function flyoutHeight(surface) {
        const flyout = flyoutByName(surface);
        return flyout ? flyout.livePanelHeight : -1;
    }

    // Force singleton construction before the control IPC endpoint reports ready.
    readonly property bool notificationsReady: Notifications.dnd || !Notifications.dnd
    readonly property bool launcherReady: Launcher !== null
    readonly property bool clipboardReady: ClipboardMenu !== null
    readonly property bool quickSettingsReady: QuickSettings !== null
    readonly property bool networkReady: NetworkMenu !== null
    readonly property bool bluetoothReady: BluetoothMenu !== null
    readonly property bool powerReady: PowerMenu !== null
    readonly property bool themesReady: ThemePicker !== null

    Process {
        id: runtimeRules
        running: true
        command: [root.runtimeRulesScript]
        onExited: flyoutGuard.exec([root.flyoutGuardScript])
    }

    Process {
        id: flyoutGuard
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
            implicitWidth: vertical ? BarState.barSizeFor(monitorName, true) : 0
            implicitHeight: vertical ? 0 : BarState.barSizeFor(monitorName, false)
            exclusiveZone: BarState.barSizeFor(monitorName, vertical)
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
        function beginBarDrag(monitor: string): void { root.beginBarDrag(monitor); }
        function previewBarDrag(monitor: string, candidate: string): void { root.previewBarDrag(monitor, candidate); }
        function finishBarDrag(monitor: string, candidate: string): void { root.finishBarDrag(monitor, candidate); }
        function cancelBarDrag(): void { root.cancelBarDrag(); }
        function flyoutWidth(surface: string): int { return root.flyoutWidth(surface); }
        function flyoutHeight(surface: string): int { return root.flyoutHeight(surface); }
    }
}
