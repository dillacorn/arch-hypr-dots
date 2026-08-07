pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // During conversion, use the existing Awtarchy Waybar color variables as the
    // single source of truth. Existing theme scripts already update these values,
    // so every current theme immediately drives Quickshell without duplicating
    // color tables. Once the conversion is proven, this compatibility source can
    // be replaced with a native Quickshell theme file without changing components.
    readonly property string legacyWaybarCss: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/waybar/style.css"

    FileView {
        id: styleFile
        path: root.legacyWaybarCss
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
    }

    function colorValue(name, fallback) {
        const text = styleFile.text();
        if (!text || text.length === 0)
            return fallback;

        const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const match = text.match(new RegExp("@define-color\\s+" + escaped + "\\s+([^;]+);"));
        return match && match.length > 1 ? match[1].trim() : fallback;
    }

    readonly property color background: colorValue("bg-default", "#353535")
    readonly property color hover: colorValue("bg-hover", "#404040")
    readonly property color focus: colorValue("bg-focus", "#4a4a4a")
    readonly property color active: colorValue("bg-active", "#2b2b2b")
    readonly property color urgent: colorValue("bg-urgent", "#ff5555")
    readonly property color charging: colorValue("bg-charging", "#6a9955")
    readonly property color critical: colorValue("bg-critical", "#ff5555")
    readonly property color foreground: colorValue("color-default", "#d0d0d0")
    readonly property color dark: colorValue("color-dark", "#1a1a1a")
    readonly property color muted: colorValue("color-hover", "#4a4a4a")

    readonly property color subtleHover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
    readonly property color subtleActive: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
    readonly property color popupBackground: Qt.rgba(background.r, background.g, background.b, 0.94)
    readonly property color popupButton: Qt.rgba(active.r, active.g, active.b, 0.92)
    readonly property color popupButtonHover: Qt.rgba(focus.r, focus.g, focus.b, 0.96)

    readonly property string fontFamily: "NotoSansM Nerd Font Mono"
    readonly property int fontPixelSize: 14
}
