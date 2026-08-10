pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property var statusData: emptyStatus()
    property bool statusLoading: false
    property bool refreshPending: false
    property string actionMessage: ""
    property string actionError: ""
    property var actionQueue: []
    property string placement: "center"
    property string brightnessTarget: ""
    property string selectedSchedulerName: ""
    property bool schedulerEditorOpen: false
    property string schedulerArgsDraft: ""
    property bool schedulerArgsDirty: false
    property int brightnessHoverPercent: -1
    property bool settingsOpen: false
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

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string backend: configHome + "/hypr/scripts/hypr_quicksettings.sh"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string terminalLauncher: configHome + "/hypr/scripts/default_terminal.sh"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_flyout_position.sh"
    readonly property string activeMonitorName: quickSettingsWindow.screen ? quickSettingsWindow.screen.name : ""
    readonly property int targetScreenWidth: quickSettingsWindow.screen
        ? quickSettingsWindow.screen.width : 1920
    readonly property int targetScreenHeight: quickSettingsWindow.screen
        ? quickSettingsWindow.screen.height : 1080
    readonly property int maximumPanelWidth: Math.max(1, targetScreenWidth - 20)
    readonly property int maximumPanelHeight: Math.max(1, targetScreenHeight - 20)
    readonly property int minimumPanelWidth: Math.min(520, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(460, maximumPanelHeight)
    readonly property int configuredPanelWidth: clampWidth(panelWidthOverride >= 0
        ? panelWidthOverride : BarState.quickSettingsViewFor(activeMonitorName).width)
    readonly property int configuredPanelHeight: clampHeight(panelHeightOverride >= 0
        ? panelHeightOverride : BarState.quickSettingsViewFor(activeMonitorName).height)
    readonly property int livePanelWidth: quickSettingsWindow.visible && quickSettingsWindow.width > 0
        ? clampWidth(Math.round(quickSettingsWindow.width)) : configuredPanelWidth
    readonly property int livePanelHeight: quickSettingsWindow.visible && quickSettingsWindow.height > 0
        ? clampHeight(Math.round(quickSettingsWindow.height)) : configuredPanelHeight
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

    function emptyStatus() {
        return ({
            monitors: [],
            brightness: { target: "", connector: "", current: null, max: null },
            bar: { monitor: "", position: "top", enabled: true },
            night_light: { temperature: null, identity: "unknown", enabled: false },
            vibrance: { value: null, enabled: false },
            submap: "reset",
            sched_ext: {
                running: "off",
                mode: "",
                enabled: false,
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

    function applyWindowSize(width, height) {
        panelWidthOverride = clampWidth(width);
        panelHeightOverride = clampHeight(height);
        if (quickSettingsWindow.visible && activeMonitorName.length > 0) {
            Quickshell.execDetached([
                positionScript, "quick-settings", activeMonitorName, placement, "resize",
                String(panelWidthOverride), String(panelHeightOverride)
            ]);
        }
    }

    function positionWindow() {
        if (!quickSettingsWindow.visible || activeMonitorName.length === 0)
            return;
        Quickshell.execDetached([
            positionScript, "quick-settings", activeMonitorName, placement, "spawn"
        ]);
    }

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * effectiveTextScale / 100));
    }

    function scaledIcon(baseSize) {
        return Math.max(9, Math.round(baseSize * effectiveIconScale / 100));
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
            selected = schedulerByName(String(schedulerStatus.running || "")) || schedulers[0];
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

    function openSmtty() {
        Quickshell.execDetached([terminalLauncher, "--class", "smtty", "--", "smtty"]);
        close();
    }

    function loadSavedView(targetScreen) {
        if (!targetScreen)
            return;
        BarState.refresh();
        const persisted = BarState.quickSettingsViewFor(targetScreen.name);
        panelWidthOverride = clampWidth(persisted.width);
        panelHeightOverride = clampHeight(persisted.height);
        textScaleOverride = persisted.textScale;
        iconScaleOverride = persisted.iconScale;
        captureAllowedOverride = BarState.captureAllowedFor("quick_settings") ? 1 : 0;
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
    }

    function discardDraft() {
        const width = savedView.width;
        const height = savedView.height;
        textScaleOverride = savedView.textScale;
        iconScaleOverride = savedView.iconScale;
        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;
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
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function openForScreen(targetScreen) {
        if (!targetScreen)
            return;
        FlyoutManager.claim("quick-settings");
        quickSettingsWindow.screen = targetScreen;
        placement = placementForScreen(targetScreen);
        brightnessTarget = targetScreen.name;
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        schedulerEditorOpen = false;
        schedulerArgsDirty = false;
        loadSavedView(targetScreen);
        quickSettingsWindow.visible = true;
        Qt.callLater(() => root.positionWindow());
        refreshStatus();
    }

    function openFocused() { openForScreen(focusedScreen()); }

    function close() {
        if (settingsDirty)
            discardDraft();
        quickSettingsWindow.visible = false;
        FlyoutManager.release("quick-settings");
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        schedulerEditorOpen = false;
        brightnessHoverPercent = -1;
    }

    function toggleForScreen(targetScreen) {
        const currentName = quickSettingsWindow.screen ? quickSettingsWindow.screen.name : "";
        const targetName = targetScreen ? targetScreen.name : "";
        if (quickSettingsWindow.visible && currentName.length > 0 && currentName === targetName)
            close();
        else
            openForScreen(targetScreen);
    }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void { root.toggleForScreen(root.focusedScreen()); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
        function refresh(): void { root.refreshStatus(); }
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
            if (exceptSurface !== "quick-settings" && quickSettingsWindow.visible)
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
        implicitHeight: root.configuredPanelHeight
        minimumSize: Qt.size(root.minimumPanelWidth, root.minimumPanelHeight)
        maximumSize: Qt.size(root.maximumPanelWidth, root.maximumPanelHeight)

        onClosed: root.close()
        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => root.positionWindow());
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            color: Theme.popupBackground
            radius: 0
            focus: true
            Keys.onEscapePressed: root.close()

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: mouse => mouse.accepted = true
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
                            label: ""
                            available: root.settingsDirty
                            textSize: root.scaledIcon(12)
                            onClicked: root.saveDisplaySettings()
                        }

                        SettingsButton {
                            label: ""
                            active: root.settingsOpen
                            textSize: root.scaledIcon(11)
                            onClicked: root.toggleSettings()
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

                        onResetRequested: root.resetDisplaySettings()
                        onWidthAdjustmentRequested: delta => root.adjustPanelWidth(delta)
                        onHeightAdjustmentRequested: delta => root.adjustPanelHeight(delta)
                        onTextScaleAdjustmentRequested: delta => root.adjustTextScale(delta)
                        onIconScaleAdjustmentRequested: delta => root.adjustIconScale(delta)
                        onCaptureToggleRequested: root.toggleCaptureAllowed()
                        onCopyRequested: monitorNames => root.copyDisplaySettings(monitorNames)
                    }
                }

                Flickable {
                    id: contentFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.bottomMargin: root.placement === "top" ? 34 : 0
                    contentWidth: width
                    contentHeight: settingsColumn.implicitHeight + 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: settingsColumn
                        x: 6
                        y: 6
                        width: contentFlick.width - (contentScrollBar.visible ? 26 : 12)
                        spacing: 8

                        Rectangle {
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
                                            : "DDC unavailable"
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
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Bar · " + root.activeMonitorName
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                    }
                                    SettingsButton {
                                        label: root.barStatus.enabled ? "Visible" : "Hidden"
                                        active: Boolean(root.barStatus.enabled)
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction([
                                            "bar-enabled", root.activeMonitorName,
                                            root.barStatus.enabled ? "false" : "true"
                                        ], "Updating bar visibility…")
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
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
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: nightContent.implicitHeight + 16
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
                                    Text {
                                        Layout.fillWidth: true
                                        text: "SUPER+ALT+CTRL+- warmer  ·  SUPER+ALT+CTRL+= cooler  ·  SUPER+ALT+CTRL+BACKSPACE toggle"
                                        color: Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(8)
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: vibranceContent.implicitHeight + 16
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
                                }
                            }
                        }

                        Rectangle {
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
                                        label: "Start / Switch"
                                        available: Boolean(root.schedulerStatus.available)
                                            && root.selectedSchedulerName.length > 0
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction([
                                            "scheduler-start", root.selectedSchedulerName
                                        ], "Starting " + root.selectedSchedulerName + "…")
                                    }
                                    SettingsButton {
                                        label: "Stop"
                                        available: Boolean(root.schedulerStatus.enabled)
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction(["scheduler-stop"], "Stopping sched-ext…")
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !root.schedulerStatus.available || !root.schedulerStatus.authorized
                                    text: !root.schedulerStatus.available
                                        ? "scxctl is unavailable"
                                        : "Starting sched-ext needs the existing one-time scxctl authorization"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(9)
                                    wrapMode: Text.Wrap
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

            Rectangle {
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
    }
}
