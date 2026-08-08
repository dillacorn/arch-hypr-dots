pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string statePath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/awtarchy/quickshell-state.json"
    readonly property int defaultLauncherWidth: 420
    readonly property int defaultLauncherHeight: 582
    readonly property int defaultAppTextSize: 14
    readonly property int defaultAppIconSize: 18
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
            return ({ enabled: true, monitors: {}, application_view: {} });

        try {
            const parsed = JSON.parse(text);
            if (!parsed.monitors)
                parsed.monitors = {};
            if (!parsed.application_view)
                parsed.application_view = {};
            if (parsed.enabled === undefined)
                parsed.enabled = true;
            return parsed;
        } catch (error) {
            console.warn("Awtarchy Quickshell: invalid shell state:", error);
            return ({ enabled: true, monitors: {}, application_view: {} });
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

    function globalApplicationView() {
        const d = data();
        const view = d.application_view || ({});
        const customized = view.customized === true;
        return ({
            width: Math.max(420, Math.min(3840, Math.round(Number(customized && view.width !== undefined ? view.width : defaultLauncherWidth)))),
            height: Math.max(360, Math.min(2160, Math.round(Number(customized && view.height !== undefined ? view.height : defaultLauncherHeight)))),
            textSize: Math.max(10, Math.min(28, Math.round(Number(customized && view.text_size !== undefined ? view.text_size : defaultAppTextSize)))),
            iconSize: Math.max(12, Math.min(48, Math.round(Number(customized && view.icon_size !== undefined ? view.icon_size : defaultAppIconSize)))),
            customized: customized
        });
    }

    // Application View spawn dimensions are intentionally global. ALT+P,
    // SUPER+D, and the bar Apps button must all open the same launcher size.
    function applicationViewFor(name, globalOnly) {
        return globalApplicationView();
    }

    function launcherWidthFor(name, globalOnly) {
        return applicationViewFor(name, globalOnly).width;
    }

    function launcherHeightFor(name, globalOnly) {
        return applicationViewFor(name, globalOnly).height;
    }

    function appTextSizeFor(name, globalOnly) {
        return applicationViewFor(name, globalOnly).textSize;
    }

    function appIconSizeFor(name, globalOnly) {
        return applicationViewFor(name, globalOnly).iconSize;
    }
}
