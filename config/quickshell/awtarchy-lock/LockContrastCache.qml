import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string cachePath:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/awtarchy/lockscreen-contrast.txt"
    property color accent: "#ffffff"

    function refresh() {
        const value = String(cacheFile.text() || "").trim();
        accent = /^#[0-9a-fA-F]{6}$/.test(value) ? value : "#ffffff";
    }

    FileView {
        id: cacheFile
        path: root.cachePath
        watchChanges: false
        blockLoading: true
        printErrors: false
        onLoaded: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
