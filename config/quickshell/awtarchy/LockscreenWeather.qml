pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string weatherHelper:
        configHome + "/hypr/scripts/quickshell_lockscreen_weather.sh"
    readonly property int minimumRefreshIntervalMs: 1200000
    readonly property string configuredLocation:
        String(BarState.lockscreenWeatherLocation() || "").trim()
    readonly property bool refreshEnabled:
        BarState.lockscreenShowWeather() && configuredLocation.length > 0

    property string lastRequestedLocation: ""
    property double lastRequestMs: 0

    function requestRefresh() {
        const location = String(root.configuredLocation || "").trim();
        if (!root.refreshEnabled || location.length === 0 || refreshProcess.running)
            return;

        const now = Date.now();
        const locationChanged = location !== root.lastRequestedLocation;
        if (!locationChanged && root.lastRequestMs > 0
                && now - root.lastRequestMs < root.minimumRefreshIntervalMs)
            return;

        root.lastRequestedLocation = location;
        root.lastRequestMs = now;
        refreshProcess.exec([root.weatherHelper, "refresh", location]);
    }

    Process {
        id: refreshProcess
    }

    Timer {
        interval: 1200000
        repeat: true
        running: root.refreshEnabled
        onTriggered: root.requestRefresh()
    }

    Timer {
        id: stateRefresh
        interval: 180
        repeat: false
        onTriggered: root.requestRefresh()
    }

    Connections {
        target: BarState
        function onRevisionChanged() {
            if (root.refreshEnabled)
                stateRefresh.restart();
        }
    }

    Component.onCompleted: {
        if (root.refreshEnabled)
            stateRefresh.restart();
    }
}
