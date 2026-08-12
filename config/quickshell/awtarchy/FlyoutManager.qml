pragma Singleton

import QtQuick
import Quickshell.Hyprland

QtObject {
    id: root

    property string activeSurface: ""
    property string activeMonitorName: ""
    property string recentBarMonitorName: ""
    property real recentBarMonitorTimestamp: 0
    property var barWindows: []
    readonly property int recentBarMonitorLifetimeMs: 1500
    signal closeRequested(string exceptSurface)

    function focusedMonitorName() {
        return Hyprland.focusedMonitor && Hyprland.focusedMonitor.name
            ? String(Hyprland.focusedMonitor.name) : "";
    }

    function armBar(monitorName) {
        const monitor = String(monitorName || "");
        if (monitor.length === 0)
            return;

        // Launcher.openForScreen() toggles itself closed before it reaches
        // claim(). Pre-close only that focus-grab surface during a cross-monitor
        // bar click so the following launcher click can reopen it on the target.
        if (activeSurface === "launcher"
            && activeMonitorName.length > 0
            && activeMonitorName !== monitor) {
            closeRequested("");
        }

        recentBarMonitorName = monitor;
        recentBarMonitorTimestamp = Date.now();
    }

    function recentBarMonitor() {
        if (recentBarMonitorName.length === 0)
            return "";
        if (Date.now() - recentBarMonitorTimestamp > recentBarMonitorLifetimeMs) {
            recentBarMonitorName = "";
            recentBarMonitorTimestamp = 0;
            return "";
        }
        return recentBarMonitorName;
    }

    function consumeTargetMonitor() {
        const barMonitor = recentBarMonitor();
        recentBarMonitorName = "";
        recentBarMonitorTimestamp = 0;
        return barMonitor.length > 0 ? barMonitor : focusedMonitorName();
    }

    function claim(surface, monitorName) {
        const explicitMonitor = String(monitorName || "");
        let targetMonitor = "";

        if (explicitMonitor.length > 0) {
            targetMonitor = explicitMonitor;
            // Do not let a bar click cached for this request leak into the next
            // flyout open. Callers that already know their ShellScreen should
            // always be authoritative.
            recentBarMonitorName = "";
            recentBarMonitorTimestamp = 0;
        } else {
            targetMonitor = consumeTargetMonitor();
        }

        // A single FloatingWindow instance cannot be retargeted safely while
        // mapped. Legacy callers still rely on this guard. Surfaces converted
        // to a backingWindowVisible handoff call claim only after their old
        // native window has actually disappeared, making this branch harmless.
        if (activeSurface === surface
            && activeMonitorName.length > 0
            && targetMonitor.length > 0
            && activeMonitorName !== targetMonitor) {
            closeRequested("");
        }

        closeRequested(surface);
        activeSurface = surface;
        activeMonitorName = targetMonitor;
    }

    function release(surface) {
        if (activeSurface === surface) {
            activeSurface = "";
            activeMonitorName = "";
        }
    }
}
