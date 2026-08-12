pragma ComponentBehavior: Bound

pragma Singleton

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property var entries: []
    property string placement: "center"
    property bool settingsOpen: false
    property bool detailOpen: false
    property var detailEntry: null
    property string detailText: ""
    property bool detailLoading: false
    property string detailError: ""
    property int panelWidthOverride: -1
    property int panelHeightOverride: -1
    property int textScaleOverride: -1
    property int iconScaleOverride: -1
    property int captureAllowedOverride: -1
    property string settingsMessage: ""
    property var savedView: ({
        width: BarState.defaultClipboardWidth,
        height: BarState.defaultClipboardHeight,
        textScale: 100,
        iconScale: 100,
        captureAllowed: false
    })
    property var stateCommandQueue: []
    property bool privacyRemapPending: false
    property bool openPreparing: false
    property var flyoutScreen: null

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string backend: configHome + "/hypr/scripts/quickshell_clipboard.sh"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_flyout_position.sh"
    readonly property string prepareScript: configHome + "/hypr/scripts/quickshell_flyout_prepare.sh"
    readonly property var activeScreen: flyoutScreen || clipboardWindow.screen
    readonly property int minimumPanelWidth: Math.min(480, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(360, maximumPanelHeight)
    readonly property int targetScreenWidth: activeScreen ? activeScreen.width : 1920
    readonly property int targetScreenHeight: activeScreen ? activeScreen.height : 1080
    readonly property int maximumPanelWidth: Math.max(1, targetScreenWidth - 20)
    readonly property int maximumPanelHeight: Math.max(1, targetScreenHeight - 20)
    readonly property int configuredPanelWidth: clampWidth(panelWidthOverride >= 0
        ? panelWidthOverride : BarState.clipboardViewFor(activeMonitorName).width)
    readonly property int configuredPanelHeight: clampHeight(panelHeightOverride >= 0
        ? panelHeightOverride : BarState.clipboardViewFor(activeMonitorName).height)
    readonly property int livePanelWidth: clipboardWindow.visible && clipboardWindow.width > 0
        ? clampWidth(Math.round(clipboardWindow.width)) : configuredPanelWidth
    readonly property int livePanelHeight: clipboardWindow.visible && clipboardWindow.height > 0
        ? clampHeight(Math.round(clipboardWindow.height)) : configuredPanelHeight
    readonly property int effectiveTextScale: textScaleOverride >= 0
        ? textScaleOverride : BarState.clipboardViewFor(activeMonitorName).textScale
    readonly property int effectiveIconScale: iconScaleOverride >= 0
        ? iconScaleOverride : BarState.clipboardViewFor(activeMonitorName).iconScale
    readonly property bool captureAllowed: captureAllowedOverride >= 0
        ? captureAllowedOverride === 1 : BarState.captureAllowedFor("clipboard")
    readonly property string activeMonitorName: activeScreen && activeScreen.name
        ? String(activeScreen.name) : ""
    readonly property bool settingsDirty: savedView.width !== livePanelWidth
        || savedView.height !== livePanelHeight
        || savedView.textScale !== effectiveTextScale
        || savedView.iconScale !== effectiveIconScale
        || savedView.captureAllowed !== captureAllowed

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
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
        if (clipboardWindow.visible && activeMonitorName.length > 0) {
            Quickshell.execDetached([
                positionScript, "clipboard", activeMonitorName, placement, "resize",
                String(panelWidthOverride), String(panelHeightOverride)
            ]);
        }
    }

    function positionWindow() {
        if (!clipboardWindow.visible || activeMonitorName.length === 0)
            return;
        Quickshell.execDetached([
            positionScript, "clipboard", activeMonitorName, placement, "spawn"
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
            "bash", prepareScript, "clipboard", targetScreen.name, placement,
            String(configuredPanelWidth), String(configuredPanelHeight),
            String(barSize), "-1",
            String(Math.round(targetScreen.width)), String(Math.round(targetScreen.height))
        ]);
    }

    function finishPreparedOpen() {
        if (!openPreparing)
            return;

        const wasVisible = clipboardWindow.visible;

        openPreparing = false;
        clipboardWindow.visible = true;
        if (wasVisible)
            Qt.callLater(() => root.positionWindow());
        listProcess.running = true;
        Qt.callLater(() => {
            clipboardList.positionViewAtBeginning();
            search.forceActiveFocus();
        });
    }

    function loadSavedView(targetScreen) {
        if (!targetScreen)
            return;

        BarState.refresh();
        const persisted = BarState.clipboardViewFor(targetScreen.name);
        panelWidthOverride = clampWidth(persisted.width);
        panelHeightOverride = clampHeight(persisted.height);
        textScaleOverride = persisted.textScale;
        iconScaleOverride = persisted.iconScale;
        captureAllowedOverride = BarState.captureAllowedFor("clipboard") ? 1 : 0;
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

    function openForScreen(target) {
        if (!target)
            return;

        FlyoutManager.claim("clipboard", target.name);
        flyoutScreen = target;
        if (!clipboardWindow.visible)
            clipboardWindow.screen = target;
        placement = placementForScreen(target);
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        closeDetail();
        loadSavedView(target);
        search.text = "";
        prepareWindowOpen(target);
    }

    function openFocused() { openForScreen(focusedScreen()); }

    function close() {
        openPreparing = false;
        if (prepareProcess.running)
            prepareProcess.running = false;
        if (settingsDirty)
            discardDraft();
        clipboardWindow.visible = false;
        FlyoutManager.release("clipboard");
        search.text = "";
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        closeDetail();
    }

    function toggleFocused() {
        if (clipboardWindow.visible || openPreparing)
            close();
        else
            openFocused();
    }

    function toggleForScreen(target) {
        const currentName = activeMonitorName;
        const targetName = target ? target.name : "";
        if ((clipboardWindow.visible || openPreparing)
            && currentName.length > 0 && currentName === targetName)
            close();
        else
            openForScreen(target);
    }

    function otherMonitorNames() {
        return Quickshell.screens
            .map(target => target ? target.name : "")
            .filter(name => name.length > 0 && name !== activeMonitorName);
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
            "save-flyout", "clipboard", activeMonitorName,
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            captureAllowed ? "true" : "false"
        ]);
        panelWidthOverride = livePanelWidth;
        panelHeightOverride = livePanelHeight;
        acceptDraftAsSaved();
        settingsMessage = "Saved Clipboard settings for " + activeMonitorName;
    }

    function resetDisplaySettings() {
        if (activeMonitorName.length === 0)
            return;
        const wasCaptureAllowed = captureAllowed;
        textScaleOverride = 100;
        iconScaleOverride = 100;
        captureAllowedOverride = 0;
        applyWindowSize(BarState.defaultClipboardWidth, BarState.defaultClipboardHeight);
        savedView = ({
            width: panelWidthOverride,
            height: panelHeightOverride,
            textScale: 100,
            iconScale: 100,
            captureAllowed: false
        });
        privacyRemapPending = wasCaptureAllowed;
        queueStateCommand(["reset-flyout", "clipboard", activeMonitorName]);
        settingsMessage = "Clipboard defaults restored for " + activeMonitorName;
    }

    function copyDisplaySettings(targets) {
        if (!targets || targets.length === 0)
            return;
        queueStateCommand([
            "copy-flyout", "clipboard",
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            ...targets
        ]);
        settingsMessage = "Copied Clipboard settings to " + targets.length
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
        queueStateCommand(["set-capture", "clipboard", next ? "true" : "false"]);
        settingsMessage = next
            ? "Clipboard is visible in captures" : "Clipboard capture protection enabled";
    }

    function toggleSettings() {
        settingsOpen = !settingsOpen;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function choose(entry) {
        if (!entry)
            return;
        selectProcess.exec([backend, "select", String(entry.index)]);
        close();
    }

    function openDetail(entry) {
        if (!entry || entry.binary)
            return;
        detailEntry = entry;
        detailText = "";
        detailError = "";
        detailLoading = true;
        detailOpen = true;
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        detailProcess.exec([backend, "decode", String(entry.index)]);
    }

    function closeDetail() {
        detailOpen = false;
        detailEntry = null;
        detailText = "";
        detailError = "";
        detailLoading = false;
        if (clipboardWindow.visible)
            Qt.callLater(() => search.forceActiveFocus());
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
            const found = haystack.indexOf(query[i], at);
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

    function filteredEntries() {
        const query = search.text.trim().toLowerCase();
        const scored = entries.map(entry => ({
            entry: entry,
            score: fuzzyScore(String(entry.label || "").toLowerCase(), query)
        })).filter(item => item.score >= 0);

        if (query.length > 0)
            scored.sort((a, b) => b.score - a.score);
        return scored.map(item => item.entry);
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggleFocused(); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
    }

    Process {
        id: prepareProcess
        onExited: root.finishPreparedOpen()
    }

    Process {
        id: listProcess
        command: [root.backend, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.entries = JSON.parse(text.trim() || "[]");
                    clipboardList.currentIndex = root.entries.length > 0 ? 0 : -1;
                    Qt.callLater(() => clipboardList.positionViewAtBeginning());
                } catch (error) {
                    console.warn("Awtarchy clipboard list parse failed:", error);
                    root.entries = [];
                }
            }
        }
    }

    Process {
        id: detailProcess
        stdout: StdioCollector {
            onStreamFinished: {
                root.detailText = text;
                root.detailLoading = false;
                if (root.detailOpen)
                    Qt.callLater(() => detailTextArea.forceActiveFocus());
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.detailError = errorText.split("\n")[0];
            }
        }
        onExited: {
            if (root.detailLoading)
                root.detailLoading = false;
            if (root.detailOpen && root.detailText.length === 0 && root.detailError.length === 0)
                root.detailError = "Clipboard text is empty or unavailable";
        }
    }

    Process { id: selectProcess }

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
            if (!clipboardWindow.visible)
                return;
            clipboardWindow.visible = false;
            Qt.callLater(() => {
                clipboardWindow.visible = true;
                root.positionWindow();
                if (root.detailOpen)
                    detailTextArea.forceActiveFocus();
                else
                    search.forceActiveFocus();
            });
        }
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "clipboard"
                && (clipboardWindow.visible || root.openPreparing))
                root.close();
        }
    }

    FloatingWindow {
        id: clipboardWindow
        visible: false
        title: "Awtarchy Clipboard History"
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: root.configuredPanelWidth
        implicitHeight: root.configuredPanelHeight
        minimumSize: Qt.size(root.minimumPanelWidth, root.minimumPanelHeight)
        maximumSize: Qt.size(root.maximumPanelWidth, root.maximumPanelHeight)

        onClosed: root.close()
        onVisibleChanged: {
            if (visible) {
                Qt.callLater(() => {
                    root.positionWindow();
                    if (root.detailOpen)
                        detailTextArea.forceActiveFocus();
                    else
                        search.forceActiveFocus();
                });
            }
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
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: "Clipboard"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.max(10, Math.round(14 * root.effectiveTextScale / 100))
                            font.weight: Font.Medium
                        }

                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: !root.detailOpen
                            enabled: visible
                            color: Theme.foreground
                            selectionColor: Theme.focus
                            selectedTextColor: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.max(10, Math.round(14 * root.effectiveTextScale / 100))
                            font.weight: Font.Medium
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    root.close();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down && clipboardList.count > 0) {
                                    clipboardList.currentIndex = Math.min(clipboardList.count - 1, clipboardList.currentIndex + 1);
                                    clipboardList.positionViewAtIndex(clipboardList.currentIndex, ListView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up && clipboardList.count > 0) {
                                    clipboardList.currentIndex = Math.max(0, clipboardList.currentIndex - 1);
                                    clipboardList.positionViewAtIndex(clipboardList.currentIndex, ListView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    const values = root.filteredEntries();
                                    if (clipboardList.currentIndex >= 0 && clipboardList.currentIndex < values.length)
                                        root.choose(values[clipboardList.currentIndex]);
                                    event.accepted = true;
                                }
                            }

                            onTextChanged: {
                                clipboardList.currentIndex = 0;
                                Qt.callLater(() => clipboardList.positionViewAtBeginning());
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            visible: root.detailOpen
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

                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 26
                            color: closeMouse.containsMouse ? Theme.focus : "transparent"
                            border.width: 0

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
                                onClicked: root.close()
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
                        surfaceLabel: "Clipboard"
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

                ListView {
                    id: clipboardList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.detailOpen
                    model: ScriptModel { values: root.filteredEntries() }
                    clip: true
                    currentIndex: count > 0 ? 0 : -1
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        readonly property string thumbnailPath: modelData && modelData.thumb
                            ? String(modelData.thumb) : ""
                        readonly property bool hasThumbnail: thumbnailPath.length > 0
                        readonly property string previewLabel: modelData
                            ? String(modelData.label || "").replace(/[\r\n]+/g, " ") : ""
                        readonly property int thumbnailSize: Math.max(48,
                            Math.min(160, Math.round(96 * root.effectiveIconScale / 100)))
                        readonly property color previewBackground: ListView.isCurrentItem
                            ? Theme.focus
                            : ((rowMouse.containsMouse || viewMouse.containsMouse)
                                ? Theme.subtleHover : Theme.popupBackground)
                        height: hasThumbnail
                            ? thumbnailSize + 20
                            : Math.max(40, Math.round(44 * root.effectiveTextScale / 100))
                        color: previewBackground

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: (clipboardScrollBar.visible ? 20 : 10)
                                + (viewButton.visible ? 36 : 0)
                            spacing: 12

                            Image {
                                visible: row.hasThumbnail
                                Layout.preferredWidth: row.hasThumbnail ? row.thumbnailSize : 0
                                Layout.preferredHeight: row.hasThumbnail ? row.thumbnailSize : 0
                                source: row.hasThumbnail ? "file://" + row.thumbnailPath : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                            }

                            Text {
                                id: previewText
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: row.previewLabel
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.max(8, Math.round(14 * root.effectiveTextScale / 100))
                                wrapMode: Text.NoWrap
                                elide: Text.ElideNone
                                clip: true
                            }
                        }

                        Rectangle {
                            id: previewFade
                            visible: Boolean(row.modelData)
                                && row.modelData.binary === false
                                && previewText.contentWidth > previewText.width + 1
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.rightMargin: (clipboardScrollBar.visible ? 20 : 10)
                                + (viewButton.visible ? 36 : 0)
                            width: Math.min(56, Math.max(32, row.width * 0.08))
                            z: 8
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop {
                                    position: 0.0
                                    color: Qt.rgba(row.previewBackground.r,
                                        row.previewBackground.g,
                                        row.previewBackground.b, 0)
                                }
                                GradientStop {
                                    position: 1.0
                                    color: row.previewBackground
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: clipboardList.currentIndex = row.index
                            onClicked: root.choose(row.modelData)
                            onWheel: wheel => {
                                const minY = clipboardList.originY;
                                const maxY = Math.max(minY,
                                    minY + clipboardList.contentHeight - clipboardList.height);
                                clipboardList.contentY = Math.max(minY,
                                    Math.min(maxY, clipboardList.contentY - wheel.angleDelta.y));
                                wheel.accepted = true;
                            }
                        }

                        Rectangle {
                            id: viewButton
                            visible: Boolean(row.modelData)
                                && row.modelData.binary === false
                                && (rowMouse.containsMouse || viewMouse.containsMouse)
                            width: 28
                            height: 28
                            anchors.right: parent.right
                            anchors.rightMargin: clipboardScrollBar.visible ? 18 : 7
                            anchors.verticalCenter: parent.verticalCenter
                            color: viewMouse.containsMouse ? Theme.focus : Theme.active
                            border.width: 1
                            border.color: Theme.focus
                            z: 20

                            Text {
                                anchors.centerIn: parent
                                text: ""
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.max(9,
                                    Math.round(12 * root.effectiveIconScale / 100))
                            }

                            MouseArea {
                                id: viewMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    root.openDetail(row.modelData);
                                    mouse.accepted = true;
                                }
                            }
                        }
                    }

                    ListScrollBar {
                        id: clipboardScrollBar
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        flickable: clipboardList
                        z: 10
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.detailOpen

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            color: Theme.popupButton
                            border.width: 0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                SettingsButton {
                                    label: "← Back"
                                    textSize: Math.max(9,
                                        Math.round(10 * root.effectiveTextScale / 100))
                                    onClicked: root.closeDetail()
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.detailLoading
                                        ? "Loading full clipboard text…" : "Full clipboard text"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Math.max(9,
                                        Math.round(11 * root.effectiveTextScale / 100))
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }

                                SettingsButton {
                                    label: "Select All"
                                    available: !root.detailLoading && root.detailText.length > 0
                                    textSize: Math.max(9,
                                        Math.round(10 * root.effectiveTextScale / 100))
                                    onClicked: detailTextArea.selectAll()
                                }

                                SettingsButton {
                                    label: "Copy Selected"
                                    available: !root.detailLoading
                                        && detailTextArea.selectionStart !== detailTextArea.selectionEnd
                                    textSize: Math.max(9,
                                        Math.round(10 * root.effectiveTextScale / 100))
                                    onClicked: detailTextArea.copy()
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            Layout.rightMargin: 10
                            Layout.topMargin: 6
                            Layout.bottomMargin: 6
                            text: "Select text with the mouse · Ctrl+C or Copy Selected"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.max(8,
                                Math.round(9 * root.effectiveTextScale / 100))
                            elide: Text.ElideRight
                        }

                        Flickable {
                            id: detailFlick
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: Math.max(height, detailTextArea.height + 20)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            TextEdit {
                                id: detailTextArea
                                x: 10
                                y: 10
                                width: Math.max(1, detailFlick.width
                                    - (detailScrollBar.visible ? 34 : 20))
                                height: Math.max(detailFlick.height - 20, contentHeight)
                                text: root.detailText
                                readOnly: true
                                selectByMouse: true
                                persistentSelection: true
                                textFormat: TextEdit.PlainText
                                wrapMode: TextEdit.Wrap
                                color: Theme.foreground
                                selectionColor: Theme.focus
                                selectedTextColor: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.max(9,
                                    Math.round(13 * root.effectiveTextScale / 100))

                                Keys.onPressed: event => {
                                    if ((event.modifiers & Qt.ControlModifier)
                                        && event.key === Qt.Key_C) {
                                        copy();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Escape) {
                                        root.closeDetail();
                                        event.accepted = true;
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: root.detailLoading
                                    || root.detailError.length > 0
                                    || (!root.detailLoading && root.detailText.length === 0)
                                text: root.detailLoading ? "Loading…"
                                    : (root.detailError.length > 0
                                        ? root.detailError : "Clipboard text is empty")
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.max(9,
                                    Math.round(11 * root.effectiveTextScale / 100))
                                horizontalAlignment: Text.AlignHCenter
                            }

                            ListScrollBar {
                                id: detailScrollBar
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                flickable: detailFlick
                                z: 10
                            }
                        }
                    }
                }
            }
        }
    }
}
