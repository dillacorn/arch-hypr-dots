pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string themePath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickshell/awtarchy/theme.json"

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
            console.warn("Awtarchy Quickshell: invalid theme.json:", error);
            return ({});
        }
    }

    function value(name, fallback) {
        const theme = data();
        return theme[name] || fallback;
    }

    readonly property color background: value("background", "#353535")
    readonly property color hover: value("hover", "#404040")
    readonly property color focus: value("focus", "#4a4a4a")
    readonly property color active: value("active", "#2b2b2b")
    readonly property color urgent: value("urgent", "#ff5555")
    readonly property color charging: value("charging", "#6a9955")
    readonly property color critical: value("critical", "#ff5555")
    readonly property color foreground: value("foreground", "#d0d0d0")
    readonly property color dark: value("dark", "#1a1a1a")
    readonly property color muted: value("muted", "#4a4a4a")

    // Match the current Waybar CSS interaction states.
    readonly property color subtleHover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
    readonly property color subtleActive: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
    readonly property color strongHover: Qt.rgba(115 / 255, 121 / 255, 148 / 255, 0.25)

    // Fuzzel and Mako use the configured background without transparency.
    readonly property color popupBackground: background

    // Match the existing wlogout button CSS exactly.
    readonly property color popupButton: Qt.rgba(active.r, active.g, active.b, 0.85)
    readonly property color popupButtonHover: Qt.rgba(focus.r, focus.g, focus.b, 0.92)

    readonly property string fontFamily: "NotoSansM Nerd Font Mono"
    readonly property int fontPixelSize: 14
}
