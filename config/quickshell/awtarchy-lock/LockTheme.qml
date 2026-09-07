import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string themePath: configHome + "/quickshell/awtarchy/theme.json"

    FileView {
        id: themeFile
        path: root.themePath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
    }

    function data() {
        const text = themeFile.text();
        if (!text || text.length === 0)
            return ({});

        try {
            return JSON.parse(text);
        } catch (error) {
            return ({});
        }
    }

    function value(name, fallback) {
        const theme = data();
        return theme[name] || fallback;
    }

    readonly property color background: value("dark", "#000000")
    readonly property color foreground: value("foreground", "#d0d0d0")
    readonly property color muted: value("muted", "#666666")
    readonly property color accent: value("focus", "#4a4a4a")
    readonly property color error: value("critical", "#ff5555")
    readonly property string fontFamily: "NotoSansM Nerd Font Mono"
}
