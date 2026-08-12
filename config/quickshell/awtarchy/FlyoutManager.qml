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

        // A single FloatingWindow instance cannot be retargeted safely while
        // mapped. Changing its QsWindow.screen across monitors causes Qt to
        // tear down/recreate the native toplevel; Hyprland can focus that
        // transient replacement on the old monitor and warp the cursor there.
        // Close the active flyout before the bar button emits its click so the
        // target singleton changes screen only while hidden.
        if (activeSurface.length > 0
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

    function claim(surface) {
        const targetMonitor = consumeTargetMonitor();

        // Cover non-bar entry points as well. Most flyouts call claim() before
        // assigning their QsWindow.screen, so a keyboard/IPC open targeting a
        // different focused monitor gets the same safe hidden handoff.
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
