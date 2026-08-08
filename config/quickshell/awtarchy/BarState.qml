pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string statePath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/awtarchy/quickshell-state.json"
    property int revision: 0

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.revision++
        onFileChanged: {
            reload();
            root.revision++;
        }
    }

    function data() {
        const dependency = revision;
        const text = stateFile.text();
        if (!text || text.length === 0)
            return ({ enabled: true, monitors: {} });

        try {
            const parsed = JSON.parse(text);
            if (!parsed.monitors)
                parsed.monitors = {};
            if (parsed.enabled === undefined)
                parsed.enabled = true;
            return parsed;
        } catch (error) {
            console.warn("Awtarchy Quickshell: invalid bar state:", error);
            return ({ enabled: true, monitors: {} });
        }
    }

    function monitorState(name) {
        const d = data();
        return d.monitors[name] || ({});
    }

    function enabledFor(name) {
        const d = data();
        if (!d.enabled)
            return false;
        const mon = d.monitors[name];
        return !mon || mon.enabled === undefined ? true : !!mon.enabled;
    }

    function positionFor(name) {
        const mon = monitorState(name);
        const pos = mon.position || "top";
        return ["top", "bottom", "left", "right"].indexOf(pos) >= 0 ? pos : "top";
    }

    function barSizeFor(name, vertical) {
        const mon = monitorState(name);
        const custom = Number(mon.bar_size || 0);
        if (Number.isFinite(custom) && custom >= 20 && custom <= 80)
            return Math.round(custom);
        return vertical ? 36 : 28;
    }

    function iconScaleFor(name) {
        const mon = monitorState(name);
        const percent = Number(mon.icon_scale === undefined ? 100 : mon.icon_scale);
        if (!Number.isFinite(percent))
            return 1.0;
        return Math.max(50, Math.min(200, percent)) / 100.0;
    }
}
