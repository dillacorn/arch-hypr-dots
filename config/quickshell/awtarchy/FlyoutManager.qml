pragma Singleton

import QtQuick

QtObject {
    id: root

    property string activeSurface: ""
    property string recentBarMonitorName: ""
    property real recentBarMonitorTimestamp: 0
    readonly property int recentBarMonitorLifetimeMs: 1500
    signal closeRequested(string exceptSurface)

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

    function claim(surface) {
        closeRequested(surface);
        activeSurface = surface;
    }

    function release(surface) {
        if (activeSurface === surface)
            activeSurface = "";
    }
}
