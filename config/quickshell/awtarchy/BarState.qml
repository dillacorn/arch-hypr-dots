pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string statePath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/awtarchy/quickshell-state.json"
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string idleStatePath: runtimeDir + "/awtarchy-quickshell-idle-hidden"
    readonly property int defaultLauncherWidth: 420
    readonly property int defaultLauncherHeight: 582
    readonly property int defaultAppTextSize: 14
    readonly property int defaultAppIconSize: 18
    property int revision: 0
    property int idleRevision: 0

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

    function refreshIdleState() {
        idleStateFile.reload();
        idleRevision++;
    }

    function setIdleHidden(hidden) {
        idleStateFile.setText(hidden ? "1\n" : "0\n");
        idleRevision++;
    }

    function idleHidden() {
        const dependency = idleRevision;
        return idleStateFile.text().trim() === "1";
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

    FileView {
        id: idleStateFile
        path: root.idleStatePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.idleRevision++
        onFileChanged: root.refreshIdleState()
    }

    IpcHandler {
        target: "barstate"
        function refresh(): void { root.refresh(); }
        function refreshIdle(): void { root.refreshIdleState(); }
        function setIdleHidden(hidden: bool): void { root.setIdleHidden(hidden); }
    }

    function data() {
        const dependency = revision;
        const text = stateFile.text();
        if (!text || text.length === 0)
            return ({ enabled: true, monitors: {}, launcher_sizes: {} });

        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
                return ({ enabled: true, monitors: {}, launcher_sizes: {} });
            if (!parsed.monitors || typeof parsed.monitors !== "object"
                || Array.isArray(parsed.monitors))
                parsed.monitors = {};
            if (!parsed.launcher_sizes || typeof parsed.launcher_sizes !== "object"
                || Array.isArray(parsed.launcher_sizes))
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
        const idleDependency = idleRevision;
        if (idleHidden())
            return false;
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

    function launcherViewFor(name) {
        const d = data();
        const rawView = (d.launcher_sizes || ({}))[name];
        const view = rawView && typeof rawView === "object" && !Array.isArray(rawView)
            ? rawView : ({});
        // Legacy locked and unlocked entries both remain valid saved views.
        // This migrates existing per-display launcher geometry without loss.
        const rawWidth = Number(view.width);
        const rawHeight = Number(view.height);
        const validWidth = Number.isFinite(rawWidth) && rawWidth >= 1 && rawWidth <= 16384;
        const validHeight = Number.isFinite(rawHeight) && rawHeight >= 1 && rawHeight <= 16384;

        let rawTextScale = view.text_scale;
        if (rawTextScale === undefined && view.text_size !== undefined)
            rawTextScale = Number(view.text_size) * 100 / defaultAppTextSize;

        let rawIconScale = view.icon_scale;
        if (rawIconScale === undefined && view.icon_size !== undefined)
            rawIconScale = Number(view.icon_size) * 100 / defaultAppIconSize;

        const textScale = Number(rawTextScale === undefined ? 100 : rawTextScale);
        const iconScale = Number(rawIconScale === undefined ? 100 : rawIconScale);

        return ({
            locked: view.locked === true && validWidth && validHeight,
            width: validWidth ? Math.round(rawWidth) : defaultLauncherWidth,
            height: validHeight ? Math.round(rawHeight) : defaultLauncherHeight,
            centered: view.centered === true,
            textScale: Number.isFinite(textScale)
                ? Math.max(50, Math.min(200, Math.round(textScale))) : 100,
            iconScale: Number.isFinite(iconScale)
                ? Math.max(50, Math.min(200, Math.round(iconScale))) : 100
        });
    }

    function applicationSizeLockedFor(name) {
        return launcherViewFor(name).locked;
    }

    function launcherWidthFor(name, globalOnly) {
        return launcherViewFor(name).width;
    }

    function launcherHeightFor(name, globalOnly) {
        return launcherViewFor(name).height;
    }

    function appTextScaleFor(name) {
        return launcherViewFor(name).textScale;
    }

    function appIconScaleFor(name) {
        return launcherViewFor(name).iconScale;
    }

    function launcherCenteredFor(name) {
        return launcherViewFor(name).centered;
    }

    function appTextSizeFor(name, globalOnly) {
        return Math.max(7, Math.round(defaultAppTextSize * appTextScaleFor(name) / 100));
    }

    function appIconSizeFor(name, globalOnly) {
        return Math.max(9, Math.round(defaultAppIconSize * appIconScaleFor(name) / 100));
    }
}
