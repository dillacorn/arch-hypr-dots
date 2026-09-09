import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    required property bool enabled
    property string summary: ""

    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")
    readonly property string cachePath: root.cacheHome
        + "/awtarchy/lockscreen-weather.json"

    function refreshCache() {
        if (!root.enabled) {
            root.summary = "";
            return;
        }

        const text = cacheFile.text();
        if (!text || text.length === 0) {
            root.summary = "";
            return;
        }

        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
                root.summary = "";
                return;
            }

            const value = typeof parsed.summary === "string"
                ? parsed.summary.trim() : "";
            const expiresAt = Number(parsed.expires_at);
            const provider = typeof parsed.provider === "string"
                ? parsed.provider : "";
            const now = Math.floor(Date.now() / 1000);

            if (value.length === 0 || Array.from(value).length > 96
                    || !Number.isFinite(expiresAt) || expiresAt <= now
                    || provider !== "open-meteo") {
                root.summary = "";
                return;
            }

            root.summary = value;
        } catch (error) {
            root.summary = "";
        }
    }

    onEnabledChanged: {
        if (root.enabled)
            cacheFile.reload();
        else
            root.summary = "";
    }

    FileView {
        id: cacheFile
        path: root.cachePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.refreshCache()
        onFileChanged: root.refreshCache()
    }
}
