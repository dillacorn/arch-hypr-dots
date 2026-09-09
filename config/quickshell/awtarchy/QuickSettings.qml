pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "FlyoutEdgeLayout.js" as FlyoutEdgeLayout

Singleton {
    id: root

    property var statusData: emptyStatus()
    property bool statusLoading: false
    property bool refreshPending: false
    property string actionMessage: ""
    property string actionError: ""
    property var actionQueue: []
    property string placement: "center"
    readonly property bool bottomEdgeLayout: FlyoutEdgeLayout.isBottom(placement)
    property string brightnessTarget: ""
    property string selectedSchedulerName: ""
    property bool schedulerEditorOpen: false
    property string schedulerArgsDraft: ""
    property bool schedulerArgsDirty: false
    property bool schedulerAuthOpen: false
    property bool schedulerAuthBusy: false
    property string schedulerAuthError: ""
    property string schedulerAuthPendingPassword: ""
    property int brightnessHoverPercent: -1
    property int outputVolumeHoverPercent: -1
    property bool nightLightScheduleEditorOpen: false
    property string nightLightScheduleStartDraft: "20:00"
    property string nightLightScheduleEndDraft: "07:00"
    property string nightLightScheduleTemperatureDraft: "5000"
    property string nightLightScheduleError: ""
    property bool settingsOpen: false
    property bool layoutEditorOpen: false
    property bool barIconsOpen: false
    property bool barAppearanceOpen: false
    property bool barVisibilityOpen: false
    property bool lockscreenSectionExpanded: false
    property string lockscreenWeatherLocationDraft: ""
    property string lockscreenWeatherLocationError: ""
    property var layoutOrderDraft: []
    property var layoutHiddenDraft: []
    property var savedLayout: ({ order: [], hidden: [] })
    property int panelWidthOverride: -1
    property int panelHeightOverride: -1
    property int textScaleOverride: -1
    property int iconScaleOverride: -1
    property int captureAllowedOverride: -1
    property string settingsMessage: ""
    property var savedView: ({
        width: BarState.defaultQuickSettingsWidth,
        height: BarState.defaultQuickSettingsHeight,
        textScale: 100,
        iconScale: 100,
        captureAllowed: false
    })
    property var stateCommandQueue: []
    property bool privacyRemapPending: false
    property bool openPreparing: false
    property bool panelPresented: false
    readonly property int panelFadeDuration: 140
    property var flyoutScreen: null

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string backend: configHome + "/hypr/scripts/hypr_quicksettings.sh"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string terminalLauncher: configHome + "/hypr/scripts/default_terminal.sh"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_flyout_position.sh"
    readonly property string prepareScript: configHome + "/hypr/scripts/quickshell_flyout_prepare.sh"
    readonly property bool disableNumlockAtSessionStart: numlockSettings.disableNumlockAtSessionStart
    readonly property var activeScreen: flyoutScreen || quickSettingsWindow.screen
    readonly property string activeMonitorName: activeScreen && activeScreen.name
        ? String(activeScreen.name) : ""
    readonly property int targetScreenWidth: activeScreen ? activeScreen.width : 1920
    readonly property int targetScreenHeight: activeScreen ? activeScreen.height : 1080
    readonly property int maximumPanelWidth: Math.max(1, targetScreenWidth - 20)
    readonly property int maximumPanelHeight: Math.max(1, targetScreenHeight - 20)
    readonly property int minimumPanelWidth: Math.min(520, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(460, maximumPanelHeight)
    readonly property int minimumSettingsPanelHeight: Math.min(180, maximumPanelHeight)
    readonly property int configuredPanelWidth: clampWidth(panelWidthOverride >= 0
        ? panelWidthOverride : BarState.quickSettingsViewFor(activeMonitorName).width)
    readonly property int configuredPanelHeight: clampHeight(panelHeightOverride >= 0
        ? panelHeightOverride : BarState.quickSettingsViewFor(activeMonitorName).height)
    readonly property int livePanelWidth: quickSettingsWindow.visible && quickSettingsWindow.width > 0
        ? clampWidth(Math.round(quickSettingsWindow.width)) : configuredPanelWidth
    readonly property int livePanelHeight: quickSettingsWindow.visible && !root.settingsOpen
        && quickSettingsWindow.height > 0
        ? clampHeight(Math.round(quickSettingsWindow.height)) : configuredPanelHeight
    readonly property int settingsModePanelHeight: clampSettingsHeight(38
        + (layoutEditorOpen ? layoutEditor.implicitHeight : settingsPanel.implicitHeight) + 12)
    readonly property int effectiveTextScale: textScaleOverride >= 0
        ? textScaleOverride : BarState.quickSettingsViewFor(activeMonitorName).textScale
    readonly property int effectiveIconScale: iconScaleOverride >= 0
        ? iconScaleOverride : BarState.quickSettingsViewFor(activeMonitorName).iconScale
    readonly property bool captureAllowed: captureAllowedOverride >= 0
        ? captureAllowedOverride === 1 : BarState.captureAllowedFor("quick_settings")
    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed
    readonly property var brightnessStatus: statusData.brightness || ({})
    readonly property var barStatus: statusData.bar || ({})
    readonly property var nightLightStatus: statusData.night_light || ({})
    readonly property var vibranceStatus: statusData.vibrance || ({})
    readonly property var schedulerStatus: statusData.sched_ext || ({ schedulers: [] })
    readonly property int brightnessPercent: {
        const current = Number(brightnessStatus.current);
        const maximum = Number(brightnessStatus.max);
        if (!Number.isFinite(current) || !Number.isFinite(maximum) || maximum <= 0)
            return -1;
        return Math.max(0, Math.min(100, Math.round(current * 100 / maximum)));
    }

    onBottomEdgeLayoutChanged: Qt.callLater(() => alignContentToBar())
    onSettingsModePanelHeightChanged: {
        if (settingsOpen)
            Qt.callLater(() => resizeForSettingsMode());
    }
    onPlacementChanged: {
        if (!quickSettingsWindow.visible || openPreparing)
            return;
        Qt.callLater(() => {
            if (root.settingsOpen)
                root.resizeForSettingsMode();
            else
                root.positionWindow();
        });
    }

    function emptyStatus() {
        return ({
            monitors: [],
            brightness: { target: "", connector: "", current: null, max: null },
            bar: { monitor: "", position: "top", enabled: true, auto_hide: false },
            night_light: {
                temperature: null,
                identity: "unknown",
                enabled: false,
                schedule_enabled: false,
                schedule_start: "20:00",
                schedule_end: "07:00",
                schedule_temperature: 5000,
                schedule_next_day: true
            },
            vibrance: { value: null, enabled: false },
            submap: "reset",
            sched_ext: {
                running: "off",
                mode: "",
                enabled: false,
                last_selected: "",
                restore_enabled: false,
                available: false,
                authorized: false,
                schedulers: []
            }
        });
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0]
            : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function placementForScreen(targetScreen) {
        if (!targetScreen || !BarState.enabledFor(targetScreen.name))
            return "center";
        return BarState.positionFor(targetScreen.name);
    }

    function clampWidth(value) {
        return Math.max(minimumPanelWidth, Math.min(maximumPanelWidth, Math.round(value)));
    }

    function clampHeight(value) {
        return Math.max(minimumPanelHeight, Math.min(maximumPanelHeight, Math.round(value)));
    }

    function clampSettingsHeight(value) {
        return Math.max(minimumSettingsPanelHeight,
            Math.min(maximumPanelHeight, Math.round(value)));
    }

    function outputLimitForPosition(x, width) {
        if (width <= 0)
            return AudioLimitState.limitPercent;
        const ratio = Math.max(0, Math.min(1, x / width));
        const raw = AudioLimitState.minimumPercent
            + ratio * (AudioLimitState.maximumPercent - AudioLimitState.minimumPercent);
        return AudioLimitState.normalized(raw);
    }

    function applyWindowSize(width, height) {
        panelWidthOverride = clampWidth(width);
        panelHeightOverride = clampHeight(height);
        if (quickSettingsWindow.visible && activeMonitorName.length > 0) {
            Quickshell.execDetached([
                positionScript, "quick-settings", activeMonitorName, placement,
                settingsOpen ? "resize-compact" : "resize",
                String(panelWidthOverride),
                String(settingsOpen ? settingsModePanelHeight : panelHeightOverride)
            ]);
        }
    }

    function resizeForSettingsMode() {
        if (!quickSettingsWindow.visible || activeMonitorName.length === 0)
            return;
        Quickshell.execDetached([
            positionScript, "quick-settings", activeMonitorName, placement,
            settingsOpen ? "resize-compact" : "resize",
            String(configuredPanelWidth),
            String(settingsOpen ? settingsModePanelHeight : configuredPanelHeight)
        ]);
    }

    function positionWindow() {
        if (!quickSettingsWindow.visible || activeMonitorName.length === 0)
            return;
        Quickshell.execDetached([
            positionScript, "quick-settings", activeMonitorName, placement, "spawn"
        ]);
    }

    function prepareWindowOpen(targetScreen) {
        if (!targetScreen)
            return;
        const vertical = placement === "left" || placement === "right";
        const barSize = placement === "center"
            ? 0 : BarState.barSizeFor(targetScreen.name, vertical);
        openPreparing = true;
        prepareProcess.exec([
            "bash", prepareScript, "quick-settings", targetScreen.name, placement,
            String(configuredPanelWidth), String(configuredPanelHeight),
            String(barSize), "-1",
            String(Math.round(targetScreen.width)), String(Math.round(targetScreen.height))
        ]);
    }

    function finishPreparedOpen() {
        if (!openPreparing)
            return;

        const wasVisible = quickSettingsWindow.visible;

        openPreparing = false;
        panelPresented = true;
        quickSettingsWindow.visible = true;
        if (wasVisible)
            Qt.callLater(() => root.positionWindow());
        refreshStatus();
    }

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * effectiveTextScale / 100));
    }

    function scaledIcon(baseSize) {
        return Math.max(9, Math.round(baseSize * effectiveIconScale / 100));
    }

    function alignContentToBar() {
        const minimumY = contentFlick.originY;
        const maximumY = Math.max(minimumY,
            minimumY + contentFlick.contentHeight - contentFlick.height);
        contentFlick.contentY = bottomEdgeLayout ? maximumY : minimumY;
    }

    function monitorNames() {
        const values = statusData.monitors || [];
        return values.map(monitor => String(monitor.name || "")).filter(name => name.length > 0);
    }

    function otherMonitorNames() {
        return Quickshell.screens
            .map(target => target ? target.name : "")
            .filter(name => name.length > 0 && name !== activeMonitorName);
    }

    function layoutSignature(order, hidden) {
        const ordered = Array.isArray(order) ? order : [];
        const hiddenValues = Array.isArray(hidden) ? hidden : [];
        const normalizedHidden = ordered.filter(sectionId => hiddenValues.indexOf(sectionId) >= 0);
        return JSON.stringify(ordered) + "|" + JSON.stringify(normalizedHidden);
    }

    function persistQuickSettingsLayout() {
        if (activeMonitorName.length === 0)
            return;
        queueStateCommand([
            "save-quick-settings-layout", activeMonitorName,
            JSON.stringify(layoutOrderDraft), JSON.stringify(layoutHiddenDraft)
        ]);
        savedLayout = ({
            order: layoutOrderDraft.slice(),
            hidden: layoutHiddenDraft.slice()
        });
        settingsMessage = "Quick Settings layout updated";
    }

    function resetQuickSettingsLayout() {
        if (activeMonitorName.length === 0)
            return;
        queueStateCommand(["reset-quick-settings-layout", activeMonitorName]);
        savedLayout = ({
            order: layoutOrderDraft.slice(),
            hidden: layoutHiddenDraft.slice()
        });
        settingsMessage = "Stock Quick Settings layout restored";
    }

    function quickSettingsSectionVisible(sectionId) {
        return layoutHiddenDraft.indexOf(sectionId) < 0;
    }

    function visibleQuickSettingsSectionOrder() {
        const ordered = layoutOrderDraft.length > 0
            ? layoutOrderDraft
            : BarState.defaultQuickSettingsSectionOrder;
        return ordered.filter(sectionId => quickSettingsSectionVisible(sectionId));
    }

    function quickSettingsSectionRow(sectionId) {
        const visibleOrder = visibleQuickSettingsSectionOrder();
        const index = visibleOrder.indexOf(sectionId);
        if (index < 0)
            return 0;
        return FlyoutEdgeLayout.sectionRow(bottomEdgeLayout, index, visibleOrder.length);
    }

    function moveQuickSettingsSection(sectionId, delta) {
        const index = layoutOrderDraft.indexOf(sectionId);
        const target = index + delta;
        if (index < 0 || target < 0 || target >= layoutOrderDraft.length)
            return;
        const next = layoutOrderDraft.slice();
        const moved = next.splice(index, 1)[0];
        next.splice(target, 0, moved);
        layoutOrderDraft = next;
        persistQuickSettingsLayout();
        Qt.callLater(() => alignContentToBar());
    }

    function setQuickSettingsSectionVisible(sectionId, visible) {
        const currentlyVisible = quickSettingsSectionVisible(sectionId);
        if (currentlyVisible === visible)
            return;
        if (!visible && visibleQuickSettingsSectionOrder().length <= 1)
            return;
        const next = layoutHiddenDraft.slice();
        const index = next.indexOf(sectionId);
        if (visible && index >= 0)
            next.splice(index, 1);
        else if (!visible && index < 0)
            next.push(sectionId);
        layoutHiddenDraft = next;
        persistQuickSettingsLayout();
        Qt.callLater(() => alignContentToBar());
    }

    function resetQuickSettingsLayoutDraft() {
        layoutOrderDraft = BarState.defaultQuickSettingsSectionOrder.slice();
        layoutHiddenDraft = [];
        resetQuickSettingsLayout();
        Qt.callLater(() => alignContentToBar());
    }

    function schedulerByName(name) {
        const schedulers = schedulerStatus.schedulers || [];
        for (const scheduler of schedulers) {
            if (String(scheduler.name || "") === name)
                return scheduler;
        }
        return null;
    }

    function selectedScheduler() {
        return schedulerByName(selectedSchedulerName);
    }

    function syncSelectedScheduler() {
        const schedulers = schedulerStatus.schedulers || [];
        if (schedulers.length === 0) {
            selectedSchedulerName = "";
            schedulerArgsDraft = "";
            schedulerArgsDirty = false;
            return;
        }

        let selected = schedulerByName(selectedSchedulerName);
        if (!selected) {
            selected = schedulerByName(String(schedulerStatus.running || ""))
                || schedulerByName(String(schedulerStatus.last_selected || ""))
                || schedulers[0];
            selectedSchedulerName = String(selected.name || "");
            schedulerArgsDirty = false;
        }
        if (!schedulerArgsDirty)
            schedulerArgsDraft = String(selected.custom_args || "");
    }

    function selectScheduler(name) {
        selectedSchedulerName = name;
        const selected = schedulerByName(name);
        schedulerArgsDraft = selected ? String(selected.custom_args || "") : "";
        schedulerArgsDirty = false;
        schedulerEditorOpen = true;
        if (Boolean(schedulerStatus.available) && Boolean(schedulerStatus.authorized))
            queueAction(["scheduler-start", name], "Switching to " + name + "…");
    }

    function refreshStatus() {
        if (!quickSettingsWindow.visible)
            return;
        if (statusReader.running) {
            refreshPending = true;
            return;
        }
        statusLoading = true;
        refreshPending = false;
        statusReader.exec([
            backend,
            "--status-json",
            activeMonitorName,
            brightnessTarget.length > 0 ? brightnessTarget : activeMonitorName
        ]);
    }

    function queueAction(commandArgs, message) {
        const nextQueue = actionQueue.slice();
        nextQueue.push({ args: commandArgs, message: message || "" });
        actionQueue = nextQueue;
        runNextAction();
    }

    function runNextAction() {
        if (actionRunner.running || actionQueue.length === 0)
            return;
        const next = actionQueue[0];
        actionQueue = actionQueue.slice(1);
        actionMessage = next.message;
        actionError = "";
        actionRunner.exec([backend, "--action", ...next.args]);
    }

    function adjustBrightness(delta) {
        const target = brightnessTarget.length > 0 ? brightnessTarget : activeMonitorName;
        queueAction(["brightness-adjust", target, String(delta)],
            "Adjusting brightness on " + target + "…");
    }

    function setBrightnessPercent(percent) {
        const target = brightnessTarget.length > 0 ? brightnessTarget : activeMonitorName;
        queueAction(["brightness-percent", target,
            String(Math.max(0, Math.min(100, Math.round(percent))))],
            "Setting brightness on " + target + "…");
    }

    function nightLightScheduleLabel() {
        const start = String(nightLightStatus.schedule_start || "20:00");
        const end = String(nightLightStatus.schedule_end || "07:00");
        return start + " ~ " + end
            + (Boolean(nightLightStatus.schedule_next_day) ? " next day" : "");
    }

    function syncNightLightScheduleDraft() {
        nightLightScheduleStartDraft = String(nightLightStatus.schedule_start || "20:00");
        nightLightScheduleEndDraft = String(nightLightStatus.schedule_end || "07:00");
        const scheduled = Number(nightLightStatus.schedule_temperature);
        const current = Number(nightLightStatus.temperature);
        const temperature = Number.isFinite(scheduled) && scheduled >= 1000 && scheduled <= 20000
            ? scheduled
            : (Number.isFinite(current) && current >= 1000 && current <= 20000 ? current : 5000);
        nightLightScheduleTemperatureDraft = String(Math.round(temperature));
        nightLightScheduleError = "";
    }

    function toggleNightLightScheduleEditor() {
        if (!nightLightScheduleEditorOpen)
            syncNightLightScheduleDraft();
        nightLightScheduleEditorOpen = !nightLightScheduleEditorOpen;
        nightLightScheduleError = "";
    }

    function validNightLightScheduleTime(value) {
        return /^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/.test(String(value || "").trim());
    }

    function saveNightLightSchedule() {
        const start = String(nightLightScheduleStartDraft || "").trim();
        const end = String(nightLightScheduleEndDraft || "").trim();
        const temperature = Number(String(nightLightScheduleTemperatureDraft || "").trim());

        if (!validNightLightScheduleTime(start) || !validNightLightScheduleTime(end)) {
            nightLightScheduleError = "Use 24-hour HH:MM times";
            return;
        }
        if (start === end) {
            nightLightScheduleError = "Start and end times must be different";
            return;
        }
        if (!Number.isInteger(temperature) || temperature < 1000 || temperature > 20000) {
            nightLightScheduleError = "Color temperature must be 1000–20000K";
            return;
        }

        nightLightScheduleError = "";
        queueAction(["night-light-schedule", "set", start, end, String(temperature)],
            "Saving Night Light schedule…");
    }

    function disableNightLightSchedule() {
        nightLightScheduleError = "";
        queueAction(["night-light-schedule", "disable"], "Disabling Night Light schedule…");
    }

    function openSmtty() {
        Quickshell.execDetached([terminalLauncher, "--class", "smtty", "--", "smtty"]);
        close();
    }

    function openAwtarchyTips() {
        Quickshell.execDetached([
            terminalLauncher, "--class", "awtarchy-tips-tui", "--", "bash",
            configHome + "/hypr/scripts/awtarchy-tips-tui.sh", "--tui"
        ]);
        close();
    }

    function openLockscreenEditor() {
        const target = root.activeScreen;
        root.close();
        Qt.callLater(() => LockscreenEditor.openForScreen(target));
    }

    function saveLockscreenWeatherLocation() {
        const value = String(lockscreenWeatherLocationDraft || "").trim();
        const points = Array.from(value);
        if (points.length > 96 || /[\u0000-\u001f\u007f-\u009f]/.test(value)) {
            lockscreenWeatherLocationError = "Use at most 96 characters with no control characters";
            return;
        }
        lockscreenWeatherLocationError = "";
        lockscreenWeatherLocationDraft = value;
        root.queueStateCommand(["set-lockscreen-weather-location", value]);
    }

    function resetLockscreenPresentation() {
        lockscreenWeatherLocationDraft = "";
        lockscreenWeatherLocationError = "";
        root.queueStateCommand(["reset-lockscreen-presentation"]);
    }

    function openSchedulerAuthorization() {
        if (schedulerAuthBusy)
            return;
        schedulerAuthOpen = true;
        schedulerAuthError = "";
        actionError = "";
        actionMessage = "sched-ext authorization required";
        Qt.callLater(() => schedulerPasswordInput.forceActiveFocus());
    }

    function cancelSchedulerAuthorization() {
        if (schedulerAuthBusy)
            return;
        schedulerAuthOpen = false;
        schedulerAuthError = "";
        schedulerAuthPendingPassword = "";
        schedulerPasswordInput.text = "";
    }

    function submitSchedulerAuthorization() {
        if (schedulerAuthBusy)
            return;
        if (schedulerPasswordInput.text.length === 0) {
            schedulerAuthError = "Enter your sudo password";
            schedulerPasswordInput.forceActiveFocus();
            return;
        }

        schedulerAuthPendingPassword = schedulerPasswordInput.text;
        schedulerPasswordInput.text = "";
        schedulerAuthError = "";
        actionError = "";
        schedulerAuthBusy = true;
        actionMessage = "Authorizing sched-ext…";
        schedulerAuthRunner.exec([backend, "--authorize-scheduler-stdin"]);
    }

    function openThemeMenu() {
        ThemePicker.toggleForScreen(activeScreen);
    }

    function toggleNumlockSessionStart() {
        numlockSettings.disableNumlockAtSessionStart = !numlockSettings.disableNumlockAtSessionStart;
        if (numlockSettings.disableNumlockAtSessionStart) {
            NumlockSessionTweak.enforce();
            actionMessage = "Num Lock will be disabled at session start";
        } else {
            actionMessage = "Num Lock session-start override disabled";
        }
    }

    function loadSavedView(targetScreen) {
        if (!targetScreen)
            return;
        const persisted = BarState.quickSettingsViewFor(targetScreen.name);
        panelWidthOverride = clampWidth(persisted.width);
        panelHeightOverride = clampHeight(persisted.height);
        textScaleOverride = persisted.textScale;
        iconScaleOverride = persisted.iconScale;
        captureAllowedOverride = BarState.captureAllowedFor("quick_settings") ? 1 : 0;
        const layout = BarState.quickSettingsLayoutFor(targetScreen.name);
        layoutOrderDraft = layout.order.slice();
        layoutHiddenDraft = layout.hidden.slice();
        savedLayout = ({ order: layoutOrderDraft.slice(), hidden: layoutHiddenDraft.slice() });
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: textScaleOverride,
            iconScale: iconScaleOverride,
            captureAllowed: captureAllowed
        });
    }

    function acceptDraftAsSaved() {
        savedView = ({
            width: livePanelWidth,
            height: livePanelHeight,
            textScale: effectiveTextScale,
            iconScale: effectiveIconScale,
            captureAllowed: captureAllowed
        });
        savedLayout = ({
            order: layoutOrderDraft.slice(),
            hidden: layoutHiddenDraft.slice()
        });
    }

    function discardDraft() {
        const width = savedView.width;
        const height = savedView.height;
        textScaleOverride = savedView.textScale;
        iconScaleOverride = savedView.iconScale;
        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;
        layoutOrderDraft = savedLayout.order.slice();
        layoutHiddenDraft = savedLayout.hidden.slice();
        applyWindowSize(width, height);
    }

    function queueStateCommand(commandArgs) {
        const nextQueue = stateCommandQueue.slice();
        nextQueue.push(commandArgs);
        stateCommandQueue = nextQueue;
        runNextStateCommand();
    }

    function runNextStateCommand() {
        if (stateWriter.running || stateCommandQueue.length === 0)
            return;
        const nextCommand = stateCommandQueue[0];
        stateCommandQueue = stateCommandQueue.slice(1);
        stateWriter.exec([stateScript, ...nextCommand]);
    }

    function saveDisplaySettings() {
        if (activeMonitorName.length === 0)
            return;
        queueStateCommand([
            "save-flyout", "quick-settings", activeMonitorName,
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            captureAllowed ? "true" : "false"
        ]);
        panelWidthOverride = livePanelWidth;
        panelHeightOverride = livePanelHeight;
        acceptDraftAsSaved();
        settingsMessage = "Saved Quick Settings for " + activeMonitorName;
    }

    function resetDisplaySettings() {
        if (activeMonitorName.length === 0)
            return;
        const wasCaptureAllowed = captureAllowed;
        textScaleOverride = 100;
        iconScaleOverride = 100;
        captureAllowedOverride = 0;
        layoutOrderDraft = BarState.defaultQuickSettingsSectionOrder.slice();
        layoutHiddenDraft = [];
        savedLayout = ({ order: layoutOrderDraft.slice(), hidden: [] });
        applyWindowSize(BarState.defaultQuickSettingsWidth, BarState.defaultQuickSettingsHeight);
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: 100,
            iconScale: 100,
            captureAllowed: false
        });
        privacyRemapPending = wasCaptureAllowed;
        queueStateCommand(["reset-flyout", "quick-settings", activeMonitorName]);
        queueStateCommand(["reset-quick-settings-layout", activeMonitorName]);
        settingsMessage = "Quick Settings defaults restored for " + activeMonitorName;
    }

    function copyDisplaySettings(targets) {
        if (!targets || targets.length === 0)
            return;
        queueStateCommand([
            "copy-flyout", "quick-settings",
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            ...targets
        ]);
        queueStateCommand([
            "copy-quick-settings-layout",
            JSON.stringify(layoutOrderDraft), JSON.stringify(layoutHiddenDraft),
            ...targets
        ]);
        settingsMessage = "Copied Quick Settings to " + targets.length
            + (targets.length === 1 ? " display" : " displays");
    }

    function adjustPanelWidth(delta) {
        applyWindowSize(livePanelWidth + delta, livePanelHeight);
        settingsMessage = "Width " + panelWidthOverride + " px";
    }

    function adjustPanelHeight(delta) {
        applyWindowSize(livePanelWidth, livePanelHeight + delta);
        settingsMessage = "Height " + panelHeightOverride + " px";
    }

    function adjustTextScale(delta) {
        textScaleOverride = Math.max(50, Math.min(200, effectiveTextScale + delta));
        settingsMessage = "Text size " + textScaleOverride + "%";
    }

    function adjustIconScale(delta) {
        iconScaleOverride = Math.max(50, Math.min(200, effectiveIconScale + delta));
        settingsMessage = "Icon size " + iconScaleOverride + "%";
    }

    function toggleCaptureAllowed() {
        const next = !captureAllowed;
        captureAllowedOverride = next ? 1 : 0;
        savedView = Object.assign({}, savedView, { captureAllowed: next });
        privacyRemapPending = true;
        queueStateCommand(["set-capture", "quick-settings", next ? "true" : "false"]);
        settingsMessage = next
            ? "Quick Settings is visible in captures" : "Quick Settings capture protection enabled";
    }

    function toggleSettings() {
        settingsOpen = !settingsOpen;
        layoutEditorOpen = false;
        if (settingsOpen) {
            barIconsOpen = false;
            barAppearanceOpen = false;
            barVisibilityOpen = false;
            barAppearanceSettings.resetTransientState();
        }
        settingsPanel.resetTransientState();
        settingsMessage = "";
        Qt.callLater(() => root.resizeForSettingsMode());
    }

    function openForScreen(targetScreen) {
        if (!targetScreen)
            return;
        FlyoutManager.claim("quick-settings", targetScreen.name);
        flyoutScreen = targetScreen;
        if (!quickSettingsWindow.visible)
            quickSettingsWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        brightnessTarget = targetScreen.name;
        settingsOpen = false;
        layoutEditorOpen = false;
        barIconsOpen = false;
        barAppearanceOpen = false;
        barVisibilityOpen = false;
        settingsPanel.resetTransientState();
        barAppearanceSettings.resetTransientState();
        settingsMessage = "";
        schedulerEditorOpen = false;
        schedulerArgsDirty = false;
        nightLightScheduleEditorOpen = false;
        nightLightScheduleError = "";
        lockscreenWeatherLocationDraft = BarState.lockscreenWeatherLocation();
        lockscreenWeatherLocationError = "";
        loadSavedView(targetScreen);
        prepareWindowOpen(targetScreen);
    }

    function openFocused() { openForScreen(focusedScreen()); }

    function close() {
        openPreparing = false;
        if (prepareProcess.running)
            prepareProcess.running = false;
        if (settingsDirty)
            discardDraft();
        quickSettingsWindow.visible = false;
        panelPresented = false;
        FlyoutManager.release("quick-settings");
        settingsOpen = false;
        layoutEditorOpen = false;
        barIconsOpen = false;
        barAppearanceOpen = false;
        barVisibilityOpen = false;
        settingsPanel.resetTransientState();
        barAppearanceSettings.resetTransientState();
        settingsMessage = "";
        schedulerEditorOpen = false;
        nightLightScheduleEditorOpen = false;
        nightLightScheduleError = "";
        if (!schedulerAuthBusy)
            cancelSchedulerAuthorization();
        else
            schedulerPasswordInput.text = "";
        brightnessHoverPercent = -1;
        outputVolumeHoverPercent = -1;
    }

    function toggleForScreen(targetScreen) {
        if (!FlyoutManager.acceptToggle("quick-settings"))
            return;
        const currentName = activeMonitorName;
        const targetName = targetScreen ? targetScreen.name : "";
        if ((quickSettingsWindow.visible || openPreparing)
            && currentName.length > 0 && currentName === targetName)
            close();
        else
            openForScreen(targetScreen);
    }

    FileView {
        id: quickSettingsTweaksFile
        path: Quickshell.statePath("quick-settings-tweaks.json")
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            if (numlockSettings.disableNumlockAtSessionStart)
                Qt.callLater(() => NumlockSessionTweak.enforce());
        }

        JsonAdapter {
            id: numlockSettings
            property bool disableNumlockAtSessionStart: false
        }
    }


    IpcHandler {
        target: "quicksettings"
        function toggle(): void { root.toggleForScreen(root.focusedScreen()); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
        function refresh(): void { root.refreshStatus(); }
    }

    Timer {
        interval: 1800
        repeat: false
        running: true
        onTriggered: {
            if (!schedulerRestoreRunner.running)
                schedulerRestoreRunner.exec([backend, "--restore-scheduler"]);
        }
    }

    Process {
        id: schedulerRestoreRunner
        onExited: {
            if (quickSettingsWindow.visible)
                root.refreshStatus();
        }
    }

    Process {
        id: prepareProcess
        onExited: root.finishPreparedOpen()
    }

    Process {
        id: statusReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "{}");
                    root.statusData = parsed && typeof parsed === "object"
                        ? parsed : root.emptyStatus();
                    const nextPlacement = String((root.statusData.bar || ({})).position || "");
                    if (!Boolean((root.statusData.bar || ({})).enabled))
                        root.placement = "center";
                    else if (["top", "bottom", "left", "right"].indexOf(nextPlacement) >= 0)
                        root.placement = nextPlacement;
                    root.syncSelectedScheduler();
                } catch (error) {
                    console.warn("Awtarchy Quick Settings status parse failed:", error);
                    root.actionMessage = "Quick Settings status unavailable";
                }
            }
        }
        onExited: {
            root.statusLoading = false;
            if (root.refreshPending)
                Qt.callLater(() => root.refreshStatus());
        }
    }

    Process {
        id: actionRunner
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.actionError = errorText.split("\n")[0];
            }
        }
        onExited: {
            if (root.actionError.length > 0)
                root.actionMessage = root.actionError;
            else
                root.actionMessage = "Updated";
            root.refreshStatus();
            Qt.callLater(() => root.runNextAction());
        }
    }

    Process {
        id: schedulerAuthRunner
        stdinEnabled: true
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.schedulerAuthError = errorText.split("\n")[0];
            }
        }
        onStarted: {
            // sudo may request up to three attempts. Extra blank responses make
            // a wrong password fail promptly instead of leaving a hidden process
            // blocked waiting for another line of input.
            schedulerAuthRunner.write(root.schedulerAuthPendingPassword + "\n\n\n");
            root.schedulerAuthPendingPassword = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.schedulerAuthPendingPassword = "";
            root.schedulerAuthBusy = false;
            if (exitCode === 0) {
                root.schedulerAuthOpen = false;
                root.schedulerAuthError = "";
                root.actionMessage = "sched-ext authorization complete";
                root.refreshStatus();
                return;
            }

            if (root.schedulerAuthError.length === 0)
                root.schedulerAuthError = "sched-ext authorization failed";
            root.actionMessage = root.schedulerAuthError;
            if (quickSettingsWindow.visible)
                Qt.callLater(() => schedulerPasswordInput.forceActiveFocus());
        }
    }

    Process {
        id: stateWriter
        onExited: {
            BarState.refresh();
            privacyRuleUpdater.exec([root.configHome + "/hypr/scripts/quickshell_runtime_rules.sh"]);
            Qt.callLater(() => root.runNextStateCommand());
        }
    }

    Process {
        id: privacyRuleUpdater
        onExited: {
            if (!root.privacyRemapPending)
                return;
            root.privacyRemapPending = false;
            if (!quickSettingsWindow.visible)
                return;
            quickSettingsWindow.visible = false;
            Qt.callLater(() => {
                quickSettingsWindow.visible = true;
                root.positionWindow();
            });
        }
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "quick-settings"
                && (quickSettingsWindow.visible || root.openPreparing))
                root.close();
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: quickSettingsWindow.visible
        onTriggered: root.refreshStatus()
    }


    FloatingWindow {
        id: quickSettingsWindow
        visible: false
        title: "Awtarchy Quick Settings"
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: root.configuredPanelWidth
        implicitHeight: root.settingsOpen ? root.settingsModePanelHeight : root.configuredPanelHeight
        minimumSize: Qt.size(root.minimumPanelWidth,
            root.settingsOpen ? root.minimumSettingsPanelHeight : root.minimumPanelHeight)
        maximumSize: Qt.size(root.maximumPanelWidth, root.maximumPanelHeight)
        onClosed: root.close()
        onVisibleChanged: {
            if (visible) {
                Qt.callLater(() => root.positionWindow());
                Qt.callLater(() => root.alignContentToBar());
            }
        }

        Rectangle {
            id: panel
            opacity: root.panelPresented ? 1 : 0

            Behavior on opacity {
                enabled: FlyoutManager.animationsEnabled
                NumberAnimation {
                    duration: root.panelFadeDuration
                    easing.type: Easing.OutCubic
                }
            }
            anchors.fill: parent
            color: Theme.popupBackground
            radius: 0
            focus: true
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: mouse => mouse.accepted = true
            }

            PowerModeCard {
                active: quickSettingsWindow.visible
                textScale: root.effectiveTextScale
                iconScale: root.effectiveIconScale
            }

            GridLayout {
                anchors.fill: parent
                columns: 1
                rowSpacing: 0
                columnSpacing: 0

                Rectangle {
                    id: headerBar
                    Layout.row: root.bottomEdgeLayout ? 2 : 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: Theme.active
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 40
                        spacing: 6

                        Text {
                            text: ""
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledIcon(14)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.actionMessage.length > 0
                                ? "Quick Settings · " + root.actionMessage
                                : "Quick Settings"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledText(13)
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            text: "SUPER+ALT+BACKSPACE"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledText(8)
                        }

                        SettingsButton {
                            label: root.statusLoading ? "…" : "↻"
                            textSize: root.scaledText(11)
                            onClicked: root.refreshStatus()
                        }

                        SettingsButton {
                            label: "?"
                            textSize: root.scaledText(11)
                            onClicked: root.openAwtarchyTips()
                        }

                        SettingsButton {
                            label: ""
                            available: root.settingsDirty
                            textSize: root.scaledIcon(12)
                            onClicked: root.saveDisplaySettings()
                        }

                        CaptureEyeButton {
                            captureAllowed: root.captureAllowed
                            textSize: root.scaledIcon(12)
                            onClicked: root.toggleCaptureAllowed()
                        }

                        SettingsButton {
                            label: ""
                            active: root.settingsOpen
                            textSize: root.scaledIcon(11)
                            onClicked: root.toggleSettings()
                        }
                    }

                    Rectangle {
                        id: closeButton
                        width: 28
                        height: 28
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: closeMouse.containsMouse ? Theme.focus : Theme.active
                        border.width: 1
                        border.color: closeMouse.containsMouse ? Theme.focus : Theme.muted
                        radius: 0
                        z: 20

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: root.scaledIcon(15)
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                Rectangle {
                    Layout.row: 1
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.settingsOpen
                        ? (root.layoutEditorOpen ? layoutEditor.implicitHeight : settingsPanel.implicitHeight) + 12
                        : 0
                    visible: root.settingsOpen
                    color: Theme.popupButton
                    border.width: 0
                    clip: true

                    FlyoutSettings {
                        id: settingsPanel
                        anchors.fill: parent
                        anchors.margins: 6
                        visible: !root.layoutEditorOpen
                        surfaceLabel: "Quick Settings"
                        monitorName: root.activeMonitorName
                        panelWidth: root.livePanelWidth
                        panelHeight: root.livePanelHeight
                        minimumWidth: root.minimumPanelWidth
                        maximumWidth: root.maximumPanelWidth
                        minimumHeight: root.minimumPanelHeight
                        maximumHeight: root.maximumPanelHeight
                        textScale: root.effectiveTextScale
                        iconScale: root.effectiveIconScale
                        captureAllowed: root.captureAllowed
                        message: root.settingsMessage
                        otherMonitorNames: root.otherMonitorNames()
                        quickSettingsOrder: root.layoutOrderDraft
                        quickSettingsHidden: root.layoutHiddenDraft

                        onResetRequested: root.resetDisplaySettings()
                        onWidthAdjustmentRequested: delta => root.adjustPanelWidth(delta)
                        onHeightAdjustmentRequested: delta => root.adjustPanelHeight(delta)
                        onTextScaleAdjustmentRequested: delta => root.adjustTextScale(delta)
                        onIconScaleAdjustmentRequested: delta => root.adjustIconScale(delta)
                        onCaptureToggleRequested: root.toggleCaptureAllowed()
                        onCopyRequested: monitorNames => root.copyDisplaySettings(monitorNames)
                        onThemePickerRequested: root.openThemeMenu()
                        onQuickSettingsVisibilityRequested: (sectionId, visible) =>
                            root.setQuickSettingsSectionVisible(sectionId, visible)
                        onQuickSettingsLayoutResetRequested: root.resetQuickSettingsLayoutDraft()
                        onLayoutEditorRequested: {
                            settingsPanel.resetTransientState();
                            root.layoutEditorOpen = true;
                        }
                    }

                    QuickSettingsLayoutEditor {
                        id: layoutEditor
                        anchors.fill: parent
                        anchors.margins: 6
                        visible: root.layoutEditorOpen
                        monitorName: root.activeMonitorName
                        order: root.layoutOrderDraft
                        hidden: root.layoutHiddenDraft
                        onBackRequested: root.layoutEditorOpen = false
                        onMoveRequested: (sectionId, delta) => root.moveQuickSettingsSection(sectionId, delta)
                        onVisibilityRequested: (sectionId, visible) => root.setQuickSettingsSectionVisible(sectionId, visible)
                        onResetRequested: root.resetQuickSettingsLayoutDraft()
                    }
                }

                Flickable {
                    id: contentFlick
                    visible: !root.settingsOpen
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: !root.settingsOpen
                    Layout.preferredHeight: root.settingsOpen ? 0 : -1
                    Layout.maximumHeight: root.settingsOpen ? 0 : root.maximumPanelHeight
                    Layout.bottomMargin: 0
                    contentWidth: width
                    contentHeight: Math.max(height, settingsColumn.implicitHeight + 12)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    GridLayout {
                        id: settingsColumn
                        columns: 1
                        x: 6
                        y: root.bottomEdgeLayout
                            ? Math.max(6, contentFlick.contentHeight - implicitHeight - 6) : 6
                        width: contentFlick.width - (contentScrollBar.visible ? 26 : 12)
                        rowSpacing: 8
                        columnSpacing: 0

                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("brightness")
                            visible: root.quickSettingsSectionVisible("brightness")
                            Layout.fillWidth: true
                            Layout.preferredHeight: brightnessContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: brightnessContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Brightness · " + (root.brightnessTarget || root.activeMonitorName)
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: root.brightnessPercent >= 0
                                            ? root.brightnessPercent + "%  (" + root.brightnessStatus.current
                                                + "/" + root.brightnessStatus.max + ")"
                                            : "Unavailable"
                                        color: root.brightnessPercent >= 0 ? Theme.foreground : Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5

                                    Repeater {
                                        model: root.monitorNames()
                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData)
                                            active: root.brightnessTarget === String(modelData)
                                            textSize: root.scaledText(9)
                                            onClicked: {
                                                root.brightnessTarget = String(modelData);
                                                root.refreshStatus();
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    SettingsButton {
                                        label: "−5"
                                        available: root.brightnessPercent >= 0
                                        textSize: root.scaledText(10)
                                        onClicked: root.adjustBrightness(-5)
                                    }

                                    Rectangle {
                                        id: brightnessTrack
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        color: Theme.active
                                        border.width: 0

                                        Rectangle {
                                            width: root.brightnessPercent >= 0
                                                ? parent.width * root.brightnessPercent / 100 : 0
                                            height: parent.height
                                            color: Theme.focus
                                        }

                                        Rectangle {
                                            visible: root.brightnessHoverPercent >= 0
                                            width: 46
                                            height: 21
                                            x: Math.max(0, Math.min(parent.width - width,
                                                parent.width * root.brightnessHoverPercent / 100 - width / 2))
                                            y: -25
                                            color: Theme.background
                                            border.width: 1
                                            border.color: Theme.focus
                                            z: 4

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.brightnessHoverPercent + "%"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(9)
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: root.brightnessPercent >= 0
                                            hoverEnabled: true
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onPositionChanged: mouse => root.brightnessHoverPercent = Math.max(0,
                                                Math.min(100, Math.round(mouse.x * 100 / width)))
                                            onExited: root.brightnessHoverPercent = -1
                                            onPressed: mouse => root.setBrightnessPercent(mouse.x * 100 / width)
                                        }
                                    }

                                    SettingsButton {
                                        label: "+5"
                                        available: root.brightnessPercent >= 0
                                        textSize: root.scaledText(10)
                                        onClicked: root.adjustBrightness(5)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "SUPER+ALT+- decrease 5%  ·  SUPER+ALT+= increase 5%  ·  scroll does not change this slider"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("output-volume")
                            visible: root.quickSettingsSectionVisible("output-volume")
                            Layout.fillWidth: true
                            Layout.preferredHeight: outputVolumeContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: outputVolumeContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Maximum output volume"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                    }

                                    Text {
                                        text: AudioLimitState.limitPercent + "%"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    SettingsButton {
                                        label: "−5"
                                        available: AudioLimitState.limitPercent > AudioLimitState.minimumPercent
                                        textSize: root.scaledText(10)
                                        onClicked: AudioLimitState.setLimit(
                                            AudioLimitState.limitPercent - AudioLimitState.stepPercent)
                                    }

                                    Rectangle {
                                        id: outputVolumeTrack
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        color: Theme.active
                                        border.width: 0

                                        Rectangle {
                                            width: parent.width
                                                * (AudioLimitState.limitPercent - AudioLimitState.minimumPercent)
                                                / (AudioLimitState.maximumPercent - AudioLimitState.minimumPercent)
                                            height: parent.height
                                            color: Theme.focus
                                        }

                                        Rectangle {
                                            visible: root.outputVolumeHoverPercent >= 0
                                            width: 46
                                            height: 21
                                            x: {
                                                const ratio = (root.outputVolumeHoverPercent
                                                    - AudioLimitState.minimumPercent)
                                                    / (AudioLimitState.maximumPercent
                                                        - AudioLimitState.minimumPercent);
                                                return Math.max(0, Math.min(parent.width - width,
                                                    parent.width * ratio - width / 2));
                                            }
                                            y: -25
                                            color: Theme.background
                                            border.width: 1
                                            border.color: Theme.focus
                                            z: 4

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.outputVolumeHoverPercent + "%"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(9)
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onPositionChanged: mouse => root.outputVolumeHoverPercent
                                                = root.outputLimitForPosition(mouse.x, width)
                                            onExited: root.outputVolumeHoverPercent = -1
                                            onPressed: mouse => {
                                                root.outputVolumeHoverPercent
                                                    = root.outputLimitForPosition(mouse.x, width);
                                                AudioLimitState.setLimit(root.outputVolumeHoverPercent);
                                            }
                                        }
                                    }

                                    SettingsButton {
                                        label: "+5"
                                        available: AudioLimitState.limitPercent < AudioLimitState.maximumPercent
                                        textSize: root.scaledText(10)
                                        onClicked: AudioLimitState.setLimit(
                                            AudioLimitState.limitPercent + AudioLimitState.stepPercent)
                                    }

                                    SettingsButton {
                                        label: "100%"
                                        available: AudioLimitState.limitPercent !== 100
                                        textSize: root.scaledText(9)
                                        onClicked: AudioLimitState.setLimit(100)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Global limit for Wiremix and bar volume scrolling · click bar to set · range 100–200%"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }
                            }
                        }


                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("bar")
                            visible: root.quickSettingsSectionVisible("bar")
                            Layout.fillWidth: true
                            Layout.preferredHeight: barContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: barContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Bar · " + root.activeMonitorName
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                    }

                                    SettingsButton {
                                        label: "Themes"
                                        active: ThemePicker.open
                                        textSize: root.scaledText(9)
                                        onClicked: root.openThemeMenu()
                                    }

                                    SettingsButton {
                                        label: "Icons"
                                        active: root.barIconsOpen
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.barIconsOpen = !root.barIconsOpen;
                                            root.barAppearanceOpen = false;
                                            root.barVisibilityOpen = false;
                                            barAppearanceSettings.resetTransientState();
                                            if (root.bottomEdgeLayout)
                                                Qt.callLater(() => root.alignContentToBar());
                                        }
                                    }

                                    SettingsButton {
                                        label: "Appearance"
                                        active: root.barAppearanceOpen
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.barAppearanceOpen = !root.barAppearanceOpen;
                                            root.barIconsOpen = false;
                                            root.barVisibilityOpen = false;
                                            if (!root.barAppearanceOpen)
                                                barAppearanceSettings.resetTransientState();
                                            if (root.bottomEdgeLayout)
                                                Qt.callLater(() => root.alignContentToBar());
                                        }
                                    }

                                    SettingsButton {
                                        label: root.barStatus.enabled ? "Visible" : "Hidden"
                                        active: root.barVisibilityOpen
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.barVisibilityOpen = !root.barVisibilityOpen;
                                            root.barIconsOpen = false;
                                            root.barAppearanceOpen = false;
                                            barAppearanceSettings.resetTransientState();
                                            if (root.bottomEdgeLayout)
                                                Qt.callLater(() => root.alignContentToBar());
                                        }
                                    }

                                    SettingsButton {
                                        label: root.barStatus.auto_hide ? "Auto-hide: On" : "Auto-hide: Off"
                                        active: Boolean(root.barStatus.auto_hide)
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction([
                                            "bar-auto-hide", root.activeMonitorName,
                                            root.barStatus.auto_hide ? "false" : "true"
                                        ], root.barStatus.auto_hide
                                            ? "Disabling bar auto-hide…" : "Enabling bar auto-hide…")
                                    }
                                }

                                RowLayout {
                                    visible: root.barVisibilityOpen
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: visible ? 28 : 0
                                    spacing: 5

                                    Text {
                                        text: "Visible on workspaces"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                    }

                                    Repeater {
                                        model: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData)
                                            active: BarState.workspaceVisible(Number(modelData))
                                            textSize: root.scaledText(9)
                                            horizontalPadding: 9
                                            onClicked: root.queueStateCommand([
                                                "set-bar-workspace-visible", String(modelData),
                                                BarState.workspaceVisible(Number(modelData))
                                                    ? "false" : "true"
                                            ])
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    RowLayout {
                                        spacing: 5
                                        Repeater {
                                            model: ["top", "bottom", "left", "right"]
                                            SettingsButton {
                                                required property var modelData
                                                label: String(modelData)
                                                active: String(root.barStatus.position) === String(modelData)
                                                textSize: root.scaledText(9)
                                                onClicked: root.queueAction([
                                                    "bar-position", root.activeMonitorName, String(modelData)
                                                ], "Moving bar to " + String(modelData) + "…")
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Themes: SUPER+T"
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            horizontalAlignment: Text.AlignRight
                                            wrapMode: Text.Wrap
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Position: SUPER+Mouse1 / ALT+Mouse1 drag · CTRL+SUPER+B / SUPER+ALT+B change edge"
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            horizontalAlignment: Text.AlignRight
                                            wrapMode: Text.Wrap
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Auto-hide: CTRL+SUPER+ALT+B toggle"
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }

                                BarIconSettings {
                                    Layout.fillWidth: true
                                    visible: root.barIconsOpen
                                }

                                BarSettingsSection {
                                    id: barAppearanceSettings
                                    Layout.fillWidth: true
                                    visible: root.barAppearanceOpen
                                    active: quickSettingsWindow.visible
                                        && root.quickSettingsSectionVisible("bar")
                                        && root.barAppearanceOpen
                                    monitorName: root.activeMonitorName
                                    monitorNames: [root.activeMonitorName]
                                        .concat(root.otherMonitorNames())
                                }
                            }
                        }

                        RowLayout {
                            id: nightLightVibranceRow
                            readonly property real cardHeight: Math.max(nightContent.implicitHeight, vibranceContent.implicitHeight) + 16
                            Layout.row: root.quickSettingsSectionRow("display-effects")
                            visible: root.quickSettingsSectionVisible("display-effects")
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: nightLightVibranceRow.cardHeight
                                color: Theme.popupButton
                                border.width: 1
                                border.color: Theme.active

                                ColumnLayout {
                                    id: nightContent
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Night Light · "
                                            + (root.nightLightStatus.temperature === null
                                                || root.nightLightStatus.temperature === undefined
                                                ? "N/A" : root.nightLightStatus.temperature + "K")
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(11)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    RowLayout {
                                        SettingsButton {
                                            label: "Warmer"
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction(["night-light", "down"], "Making display warmer…")
                                        }
                                        SettingsButton {
                                            label: root.nightLightStatus.enabled ? "On" : "Off"
                                            active: Boolean(root.nightLightStatus.enabled)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction(["night-light", "toggle"], "Toggling Night Light…")
                                        }
                                        SettingsButton {
                                            label: "Cooler"
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction(["night-light", "up"], "Making display cooler…")
                                        }
                                    }

                                    SettingsButton {
                                        Layout.fillWidth: true
                                        label: "Set schedule: " + root.nightLightScheduleLabel()
                                        active: Boolean(root.nightLightStatus.schedule_enabled)
                                        textSize: root.scaledText(9)
                                        onClicked: root.toggleNightLightScheduleEditor()
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: root.nightLightScheduleEditorOpen
                                        spacing: 5

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.nightLightStatus.schedule_enabled
                                                ? "Schedule enabled" : "Schedule disabled"
                                            color: root.nightLightStatus.schedule_enabled
                                                ? Theme.foreground : Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            Text {
                                                text: "Start"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(8)
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 27
                                                color: Theme.active
                                                border.width: 1
                                                border.color: nightLightScheduleStartInput.activeFocus
                                                    ? Theme.focus : Theme.muted
                                                TextInput {
                                                    id: nightLightScheduleStartInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 6
                                                    anchors.rightMargin: 6
                                                    text: root.nightLightScheduleStartDraft
                                                    color: Theme.foreground
                                                    selectionColor: Theme.focus
                                                    selectedTextColor: Theme.foreground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root.scaledText(8)
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    selectByMouse: true
                                                    clip: true
                                                    onTextEdited: root.nightLightScheduleStartDraft = text
                                                }
                                            }

                                            Text {
                                                text: "End"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(8)
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 27
                                                color: Theme.active
                                                border.width: 1
                                                border.color: nightLightScheduleEndInput.activeFocus
                                                    ? Theme.focus : Theme.muted
                                                TextInput {
                                                    id: nightLightScheduleEndInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 6
                                                    anchors.rightMargin: 6
                                                    text: root.nightLightScheduleEndDraft
                                                    color: Theme.foreground
                                                    selectionColor: Theme.focus
                                                    selectedTextColor: Theme.foreground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root.scaledText(8)
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    selectByMouse: true
                                                    clip: true
                                                    onTextEdited: root.nightLightScheduleEndDraft = text
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            Text {
                                                text: "Color temp"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(8)
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 27
                                                color: Theme.active
                                                border.width: 1
                                                border.color: nightLightScheduleTemperatureInput.activeFocus
                                                    ? Theme.focus : Theme.muted
                                                TextInput {
                                                    id: nightLightScheduleTemperatureInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 6
                                                    anchors.rightMargin: 6
                                                    text: root.nightLightScheduleTemperatureDraft
                                                    color: Theme.foreground
                                                    selectionColor: Theme.focus
                                                    selectedTextColor: Theme.foreground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root.scaledText(8)
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    selectByMouse: true
                                                    clip: true
                                                    onTextEdited: root.nightLightScheduleTemperatureDraft = text
                                                }
                                            }
                                            Text {
                                                text: "K"
                                                color: Theme.muted
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(8)
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            visible: root.nightLightScheduleError.length > 0
                                            text: root.nightLightScheduleError
                                            color: Theme.urgent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            wrapMode: Text.Wrap
                                        }

                                        Flow {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: childrenRect.height
                                            spacing: 5

                                            SettingsButton {
                                                label: root.nightLightStatus.schedule_enabled
                                                    ? "Save" : "Save & Enable"
                                                textSize: root.scaledText(8)
                                                onClicked: root.saveNightLightSchedule()
                                            }
                                            SettingsButton {
                                                visible: Boolean(root.nightLightStatus.schedule_enabled)
                                                label: "Disable"
                                                textSize: root.scaledText(8)
                                                onClicked: root.disableNightLightSchedule()
                                            }
                                            SettingsButton {
                                                label: "Cancel"
                                                textSize: root.scaledText(8)
                                                onClicked: root.toggleNightLightScheduleEditor()
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "CTRL+SUPER+ALT+[ warmer  ·  CTRL+SUPER+ALT+] cooler  ·  CTRL+SUPER+ALT+N toggle"
                                        color: Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(8)
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: nightLightVibranceRow.cardHeight
                                color: Theme.popupButton
                                border.width: 1
                                border.color: Theme.active

                                ColumnLayout {
                                    id: vibranceContent
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Vibrance · "
                                            + (root.vibranceStatus.value === null
                                                || root.vibranceStatus.value === undefined
                                                ? "N/A" : Number(root.vibranceStatus.value).toFixed(2))
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(11)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    RowLayout {
                                        SettingsButton {
                                            label: "−"
                                            textSize: root.scaledText(10)
                                            onClicked: root.queueAction(["vibrance", "down"], "Reducing vibrance…")
                                        }
                                        SettingsButton {
                                            label: root.vibranceStatus.enabled ? "On" : "Off"
                                            active: Boolean(root.vibranceStatus.enabled)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction(["vibrance", "toggle"], "Toggling vibrance…")
                                        }
                                        SettingsButton {
                                            label: "+"
                                            textSize: root.scaledText(10)
                                            onClicked: root.queueAction(["vibrance", "up"], "Increasing vibrance…")
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "SUPER+ALT+[ decrease  ·  SUPER+ALT+] increase  ·  CTRL+SUPER+ALT+V toggle"
                                        color: Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(8)
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("submap")
                            visible: root.quickSettingsSectionVisible("submap")
                            Layout.fillWidth: true
                            Layout.preferredHeight: submapContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: submapContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6
                                Text {
                                    text: "Hyprland Submap"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(11)
                                    font.bold: true
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5
                                    Repeater {
                                        model: [
                                            { value: "reset", label: "Off / Normal" },
                                            { value: "noalt", label: "noalt" },
                                            { value: "mouse", label: "mouse" },
                                            { value: "vm", label: "VM" }
                                        ]
                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData.label)
                                            active: String(root.statusData.submap || "reset") === String(modelData.value)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction([
                                                "submap", String(modelData.value)
                                            ], "Switching submap…")
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("wallpaper")
                            visible: root.quickSettingsSectionVisible("wallpaper")
                            Layout.fillWidth: true
                            Layout.preferredHeight: wallpaperContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: wallpaperContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Wallpaper Picker"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(11)
                                        font.bold: true
                                    }
                                    SettingsButton {
                                        label: "Open awtwall"
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.queueAction(["wallpaper"], "Opening wallpaper picker…");
                                            root.close();
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "SUPER+W open  ·  SUPER+SHIFT+W random current  ·  SUPER+CTRL+W random all  ·  SUPER+ALT+W random all, different"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("awtarchy")
                            visible: root.quickSettingsSectionVisible("awtarchy")
                            Layout.fillWidth: true
                            Layout.preferredHeight: awtarchyContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: awtarchyContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Awtarchy"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(11)
                                        font.bold: true
                                    }
                                    SettingsButton {
                                        label: "Awtarchy Tips"
                                        textSize: root.scaledText(9)
                                        onClicked: root.openAwtarchyTips()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Built-in manual for keybinds, Quickshell, display, gaming, packages, maintenance, networking, troubleshooting, and Extra Notes."
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }

                                CursorThemeSettings {
                                    id: awtarchyCursorThemeSection
                                    Layout.fillWidth: true
                                    active: quickSettingsWindow.visible
                                        && !root.settingsOpen
                                        && root.quickSettingsSectionVisible("awtarchy")
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Lockscreen Animation"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                    font.bold: true
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5

                                    Repeater {
                                        model: BarState.lockscreenAnimationPresets

                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData.label)
                                            active: BarState.lockscreenAnimationPreference()
                                                === String(modelData.key)
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueStateCommand([
                                                "set-lockscreen-animation", String(modelData.key)
                                            ])
                                        }
                                    }
                                }

                                RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "Lockscreen"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: root.scaledText(9)
                                font.bold: true
                            }

                            SettingsButton {
                                label: root.lockscreenSectionExpanded ? "Collapse" : "Expand"
                                active: root.lockscreenSectionExpanded
                                textSize: root.scaledText(9)
                                onClicked: root.lockscreenSectionExpanded = !root.lockscreenSectionExpanded
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.lockscreenSectionExpanded
                            spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                SettingsButton {
                                    label: "Edit Layout"
                                    active: true
                                    textSize: root.scaledText(9)
                                    onClicked: root.openLockscreenEditor()
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Drag enabled lockscreen elements on the focused display"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }
                            }

                            Text { Layout.fillWidth: true; text: "Background"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                SettingsButton {
                                    label: "Black"
                                    active: BarState.lockscreenBackground() === "black"
                                    textSize: root.scaledText(9)
                                    onClicked: root.queueStateCommand(["set-lockscreen-background", "black"])
                                }
                                SettingsButton {
                                    label: "Wallpaper"
                                    active: BarState.lockscreenBackground() === "wallpaper"
                                    textSize: root.scaledText(9)
                                    onClicked: root.queueStateCommand(["set-lockscreen-background", "wallpaper"])
                                }
                                Item { Layout.fillWidth: true }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 4

                                Text { Layout.fillWidth: true; text: "Mouse Interaction"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                SettingsButton { label: BarState.lockscreenMouseInteractiveEnabled() ? "On" : "Off"; active: BarState.lockscreenMouseInteractiveEnabled(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-mouse-interactive", BarState.lockscreenMouseInteractiveEnabled() ? "false" : "true"]) }
                                Text { Layout.fillWidth: true; text: "Audio Reactive"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                SettingsButton { label: BarState.lockscreenAudioReactiveEnabled() ? "On" : "Off"; active: BarState.lockscreenAudioReactiveEnabled(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-audio-reactive", BarState.lockscreenAudioReactiveEnabled() ? "false" : "true"]) }
                                Text { Layout.fillWidth: true; text: "Time"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                SettingsButton { label: BarState.lockscreenShowTime() ? "On" : "Off"; active: BarState.lockscreenShowTime(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-show-time", BarState.lockscreenShowTime() ? "false" : "true"]) }
                                Text { Layout.fillWidth: true; text: "Date"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                SettingsButton { label: BarState.lockscreenShowDate() ? "On" : "Off"; active: BarState.lockscreenShowDate(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-show-date", BarState.lockscreenShowDate() ? "false" : "true"]) }
                                Text { Layout.fillWidth: true; text: "Username"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                SettingsButton { label: BarState.lockscreenShowUsername() ? "On" : "Off"; active: BarState.lockscreenShowUsername(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-show-username", BarState.lockscreenShowUsername() ? "false" : "true"]) }
                                Text { Layout.fillWidth: true; text: "Weather"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                SettingsButton { label: BarState.lockscreenShowWeather() ? "On" : "Off"; active: BarState.lockscreenShowWeather(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-show-weather", BarState.lockscreenShowWeather() ? "false" : "true"]) }
                            }

                            Text { Layout.fillWidth: true; text: "Weather Location"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9); font.bold: true }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    color: Theme.popupBackground
                                    border.width: 1
                                    border.color: lockscreenWeatherLocationInput.activeFocus ? Theme.focus : Theme.active
                                    TextInput {
                                        id: lockscreenWeatherLocationInput
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        text: root.lockscreenWeatherLocationDraft
                                        maximumLength: 96
                                        color: Theme.foreground
                                        selectionColor: Theme.focus
                                        selectedTextColor: Theme.background
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                        clip: true
                                        onTextChanged: root.lockscreenWeatherLocationDraft = text
                                        Keys.onReturnPressed: event => { root.saveLockscreenWeatherLocation(); event.accepted = true; }
                                    }
                                }
                                SettingsButton { label: "Save Location"; textSize: root.scaledText(9); onClicked: root.saveLockscreenWeatherLocation() }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: root.lockscreenWeatherLocationError.length > 0
                                text: root.lockscreenWeatherLocationError
                                color: Theme.error
                                font.family: Theme.fontFamily
                                font.pixelSize: root.scaledText(8)
                                wrapMode: Text.Wrap
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "When Weather is enabled, this explicit location is sent to Open-Meteo. No IP or device geolocation is used."
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: root.scaledText(8)
                                wrapMode: Text.Wrap
                            }
                            SettingsButton { label: "Restore Awtarchy Defaults"; textSize: root.scaledText(9); onClicked: root.resetLockscreenPresentation() }
                        }

                            }
                        }

                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("smtty")
                            visible: root.quickSettingsSectionVisible("smtty")
                            Layout.fillWidth: true
                            Layout.preferredHeight: smttyContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: smttyContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "smtty · Steam session manager"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(11)
                                        font.bold: true
                                    }
                                    SettingsButton {
                                        label: "Open smtty"
                                        textSize: root.scaledText(9)
                                        onClicked: root.openSmtty()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "SUPER+ALT+G open interactive  ·  SUPER+ALT+L launch last profile  ·  SUPER+ALT+O write Steam launch options  ·  SUPER+ALT+K end session and restore audio/cleanup"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("scheduler")
                            visible: root.quickSettingsSectionVisible("scheduler")
                            Layout.fillWidth: true
                            Layout.preferredHeight: schedulerContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: schedulerContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "sched-ext · " + (root.schedulerStatus.enabled
                                            ? root.schedulerStatus.running
                                                + (root.schedulerStatus.mode
                                                    ? " (" + root.schedulerStatus.mode + ")" : "")
                                            : "off")
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    SettingsButton {
                                        label: root.schedulerEditorOpen ? "Hide Editor" : "Edit"
                                        available: (root.schedulerStatus.schedulers || []).length > 0
                                        active: root.schedulerEditorOpen
                                        textSize: root.scaledText(9)
                                        onClicked: root.schedulerEditorOpen = !root.schedulerEditorOpen
                                    }
                                    SettingsButton {
                                        label: "Authorize"
                                        visible: Boolean(root.schedulerStatus.available)
                                            && !Boolean(root.schedulerStatus.authorized)
                                        available: visible
                                        textSize: root.scaledText(9)
                                        onClicked: root.openSchedulerAuthorization()
                                    }
                                    SettingsButton {
                                        label: "Stop"
                                        available: Boolean(root.schedulerStatus.enabled)
                                            && Boolean(root.schedulerStatus.authorized)
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction(["scheduler-stop"], "Stopping sched-ext…")
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !root.schedulerStatus.available || !root.schedulerStatus.authorized
                                    text: !root.schedulerStatus.available
                                        ? "scxctl is unavailable"
                                        : "Authorize once to let Quick Settings start, switch, and stop sched-ext"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                    wrapMode: Text.Wrap
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.schedulerAuthOpen
                                        && Boolean(root.schedulerStatus.available)
                                        && !Boolean(root.schedulerStatus.authorized)
                                    spacing: 5

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.schedulerAuthError.length > 0
                                            ? root.schedulerAuthError
                                            : "Enter your sudo password to authorize the restricted scheduler helper"
                                        color: root.schedulerAuthError.length > 0 ? Theme.urgent : Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                        wrapMode: Text.Wrap
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: "Password"
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(9)
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 30
                                            color: Theme.active
                                            border.width: 1
                                            border.color: schedulerPasswordInput.activeFocus
                                                ? Theme.focus : Theme.muted

                                            TextInput {
                                                id: schedulerPasswordInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 7
                                                anchors.rightMargin: 7
                                                enabled: !root.schedulerAuthBusy
                                                echoMode: TextInput.Password
                                                color: Theme.foreground
                                                selectionColor: Theme.focus
                                                selectedTextColor: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(9)
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                selectByMouse: true
                                                onAccepted: root.submitSchedulerAuthorization()
                                                Keys.onEscapePressed: root.cancelSchedulerAuthorization()
                                            }
                                        }

                                        SettingsButton {
                                            label: root.schedulerAuthBusy ? "Authorizing…" : "Authorize"
                                            available: !root.schedulerAuthBusy
                                                && schedulerPasswordInput.text.length > 0
                                            textSize: root.scaledText(9)
                                            onClicked: root.submitSchedulerAuthorization()
                                        }

                                        SettingsButton {
                                            label: "Cancel"
                                            available: !root.schedulerAuthBusy
                                            textSize: root.scaledText(9)
                                            onClicked: root.cancelSchedulerAuthorization()
                                        }
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5
                                    Repeater {
                                        model: root.schedulerStatus.schedulers || []
                                        SettingsButton {
                                            required property var modelData
                                            label: String(modelData.name).replace(/^scx_/, "")
                                                + (String(root.schedulerStatus.running) === String(modelData.name)
                                                    ? " ●" : "")
                                            active: root.selectedSchedulerName === String(modelData.name)
                                            available: Boolean(root.schedulerStatus.available)
                                                && Boolean(root.schedulerStatus.authorized)
                                            textSize: root.scaledText(9)
                                            onClicked: root.selectScheduler(String(modelData.name))
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.schedulerEditorOpen && root.selectedScheduler() !== null
                                    spacing: 6

                                    Text {
                                        text: root.selectedSchedulerName + " configuration"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                        font.bold: true
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: childrenRect.height
                                        spacing: 5
                                        Repeater {
                                            model: root.selectedScheduler()
                                                ? root.selectedScheduler().profiles || [] : []
                                            SettingsButton {
                                                required property var modelData
                                                label: String(modelData)
                                                active: root.selectedScheduler()
                                                    && String(root.selectedScheduler().profile) === String(modelData)
                                                textSize: root.scaledText(9)
                                                onClicked: root.queueAction([
                                                    "scheduler-profile", root.selectedSchedulerName, String(modelData)
                                                ], "Saving scheduler profile…")
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: "Custom args"
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(9)
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            color: Theme.active
                                            border.width: 1
                                            border.color: schedulerArgsInput.activeFocus ? Theme.focus : Theme.muted
                                            TextInput {
                                                id: schedulerArgsInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 7
                                                anchors.rightMargin: 7
                                                text: root.schedulerArgsDraft
                                                color: Theme.foreground
                                                selectionColor: Theme.focus
                                                selectedTextColor: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(9)
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                onTextEdited: {
                                                    root.schedulerArgsDraft = text;
                                                    root.schedulerArgsDirty = true;
                                                }
                                            }
                                        }
                                        SettingsButton {
                                            label: "Save Args"
                                            available: root.schedulerArgsDirty
                                            textSize: root.scaledText(9)
                                            onClicked: {
                                                root.queueAction([
                                                    "scheduler-args", root.selectedSchedulerName,
                                                    root.schedulerArgsDraft
                                                ], "Saving scheduler arguments…");
                                                root.schedulerArgsDirty = false;
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        SettingsButton {
                                            visible: root.selectedSchedulerName === "scx_lavd"
                                            label: root.selectedScheduler() && root.selectedScheduler().autopower
                                                ? "Autopower On" : "Autopower Off"
                                            active: root.selectedScheduler()
                                                ? Boolean(root.selectedScheduler().autopower) : false
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueAction([
                                                "scheduler-autopower", "scx_lavd",
                                                root.selectedScheduler() && root.selectedScheduler().autopower
                                                    ? "false" : "true"
                                            ], "Updating LAVD autopower…")
                                        }
                                        Item { Layout.fillWidth: true }
                                        SettingsButton {
                                            label: "Reset Config"
                                            textSize: root.scaledText(9)
                                            onClicked: {
                                                root.queueAction([
                                                    "scheduler-reset", root.selectedSchedulerName
                                                ], "Resetting scheduler configuration…");
                                                root.schedulerArgsDirty = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("numlock")
                            visible: root.quickSettingsSectionVisible("numlock")
                            Layout.fillWidth: true
                            Layout.preferredHeight: numlockContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: numlockContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Disable Num Lock at session start"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(11)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    SettingsButton {
                                        label: root.disableNumlockAtSessionStart ? "On" : "Off"
                                        active: root.disableNumlockAtSessionStart
                                        textSize: root.scaledText(9)
                                        onClicked: root.toggleNumlockSessionStart()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Forces Num Lock off when this Quickshell session starts. Useful when firmware or a login manager leaves it enabled."
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

              ColumnLayout {
                  Layout.row: root.quickSettingsSectionRow("title-bars")
                  visible: root.quickSettingsSectionVisible("title-bars")
                  Layout.fillWidth: true
                  spacing: 8

                  TitleBarsCard {
                      active: quickSettingsWindow.visible
                      textScale: root.effectiveTextScale
                      iconScale: root.effectiveIconScale
                  }

                  FloatingWindowsCard {
                      active: quickSettingsWindow.visible
                      textScale: root.effectiveTextScale
                      iconScale: root.effectiveIconScale
                  }
              }

              ScreenShareGuardCard {
                  Layout.row: root.visibleQuickSettingsSectionOrder().length
                  Layout.fillWidth: true
                  active: quickSettingsWindow.visible
                  textScale: root.effectiveTextScale
                  iconScale: root.effectiveIconScale
              }
          }

          ListScrollBar {
                        id: contentScrollBar
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        flickable: contentFlick
                        z: 10
                    }
                }
            }

        }
    }
}
