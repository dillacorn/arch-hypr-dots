pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell as Qs
import Quickshell.Io

Qs.Singleton {
    id: root

    property bool stateLoaded: false
    property int startupAttemptsRemaining: 0
    readonly property bool enabled: numlockSettings.disableNumlockAtSessionStart

    function enforce() {
        if (!enabled || primeProcess.running || offProcess.running)
            return;

        primeProcess.exec([
            "hyprctl", "eval",
            "hl.config({ input = { numlock_by_default = true } })"
        ]);
    }

    function beginEnforcementBurst() {
        if (!enabled) {
            startupAttemptsRemaining = 0;
            return;
        }
        startupAttemptsRemaining = 4;
        enforce();
    }

    FileView {
        id: settingsFile
        path: Qs.Quickshell.statePath("quick-settings-tweaks.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.stateLoaded = true;
            if (numlockSettings.disableNumlockAtSessionStart)
                Qt.callLater(() => root.beginEnforcementBurst());
        }

        JsonAdapter {
            id: numlockSettings
            property bool disableNumlockAtSessionStart: false

            onDisableNumlockAtSessionStartChanged: {
                if (!root.stateLoaded)
                    return;
                if (disableNumlockAtSessionStart)
                    Qt.callLater(() => root.beginEnforcementBurst());
                else
                    root.startupAttemptsRemaining = 0;
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.enabled && root.startupAttemptsRemaining > 0
        onTriggered: {
            root.enforce();
            root.startupAttemptsRemaining--;
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: !root.stateLoaded
        onTriggered: settingsFile.reload()
    }

    Process {
        id: primeProcess
        onExited: {
            if (!root.enabled)
                return;
            offProcess.exec([
                "hyprctl", "eval",
                "hl.config({ input = { numlock_by_default = false } })"
            ]);
        }
    }

    Process {
        id: offProcess
    }
}
