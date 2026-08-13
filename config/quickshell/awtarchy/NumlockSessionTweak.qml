pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string manager: configHome + "/hypr/scripts/quickshell.sh"
    readonly property bool enabled: QuickSettings.disableNumlockAtSessionStart

    function enforce() {
        Quickshell.execDetached([manager, "numlock-off"]);
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
