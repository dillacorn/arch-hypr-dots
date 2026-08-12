pragma Singleton

import QtQuick
import Quickshell.Hyprland

QtObject {
    id: root

    property string activeSurface: ""
    property string activeMonitorName: ""
    property string recentBarMonitorName: ""
    property real recentBarMonitorTimestamp: 0
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

    function claim(surface) {
        const targetMonitor = consumeTargetMonitor();

        // A single FloatingWindow instance cannot be retargeted safely while
        // mapped. Changing its QsWindow.screen across monitors causes Qt to
        // tear down/recreate the native toplevel; Hyprland can focus that
        // transient replacement on the old monitor and warp the cursor there.
        // Every floating menu calls claim() before assigning its target screen,
        // so close a same-surface cross-monitor instance here while it is still
        // on the old screen. The caller then retargets the hidden window and
        // maps it through the prepared-position path.
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
