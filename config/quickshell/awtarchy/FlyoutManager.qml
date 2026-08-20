pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

QtObject {
    id: root

    property string activeSurface: ""
    property string activeMonitorName: ""
    property string recentBarMonitorName: ""
    property real recentBarMonitorTimestamp: 0
    property var barWindows: []
    property var lastToggleTimestamps: ({})
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string animationStatePath: runtimeDir + "/hypr-animations-enabled"
    readonly property bool animationsEnabled: animationStateFile.text().trim() !== "0"
    readonly property int recentBarMonitorLifetimeMs: 1500
    readonly property int toggleDebounceMs: 250
    signal closeRequested(string exceptSurface)

    property FileView animationStateFile: FileView {
        path: root.animationStatePath
        blockLoading: false
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    // Keep the previous flyout mapped until the newly requested different
    // surface is not only mapped, but actually active in Hyprland. Closing the
    // old focused flyout any earlier can create an empty focus gap where
    // Hyprland restores a normal window and warps the cursor to that window.
    property Connections hyprEventConnection: Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (!event || event.name !== "activewindow")
                return;

            const fields = event.parse(2);
            if (!fields || fields.length < 2)
                return;

            const expectedTitle = root.titleForSurface(root.activeSurface);
            const activeTitle = String(fields[1] || "");
            if (expectedTitle.length > 0 && activeTitle === expectedTitle)
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
        if (surface === "battery")
            return "Awtarchy Battery";
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

    function acceptToggle(surface) {
        const key = String(surface || "");
        if (key.length === 0)
            return true;

        const now = Date.now();
        const previous = Number(lastToggleTimestamps[key] || 0);
        if (previous > 0 && now >= previous
            && now - previous < toggleDebounceMs)
            return false;

        lastToggleTimestamps[key] = now;
        return true;
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
        // Different surfaces overlap only until the requested replacement is
        // active; the activewindow hook above then closes every competitor.
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
