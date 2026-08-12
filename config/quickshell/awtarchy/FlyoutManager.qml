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

    // Keep the previous flyout mapped until the newly requested different
    // surface actually appears in Hyprland. This avoids an empty focus gap
    // where Hyprland would restore a normal window and warp the cursor.
    property Connections hyprEventConnection: Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (!event || event.name !== "openwindow")
                return;

            const fields = event.parse(4);
            if (!fields || fields.length < 4)
                return;

            const expectedTitle = root.titleForSurface(root.activeSurface);
            const openedTitle = String(fields[3] || "");
            if (expectedTitle.length > 0 && openedTitle === expectedTitle)
                root.closeRequested(root.activeSurface);
        }
    }

    function titleForSurface(surface) {
        if (surface === "launcher")
            return "Awtarchy Application Search";
        if (surface === "clipboard")
            return "Awtarchy Clipboard History";
        if (surface === "notifications")
            return "Awtarchy Notification Center";
        if (surface === "quick-settings")
            return "Awtarchy Quick Settings";
        if (surface === "network")
            return "Awtarchy Network";
        if (surface === "bluetooth")
            return "Awtarchy Bluetooth";
        return "";
    }

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

        // Same-surface monitor handoffs stay mapped and retarget in place.
        // Different surfaces stay overlapped only until the requested new
        // Hyprland window emits openwindow, at which point the connection above
        // closes every competing surface except the newly active one.
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
