pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string helper: configHome + "/hypr/scripts/quickshell_numlock_tweak.sh"
    readonly property bool enabled: QuickSettings.disableNumlockAtSessionStart

    function enforce() {
        Quickshell.execDetached([helper]);
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
