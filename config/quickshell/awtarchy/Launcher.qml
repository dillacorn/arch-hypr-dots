pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import "FlyoutEdgeLayout.js" as FlyoutEdgeLayout

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_launcher_position.sh"
    readonly property string prepareScript: configHome + "/hypr/scripts/quickshell_flyout_prepare.sh"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string usageScript: configHome + "/hypr/scripts/quickshell_launcher_usage.sh"
    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"
    readonly property string animationStatePath: runtimeDir + "/hypr-animations-enabled"
    readonly property string launcherUsagePath: cacheHome + "/awtarchy/launcher-usage.json"
    readonly property int minimumLauncherWidth: 420
    readonly property int minimumLauncherHeight: 360
    readonly property int screenEdgeMargin: 16
    readonly property int minimumTextScale: 50
    readonly property int maximumTextScale: 200
    readonly property int minimumIconScale: 50
    readonly property int maximumIconScale: 200
    readonly property int applicationColumnMinimumWidth: 300
    property var launcherScreen: null
    readonly property var activeScreen: launcherScreen || launcherWindow.screen
    readonly property string activeMonitorName: targetMonitorName.length > 0
        ? targetMonitorName
        : (activeScreen && activeScreen.name ? String(activeScreen.name) : "")
    readonly property int effectiveTextScale: textScaleOverride >= 0
        ? textScaleOverride : BarState.appTextScaleFor(activeMonitorName)
    readonly property int effectiveIconScale: iconScaleOverride >= 0
        ? iconScaleOverride : BarState.appIconScaleFor(activeMonitorName)
    readonly property int configuredAppTextSize: Math.max(7,
        Math.round(BarState.defaultAppTextSize * effectiveTextScale / 100))
    readonly property int configuredAppIconSize: Math.max(9,
        Math.round(BarState.defaultAppIconSize * effectiveIconScale / 100))
    readonly property int liveWidth: Math.round(launcherWindow.width)
    readonly property int liveHeight: Math.round(launcherWindow.height)
    readonly property bool centerOnScreen: launcherCenteredFor(activeMonitorName)
    readonly property bool bottomEdgeLayout: FlyoutEdgeLayout.isBottom(requestedPlacement)
    readonly property bool captureAllowed: captureAllowedOverride >= 0
        ? captureAllowedOverride === 1 : BarState.captureAllowedFor("launcher")
    readonly property bool settingsDirty: savedView.width !== liveWidth
        || savedView.height !== liveHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.centered !== centerOnScreen
        || savedView.captureAllowed !== captureAllowed
    property string targetMonitorName: ""
    property string requestedPlacement: "center"
    property string savedPlacement: "center"
    property bool launcherPositioned: false
    property bool launcherFocusGrabExpanded: false
    property bool openPreparing: false
    property bool settingsOpen: false
    property bool copySettingsOpen: false
    property int textScaleOverride: -1
    property int iconScaleOverride: -1
    property int centeredPlacementOverride: -1
    property int captureAllowedOverride: -1
    property bool settingWindowSize: false
    property int resizeStartWidth: 0
    property int resizeStartHeight: 0
    property var savedView: ({
        width: BarState.defaultLauncherWidth,
        height: BarState.defaultLauncherHeight,
        textScale: 100,
        iconScale: 100,
        centered: false,
        captureAllowed: false
    })
    property var copyTargets: ({})
    property int copySelectionRevision: 0
    property var stateCommandQueue: []
    property string settingsMessage: ""
    property bool privacyRemapPending: false
    property bool resetResizePending: false
    property var launchCounts: ({})

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function launcherCenteredFor(monitorName) {
        if (!monitorName || monitorName.length === 0)
            return false;
        if (monitorName === activeMonitorName && centeredPlacementOverride >= 0)
            return centeredPlacementOverride === 1;

        return BarState.launcherCenteredFor(monitorName);
    }

    function barPlacementForScreen(targetScreen) {
        if (!targetScreen || !FlyoutManager.barVisibleOnMonitor(targetScreen.name))
            return "center";
        return BarState.positionFor(targetScreen.name);
    }

    function placementForScreen(targetScreen) {
        if (targetScreen && launcherCenteredFor(targetScreen.name))
            return "center";
        return barPlacementForScreen(targetScreen);
    }

    function centeredPlacementForScreen(targetScreen) {
        if (!targetScreen || launcherCenteredFor(targetScreen.name)
            || !FlyoutManager.barVisibleOnMonitor(targetScreen.name))
            return "center";
        return BarState.positionFor(targetScreen.name) + "-center";
    }

    function animationsEnabled() {
        const state = animationStateFile.text().trim();
        return state !== "0";
    }

    function resetSelection() {
        appList.currentIndex = 0;
        Qt.callLater(() => {
            appList.currentIndex = 0;
            appList.positionViewAtBeginning();
        });
    }

    function safeMaximumWidth(targetScreen) {
        const reportedWidth = targetScreen ? Math.floor(targetScreen.width) : 0;
        const screenWidth = reportedWidth > 0 ? reportedWidth : 1920;
        return Math.max(1, screenWidth - screenEdgeMargin * 2);
    }

    function safeMaximumHeight(targetScreen) {
        const reportedHeight = targetScreen ? Math.floor(targetScreen.height) : 0;
        const screenHeight = reportedHeight > 0 ? reportedHeight : 1080;
        return Math.max(1, screenHeight - screenEdgeMargin * 2);
    }

    function safeMinimumWidth(targetScreen) {
        return Math.min(minimumLauncherWidth, safeMaximumWidth(targetScreen));
    }

    function safeMinimumHeight(targetScreen) {
        return Math.min(minimumLauncherHeight, safeMaximumHeight(targetScreen));
    }

    function setWindowSize(width, height) {
        const targetScreen = activeScreen;
        const desiredWidth = Math.min(safeMaximumWidth(targetScreen),
            Math.max(safeMinimumWidth(targetScreen), Math.round(width)));
        const desiredHeight = Math.min(safeMaximumHeight(targetScreen),
            Math.max(safeMinimumHeight(targetScreen), Math.round(height)));

        settingWindowSize = true;
        launcherWindow.implicitWidth = desiredWidth;
        launcherWindow.implicitHeight = desiredHeight;
        Qt.callLater(() => settingWindowSize = false);
    }

    function clampWindowToScreen() {
        const currentScreen = activeScreen;
        if (!currentScreen || currentScreen.width <= 0 || currentScreen.height <= 0) {
            const fallback = focusedScreen();
            if (!fallback)
                return;
            resetLocalSettingsState();
            launcherScreen = fallback;
            targetMonitorName = fallback.name;
            requestedPlacement = centeredPlacementForScreen(fallback);
            if (!launcherWindow.visible)
                launcherWindow.screen = fallback;
            applySpawnSize();
            positionTimer.restart();
            return;
        }
        setWindowSize(liveWidth, liveHeight);
        if (launcherWindow.visible)
            positionTimer.restart();
    }

    function guardWindowBounds() {
        if (!launcherWindow.visible || !activeScreen
            || targetMonitorName.length === 0 || boundsProcess.running)
            return;
        setWindowSize(liveWidth, liveHeight);
        boundsProcess.exec([positionScript, targetMonitorName, "clamp"]);
    }

    function applySpawnSize() {
        if (targetMonitorName === activeMonitorName && textScaleOverride >= 0) {
            setWindowSize(savedView.width, savedView.height);
            return;
        }

        const view = BarState.launcherViewFor(targetMonitorName);
        setWindowSize(view.width, view.height);
    }

    function loadSavedView(targetScreen, placement) {
        const monitor = targetScreen ? targetScreen.name : targetMonitorName;
        const persisted = BarState.launcherViewFor(monitor);
        const width = Math.min(safeMaximumWidth(targetScreen),
            Math.max(safeMinimumWidth(targetScreen), persisted.width));
        const height = Math.min(safeMaximumHeight(targetScreen),
            Math.max(safeMinimumHeight(targetScreen), persisted.height));
        savedView = ({
            width: Math.round(width),
            height: Math.round(height),
            textScale: persisted.textScale,
            iconScale: persisted.iconScale,
            centered: persisted.centered,
            captureAllowed: BarState.captureAllowedFor("launcher")
        });
        savedPlacement = placement || "center";
        textScaleOverride = persisted.textScale;
        iconScaleOverride = persisted.iconScale;
        centeredPlacementOverride = persisted.centered ? 1 : 0;
        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;
    }

    function acceptDraftAsSaved() {
        savedView = ({
            width: liveWidth,
            height: liveHeight,
            textScale: effectiveTextScale,
            iconScale: effectiveIconScale,
            centered: centerOnScreen,
            captureAllowed: captureAllowed
        });
        savedPlacement = requestedPlacement;
    }

    function discardDraft() {
        textScaleOverride = savedView.textScale;
        iconScaleOverride = savedView.iconScale;
        centeredPlacementOverride = savedView.centered ? 1 : 0;
        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;
        setWindowSize(savedView.width, savedView.height);
        requestedPlacement = savedPlacement;
        if (launcherWindow.visible)
            positionTimer.restart();
        settingsMessage = "";
    }

    function saveDisplaySettings() {
        const monitor = activeMonitorName;
        if (monitor.length === 0 || !settingsDirty)
            return;

        queueStateCommand([
            "save-view",
            monitor,
            String(liveWidth),
            String(liveHeight),
            String(effectiveTextScale),
            String(effectiveIconScale),
            centerOnScreen ? "true" : "false",
            captureAllowed ? "true" : "false"
        ]);
        acceptDraftAsSaved();
        settingsMessage = "Saved launcher settings for " + monitor;
    }

    function toggleCenteredPlacement() {
        const monitor = activeMonitorName;
        const targetScreen = activeScreen;
        if (monitor.length === 0 || !targetScreen)
            return;

        const enabled = !centerOnScreen;
        centeredPlacementOverride = enabled ? 1 : 0;
        requestedPlacement = enabled ? "center" : barPlacementForScreen(targetScreen);
        positionTimer.restart();
        settingsMessage = enabled
            ? "Launcher centered on " + monitor
            : "Launcher attached to the bar on " + monitor;
    }

    function toggleCaptureAllowed() {
        const next = !captureAllowed;
        captureAllowedOverride = next ? 1 : 0;
        savedView = Object.assign({}, savedView, { captureAllowed: next });
        privacyRemapPending = true;
        queueStateCommand(["set-capture", "launcher", next ? "true" : "false"]);
        settingsMessage = next
            ? "Launcher is visible in captures" : "Launcher capture protection enabled";
    }

    function queueStateCommand(commandArgs) {
        const nextQueue = stateCommandQueue.slice();
        nextQueue.push(commandArgs);
        stateCommandQueue = nextQueue;
        runNextStateCommand();
    }

    function runNextStateCommand() {
        if (sizeStateWriter.running || stateCommandQueue.length === 0)
            return;

        const nextCommand = stateCommandQueue[0];
        stateCommandQueue = stateCommandQueue.slice(1);
        sizeStateWriter.exec([stateScript, ...nextCommand]);
    }

    function adjustTextScale(delta) {
        const monitor = activeMonitorName;
        if (monitor.length === 0)
            return;
        const nextScale = Math.max(minimumTextScale,
            Math.min(maximumTextScale, effectiveTextScale + delta));
        textScaleOverride = nextScale;
        settingsMessage = "Text size " + nextScale + "%";
    }

    function adjustIconScale(delta) {
        const monitor = activeMonitorName;
        if (monitor.length === 0)
            return;
        const nextScale = Math.max(minimumIconScale,
            Math.min(maximumIconScale, effectiveIconScale + delta));
        iconScaleOverride = nextScale;
        settingsMessage = "Icon size " + nextScale + "%";
    }

    function resetDisplaySettings() {
        const monitor = activeMonitorName;
        if (monitor.length === 0)
            return;

        const wasCaptureAllowed = captureAllowed;
        textScaleOverride = 100;
        iconScaleOverride = 100;
        centeredPlacementOverride = 0;
        captureAllowedOverride = 0;
        savedView = ({
            width: BarState.defaultLauncherWidth,
            height: BarState.defaultLauncherHeight,
            textScale: 100,
            iconScale: 100,
            centered: false,
            captureAllowed: false
        });
        savedPlacement = barPlacementForScreen(activeScreen);
        requestedPlacement = savedPlacement;
        privacyRemapPending = privacyRemapPending || wasCaptureAllowed;
        resetResizePending = true;
        setWindowSize(BarState.defaultLauncherWidth, BarState.defaultLauncherHeight);
        queueStateCommand(["reset-monitor", monitor]);
        settingsMessage = "Launcher defaults loaded for " + monitor;
    }

    function copyTargetNames() {
        return Quickshell.screens
            .map(targetScreen => targetScreen ? targetScreen.name : "")
            .filter(name => name.length > 0 && name !== activeMonitorName);
    }

    function targetSelected(name) {
        const dependency = copySelectionRevision;
        return copyTargets[name] === true;
    }

    function selectedTargetCount() {
        const dependency = copySelectionRevision;
        return copyTargetNames().filter(name => targetSelected(name)).length;
    }

    function allTargetsSelected() {
        const names = copyTargetNames();
        return names.length > 0 && names.every(name => targetSelected(name));
    }

    function setTargetSelected(name, selected) {
        const next = Object.assign({}, copyTargets);
        if (selected)
            next[name] = true;
        else
            delete next[name];
        copyTargets = next;
        copySelectionRevision++;
    }

    function toggleAllTargets() {
        const select = !allTargetsSelected();
        const next = {};
        if (select) {
            for (const name of copyTargetNames())
                next[name] = true;
        }
        copyTargets = next;
        copySelectionRevision++;
    }

    function clearCopyTargets() {
        copyTargets = ({});
        copySelectionRevision++;
    }

    function applyCopySettings() {
        const targets = copyTargetNames().filter(name => targetSelected(name));
        if (targets.length === 0)
            return;

        queueStateCommand([
            "copy-view",
            String(liveWidth),
            String(liveHeight),
            String(effectiveTextScale),
            String(effectiveIconScale),
            ...targets
        ]);
        settingsMessage = "Copied launcher settings to " + targets.length
            + (targets.length === 1 ? " display" : " displays");
        copySettingsOpen = false;
        clearCopyTargets();
    }

    function toggleSettings() {
        settingsOpen = !settingsOpen;
        copySettingsOpen = false;
        clearCopyTargets();
        settingsMessage = "";
    }

    function resetLocalSettingsState() {
        settingsOpen = false;
        copySettingsOpen = false;
        textScaleOverride = -1;
        iconScaleOverride = -1;
        centeredPlacementOverride = -1;
        captureAllowedOverride = -1;
        settingsMessage = "";
        clearCopyTargets();
    }

    function prepareLauncherOpen(targetScreen) {
        if (!targetScreen)
            return;
        const edgePlacement = requestedPlacement.replace("-center", "");
        const vertical = edgePlacement === "left" || edgePlacement === "right";
        const barSize = requestedPlacement === "center"
            ? 0 : BarState.barSizeFor(targetScreen.name, vertical);
        openPreparing = true;
        prepareProcess.exec([
            "bash", prepareScript, "launcher", targetScreen.name, requestedPlacement,
            String(savedView.width), String(savedView.height),
            String(barSize), "-1",
            String(Math.round(targetScreen.width)), String(Math.round(targetScreen.height))
        ]);
    }

    function finishPreparedOpen() {
        if (!openPreparing)
            return;

        const wasVisible = launcherWindow.visible;

        openPreparing = false;
        launcherPositioned = true;
        launcherWindow.visible = true;

        // A same-surface monitor handoff deliberately keeps the native window
        // mapped. visibleChanged cannot fire in that case, so run the existing
        // authoritative Hyprland positioning helper explicitly.
        if (wasVisible)
            positionTimer.restart();

        resetSelection();
    }

    function showOnScreen(targetScreen, placement) {
        if (!targetScreen)
            return;

        FlyoutManager.claim("launcher", targetScreen.name);
        focusGrab.active = false;
        focusGrabExpansionTimer.stop();
        launcherFocusGrabExpanded = false;
        resetLocalSettingsState();
        launcherScreen = targetScreen;
        targetMonitorName = targetScreen.name;
        requestedPlacement = placement || "center";
        loadSavedView(targetScreen, requestedPlacement);
        launcherPositioned = false;
        // Never retarget a mapped QWindow through Qt. The Hyprland
        // positioning helper moves an already-visible launcher directly.
        if (!launcherWindow.visible)
            launcherWindow.screen = targetScreen;
        setWindowSize(savedView.width, savedView.height);
        search.text = "";
        prepareLauncherOpen(targetScreen);
    }

    function openForScreen(targetScreen) {
        if (!targetScreen)
            return;
        if (!FlyoutManager.acceptToggle("launcher"))
            return;

        const currentName = activeMonitorName;
        const targetName = String(targetScreen.name || "");

        // Same monitor = toggle closed.
        // Different monitor = transfer in the same click.
        if ((launcherWindow.visible || openPreparing)
            && currentName.length > 0
            && currentName === targetName) {
            close();
            return;
        }

        showOnScreen(targetScreen, placementForScreen(targetScreen));
    }

    function openFocused() {
        const target = focusedScreen();
        if (launcherWindow.visible) {
            search.forceActiveFocus();
            return;
        }
        if (openPreparing)
            return;
        showOnScreen(target, centeredPlacementForScreen(target));
    }

    function close() {
        openPreparing = false;
        if (prepareProcess.running)
            prepareProcess.running = false;
        if (settingsDirty)
            discardDraft();
        focusGrab.active = false;
        focusGrabExpansionTimer.stop();
        launcherFocusGrabExpanded = false;
        launcherWindow.visible = false;
        FlyoutManager.release("launcher");
        launcherPositioned = false;
        search.text = "";
        resetLocalSettingsState();
    }

    function toggleFocused() {
        if (!FlyoutManager.acceptToggle("launcher"))
            return;
        if (launcherWindow.visible || openPreparing) {
            close();
            return;
        }
        const target = focusedScreen();
        showOnScreen(target, centeredPlacementForScreen(target));
    }

    function positionLauncher() {
        if (!launcherWindow.visible || targetMonitorName.length === 0)
            return;
        positionProcess.exec([positionScript, targetMonitorName, requestedPlacement]);
    }

    function searchText(entry) {
        if (!entry)
            return "";
        return [entry.name, entry.genericName, entry.comment, entry.id, ...(entry.keywords || [])]
            .filter(value => value && String(value).length > 0)
            .join(" ")
            .toLowerCase();
    }

    function reloadLaunchCounts() {
        const raw = launcherUsageFile.text().trim();
        if (raw.length === 0) {
            launchCounts = ({});
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            launchCounts = parsed && parsed.launches && typeof parsed.launches === "object"
                ? parsed.launches : ({});
        } catch (error) {
            launchCounts = ({});
        }
    }

    function launchCount(entry) {
        const entryId = entry && entry.id ? String(entry.id) : "";
        if (entryId.length === 0)
            return 0;

        const count = Number(launchCounts[entryId] || 0);
        return isFinite(count) && count > 0 ? Math.floor(count) : 0;
    }

    function fuzzyScore(haystack, query) {
        if (query.length === 0)
            return 0;

        const exact = haystack.indexOf(query);
        if (exact >= 0)
            return 5000 - exact * 4 + (exact === 0 ? 1000 : 0);

        let score = 0;
        let at = 0;
        let previous = -2;
        for (let i = 0; i < query.length; ++i) {
            const ch = query[i];
            const found = haystack.indexOf(ch, at);
            if (found < 0)
                return -1;

            score += 20;
            if (found === previous + 1)
                score += 35;
            if (found === 0 || " -_./".indexOf(haystack[found - 1]) >= 0)
                score += 45;
            score -= Math.min(20, found - at);
            previous = found;
            at = found + 1;
        }
        return score - Math.min(200, haystack.length);
    }

    function visibleApps() {
        return [...DesktopEntries.applications.values].filter(app => app && !app.noDisplay);
    }

    function filteredApps() {
        const query = search.text.trim().toLowerCase();
        const apps = visibleApps()
            .map(app => ({ entry: app, score: fuzzyScore(searchText(app), query) }))
            .filter(item => item.entry && item.score >= 0);

        apps.sort((a, b) => {
            if (a.score !== b.score)
                return b.score - a.score;
            const aCount = launchCount(a.entry);
            const bCount = launchCount(b.entry);
            if (aCount !== bCount)
                return bCount - aCount;
            return String(a.entry.name || "").localeCompare(String(b.entry.name || ""));
        });
        return apps.map(item => item.entry).filter(entry => entry !== null && entry !== undefined);
    }

    function launchEntry(entry) {
        if (!entry)
            return;

        const entryId = String(entry.id || "");
        if (entryId.length > 0)
            usageRecorder.exec(["bash", usageScript, "record", entryId]);

        const workingDirectory = entry.workingDirectory || "";
        if (entry.runInTerminal) {
            Quickshell.execDetached({
                command: ["alacritty", "-e", ...entry.command],
                workingDirectory: workingDirectory
            });
        } else {
            Quickshell.execDetached({
                command: entry.command,
                workingDirectory: workingDirectory
            });
        }
        close();
    }

    FileView {
        id: animationStateFile
        path: root.animationStatePath
        blockLoading: false
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    FileView {
        id: launcherUsageFile
        path: root.launcherUsagePath
        blockLoading: false
        watchChanges: true
        printErrors: false
        onLoaded: root.reloadLaunchCounts()
        onFileChanged: reload()
        onLoadFailed: root.launchCounts = ({})
    }

    Process {
        id: usageRecorder
        onExited: launcherUsageFile.reload()
    }

    Process {
        id: sizeStateWriter
        onExited: {
            BarState.refresh();
            if (root.resetResizePending && root.stateCommandQueue.length === 0) {
                root.resetResizePending = false;
                root.setWindowSize(BarState.defaultLauncherWidth,
                    BarState.defaultLauncherHeight);
                if (launcherWindow.visible && !root.privacyRemapPending)
                    positionTimer.restart();
            }
            privacyRuleUpdater.exec([root.runtimeRulesScript]);
            Qt.callLater(() => root.runNextStateCommand());
        }
    }

    Process {
        id: privacyRuleUpdater
        onExited: {
            if (!root.privacyRemapPending)
                return;
            root.privacyRemapPending = false;
            if (!launcherWindow.visible)
                return;
            launcherWindow.visible = false;
            Qt.callLater(() => {
                launcherWindow.visible = true;
                positionTimer.restart();
                search.forceActiveFocus();
            });
        }
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "launcher"
                && (launcherWindow.visible || root.openPreparing))
                root.close();
        }
    }

    IpcHandler {
        target: "launcher"
        readonly property int diagnosticResultCount: appList.count
        readonly property bool diagnosticReady: launcherWindow.visible
            && root.launcherPositioned
            && launcherPanel.opacity >= 0.99
            && search.activeFocus
            && appList.count > 0
            && appList.currentItem !== null
        function toggle(): void { root.toggleFocused(); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
        function applyConfiguredSize(): void { root.applySpawnSize(); }
        function currentWidth(): int { return root.liveWidth; }
        function currentHeight(): int { return root.liveHeight; }
    }

    Timer {
        id: positionTimer
        interval: 0
        repeat: false
        onTriggered: root.positionLauncher()
    }

    Timer {
        id: screenClampTimer
        interval: 0
        repeat: false
        onTriggered: root.clampWindowToScreen()
    }

    Timer {
        id: boundsGuardTimer
        interval: 180
        repeat: false
        onTriggered: root.guardWindowBounds()
    }

    Connections {
        target: root.activeScreen
        enabled: target !== null
        ignoreUnknownSignals: true
        function onWidthChanged() { screenClampTimer.restart(); }
        function onHeightChanged() { screenClampTimer.restart(); }
    }

    Connections {
        target: Quickshell
        ignoreUnknownSignals: true
        function onScreensChanged() { screenClampTimer.restart(); }
    }

    Process {
        id: prepareProcess
        onExited: root.finishPreparedOpen()
    }

    Process {
        id: positionProcess
        onExited: {
            if (!launcherWindow.visible)
                return;
            root.launcherPositioned = true;
            search.forceActiveFocus();
            focusGrab.active = true;
        }
    }

    Process {
        id: boundsProcess
    }

    // Start the focus grab with only the launcher surface. The protocol then
    // gives that surface keyboard entry without moving the pointer. Bar
    // surfaces join the whitelist after the initial keyboard target is set.
    Timer {
        id: focusGrabExpansionTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (launcherWindow.visible && focusGrab.active)
                root.launcherFocusGrabExpanded = true;
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: root.launcherFocusGrabExpanded
            ? [launcherWindow].concat(FlyoutManager.barWindows || [])
            : [launcherWindow]
        onActiveChanged: {
            if (active) {
                focusGrabExpansionTimer.restart();
            } else {
                focusGrabExpansionTimer.stop();
                root.launcherFocusGrabExpanded = false;
            }
        }
        onCleared: {
            if (launcherWindow.visible)
                root.close();
        }
    }

    FloatingWindow {
        id: launcherWindow
        visible: false
        title: "Awtarchy Application Search"
        color: "transparent"
        surfaceFormat.opaque: false

        implicitWidth: BarState.defaultLauncherWidth
        implicitHeight: BarState.defaultLauncherHeight
        minimumSize: Qt.size(
            root.safeMinimumWidth(screen),
            root.safeMinimumHeight(screen)
        )
        maximumSize: Qt.size(
            root.safeMaximumWidth(screen),
            root.safeMaximumHeight(screen)
        )

        onScreenChanged: screenClampTimer.restart()
        onWidthChanged: {
            if (visible && !root.settingWindowSize)
                boundsGuardTimer.restart();
        }
        onHeightChanged: {
            if (visible && !root.settingWindowSize)
                boundsGuardTimer.restart();
        }

        onVisibleChanged: {
            if (visible) {
                positionTimer.restart();
            } else {
                focusGrab.active = false;
            }
        }

        onClosed: root.close()

        Rectangle {
            id: launcherPanel
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 0
            radius: 0
            opacity: root.launcherPositioned ? 1 : 0

            Behavior on opacity {
                enabled: root.animationsEnabled()
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            DragHandler {
                target: null
                acceptedButtons: Qt.LeftButton
                acceptedModifiers: Qt.AltModifier
                onActiveChanged: {
                    if (active) {
                        positionTimer.stop();
                        launcherWindow.startSystemMove();
                    }
                }
            }

            DragHandler {
                target: null
                acceptedButtons: Qt.RightButton
                acceptedModifiers: Qt.AltModifier
                onActiveChanged: {
                    if (active) {
                        positionTimer.stop();
                        root.resizeStartWidth = root.liveWidth;
                        root.resizeStartHeight = root.liveHeight;
                    } else {
                        boundsGuardTimer.restart();
                    }
                }
                onActiveTranslationChanged: {
                    if (!active)
                        return;
                    root.setWindowSize(
                        root.resizeStartWidth + activeTranslation.x,
                        root.resizeStartHeight + activeTranslation.y
                    );
                }
            }

            GridLayout {
                anchors.fill: parent
                columns: 1
                rowSpacing: 0
                columnSpacing: 0

                Rectangle {
                    Layout.row: root.bottomEdgeLayout ? 2 : 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: Theme.active
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 40
                        spacing: 6

                        Text {
                            text: ">>"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }

                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.foreground
                            selectionColor: Theme.focus
                            selectedTextColor: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            focus: launcherWindow.visible && root.launcherPositioned

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    if (root.copySettingsOpen) {
                                        root.copySettingsOpen = false;
                                        root.clearCopyTargets();
                                    } else if (root.settingsOpen) {
                                        root.toggleSettings();
                                    } else {
                                        root.close();
                                    }
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down) {
                                    if (appList.count > 0) {
                                        const downIndex = Math.min(appList.count - 1,
                                            Math.max(0, appList.currentIndex) + appList.columnCount);
                                        appList.currentIndex = downIndex;
                                    }
                                    appList.positionViewAtIndex(appList.currentIndex, GridView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    if (appList.count > 0) {
                                        const upIndex = Math.max(0,
                                            Math.max(0, appList.currentIndex) - appList.columnCount);
                                        appList.currentIndex = upIndex;
                                    }
                                    appList.positionViewAtIndex(appList.currentIndex, GridView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Right && appList.columnCount > 1) {
                                    if (appList.count > 0)
                                        appList.currentIndex = Math.min(appList.count - 1,
                                            Math.max(0, appList.currentIndex) + 1);
                                    appList.positionViewAtIndex(appList.currentIndex, GridView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Left && appList.columnCount > 1) {
                                    if (appList.count > 0)
                                        appList.currentIndex = Math.max(0,
                                            Math.max(0, appList.currentIndex) - 1);
                                    appList.positionViewAtIndex(appList.currentIndex, GridView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    const values = root.filteredApps();
                                    if (appList.currentIndex >= 0 && appList.currentIndex < values.length)
                                        root.launchEntry(values[appList.currentIndex]);
                                    event.accepted = true;
                                }
                            }

                            onTextChanged: root.resetSelection()
                        }

                        Text {
                            readonly property int matches: appList.count
                            text: matches + "/" + root.visibleApps().length
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }

                        Rectangle {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 26
                            color: root.settingsDirty
                                ? (saveMouse.containsMouse ? Theme.focus : Theme.subtleHover)
                                : "transparent"
                            opacity: root.settingsDirty ? 1 : 0.45
                            border.width: 1
                            border.color: root.settingsDirty ? Theme.focus : Theme.muted

                            Text {
                                anchors.centerIn: parent
                                text: ""
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }

                            MouseArea {
                                id: saveMouse
                                anchors.fill: parent
                                enabled: root.settingsDirty
                                hoverEnabled: enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    root.saveDisplaySettings();
                                    Qt.callLater(() => search.forceActiveFocus());
                                }
                            }
                        }

                        CaptureEyeButton {
                            captureAllowed: root.captureAllowed
                            textSize: 13
                            onClicked: {
                                root.toggleCaptureAllowed();
                                Qt.callLater(() => search.forceActiveFocus());
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 26
                            color: root.settingsOpen ? Theme.focus
                                : (settingsMouse.containsMouse ? Theme.subtleHover : "transparent")
                            border.width: 1
                            border.color: root.settingsOpen ? Theme.focus : Theme.muted
                            radius: 0

                            Text {
                                anchors.centerIn: parent
                                text: ""
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }

                            MouseArea {
                                id: settingsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.toggleSettings();
                                    Qt.callLater(() => search.forceActiveFocus());
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.row: 1
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.settingsOpen
                        ? (root.copySettingsOpen ? 108 : 139) : 0
                    visible: root.settingsOpen
                    color: Theme.popupButton
                    border.width: 0
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: root.activeMonitorName + "  " + root.liveWidth + " × " + root.liveHeight
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.preferredWidth: 112
                                Layout.preferredHeight: 26
                                color: resetMouse.containsMouse ? Theme.focus : Theme.subtleHover
                                border.width: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "Reset Launcher"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: resetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.resetDisplaySettings()
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            spacing: 6
                            visible: !root.copySettingsOpen

                            Text {
                                Layout.fillWidth: true
                                text: "Open centered on this display"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 24
                                color: root.centerOnScreen ? Theme.focus
                                    : (centerPlacementMouse.containsMouse ? Theme.subtleHover : "transparent")
                                border.width: 1
                                border.color: Theme.focus

                                Text {
                                    anchors.centerIn: parent
                                    text: root.centerOnScreen ? "On" : "Off"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: centerPlacementMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.toggleCenteredPlacement();
                                        Qt.callLater(() => search.forceActiveFocus());
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            spacing: 5
                            visible: !root.copySettingsOpen

                            Text {
                                text: "Icons"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 24
                                color: iconMinusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                                opacity: root.effectiveIconScale > root.minimumIconScale ? 1 : 0.4
                                border.width: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: iconMinusMouse
                                    anchors.fill: parent
                                    enabled: root.effectiveIconScale > root.minimumIconScale
                                    hoverEnabled: enabled
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.adjustIconScale(-10)
                                }
                            }

                            Text {
                                Layout.preferredWidth: 42
                                horizontalAlignment: Text.AlignHCenter
                                text: root.effectiveIconScale + "%"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 24
                                color: iconPlusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                                opacity: root.effectiveIconScale < root.maximumIconScale ? 1 : 0.4
                                border.width: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: iconPlusMouse
                                    anchors.fill: parent
                                    enabled: root.effectiveIconScale < root.maximumIconScale
                                    hoverEnabled: enabled
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.adjustIconScale(10)
                                }
                            }

                            Item { Layout.preferredWidth: 8 }

                            Text {
                                text: "Text"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 24
                                color: textMinusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                                opacity: root.effectiveTextScale > root.minimumTextScale ? 1 : 0.4
                                border.width: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: textMinusMouse
                                    anchors.fill: parent
                                    enabled: root.effectiveTextScale > root.minimumTextScale
                                    hoverEnabled: enabled
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.adjustTextScale(-10)
                                }
                            }

                            Text {
                                Layout.preferredWidth: 42
                                horizontalAlignment: Text.AlignHCenter
                                text: root.effectiveTextScale + "%"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 24
                                color: textPlusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                                opacity: root.effectiveTextScale < root.maximumTextScale ? 1 : 0.4
                                border.width: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: textPlusMouse
                                    anchors.fill: parent
                                    enabled: root.effectiveTextScale < root.maximumTextScale
                                    hoverEnabled: enabled
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.adjustTextScale(10)
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            visible: root.copySettingsOpen
                            clip: true
                            contentWidth: Math.max(width, copyTargetRow.width)
                            contentHeight: height
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds

                            Row {
                                id: copyTargetRow
                                height: parent.height
                                width: childrenRect.width
                                spacing: 4

                                Rectangle {
                                    visible: root.copyTargetNames().length > 0
                                    width: visible ? 96 : 0
                                    height: 24
                                    color: root.allTargetsSelected() ? Theme.focus
                                        : (allTargetsMouse.containsMouse ? Theme.subtleHover : "transparent")
                                    border.width: 1
                                    border.color: Theme.focus

                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.allTargetsSelected() ? "✓ " : "") + "All displays"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }

                                    MouseArea {
                                        id: allTargetsMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleAllTargets()
                                    }
                                }

                                Repeater {
                                    model: root.copyTargetNames()

                                    Rectangle {
                                        id: copyTargetButton
                                        required property var modelData
                                        readonly property string monitorName: String(modelData)
                                        width: Math.max(72, Math.min(140, targetLabel.implicitWidth + 24))
                                        height: 24
                                        color: root.targetSelected(monitorName) ? Theme.focus
                                            : (targetMouse.containsMouse ? Theme.subtleHover : "transparent")
                                        border.width: 1
                                        border.color: Theme.focus

                                        Text {
                                            id: targetLabel
                                            anchors.centerIn: parent
                                            width: parent.width - 12
                                            text: (root.targetSelected(copyTargetButton.monitorName) ? "✓ " : "")
                                                + copyTargetButton.monitorName
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                        }

                                        MouseArea {
                                            id: targetMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setTargetSelected(copyTargetButton.monitorName,
                                                !root.targetSelected(copyTargetButton.monitorName))
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: root.copyTargetNames().length === 0
                                text: "No other displays connected"
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            spacing: 6
                            visible: !root.copySettingsOpen

                            Rectangle {
                                Layout.preferredWidth: 142
                                Layout.preferredHeight: 24
                                color: copyOpenMouse.containsMouse ? Theme.focus : Theme.subtleHover
                                border.width: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "Copy to Displays…"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: copyOpenMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.clearCopyTargets();
                                        root.copySettingsOpen = true;
                                        root.settingsMessage = "";
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.settingsMessage.length > 0
                                    ? root.settingsMessage
                                    : "One-time copy; center mode stays independent"
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            spacing: 6
                            visible: root.copySettingsOpen

                            Rectangle {
                                Layout.preferredWidth: 62
                                Layout.preferredHeight: 24
                                color: copyBackMouse.containsMouse ? Theme.focus : Theme.subtleHover
                                border.width: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "Back"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: copyBackMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.copySettingsOpen = false;
                                        root.clearCopyTargets();
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.selectedTargetCount() + " selected"
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                horizontalAlignment: Text.AlignRight
                            }

                            Rectangle {
                                Layout.preferredWidth: 70
                                Layout.preferredHeight: 24
                                color: root.selectedTargetCount() > 0
                                    ? (copyApplyMouse.containsMouse ? Theme.focus : Theme.subtleHover)
                                    : "transparent"
                                opacity: root.selectedTargetCount() > 0 ? 1 : 0.4
                                border.width: 1
                                border.color: Theme.focus

                                Text {
                                    anchors.centerIn: parent
                                    text: "Apply"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: copyApplyMouse
                                    anchors.fill: parent
                                    enabled: root.selectedTargetCount() > 0
                                    hoverEnabled: enabled
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.applyCopySettings()
                                }
                            }
                        }
                    }
                }

                GridView {
                    id: appList
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    currentIndex: 0
                    boundsBehavior: Flickable.StopAtBounds
                    flow: GridView.FlowLeftToRight
                    verticalLayoutDirection: GridView.TopToBottom
                    readonly property int columnCount: Math.max(1,
                        Math.floor(width / root.applicationColumnMinimumWidth))
                    cellWidth: width / columnCount
                    cellHeight: Math.max(28,
                        root.configuredAppIconSize + 10,
                        root.configuredAppTextSize + 14)

                    model: ScriptModel {
                        values: root.filteredApps()

                        // GridView may clear currentIndex after ScriptModel
                        // replaces its rows. Re-select only after that reset so
                        // opening and every search update highlight result 0.
                        onValuesChanged: Qt.callLater(() => root.resetSelection())
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        property var entry: modelData

                        width: GridView.view.cellWidth
                        height: GridView.view.cellHeight
                        color: GridView.isCurrentItem ? Theme.focus : (hover.containsMouse ? Theme.subtleHover : "transparent")
                        border.width: 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: appScrollBar.visible ? 18 : 8
                            spacing: 8

                            IconImage {
                                Layout.preferredWidth: root.configuredAppIconSize
                                Layout.preferredHeight: root.configuredAppIconSize
                                implicitSize: root.configuredAppIconSize
                                source: row.entry && row.entry.icon && row.entry.icon.length > 0
                                    ? Quickshell.iconPath(row.entry.icon, true)
                                    : Quickshell.iconPath("application-x-executable", true)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.entry ? (row.entry.name || "Application") : "Application"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: root.configuredAppTextSize
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            onPositionChanged: mouse => {
                                appList.currentIndex = row.index;
                            }
                            onClicked: root.launchEntry(row.entry)
                            onWheel: wheel => {
                                const minY = appList.originY;
                                const maxY = Math.max(minY, minY + appList.contentHeight - appList.height);
                                appList.contentY = Math.max(minY,
                                    Math.min(maxY, appList.contentY - wheel.angleDelta.y));
                                wheel.accepted = true;
                            }
                        }
                    }

                    ListScrollBar {
                        id: appScrollBar
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        flickable: appList
                        z: 10
                    }
                }
            }

            Rectangle {
                id: launcherCloseButton
                width: 28
                height: 28
                x: launcherPanel.width - width - 6
                y: root.bottomEdgeLayout ? launcherPanel.height - height - 4 : 4
                color: launcherCloseMouse.containsMouse ? Theme.focus : Theme.active
                border.width: 1
                border.color: launcherCloseMouse.containsMouse ? Theme.focus : Theme.muted
                radius: 0
                z: 20

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                }

                MouseArea {
                    id: launcherCloseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }
    }
}
