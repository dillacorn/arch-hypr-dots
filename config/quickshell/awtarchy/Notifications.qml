pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "FlyoutEdgeLayout.js" as FlyoutEdgeLayout

Singleton {
    id: root

    property bool mutePopups: false
    readonly property bool dnd: mutePopups
    property var popupNotifications: []
    property int historyRevision: 0
    property bool clearInProgress: false
    property var clearQueue: []
    property var clearVisualQueue: []
    property var clearSlideNotifications: []
    property int clearSlideIndex: 0
    property int clearVisualCount: 0
    property string placement: "center"
    readonly property bool bottomEdgeLayout: FlyoutEdgeLayout.isBottom(placement)
    property bool settingsOpen: false
    property int panelWidthOverride: -1
    property int panelHeightOverride: -1
    property int textScaleOverride: -1
    property int iconScaleOverride: -1
    property int captureAllowedOverride: -1
    property int popupLimitOverride: -1
    property int updateNotificationsOverride: -1
    property string popupPositionDraft: "automatic"
    property string popupPreviewPosition: ""
    property real anchorAlongEdge: -1
    property string settingsMessage: ""
    property var savedView: ({
        width: BarState.defaultNotificationWidth,
        height: BarState.defaultNotificationHeight,
        textScale: 100,
        iconScale: 100,
        captureAllowed: false,
        popupLimit: BarState.defaultNotificationPopupLimit,
        popupPosition: "automatic"
    })
    property var stateCommandQueue: []
    property bool privacyRemapPending: false
    property bool openPreparing: false
    property bool panelPresented: false
    readonly property int panelFadeDuration: 140
    property var centerScreen: null

    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string mutePath: cacheHome + "/awtarchy/quickshell-dnd"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_flyout_position.sh"
    readonly property string prepareScript: configHome + "/hypr/scripts/quickshell_flyout_prepare.sh"
    readonly property var activeScreen: centerScreen || centerWindow.screen
    readonly property string activeMonitorName: activeScreen && activeScreen.name
        ? String(activeScreen.name) : ""
    readonly property int activeBarSize: {
        const target = activeScreen;
        if (!target || placement === "center")
            return 0;
        return BarState.barSizeFor(target.name, placement === "left" || placement === "right");
    }
    readonly property int targetScreenWidth: activeScreen ? activeScreen.width : 1920
    readonly property int targetScreenHeight: activeScreen ? activeScreen.height : 1080
    readonly property int maximumPanelWidth: Math.max(1, targetScreenWidth - 20)
    readonly property int maximumPanelHeight: Math.max(1, targetScreenHeight - 20)
    readonly property int minimumPanelWidth: Math.min(360, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(360, maximumPanelHeight)
    readonly property int configuredPanelWidth: clampWidth(panelWidthOverride >= 0
        ? panelWidthOverride : BarState.notificationViewFor(activeMonitorName).width)
    readonly property int configuredPanelHeight: clampHeight(panelHeightOverride >= 0
        ? panelHeightOverride : BarState.notificationViewFor(activeMonitorName).height)
    readonly property int livePanelWidth: centerWindow.visible && centerWindow.width > 0
        ? clampWidth(Math.round(centerWindow.width)) : configuredPanelWidth
    readonly property int livePanelHeight: centerWindow.visible && centerWindow.height > 0
        ? clampHeight(Math.round(centerWindow.height)) : configuredPanelHeight
    readonly property int effectiveTextScale: textScaleOverride >= 0
        ? textScaleOverride : BarState.notificationViewFor(activeMonitorName).textScale
    readonly property int effectiveIconScale: iconScaleOverride >= 0
        ? iconScaleOverride : BarState.notificationViewFor(activeMonitorName).iconScale
    readonly property bool captureAllowed: captureAllowedOverride >= 0
        ? captureAllowedOverride === 1 : BarState.captureAllowedFor("notifications")
    readonly property int effectivePopupLimit: Math.max(1, Math.min(20,
        popupLimitOverride >= 0 ? popupLimitOverride : BarState.notificationPopupLimit()))
    readonly property bool updateNotificationsEnabled: updateNotificationsOverride >= 0
        ? updateNotificationsOverride === 1 : BarState.updateNotificationsEnabled()
    readonly property string effectivePopupPosition: FlyoutEdgeLayout.isNotificationPosition(popupPositionDraft)
        ? popupPositionDraft : "automatic"
    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed
        || savedView.popupLimit !== effectivePopupLimit
        || savedView.popupPosition !== effectivePopupPosition
    readonly property int historyCount: historyNotifications().length

    onBottomEdgeLayoutChanged: Qt.callLater(() => historyList.positionViewAtBeginning())

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

    function viewForScreen(targetScreen) {
        return BarState.notificationViewFor(targetScreen ? targetScreen.name : "");
    }

    function popupTextScale() { return viewForScreen(popupWindow.screen).textScale; }
    function popupIconScale() { return viewForScreen(popupWindow.screen).iconScale; }

    function popupLimitForMonitor(name) {
        return BarState.notificationPopupLimit();
    }

    function setPopupPreview(position) {
        const requested = String(position || "");
        if (FlyoutEdgeLayout.isNotificationPosition(requested))
            popupPreviewPosition = requested;
    }

    function clearPopupPreview() {
        popupPreviewPosition = "";
    }

    function clampWidth(value) {
        return Math.max(minimumPanelWidth, Math.min(maximumPanelWidth, Math.round(value)));
    }

    function clampHeight(value) {
        return Math.max(minimumPanelHeight, Math.min(maximumPanelHeight, Math.round(value)));
    }

    function applyWindowSize(width, height) {
        panelWidthOverride = clampWidth(width);
        panelHeightOverride = clampHeight(height);
        if (centerWindow.visible && activeMonitorName.length > 0) {
            Quickshell.execDetached([
                positionScript, "notifications", activeMonitorName, placement, "resize",
                String(panelWidthOverride), String(panelHeightOverride), String(anchorAlongEdge)
            ]);
        }
    }

    function positionCenter() {
        if (!centerWindow.visible || activeMonitorName.length === 0)
            return;
        Quickshell.execDetached([
            positionScript, "notifications", activeMonitorName, placement, "spawn",
            "", "", String(anchorAlongEdge)
        ]);
    }

    function prepareCenterOpen(targetScreen) {
        if (!targetScreen)
            return;
        openPreparing = true;
        prepareProcess.exec([
            "bash", prepareScript, "notifications", targetScreen.name, placement,
            String(configuredPanelWidth), String(configuredPanelHeight),
            String(activeBarSize), String(Math.round(anchorAlongEdge)),
            String(Math.round(targetScreen.width)), String(Math.round(targetScreen.height))
        ]);
    }

    function finishPreparedCenterOpen() {
        if (!openPreparing)
            return;

        const wasVisible = centerWindow.visible;

        openPreparing = false;
        panelPresented = true;
        centerWindow.visible = true;
        if (wasVisible)
            Qt.callLater(() => root.positionCenter());
    }

    function anchoredPanelX() {
        if (placement === "left")
            return activeBarSize;
        if (placement === "right")
            return targetScreenWidth - livePanelWidth - activeBarSize;
        if (placement === "center")
            return Math.round((targetScreenWidth - livePanelWidth) / 2);
        const edge = anchorAlongEdge >= 0 ? anchorAlongEdge : targetScreenWidth - 40;
        return Math.max(6, Math.min(targetScreenWidth - livePanelWidth - 6,
            Math.round(edge - livePanelWidth)));
    }

    function anchoredPanelY() {
        if (placement === "top")
            return activeBarSize;
        if (placement === "bottom")
            return targetScreenHeight - livePanelHeight - activeBarSize;
        if (placement === "center")
            return Math.round((targetScreenHeight - livePanelHeight) / 2);
        const edge = anchorAlongEdge >= 0 ? anchorAlongEdge : targetScreenHeight - 40;
        return Math.max(6, Math.min(targetScreenHeight - livePanelHeight - 6,
            Math.round(edge - livePanelHeight)));
    }

    function anchorCoordinate(item) {
        if (!item)
            return -1;
        const edgePoint = item.mapToItem(null, item.width, item.height);
        return placement === "top" || placement === "bottom" ? edgePoint.x : edgePoint.y;
    }

    function synchronousKey(notification) {
        if (!notification || !notification.hints)
            return "";
        const value = notification.hints["x-canonical-private-synchronous"];
        return value === undefined || value === null ? "" : String(value);
    }

    function isSystemSetting(notification) {
        if (!notification)
            return false;
        const appName = String(notification.appName || "").toLowerCase();
        const summary = String(notification.summary || "").toLowerCase();
        return appName === "hyprland"
            || appName === "hyprsunset"
            || appName === "hypr-ddc-brightness"
            || summary === "night light"
            || summary === "vibrance";
    }

    function isTransientNotification(notification) {
        return Boolean(notification)
            && (notification.transient
                || synchronousKey(notification).length > 0
                || isSystemSetting(notification));
    }

    function replaceSynchronous(notification) {
        const key = synchronousKey(notification);
        if (key.length === 0)
            return;
        const values = [...server.trackedNotifications.values];
        for (let i = 0; i < values.length; ++i) {
            if (values[i] !== notification && synchronousKey(values[i]) === key) {
                removePopup(values[i]);
                values[i].expire();
            }
        }
    }

    function popupTimeoutFor(notification) {
        if (!notification)
            return 5;
        const requested = Number(notification.expireTimeout || 0);
        if (isTransientNotification(notification))
            return requested > 0 ? Math.min(2.2, requested) : 2.0;
        return requested > 0 ? Math.max(2.0, Math.min(10.0, requested)) : 5.0;
    }

    function removePopup(notification) {
        popupNotifications = popupNotifications.filter(item => item !== notification);
    }

    function enqueuePopup(notification) {
        const monitor = popupWindow.screen && popupWindow.screen.name
            ? String(popupWindow.screen.name) : "";
        const limit = popupLimitForMonitor(monitor);
        const next = [notification, ...popupNotifications.filter(item => item !== notification)];
        const overflow = next.slice(limit);
        popupNotifications = next.slice(0, limit);
        for (const item of overflow) {
            if (isTransientNotification(item))
                item.expire();
        }
    }

    function hidePopup(notification) {
        removePopup(notification);
        if (isTransientNotification(notification) && notification.tracked)
            notification.expire();
    }

    function hideFirstPopup() {
        if (popupNotifications.length === 0)
            return;
        hidePopup(popupNotifications[0]);
    }

    function hideAllPopups() {
        const visiblePopups = popupNotifications.slice();
        popupNotifications = [];
        for (const notification of visiblePopups) {
            if (isTransientNotification(notification) && notification.tracked)
                notification.expire();
        }
    }

    function historyNotifications() {
        const dependency = historyRevision;
        return [...server.trackedNotifications.values]
            .filter(notification => !isTransientNotification(notification))
            .reverse();
    }

    function trimHistory() {
        const values = [...server.trackedNotifications.values]
            .filter(notification => !isTransientNotification(notification));
        const removeCount = Math.max(0, values.length - 100);
        for (let i = 0; i < removeCount; ++i)
            values[i].dismiss();
    }

    function setPopupMute(value) {
        mutePopups = value;
        muteFile.setText(value ? "1\n" : "0\n");
        if (value)
            hideAllPopups();
    }

    function togglePopupMute() { setPopupMute(!mutePopups); }
    function setDnd(value) { setPopupMute(value); }
    function toggleDnd() { togglePopupMute(); }

    function activateNotification(notification) {
        if (!notification)
            return;
        const actions = notification.actions || [];
        for (let i = 0; i < actions.length; ++i) {
            if (actions[i].identifier === "default") {
                actions[i].invoke();
                break;
            }
        }
        hidePopup(notification);
    }

    function dismissNotification(notification) {
        if (!notification)
            return;
        removePopup(notification);
        notification.dismiss();
        historyRevision++;
    }

    function dismissFirst() {
        if (popupNotifications.length > 0) {
            dismissNotification(popupNotifications[0]);
            return;
        }
        const values = historyNotifications();
        if (values.length > 0)
            dismissNotification(values[0]);
    }

    function dismissAll() {
        popupNotifications = [];
        const values = [...server.trackedNotifications.values];
        for (let i = 0; i < values.length; ++i)
            values[i].dismiss();
        historyRevision++;
    }

    function beginClearAll() {
        if (clearInProgress)
            return;

        const values = historyNotifications();
        if (values.length === 0)
            return;

        const visualCount = Math.min(values.length, 10);
        clearQueue = [...server.trackedNotifications.values];
        clearVisualQueue = values.slice();
        clearSlideNotifications = [];
        clearSlideIndex = 0;
        clearVisualCount = visualCount;
        clearInProgress = true;
        hideAllPopups();
        clearStaggerTimer.restart();
    }

    function finishClearAll() {
        if (!clearInProgress)
            return;

        const values = clearQueue.slice();
        for (let i = 0; i < values.length; ++i) {
            if (values[i] && values[i].tracked)
                values[i].dismiss();
        }

        clearQueue = [];
        clearVisualQueue = [];
        clearSlideNotifications = [];
        clearSlideIndex = 0;
        clearVisualCount = 0;
        clearInProgress = false;
        historyRevision++;
    }

    function loadSavedView(targetScreen) {
        if (!targetScreen)
            return;
        BarState.refresh();
        const persisted = BarState.notificationViewFor(targetScreen.name);
        panelWidthOverride = clampWidth(persisted.width);
        panelHeightOverride = clampHeight(persisted.height);
        textScaleOverride = persisted.textScale;
        iconScaleOverride = persisted.iconScale;
        captureAllowedOverride = BarState.captureAllowedFor("notifications") ? 1 : 0;
        popupLimitOverride = BarState.notificationPopupLimit();
        updateNotificationsOverride = BarState.updateNotificationsEnabled() ? 1 : 0;
        popupPositionDraft = BarState.notificationPopupPositionFor(targetScreen.name);
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: textScaleOverride,
            iconScale: iconScaleOverride,
            captureAllowed: captureAllowed,
            popupLimit: effectivePopupLimit,
            popupPosition: effectivePopupPosition
        });
    }

    function acceptDraftAsSaved() {
        savedView = ({
            width: livePanelWidth,
            height: livePanelHeight,
            textScale: effectiveTextScale,
            iconScale: effectiveIconScale,
            captureAllowed: captureAllowed,
            popupLimit: effectivePopupLimit,
            popupPosition: effectivePopupPosition
        });
    }

    function discardDraft() {
        const width = savedView.width;
        const height = savedView.height;
        textScaleOverride = savedView.textScale;
        iconScaleOverride = savedView.iconScale;
        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;
        popupLimitOverride = savedView.popupLimit;
        popupPositionDraft = savedView.popupPosition;
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
            "save-flyout", "notifications", activeMonitorName,
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            captureAllowed ? "true" : "false"
        ]);
        queueStateCommand([
            "set-notification-popup-limit", String(effectivePopupLimit)
        ]);
        queueStateCommand([
            "set-notification-popup-position", activeMonitorName, effectivePopupPosition
        ]);
        panelWidthOverride = livePanelWidth;
        panelHeightOverride = livePanelHeight;
        acceptDraftAsSaved();
        settingsMessage = "Saved Notification settings for " + activeMonitorName;
    }

    function resetDisplaySettings() {
        if (activeMonitorName.length === 0)
            return;
        const wasCaptureAllowed = captureAllowed;
        textScaleOverride = 100;
        iconScaleOverride = 100;
        captureAllowedOverride = 0;
        popupLimitOverride = BarState.defaultNotificationPopupLimit;
        popupPositionDraft = "automatic";
        applyWindowSize(BarState.defaultNotificationWidth, BarState.defaultNotificationHeight);
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: 100,
            iconScale: 100,
            captureAllowed: false,
            popupLimit: BarState.defaultNotificationPopupLimit,
            popupPosition: "automatic"
        });
        privacyRemapPending = wasCaptureAllowed;
        queueStateCommand(["reset-flyout", "notifications", activeMonitorName]);
        queueStateCommand([
            "set-notification-popup-limit",
            String(BarState.defaultNotificationPopupLimit)
        ]);
        settingsMessage = "Notification defaults restored for " + activeMonitorName;
    }

    function copyDisplaySettings(targets) {
        if (!targets || targets.length === 0)
            return;
        queueStateCommand([
            "copy-flyout", "notifications",
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            ...targets
        ]);
        for (const target of targets) {
            queueStateCommand([
                "set-notification-popup-position", String(target), effectivePopupPosition
            ]);
        }
        settingsMessage = "Copied Notification settings to " + targets.length
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
        queueStateCommand(["set-capture", "notifications", next ? "true" : "false"]);
        settingsMessage = next
            ? "Notifications are visible in captures" : "Notification capture protection enabled";
    }

    function toggleUpdateNotifications() {
        const next = !updateNotificationsEnabled;
        updateNotificationsOverride = next ? 1 : 0;
        queueStateCommand(["set-update-notifications", next ? "true" : "false"]);
        settingsMessage = next
            ? "Awtarchy update notifications enabled"
            : "Normal Awtarchy update notifications suppressed";
    }

    function toggleSettings() {
        settingsOpen = !settingsOpen;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function otherMonitorNames() {
        return Quickshell.screens
            .map(target => target ? target.name : "")
            .filter(name => name.length > 0 && name !== activeMonitorName);
    }

    function openForScreen(targetScreen, anchorItem) {
        if (!targetScreen)
            return;
        FlyoutManager.claim("notifications", targetScreen.name);
        hideAllPopups();
        centerScreen = targetScreen;
        if (!centerWindow.visible)
            centerWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        anchorAlongEdge = anchorCoordinate(anchorItem);
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        loadSavedView(targetScreen);
        prepareCenterOpen(targetScreen);
    }

    function openFocused() { openForScreen(focusedScreen()); }

    function closeCenter() {
        openPreparing = false;
        if (prepareProcess.running)
            prepareProcess.running = false;
        if (settingsDirty)
            discardDraft();
        centerWindow.visible = false;
        panelPresented = false;
        FlyoutManager.release("notifications");
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function toggleForScreen(targetScreen) {
        if (!FlyoutManager.acceptToggle("notifications"))
            return;
        const currentName = activeMonitorName;
        const targetName = targetScreen ? targetScreen.name : "";
        if ((centerWindow.visible || openPreparing)
            && currentName.length > 0 && currentName === targetName)
            closeCenter();
        else
            openForScreen(targetScreen);
    }

    function toggleForItem(targetScreen, anchorItem) {
        if (!FlyoutManager.acceptToggle("notifications"))
            return;
        const currentName = activeMonitorName;
        const targetName = targetScreen ? targetScreen.name : "";
        if ((centerWindow.visible || openPreparing)
            && currentName.length > 0 && currentName === targetName)
            closeCenter();
        else
            openForScreen(targetScreen, anchorItem);
    }

    onEffectivePopupLimitChanged: {
        if (popupNotifications.length > effectivePopupLimit)
            popupNotifications = popupNotifications.slice(0, effectivePopupLimit);
    }

    Timer {
        id: clearStaggerTimer
        interval: 32
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!root.clearInProgress || root.clearSlideIndex >= root.clearVisualCount) {
                stop();
                clearFinishTimer.restart();
                return;
            }

            const notification = root.clearVisualQueue[root.clearSlideIndex];
            if (notification)
                root.clearSlideNotifications = [...root.clearSlideNotifications, notification];
            root.clearSlideIndex++;

            if (root.clearSlideIndex >= root.clearVisualCount) {
                stop();
                clearFinishTimer.restart();
            }
        }
    }

    Timer {
        id: clearFinishTimer
        interval: 120
        repeat: false
        onTriggered: root.finishClearAll()
    }

    FileView {
        id: muteFile
        path: root.mutePath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.mutePopups = text().trim() === "1";
            if (root.mutePopups)
                root.hideAllPopups();
        }
        onFileChanged: reload()
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggleForScreen(root.focusedScreen()); }
        function open(): void { root.openFocused(); }
        function close(): void { root.closeCenter(); }
        function toggleDnd(): void { root.togglePopupMute(); }
        function enable(): void { root.setPopupMute(false); }
        function disable(): void { root.setPopupMute(true); }
        function hideFirstPopup(): void { root.hideFirstPopup(); }
        function dismissFirst(): void { root.dismissFirst(); }
        function dismissAll(): void { root.dismissAll(); }
        function dndEnabled(): bool { return root.mutePopups; }
        function popupsMuted(): bool { return root.mutePopups; }
        function setPopupPreview(position: string): void { root.setPopupPreview(position); }
        function clearPopupPreview(): void { root.clearPopupPreview(); }
    }

    NotificationServer {
        id: server
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: false
        persistenceSupported: true
        keepOnReload: true

        onNotification: notification => {
            root.replaceSynchronous(notification);
            const transientNotification = root.isTransientNotification(notification);
            if (transientNotification
                && (notification.lastGeneration || root.mutePopups
                    || centerWindow.visible || root.openPreparing))
                return;

            notification.tracked = true;
            root.historyRevision++;

            const target = root.focusedScreen();
            if (target)
                popupWindow.screen = target;

            if (!notification.lastGeneration && !root.mutePopups
                && !centerWindow.visible && !root.openPreparing)
                root.enqueuePopup(notification);

            if (!transientNotification)
                Qt.callLater(() => root.trimHistory());
        }
    }

    Process {
        id: prepareProcess
        onExited: root.finishPreparedCenterOpen()
    }

    Process {
        id: stateWriter
        onExited: {
            BarState.refresh();
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
            if (!centerWindow.visible)
                return;
            centerWindow.visible = false;
            Qt.callLater(() => {
                centerWindow.visible = true;
                root.positionCenter();
            });
        }
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "notifications"
                && (centerWindow.visible || root.openPreparing))
                root.closeCenter();
        }
    }

    PanelWindow {
        id: popupWindow
        WlrLayershell.namespace: "awtarchy-notification-popup"
        visible: !root.mutePopups
            && !centerWindow.visible
            && !root.openPreparing
            && root.popupNotifications.length > 0
        color: "transparent"
        focusable: false
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore

        readonly property bool barVisibleHere: screen && BarState.enabledFor(screen.name)
        readonly property string barPositionHere: screen ? BarState.positionFor(screen.name) : "top"
        readonly property string monitorNameHere: screen && screen.name ? String(screen.name) : ""
        readonly property string requestedPopupPosition: root.popupPreviewPosition.length > 0
            ? root.popupPreviewPosition : BarState.notificationPopupPositionFor(monitorNameHere)
        readonly property string resolvedPopupPosition: FlyoutEdgeLayout.resolveNotificationPosition(
            requestedPopupPosition, barPositionHere)
        readonly property int barAdjacentMargin: barVisibleHere
            ? BarState.barSizeFor(screen.name,
                barPositionHere === "left" || barPositionHere === "right") + 10
            : 10
        readonly property int popupHeightLimit: Math.max(120,
            (screen ? screen.height : 1080)
                - (barVisibleHere ? BarState.barSizeFor(screen.name,
                    barPositionHere === "left" || barPositionHere === "right") : 0) - 20)

        anchors.top: FlyoutEdgeLayout.positionIsTop(resolvedPopupPosition)
        anchors.bottom: FlyoutEdgeLayout.positionIsBottom(resolvedPopupPosition)
        anchors.left: FlyoutEdgeLayout.positionIsLeft(resolvedPopupPosition)
        anchors.right: FlyoutEdgeLayout.positionIsRight(resolvedPopupPosition)
        margins {
            top: barVisibleHere && barPositionHere === "top" ? barAdjacentMargin : 10
            bottom: barVisibleHere && barPositionHere === "bottom" ? barAdjacentMargin : 10
            left: barVisibleHere && barPositionHere === "left" ? barAdjacentMargin : 10
            right: barVisibleHere && barPositionHere === "right" ? barAdjacentMargin : 10
        }

        implicitWidth: Math.max(320, Math.min(520, root.viewForScreen(screen).width))
        implicitHeight: Math.min(popupHeightLimit, popupColumn.implicitHeight)

        Column {
            id: popupColumn
            width: parent.width
            spacing: 6

            Repeater {
                model: ScriptModel {
                    values: FlyoutEdgeLayout.positionIsBottom(popupWindow.resolvedPopupPosition)
                        ? root.popupNotifications.slice().reverse() : root.popupNotifications
                }

                delegate: NotificationCard {
                    id: popupCard
                    required property var modelData
                    width: popupColumn.width
                    notification: modelData
                    textScale: root.popupTextScale()
                    iconScale: root.popupIconScale()
                    bodyLineLimit: 4

                    Timer {
                        running: true
                        interval: Math.max(500, root.popupTimeoutFor(popupCard.notification) * 1000)
                        repeat: false
                        onTriggered: root.hidePopup(popupCard.notification)
                    }

                    onActivated: root.activateNotification(notification)
                    onDismissRequested: root.dismissNotification(notification)
                    onNotificationClosed: {
                        root.removePopup(notification);
                        root.historyRevision++;
                    }
                }
            }
        }
    }


    FloatingWindow {
        id: centerWindow
        visible: false
        title: "Awtarchy Notification Center"
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: root.configuredPanelWidth
        implicitHeight: root.configuredPanelHeight
        minimumSize: Qt.size(root.minimumPanelWidth, root.minimumPanelHeight)
        maximumSize: Qt.size(root.maximumPanelWidth, root.maximumPanelHeight)

        onClosed: root.closeCenter()
        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => root.positionCenter());
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
            Keys.onEscapePressed: root.closeCenter()

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: mouse => mouse.accepted = true
            }

            GridLayout {
                anchors.fill: parent
                columns: 1
                rowSpacing: 0
                columnSpacing: 0

                Rectangle {
                    Layout.row: root.bottomEdgeLayout ? 3 : 0
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
                            Layout.fillWidth: true
                            text: "Notifications  " + root.historyCount
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.max(10, Math.round(13 * root.effectiveTextScale / 100))
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 26
                            color: root.mutePopups ? Theme.focus
                                : (muteMouse.containsMouse ? Theme.subtleHover : "transparent")
                            border.width: 1
                            border.color: Theme.focus

                            Text {
                                anchors.centerIn: parent
                                text: root.mutePopups ? " Muted" : " Popups"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                            }

                            MouseArea {
                                id: muteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.togglePopupMute()
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 26
                            color: root.historyCount > 0
                                ? (clearMouse.containsMouse ? Theme.focus : Theme.subtleHover)
                                : "transparent"
                            opacity: root.historyCount > 0 ? 1 : 0.4
                            border.width: 0

                            Text {
                                anchors.centerIn: parent
                                text: "Clear"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                            }

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                enabled: root.historyCount > 0 && !root.clearInProgress
                                hoverEnabled: enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.beginClearAll()
                            }
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
                                onClicked: root.saveDisplaySettings()
                            }
                        }

                        CaptureEyeButton {
                            captureAllowed: root.captureAllowed
                            textSize: Math.max(11, Math.round(13 * root.effectiveIconScale / 100))
                            onClicked: root.toggleCaptureAllowed()
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
                                onClicked: root.toggleSettings()
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.row: root.bottomEdgeLayout ? 2 : 1
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.settingsOpen ? settingsPanel.implicitHeight + 12 : 0
                    visible: root.settingsOpen
                    color: Theme.popupButton
                    border.width: 0
                    clip: true

                    FlyoutSettings {
                        id: settingsPanel
                        anchors.fill: parent
                        anchors.margins: 6
                        surfaceLabel: "Notifications"
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

                        onResetRequested: root.resetDisplaySettings()
                        onWidthAdjustmentRequested: delta => root.adjustPanelWidth(delta)
                        onHeightAdjustmentRequested: delta => root.adjustPanelHeight(delta)
                        onTextScaleAdjustmentRequested: delta => root.adjustTextScale(delta)
                        onIconScaleAdjustmentRequested: delta => root.adjustIconScale(delta)
                        onCaptureToggleRequested: root.toggleCaptureAllowed()
                        onCopyRequested: monitorNames => root.copyDisplaySettings(monitorNames)
                    }
                }

                Rectangle {
                    Layout.row: root.bottomEdgeLayout ? 1 : 2
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.settingsOpen
                        ? popupSettingsContent.implicitHeight + 12 : 0
                    visible: root.settingsOpen
                    color: Theme.popupButton
                    border.width: 0

                    ColumnLayout {
                        id: popupSettingsContent
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 5

                        Text {
                            Layout.fillWidth: true
                            text: "Global behavior"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "Maximum popups"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.preferredWidth: 54
                                Layout.preferredHeight: 25
                                color: Theme.active
                                border.width: 1
                                border.color: popupLimitInput.activeFocus ? Theme.focus : Theme.muted

                                TextInput {
                                    id: popupLimitInput
                                    anchors.fill: parent
                                    text: String(root.effectivePopupLimit)
                                    color: Theme.foreground
                                    selectionColor: Theme.focus
                                    selectedTextColor: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    validator: IntValidator { bottom: 1; top: 20 }
                                    selectByMouse: true
                                    onTextEdited: {
                                        const value = Number(text);
                                        if (/^\d+$/.test(text) && value >= 1 && value <= 20)
                                            root.popupLimitOverride = value;
                                    }
                                    onEditingFinished: text = String(root.effectivePopupLimit)
                                }
                            }

                            Text {
                                text: "1–20"
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "Update alerts"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            SettingsButton {
                                label: root.updateNotificationsEnabled ? "On" : "Off"
                                active: root.updateNotificationsEnabled
                                textSize: 9
                                onClicked: root.toggleUpdateNotifications()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.updateNotificationsEnabled
                            Layout.preferredHeight: visible ? implicitHeight : 0
                            text: "When off, Awtarchy may show one catch-up notice after five stable releases."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.muted
                            opacity: 0.35
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Popup position · " + root.activeMonitorName
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Flow {
                            Layout.fillWidth: true
                            Layout.preferredHeight: childrenRect.height
                            spacing: 5

                            Repeater {
                                model: [
                                    { value: "automatic", label: "Automatic" },
                                    { value: "top-left", label: "Top Left" },
                                    { value: "top-center", label: "Top Center" },
                                    { value: "top-right", label: "Top Right" },
                                    { value: "bottom-left", label: "Bottom Left" },
                                    { value: "bottom-center", label: "Bottom Center" },
                                    { value: "bottom-right", label: "Bottom Right" }
                                ]

                                SettingsButton {
                                    required property var modelData
                                    label: modelData.label
                                    active: root.effectivePopupPosition === modelData.value
                                    textSize: 9
                                    onClicked: root.popupPositionDraft = modelData.value
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.effectivePopupPosition === "automatic"
                            Layout.preferredHeight: visible ? implicitHeight : 0
                            text: "Automatic follows this display's bar notification icon."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                        }
                    }
                }

                ListView {
                    id: historyList
                    Layout.row: root.bottomEdgeLayout ? 0 : 3
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    Layout.topMargin: 6
                    Layout.bottomMargin: 6
                    model: ScriptModel { values: root.historyNotifications() }
                    spacing: 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    verticalLayoutDirection: root.bottomEdgeLayout
                        ? ListView.BottomToTop : ListView.TopToBottom

                    delegate: NotificationCard {
                        id: historyCard
                        required property var modelData
                        width: ListView.view.width - (historyScrollBar.visible ? 14 : 0)
                        notification: modelData
                        textScale: root.effectiveTextScale
                        iconScale: root.effectiveIconScale
                        bodyLineLimit: 8
                        clearSliding: root.clearSlideNotifications.indexOf(notification) >= 0

                        onActivated: root.activateNotification(notification)
                        onDismissRequested: root.dismissNotification(notification)
                        onNotificationClosed: root.historyRevision++
                    }

                    ListScrollBar {
                        id: historyScrollBar
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        flickable: historyList
                        z: 10
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: historyList.count === 0
                        text: root.mutePopups
                            ? "No notification history\nPopups are muted; new notifications still appear here"
                            : "No notification history"
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(9, Math.round(11 * root.effectiveTextScale / 100))
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Rectangle {
                id: closeButton
                width: 28
                height: 28
                x: panel.width - width - 6
                y: root.bottomEdgeLayout ? panel.height - height - 5 : 5
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
                    font.pixelSize: 15
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeCenter()
                }
            }
        }
    }
}
