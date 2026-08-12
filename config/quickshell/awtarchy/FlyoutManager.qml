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
            recentBarMonitorName = "";
            recentBarMonitorTimestamp = 0;
        } else {
            targetMonitor = consumeTargetMonitor();
        }

        // Do not close a mapped flyout merely because the same surface is being
        // requested on another monitor. Closing it makes Hyprland restore focus
        // to a normal window before the replacement mapping completes, which can
        // trigger a compositor cursor warp. The surface retargets in-place and
        // its existing pre/post positioning helpers place it on target instead.
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
