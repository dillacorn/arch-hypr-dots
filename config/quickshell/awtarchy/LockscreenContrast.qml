pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")
    readonly property string helper:
        configHome + "/hypr/scripts/quickshell_lockscreen_contrast.sh"
    readonly property string backendStatePath:
        configHome + "/awtwall/backend_state.tsv"
    readonly property string cachePath:
        cacheHome + "/awtarchy/lockscreen-contrast.txt"

    property color accent: "#ffffff"

    function refreshAccent() {
        const value = String(contrastFile.text() || "").trim();
        accent = /^#[0-9a-fA-F]{6}$/.test(value) ? value : "#ffffff";
    }

    function requestRefresh() {
        if (refreshProcess.running)
            return;
        refreshProcess.exec([root.helper, BarState.lockscreenBackground()]);
    }

    Process {
        id: refreshProcess
        onExited: root.refreshAccent()
    }

    FileView {
        id: contrastFile
        path: root.cachePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.refreshAccent()
        onFileChanged: root.refreshAccent()
    }

    FileView {
        id: awtwallState
        path: root.backendStatePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: refreshDelay.restart()
        onFileChanged: refreshDelay.restart()
    }

    Timer {
        id: refreshDelay
        interval: 160
        repeat: false
        onTriggered: root.requestRefresh()
    }

    Connections {
        target: BarState
        function onRevisionChanged() {
            refreshDelay.restart();
        }
    }

    Component.onCompleted: refreshDelay.restart()
}
