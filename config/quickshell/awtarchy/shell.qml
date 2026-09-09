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
    readonly property string barDragRuntimeScript: configHome + "/hypr/scripts/quickshell_bar_drag_runtime.sh"
    readonly property string updateNotificationsScript: configHome + "/hypr/scripts/quickshell_update_notifications.sh"
    property bool barDragActive: false
    property bool barDropPending: false
    property string barDragMonitor: ""
    property string barDragCandidate: ""
    property string barDropTarget: ""

    function runUpdateNotificationCheck(mode) {
        if (!updateNotificationCheck.running)
            updateNotificationCheck.exec([updateNotificationsScript, mode]);
    }

    function validBarEdge(edge) {
        return ["top", "bottom", "left", "right"].indexOf(edge) >= 0;
    }

    function barWindowFor(name) {
        const monitor = String(name || "");
        for (let i = 0; i < barVariants.instances.length; ++i) {
            const window = barVariants.instances[i];
            if (window && String(window.monitorName || "") === monitor)
                return window;
        }
        return null;
    }

    function beginBarDrag(monitor) {
        if (!monitor || monitor.length === 0)
            return;
        barDropSettle.stop();
        barDragWatchdog.restart();
        barDragActive = true;
        barDropPending = false;
        barDragMonitor = monitor;
        // Do not draw a drop shadow at the bar's existing edge. A shadow only
        // appears once the drag actually selects a different destination.
        barDragCandidate = "";
        barDropTarget = "";
    }

    function previewBarDrag(monitor, candidate) {
        if (!barDragActive || barDragMonitor !== monitor)
            return;
        const current = BarState.positionFor(monitor);
        barDragCandidate = validBarEdge(candidate) && candidate !== current
            ? candidate : "";
    }

    function clearBarDragState() {
        barDragWatchdog.stop();
        barDropSettle.stop();
        barDragActive = false;
        barDropPending = false;
        barDragMonitor = "";
        barDragCandidate = "";
        barDropTarget = "";
    }

    function cancelBarDrag() {
        clearBarDragState();
    }

    function finishBarDrag(monitor, candidate) {
        const active = barDragActive && barDragMonitor === monitor;
        const current = BarState.positionFor(monitor);
        const shouldMove = active && validBarEdge(candidate) && candidate !== current;
        barDragWatchdog.stop();

        if (!shouldMove) {
            clearBarDragState();
            return;
        }

        // Keep the real bar slightly detached while the persisted edge changes,
        // then settle it back against the new edge after state refresh.
        barDragActive = false;
        barDropPending = true;
        barDragCandidate = candidate;
        barDropTarget = candidate;
        barMoveWriter.exec([
            configHome + "/hypr/scripts/quickshell.sh",
            "setpos",
            monitor,
            candidate
        ]);
    }

    function flyoutByName(surface) {
        if (surface === "clipboard")
            return ClipboardMenu;
        if (surface === "notifications")
            return Notifications;
        if (surface === "quicksettings" || surface === "quick-settings")
            return QuickSettings;
        if (surface === "network")
            return NetworkMenu;
        if (surface === "bluetooth")
            return BluetoothMenu;
        if (surface === "battery")
            return BatteryMenu;
        return null;
    }

    function closeActiveFloatingSurface() {
        const surface = String(FlyoutManager.activeSurface || "");
        if (surface.length === 0)
            return;

        if (surface === "launcher") {
            Launcher.close();
            return;
        }

        // Notifications exposes closeCenter(), unlike the other floating
        // flyouts. Handle it explicitly so workspace changes cannot leave its
        // QML visible state stale on the previous workspace.
        if (surface === "notifications") {
            Notifications.closeCenter();
            return;
        }

        const flyout = flyoutByName(surface);
        if (flyout && flyout.close)
            flyout.close();
    }

    function closeTopFloatingSurface() {
        if (LockscreenEditor.open) {
            LockscreenEditor.close();
            return;
        }
        if (ThemePicker.open) {
            ThemePicker.close();
            return;
        }
        closeActiveFloatingSurface();
    }

    function flyoutWidth(surface) {
        const flyout = flyoutByName(surface);
        return flyout ? flyout.livePanelWidth : -1;
    }

    function flyoutHeight(surface) {
        const flyout = flyoutByName(surface);
        return flyout ? flyout.livePanelHeight : -1;
    }

    function barDragState() {
        return JSON.stringify({
            active: barDragActive,
            dropPending: barDropPending,
            monitor: barDragMonitor,
            candidate: barDragCandidate,
            target: barDropTarget
        });
    }

    // Force singleton construction before the control IPC endpoint reports ready.
    readonly property bool notificationsReady: Notifications.dnd || !Notifications.dnd
    readonly property bool launcherReady: Launcher !== null
    readonly property bool clipboardReady: ClipboardMenu !== null
    readonly property bool quickSettingsReady: QuickSettings !== null
    readonly property bool numlockTweakReady: NumlockSessionTweak.enabled || !NumlockSessionTweak.enabled
    readonly property bool networkReady: NetworkMenu !== null
    readonly property bool bluetoothReady: BluetoothMenu !== null
    readonly property bool batteryReady: BatteryMenu !== null
    readonly property bool powerReady: PowerMenu !== null
    readonly property bool themesReady: ThemePicker !== null
    readonly property bool lockscreenEditorReady: LockscreenEditor !== null
    readonly property bool lockscreenWeatherReady: LockscreenWeather !== null

    // Escape always closes the topmost visible shell surface first. A Theme
    // Picker opened from Quick Settings must close without dismissing the
    // Quick Settings flyout beneath it.
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: LockscreenEditor.open
            || ThemePicker.open
            || String(FlyoutManager.activeSurface || "").length > 0
        autoRepeat: false
        onActivated: root.closeTopFloatingSurface()
    }

    Process {
        id: updateNotificationCheck
    }

    Timer {
        id: initialUpdateNotificationCheck
        interval: 30000
        repeat: false
        running: true
        onTriggered: root.runUpdateNotificationCheck("login")
    }

    Timer {
        id: periodicUpdateNotificationCheck
        interval: 21600000
        repeat: true
        running: true
        onTriggered: root.runUpdateNotificationCheck("check")
    }

    Process {
        id: runtimeRules
        running: true
        command: [root.runtimeRulesScript]
        onExited: {
            if (!barDragRuntime.running)
                barDragRuntime.exec(["bash", root.barDragRuntimeScript]);
        }
    }

    Process {
        id: barDragRuntime
    }

    Process {
        id: barMoveWriter
        onExited: {
            BarState.refresh();
            dragRefreshFollowup.restart();
            if (root.barDropPending)
                barDropSettle.restart();
        }
    }

    Timer {
        id: dragRefreshFollowup
        interval: 120
        repeat: false
        onTriggered: {
            BarState.refresh();
            if (root.barDropPending)
                barDropSettle.restart();
        }
    }

    Timer {
        id: barDropSettle
        interval: 160
        repeat: false
        onTriggered: root.clearBarDragState()
    }

    Timer {
        id: barDragWatchdog
        interval: 15000
        repeat: false
        onTriggered: {
            root.clearBarDragState();
            if (!barDragRuntime.running)
                barDragRuntime.exec(["bash", root.barDragRuntimeScript]);
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!event)
                return;

            if (event.name === "moveworkspace" || event.name === "moveworkspacev2") {
                Hyprland.refreshMonitors();
                return;
            }

            if (event.name === "configreloaded") {
                runtimeRules.exec([root.runtimeRulesScript]);
                NumlockSessionTweak.enforce();
                return;
            }

            // FloatingWindow visibility is QML state, not Hyprland workspace
            // visibility. Close the active surface when the focused workspace
            // changes so a window left on the previous workspace can never
            // consume the next toggle as a stale close operation.
            if (event.name === "workspace" || event.name === "workspacev2")
                root.closeActiveFloatingSurface();
        }
    }

    Variants {
        id: barVariants
        model: Quickshell.screens

        Bar {
            id: barInstance
            readonly property bool dragVisualActive: root.barDragMonitor === monitorName
                && (root.barDragActive || root.barDropPending)
            readonly property bool autoHide: BarState.autoHideFor(monitorName)
            readonly property bool autoHideFlyoutHeld: autoHide
                && FlyoutManager.activeMonitorName === monitorName
                && String(FlyoutManager.activeSurface || "").length > 0
            readonly property bool autoHideHeld: autoHide
                && (autoHideHover.hovered || autoHideFlyoutHeld || dragVisualActive)
            property bool autoHideRevealed: true
            property real autoHideOffset: autoHide && !autoHideRevealed
                ? -BarState.barSizeFor(monitorName, vertical) : 0
            property real dragFloatGap: dragVisualActive ? 5 : 0

            implicitWidth: vertical ? BarState.barSizeFor(monitorName, true) : 0
            implicitHeight: vertical ? 0 : BarState.barSizeFor(monitorName, false)
            exclusiveZone: autoHide ? 0 : BarState.barSizeFor(monitorName, vertical)

            // PanelWindow margins apply only to anchored edges. In auto-hide
            // mode only the configured screen edge receives the negative slide
            // offset, while dragFloatGap keeps the existing drag affordance.
            margins.top: Math.round(dragFloatGap + (position === "top" ? autoHideOffset : 0))
            margins.bottom: Math.round(dragFloatGap + (position === "bottom" ? autoHideOffset : 0))
            margins.left: Math.round(dragFloatGap + (position === "left" ? autoHideOffset : 0))
            margins.right: Math.round(dragFloatGap + (position === "right" ? autoHideOffset : 0))

            function revealAutoHide() {
                if (!autoHide || !visible)
                    return;
                autoHideInitialTimer.stop();
                autoHideRevealed = true;
                if (autoHideHeld)
                    autoHideLeaveTimer.stop();
                else
                    autoHideLeaveTimer.restart();
            }

            function hideAutoHide() {
                if (!autoHide || !visible || autoHideHeld)
                    return;
                autoHideInitialTimer.stop();
                autoHideLeaveTimer.stop();
                autoHideRevealed = false;
            }

            function scheduleAutoHide() {
                if (!autoHide || !visible || autoHideHeld) {
                    autoHideLeaveTimer.stop();
                    return;
                }
                autoHideLeaveTimer.restart();
            }

            onAutoHideChanged: {
                autoHideInitialTimer.stop();
                autoHideLeaveTimer.stop();
                autoHideRevealed = true;
                if (autoHide && visible)
                    autoHideInitialTimer.restart();
            }

            onAutoHideHeldChanged: {
                if (autoHideHeld)
                    revealAutoHide();
                else
                    scheduleAutoHide();
            }

            onVisibleChanged: {
                autoHideInitialTimer.stop();
                autoHideLeaveTimer.stop();
                if (!visible) {
                    if (autoHide)
                        autoHideRevealed = false;
                    return;
                }
                autoHideRevealed = true;
                if (autoHide)
                    autoHideInitialTimer.restart();
            }

            Component.onCompleted: {
                if (autoHide && visible)
                    autoHideInitialTimer.restart();
            }

            HoverHandler {
                id: autoHideHover
                enabled: barInstance.autoHide
            }

            Timer {
                id: autoHideInitialTimer
                interval: 2000
                repeat: false
                onTriggered: barInstance.hideAutoHide()
            }

            Timer {
                id: autoHideLeaveTimer
                interval: 700
                repeat: false
                onTriggered: barInstance.hideAutoHide()
            }

            Behavior on autoHideOffset {
                enabled: FlyoutManager.animationsEnabled
                NumberAnimation {
                    duration: 170
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on dragFloatGap {
                NumberAnimation {
                    duration: 110
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // Expose the actual per-monitor bar QsWindow instances to popup focus grabs.
    // A bar click should remain an actionable shell click, while application
    // windows stay outside the whitelist and continue to dismiss the launcher.
    Binding {
        target: FlyoutManager
        property: "barWindows"
        value: {
            const windows = [];
            for (let i = 0; i < barVariants.instances.length; ++i)
                windows.push(barVariants.instances[i]);
            return windows;
        }
    }

    // Auto-hidden bars remain mapped so their runtime state and flyout ownership
    // stay intact. A separate 2px transparent layer-shell strip is the only
    // pointer-active surface left on the configured edge while the bar is away.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: edgeReveal
            required property var modelData

            screen: modelData
            readonly property string monitorName: modelData ? modelData.name : ""
            readonly property var targetBar: root.barWindowFor(monitorName)
            readonly property string edgePosition: BarState.positionFor(monitorName)
            readonly property bool edgeVertical: edgePosition === "left" || edgePosition === "right"

            visible: targetBar !== null
                && targetBar.visible && targetBar.autoHide && !targetBar.autoHideRevealed
            color: "transparent"
            surfaceFormat.opaque: false
            focusable: false
            aboveWindows: true
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            implicitWidth: edgeVertical ? 2 : 0
            implicitHeight: edgeVertical ? 0 : 2

            anchors.top: edgePosition === "top" || edgeVertical
            anchors.bottom: edgePosition === "bottom" || edgeVertical
            anchors.left: edgePosition === "left" || !edgeVertical
            anchors.right: edgePosition === "right" || !edgeVertical

            HoverHandler {
                id: edgeHover
                onHoveredChanged: {
                    if (hovered)
                        edgeRevealDelay.restart();
                    else
                        edgeRevealDelay.stop();
                }
            }

            Timer {
                id: edgeRevealDelay
                interval: 100
                repeat: false
                onTriggered: {
                    if (edgeHover.hovered && edgeReveal.targetBar)
                        edgeReveal.targetBar.revealAutoHide();
                }
            }
        }
    }

    // A non-interactive full-edge ghost shows only a different destination.
    // Returning the pointer toward the bar's existing edge hides the ghost so
    // a no-op drop is represented by the floating bar itself, not a fake move.
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
                && root.validBarEdge(candidate)
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
        function barDragState(): string { return root.barDragState(); }
        function flyoutWidth(surface: string): int { return root.flyoutWidth(surface); }
        function flyoutHeight(surface: string): int { return root.flyoutHeight(surface); }
        function recentBarMonitor(): string { return FlyoutManager.recentBarMonitor(); }
    }
}
