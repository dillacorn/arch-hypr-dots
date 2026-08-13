pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool stateLoaded: false
    readonly property bool enabled: numlockSettings.disableNumlockAtSessionStart

    function enforce() {
        if (!enabled || primeProcess.running || offProcess.running)
            return;

        primeProcess.exec([
            "hyprctl", "eval",
            "hl.config({ input = { numlock_by_default = true } })"
        ]);
    }

    FileView {
        id: settingsFile
        path: Quickshell.statePath("quick-settings-tweaks.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.stateLoaded = true;
            if (numlockSettings.disableNumlockAtSessionStart)
                Qt.callLater(() => root.enforce());
        }

        JsonAdapter {
            id: numlockSettings
            property bool disableNumlockAtSessionStart: false

            onDisableNumlockAtSessionStartChanged: {
                if (root.stateLoaded && disableNumlockAtSessionStart)
                    Qt.callLater(() => root.enforce());
            }
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
