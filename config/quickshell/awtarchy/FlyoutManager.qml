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

        // Do not hide the current surface during a bar handoff. Closing a
        // focused flyout before its replacement maps makes Hyprland restore a
        // normal window in between, which can warp the cursor to that window.
        // The newly requested surface becomes authoritative immediately, but
        // competing flyouts remain mapped until opened() confirms the target
        // flyout exists. Then they are closed with no empty focus gap.
        activeSurface = surface;
        activeMonitorName = targetMonitor;
    }

    function opened(surface) {
        if (activeSurface !== surface)
            return;
        closeRequested(surface);
    }

    function release(surface) {
        if (activeSurface === surface) {
            activeSurface = "";
            activeMonitorName = "";
        }
    }
}
