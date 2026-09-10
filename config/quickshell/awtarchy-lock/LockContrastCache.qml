import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string cachePath:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/awtarchy/lockscreen-contrast.json"
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]
    property var colors: ({
        logo: "#ffffff",
        time: "#ffffff",
        date: "#ffffff",
        username: "#ffffff",
        weather: "#ffffff",
        password: "#ffffff"
    })

    function colorFor(name) {
        const value = String(colors && colors[name] !== undefined ? colors[name] : "#ffffff");
        return /^#[0-9a-fA-F]{6}$/.test(value) ? value : "#ffffff";
    }

    function refresh() {
        const text = String(cacheFile.text() || "").trim();
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
            colors = next;
        } catch (error) {
            // Keep safe white fallbacks for malformed or partial local cache data.
        }
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
