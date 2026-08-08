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

    // Immediate in-process overrides keep bar geometry and icon sizing
    // responsive while persistent JSON writes complete in the background.
    property var livePositions: ({})
    property var liveEnabled: ({})
    property var liveBarSizes: ({})
    property var liveIconScales: ({})

    function refresh() {
        stateFile.reload();
        revision++;
    }

    function setLivePosition(name, value) {
        const next = Object.assign({}, livePositions);
        next[name] = value;
        livePositions = next;
        revision++;
    }

    function setLiveEnabled(name, value) {
        const next = Object.assign({}, liveEnabled);
        next[name] = !!value;
        liveEnabled = next;
        revision++;
    }

    function setLiveBarSize(name, value) {
        const next = Object.assign({}, liveBarSizes);
        next[name] = Number(value);
        liveBarSizes = next;
        revision++;
    }

    function setLiveIconScale(name, value) {
        const next = Object.assign({}, liveIconScales);
        next[name] = Number(value);
        liveIconScales = next;
        revision++;
    }

    function clearLiveOverrides(name) {
        const positions = Object.assign({}, livePositions);
        const enabled = Object.assign({}, liveEnabled);
        const sizes = Object.assign({}, liveBarSizes);
        const scales = Object.assign({}, liveIconScales);
        delete positions[name];
        delete enabled[name];
        delete sizes[name];
        delete scales[name];
        livePositions = positions;
        liveEnabled = enabled;
        liveBarSizes = sizes;
        liveIconScales = scales;
        revision++;
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.revision++
        onFileChanged: root.refresh()
    }

    IpcHandler {
        target: "barstate"
        function refresh(): void { root.refresh(); }
    }

    function data() {
        const dependency = revision;
        const text = stateFile.text();
        if (!text || text.length === 0)
            return ({ enabled: true, monitors: {}, launcher_sizes: {} });

        try {
            const parsed = JSON.parse(text);
            if (!parsed.monitors)
                parsed.monitors = {};
            if (!parsed.launcher_sizes)
                parsed.launcher_sizes = {};
            if (parsed.enabled === undefined)
                parsed.enabled = true;
            return parsed;
        } catch (error) {
            console.warn("Awtarchy Quickshell: invalid shell state:", error);
            return ({ enabled: true, monitors: {}, launcher_sizes: {} });
        }
    }

    function monitorState(name) {
        const d = data();
        return d.monitors[name] || ({});
    }

    function enabledFor(name) {
        const dependency = revision;
        if (liveEnabled[name] !== undefined)
            return !!liveEnabled[name];
        const d = data();
        if (!d.enabled)
            return false;
        const mon = d.monitors[name];
        return !mon || mon.enabled === undefined ? true : !!mon.enabled;
    }

    function positionFor(name) {
        const dependency = revision;
        if (livePositions[name] !== undefined)
            return livePositions[name];
        const mon = monitorState(name);
        const pos = mon.position || "top";
        return ["top", "bottom", "left", "right"].indexOf(pos) >= 0 ? pos : "top";
    }

    function barSizeFor(name, vertical) {
        const dependency = revision;
        const override = liveBarSizes[name];
        const custom = override !== undefined
            ? Number(override)
            : Number(monitorState(name).bar_size || 0);
        if (Number.isFinite(custom) && custom >= 20 && custom <= 80)
            return Math.round(custom);
        return vertical ? 36 : 28;
    }

    function iconScaleFor(name) {
        const dependency = revision;
        const override = liveIconScales[name];
        const mon = monitorState(name);
        const percent = Number(override !== undefined
            ? override
            : (mon.icon_scale === undefined ? 100 : mon.icon_scale));
        if (!Number.isFinite(percent))
            return 1.0;
        return Math.max(50, Math.min(200, percent)) / 100.0;
    }

    function launcherLockFor(name) {
        const d = data();
        const view = (d.launcher_sizes || ({}))[name] || ({});
        const width = Number(view.width);
        const height = Number(view.height);
        const locked = view.locked === true
            && Number.isFinite(width) && width >= 420 && width <= 3840
            && Number.isFinite(height) && height >= 360 && height <= 2160;

        return ({
            locked: locked,
            width: locked ? Math.round(width) : defaultLauncherWidth,
            height: locked ? Math.round(height) : defaultLauncherHeight
        });
    }

    function applicationSizeLockedFor(name) {
        return launcherLockFor(name).locked;
    }

    function launcherWidthFor(name, globalOnly) {
        return launcherLockFor(name).width;
    }

    function launcherHeightFor(name, globalOnly) {
        return launcherLockFor(name).height;
    }

    function appTextSizeFor(name, globalOnly) {
        return defaultAppTextSize;
    }

    function appIconSizeFor(name, globalOnly) {
        return defaultAppIconSize;
    }
}
