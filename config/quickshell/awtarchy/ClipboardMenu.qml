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

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string backend: configHome + "/hypr/scripts/quickshell_clipboard.sh"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_flyout_position.sh"
    readonly property int minimumPanelWidth: Math.min(480, maximumPanelWidth)
    readonly property int minimumPanelHeight: Math.min(360, maximumPanelHeight)
    readonly property int targetScreenWidth: clipboardWindow.screen
        ? clipboardWindow.screen.width : 1920
    readonly property int targetScreenHeight: clipboardWindow.screen
        ? clipboardWindow.screen.height : 1080
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
    readonly property string activeMonitorName: clipboardWindow.screen ? clipboardWindow.screen.name : ""
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

        FlyoutManager.claim("clipboard");
        clipboardWindow.screen = target;
        placement = placementForScreen(target);
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        loadSavedView(target);
        search.text = "";
        clipboardWindow.visible = true;
        listProcess.running = true;
        Qt.callLater(() => {
            root.positionWindow();
            clipboardList.positionViewAtBeginning();
            search.forceActiveFocus();
        });
    }

    function openFocused() { openForScreen(focusedScreen()); }

    function close() {
        if (settingsDirty)
            discardDraft();
        clipboardWindow.visible = false;
        FlyoutManager.release("clipboard");
        search.text = "";
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }

    function toggleFocused() {
        if (clipboardWindow.visible)
            close();
        else
            openFocused();
    }

    function toggleForScreen(target) {
        const currentName = clipboardWindow.screen ? clipboardWindow.screen.name : "";
        const targetName = target ? target.name : "";
        if (clipboardWindow.visible && currentName.length > 0 && currentName === targetName)
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
        if (settingsOpen && settingsDirty)
            discardDraft();
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
                search.forceActiveFocus();
            });
        }
    }

    Connections {
        target: FlyoutManager
        function onCloseRequested(exceptSurface) {
            if (exceptSurface !== "clipboard" && clipboardWindow.visible)
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
                    search.forceActiveFocus();
                });
            }
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            color: Theme.popupBackground
            radius: 0

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
                    model: ScriptModel { values: root.filteredEntries() }
                    clip: true
                    currentIndex: count > 0 ? 0 : -1
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        readonly property int thumbnailSize: Math.max(48,
                            Math.min(160, Math.round(96 * root.effectiveIconScale / 100)))
                        height: modelData.thumb && modelData.thumb.length > 0
                            ? thumbnailSize + 20
                            : Math.max(40, Math.round(44 * root.effectiveTextScale / 100))
                        color: ListView.isCurrentItem ? Theme.focus : (rowMouse.containsMouse ? Theme.subtleHover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: clipboardScrollBar.visible ? 20 : 10
                            spacing: 12

                            Image {
                                visible: row.modelData.thumb && row.modelData.thumb.length > 0
                                Layout.preferredWidth: visible ? row.thumbnailSize : 0
                                Layout.preferredHeight: visible ? row.thumbnailSize : 0
                                source: visible ? "file://" + row.modelData.thumb : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.label
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.max(8, Math.round(14 * root.effectiveTextScale / 100))
                                elide: Text.ElideRight
                                maximumLineCount: 3
                                wrapMode: Text.WrapAnywhere
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
            }
        }
    }
}
