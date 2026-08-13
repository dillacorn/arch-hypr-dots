pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

Singleton {
    id: root

    readonly property bool enabled: QuickSettings.disableNumlockAtSessionStart

    function enforce() {
        if (primeProcess.running || offProcess.running)
            return;
        primeProcess.exec([
            "hyprctl", "eval",
            "hl.config({ input = { numlock_by_default = true } })"
        ]);
    }

    onEnabledChanged: {
        if (enabled)
            enforce();
    }

    Component.onCompleted: {
        if (enabled)
            Qt.callLater(() => root.enforce());
    }

    Process {
        id: primeProcess
        onExited: offProcess.exec([
            "hyprctl", "eval",
            "hl.config({ input = { numlock_by_default = false } })"
        ])
    }

    Process {
        id: offProcess
    }
}
