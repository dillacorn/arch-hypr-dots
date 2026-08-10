pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland

Singleton {
    id: root

    property bool mutePopups: false
    readonly property bool dnd: mutePopups
    property var popupNotifications: []
    property int historyRevision: 0
    property string placement: "center"
    property bool settingsOpen: false
    property int panelWidthOverride: -1
    property int panelHeightOverride: -1
    property int textScaleOverride: -1
    property int iconScaleOverride: -1
    property int captureAllowedOverride: -1
    property int popupLimitOverride: -1
    property int resizeStartWidth: 0
    property int resizeStartHeight: 0
    property real anchorAlongEdge: -1
    property string settingsMessage: ""
    property var savedView: ({
        width: BarState.defaultNotificationWidth,
        height: BarState.defaultNotificationHeight,
        textScale: 100,
        iconScale: 100,
        captureAllowed: false,
        popupLimit: BarState.defaultNotificationPopupLimit
    })
    property var stateCommandQueue: []
    property bool privacyRemapPending: false

    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string mutePath: cacheHome + "/awtarchy/quickshell-dnd"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"
    readonly property string activeMonitorName: centerWindow.screen ? centerWindow.screen.name : ""
    readonly property int activeBarSize: {
        const target = centerWindow.screen;
        if (!target || placement === "center")
            return 0;
        return BarState.barSizeFor(target.name, placement === "left" || placement === "right");
    }
    readonly property int targetScreenWidth: centerWindow.screen
        ? centerWindow.screen.width : 1920
    readonly property int targetScreenHeight: centerWindow.screen
        ? centerWindow.screen.height : 1080
    readonly property int maximumPanelWidth: Math.max(1, targetScreenWidth
        - ((placement === "left" || placement === "right") ? activeBarSize : 0) - 20)
    readonly property int maximumPanelHeight: Math.max(1, targetScreenHeight
        - ((placement === "top" || placement === "bottom") ? activeBarSize : 0) - 20)
    readonly property int minimumPanelWidth: Math.min(360, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(360, maximumPanelHeight)
    readonly property int livePanelWidth: clampWidth(panelWidthOverride >= 0
        ? panelWidthOverride : BarState.notificationViewFor(activeMonitorName).width)
    readonly property int livePanelHeight: clampHeight(panelHeightOverride >= 0
        ? panelHeightOverride : BarState.notificationViewFor(activeMonitorName).height)
    readonly property int effectiveTextScale: textScaleOverride >= 0
        ? textScaleOverride : BarState.notificationViewFor(activeMonitorName).textScale
    readonly property int effectiveIconScale: iconScaleOverride >= 0
        ? iconScaleOverride : BarState.notificationViewFor(activeMonitorName).iconScale
    readonly property bool captureAllowed: captureAllowedOverride >= 0
        ? captureAllowedOverride === 1 : BarState.captureAllowedFor("notifications")
    readonly property int effectivePopupLimit: Math.max(1, Math.min(20,
        popupLimitOverride >= 0 ? popupLimitOverride : BarState.notificationPopupLimit()))
    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed
        || savedView.popupLimit !== effectivePopupLimit
    readonly property int historyCount: historyNotifications().length

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

    function clampWidth(value) {
        return Math.max(minimumPanelWidth, Math.min(maximumPanelWidth, Math.round(value)));
    }

    function clampHeight(value) {
        return Math.max(minimumPanelHeight, Math.min(maximumPanelHeight, Math.round(value)));
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
        const next = [notification, ...popupNotifications.filter(item => item !== notification)];
        const overflow = next.slice(effectivePopupLimit);
        popupNotifications = next.slice(0, effectivePopupLimit);
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

    function activateOrDismiss(notification) {
        if (!notification)
            return;
        const actions = notification.actions || [];
        for (let i = 0; i < actions.length; ++i) {
            if (actions[i].identifier === "default") {
                actions[i].invoke();
                return;
            }
        }
        notification.dismiss();
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
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: textScaleOverride,
            iconScale: iconScaleOverride,
            captureAllowed: captureAllowed,
            popupLimit: effectivePopupLimit
        });
    }

    function acceptDraftAsSaved() {
        savedView = ({
            width: livePanelWidth,
            height: livePanelHeight,
            textScale: effectiveTextScale,
            iconScale: effectiveIconScale,
            captureAllowed: captureAllowed,
            popupLimit: effectivePopupLimit
        });
    }

    function discardDraft() {
        panelWidthOverride = savedView.width;
        panelHeightOverride = savedView.height;
        textScaleOverride = savedView.textScale;
        iconScaleOverride = savedView.iconScale;
        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;
        popupLimitOverride = savedView.popupLimit;
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
            captureAllowed ? "true" : "false",
            String(effectivePopupLimit)
        ]);
        acceptDraftAsSaved();
        settingsMessage = "Saved Notification settings for " + activeMonitorName;
    }

    function resetDisplaySettings() {
        if (activeMonitorName.length === 0)
            return;
        const wasCaptureAllowed = captureAllowed;
        panelWidthOverride = clampWidth(BarState.defaultNotificationWidth);
        panelHeightOverride = clampHeight(BarState.defaultNotificationHeight);
        textScaleOverride = 100;
        iconScaleOverride = 100;
        captureAllowedOverride = 0;
        if (wasCaptureAllowed) {
            savedView = Object.assign({}, savedView, { captureAllowed: false });
            privacyRemapPending = true;
            queueStateCommand(["set-capture", "notifications", "false"]);
        }
        popupLimitOverride = BarState.defaultNotificationPopupLimit;
        settingsMessage = "Notification defaults loaded for " + activeMonitorName;
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
        settingsMessage = "Copied Notification settings to " + targets.length
            + (targets.length === 1 ? " display" : " displays");
    }

    function adjustPanelWidth(delta) {
        panelWidthOverride = clampWidth(livePanelWidth + delta);
        settingsMessage = "Width " + panelWidthOverride + " px";
    }

    function adjustPanelHeight(delta) {
        panelHeightOverride = clampHeight(livePanelHeight + delta);
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

    function toggleSettings() {
        if (settingsOpen && settingsDirty)
            discardDraft();
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
        FlyoutManager.claim("notifications");
        hideAllPopups();
        centerWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        anchorAlongEdge = anchorCoordinate(anchorItem);
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        loadSavedView(targetScreen);
        centerWindow.visible = true;
    }

    function openFocused() { openForScreen(focusedScreen()); }

    function closeCenter() {
        if (settingsDirty)
            discardDraft();
        centerWindow.visible = false;
        FlyoutManager.release("notifications");
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function toggleForScreen(targetScreen) {
        const currentName = centerWindow.screen ? centerWindow.screen.name : "";
        const targetName = targetScreen ? targetScreen.name : "";
        if (centerWindow.visible && currentName.length > 0 && currentName === targetName)
            closeCenter();
        else
            openForScreen(targetScreen);
    }

    function toggleForItem(targetScreen, anchorItem) {
        const currentName = centerWindow.screen ? centerWindow.screen.name : "";
        const targetName = targetScreen ? targetScreen.name : "";
        if (centerWindow.visible && currentName.length > 0 && currentName === targetName)
            closeCenter();
        else
            openForScreen(targetScreen, anchorItem);
    }

    onEffectivePopupLimitChanged: {
        if (popupNotifications.length > effectivePopupLimit)
            popupNotifications = popupNotifications.slice(0, effectivePopupLimit);
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
        function dismissFirst(): void { root.dismissFirst(); }
        function dismissAll(): void { root.dismissAll(); }
        function dndEnabled(): bool { return root.mutePopups; }
        function popupsMuted(): bool { return root.mutePopups; }
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
                && (notification.lastGeneration || root.mutePopups || centerWindow.visible))
                return;

            notification.tracked = true;
            root.historyRevision++;

            const target = root.focusedScreen();
            if (target)
                popupWindow.screen = target;

            if (!notification.lastGeneration && !root.mutePopups && !centerWindow.visible)
                root.enqueuePopup(notification);

            if (!transientNotification)
                Qt.callLater(() => root.trimHistory());
        }
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
            Qt.callLater(() => centerWindow.visible = true);
        }
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "notifications" && centerWindow.visible)
                root.closeCenter();
        }
    }

    PanelWindow {
        id: popupWindow
        WlrLayershell.namespace: "awtarchy-notification-popup"
        visible: !root.mutePopups
            && !centerWindow.visible
            && root.popupNotifications.length > 0
        color: "transparent"
        focusable: false
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore

        readonly property bool barVisibleHere: screen && BarState.enabledFor(screen.name)
        readonly property string barPositionHere: screen ? BarState.positionFor(screen.name) : "top"
        readonly property int popupHeightLimit: Math.max(120,
            (screen ? screen.height : 1080)
                - (barVisibleHere ? BarState.barSizeFor(screen.name,
                    barPositionHere === "left" || barPositionHere === "right") : 0) - 20)

        anchors.top: barPositionHere !== "bottom"
        anchors.bottom: barPositionHere === "bottom"
        anchors.left: barPositionHere === "left"
        anchors.right: barPositionHere !== "left"
        margins {
            top: barVisibleHere && barPositionHere === "top" ? 38 : 10
            bottom: barVisibleHere && barPositionHere === "bottom" ? 38 : 10
            left: barVisibleHere && barPositionHere === "left" ? 46 : 10
            right: barVisibleHere && barPositionHere === "right" ? 46 : 10
        }

        implicitWidth: Math.max(320, Math.min(520, root.viewForScreen(screen).width))
        implicitHeight: Math.min(popupHeightLimit, popupColumn.implicitHeight)

        Column {
            id: popupColumn
            width: parent.width
            spacing: 6

            Repeater {
                model: ScriptModel { values: root.popupNotifications }

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

                    onActivated: root.activateOrDismiss(notification)
                    onDismissRequested: root.dismissNotification(notification)
                    onNotificationClosed: {
                        root.removePopup(notification);
                        root.historyRevision++;
                    }
                }
            }
        }
    }

    PanelWindow {
        id: centerWindow
        WlrLayershell.namespace: "awtarchy-notification-center"
        visible: false
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: root.livePanelWidth
        implicitHeight: root.livePanelHeight
        anchors.top: root.placement !== "bottom"
        anchors.bottom: root.placement === "bottom"
        anchors.left: root.placement !== "right"
        anchors.right: root.placement === "right"
        margins {
            top: root.placement === "top" ? root.activeBarSize
                : (root.placement === "bottom" ? 0 : root.anchoredPanelY())
            bottom: root.placement === "bottom" ? root.activeBarSize : 0
            left: root.placement === "left" ? root.activeBarSize
                : (root.placement === "right" ? 0 : root.anchoredPanelX())
            right: root.placement === "right" ? root.activeBarSize : 0
        }

        Rectangle {
            id: panel
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

            DragHandler {
                target: null
                acceptedButtons: Qt.RightButton
                acceptedModifiers: Qt.AltModifier

                onActiveChanged: {
                    if (active) {
                        root.resizeStartWidth = root.livePanelWidth;
                        root.resizeStartHeight = root.livePanelHeight;
                    }
                }

                onActiveTranslationChanged: {
                    if (!active)
                        return;
                    const horizontalDirection = root.placement === "right" ? -1 : 1;
                    const verticalDirection = root.placement === "bottom" ? -1 : 1;
                    root.panelWidthOverride = root.clampWidth(
                        root.resizeStartWidth + activeTranslation.x * horizontalDirection);
                    root.panelHeightOverride = root.clampHeight(
                        root.resizeStartHeight + activeTranslation.y * verticalDirection);
                    root.settingsMessage = root.livePanelWidth + " × " + root.livePanelHeight + " px";
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: Theme.active
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.placement === "right" ? 40 : 8
                        anchors.rightMargin: root.placement !== "right" && root.placement !== "top" ? 40 : 8
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
                                enabled: root.historyCount > 0
                                hoverEnabled: enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.dismissAll()
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

                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 26
                            color: root.settingsOpen ? Theme.focus
                                : (settingsMouse.containsMouse ? Theme.subtleHover : "transparent")
                            border.width: 0

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
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.settingsOpen ? 38 : 0
                    visible: root.settingsOpen
                    color: Theme.popupButton
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Maximum simultaneous popups"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
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
                }

                ListView {
                    id: historyList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    Layout.topMargin: 6
                    Layout.bottomMargin: root.placement === "top" ? 36 : 6
                    model: ScriptModel { values: root.historyNotifications() }
                    spacing: 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: NotificationCard {
                        id: historyCard
                        required property var modelData
                        width: ListView.view.width - (historyScrollBar.visible ? 14 : 0)
                        notification: modelData
                        textScale: root.effectiveTextScale
                        iconScale: root.effectiveIconScale
                        bodyLineLimit: 8

                        onActivated: root.activateOrDismiss(notification)
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
                x: root.placement === "right" ? 6 : panel.width - width - 6
                y: root.placement === "top" ? panel.height - height - 6 : 5
                color: closeMouse.containsMouse ? Theme.focus : Theme.active
                border.width: 0
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