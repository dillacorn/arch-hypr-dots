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
    readonly property string cachePath:
        cacheHome + "/awtarchy/lockscreen-contrast.json"
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]

    property var accents: ({
        logo: "#ffffff",
        time: "#ffffff",
        date: "#ffffff",
        username: "#ffffff",
        weather: "#ffffff",
        password: "#ffffff"
    })

    function colorFor(name) {
        const value = String(accents && accents[name] !== undefined ? accents[name] : "#ffffff");
        return /^#[0-9a-fA-F]{6}$/.test(value) ? value : "#ffffff";
    }

    function refreshAccent() {
        const text = String(contrastFile.text() || "").trim();
        if (text.length === 0)
            return;
        try {
            const parsed = JSON.parse(text);
            if (!parsed || parsed.provider !== "awtarchy-local-contrast"
                    || !parsed.colors || typeof parsed.colors !== "object")
                return;
            const next = ({});
            for (const name of elementNames) {
                const value = String(parsed.colors[name] || "");
                next[name] = /^#[0-9a-fA-F]{6}$/.test(value)
                    ? value.toLowerCase() : "#ffffff";
            }
            accents = next;
        } catch (error) {
            // Keep existing safe contrast values if the local cache is malformed.
        }
    }

    function requestRefresh() {
        if (refreshProcess.running)
            return;
        refreshProcess.exec([root.helper]);
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
