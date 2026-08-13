pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property bool enabled: QuickSettings.disableNumlockAtSessionStart

    function enforce() {
        Hyprland.dispatch("exec, hyprctl eval 'hl.config({ input = { numlock_by_default = true } })'");
        Hyprland.dispatch("exec, hyprctl eval 'hl.config({ input = { numlock_by_default = false } })'");
    }

    onEnabledChanged: {
        if (enabled)
            enforce();
    }

    Component.onCompleted: {
        if (enabled)
            Qt.callLater(() => root.enforce());
    }
}
