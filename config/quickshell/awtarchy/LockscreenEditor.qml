pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string stateBackend: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string contrastBackend: configHome + "/hypr/scripts/quickshell_lockscreen_contrast.sh"
    readonly property string wallpaperPickerBackend: configHome + "/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
    readonly property bool open: editorWindow.visible
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]

    property var draftLayout: defaultLayout()
    property var draftVisibility: defaultVisibility()
    property string draftBackgroundMode: "black"
    property string draftBackgroundColor: "#000000"
    property string draftWallpaperPath: ""
    property var draftAutoAccents: defaultAutoAccents()
    property string selectedElement: "logo"
    property string statusMessage: ""
    property bool elementPaletteOpen: false
    property bool backgroundPaletteOpen: false
    property bool contrastRefreshPending: false

    function defaultLayout() {
        return ({
            logo: ({ x: 0.50, y: 0.34, scale: 1.0, color: "auto" }),
            time: ({ x: 0.50, y: 0.51, scale: 1.0, color: "auto" }),
            date: ({ x: 0.50, y: 0.555, scale: 1.0, color: "auto" }),
            username: ({ x: 0.50, y: 0.595, scale: 1.0, color: "auto" }),
            weather: ({ x: 0.50, y: 0.635, scale: 1.0, color: "auto" }),
            password: ({ x: 0.50, y: 0.70, scale: 1.0, color: "auto" })
        });
    }

    function defaultVisibility() {
        return ({
            logo: true,
            time: false,
            date: false,
            username: false,
            weather: false,
            password: true
        });
    }

    function defaultAutoAccents() {
        return ({
            logo: "#ffffff",
            time: "#ffffff",
            date: "#ffffff",
            username: "#ffffff",
            weather: "#ffffff",
            password: "#ffffff"
        });
    }

    function validHex(value) {
        return /^#[0-9a-f]{6}$/.test(String(value || "").toLowerCase());
    }

    function setAllDraftColors(colorValue) {
        const value = String(colorValue || "").trim().toLowerCase();
        if (value !== "auto" && !validHex(value))
            return;
        const next = cloneLayout(draftLayout);
        for (const name of elementNames)
            next[name].color = value;
        draftLayout = next;
        statusMessage = value === "auto" ? "All elements use Auto contrast"
            : "All element colors updated";
    }

    function resetElementPosition(name) {
        if (elementNames.indexOf(name) < 0)
            return;
        const defaults = defaultLayout();
        const next = cloneLayout(draftLayout);
        next[name].x = defaults[name].x;
        next[name].y = defaults[name].y;
        draftLayout = next;
        selectedElement = name;
        statusMessage = elementLabel(name) + " position reset";
        scheduleContrastRefresh();
    }

    function setDraftBackgroundMode(mode) {
        const value = String(mode || "");
        if (["black", "wallpaper", "color"].indexOf(value) < 0)
            return;
        if (value === "wallpaper" && draftWallpaperPath.length === 0) {
            statusMessage = "Choose a lockscreen wallpaper first";
            return;
        }
        draftBackgroundMode = value;
        statusMessage = "";
        scheduleContrastRefresh();
    }

    function setDraftBackgroundColor(colorValue) {
        const value = String(colorValue || "").trim().toLowerCase();
        if (!validHex(value)) {
            statusMessage = "Background color must be #RRGGBB";
            return;
        }
        draftBackgroundColor = value;
        draftBackgroundMode = "color";
        statusMessage = "";
        scheduleContrastRefresh();
    }

    function acceptWallpaperSelection(line) {
        if (!open)
            return;
        const value = String(line || "").trim();
        if (!value.startsWith("/") || value.indexOf("://") >= 0) {
            statusMessage = "Awtwall returned an invalid local wallpaper";
            return;
        }
        draftWallpaperPath = value;
        draftBackgroundMode = "wallpaper";
        statusMessage = "Wallpaper selected. Save to apply.";
        scheduleContrastRefresh();
    }

    function scheduleContrastRefresh() {
        if (!open)
            return;
        contrastRefreshPending = true;
        contrastRefreshDelay.restart();
    }

    function refreshPreviewContrast() {
        if (!open)
            return;
        if (previewContrastProcess.running) {
            contrastRefreshPending = true;
            return;
        }
        contrastRefreshPending = false;
        previewContrastProcess.exec([
            "bash", contrastBackend, "--stdout",
            "--background", draftBackgroundMode,
            "--background-color", draftBackgroundColor,
            "--wallpaper", draftWallpaperPath,
            "--layout-json", JSON.stringify(draftLayout)
        ]);
    }

    function applyPreviewContrastLine(line) {
        try {
            const payload = JSON.parse(String(line || ""));
            if (!payload || payload.provider !== "awtarchy-local-contrast"
                    || !payload.colors || typeof payload.colors !== "object")
                return;
            const next = defaultAutoAccents();
            for (const name of elementNames) {
                const value = String(payload.colors[name] || "").toLowerCase();
                next[name] = validHex(value) ? value : "#ffffff";
            }
            draftAutoAccents = next;
        } catch (error) {
            // Keep the current safe preview colors on malformed helper output.
        }
    }

    function cloneObject(value, fallback) {
        try {
            const parsed = JSON.parse(JSON.stringify(value));
            return parsed && typeof parsed === "object" ? parsed : fallback();
        } catch (error) {
            return fallback();
        }
    }

    function cloneLayout(value) {
        const cloned = cloneObject(value, defaultLayout);
        const defaults = defaultLayout();
        const result = ({});
        for (const name of elementNames) {
            const raw = cloned[name] || defaults[name];
            const password = name === "password";
            const x = Number(raw.x);
            const y = Number(raw.y);
            const scale = Number(raw.scale === undefined ? 1 : raw.scale);
            const rawColor = String(raw.color === undefined ? "auto" : raw.color);
            const color = rawColor === "auto" || /^#[0-9a-fA-F]{6}$/.test(rawColor)
                ? rawColor.toLowerCase() : "auto";
            result[name] = ({
                x: Math.max(password ? 0.15 : 0.05,
                    Math.min(password ? 0.85 : 0.95,
                        Number.isFinite(x) ? x : defaults[name].x)),
                y: Math.max(password ? 0.20 : 0.08,
                    Math.min(password ? 0.86 : 0.92,
                        Number.isFinite(y) ? y : defaults[name].y)),
                scale: Math.max(0.50, Math.min(2.00,
                    Number.isFinite(scale) ? scale : 1)),
                color: color
            });
        }
        return result;
    }

    function cloneVisibility(value) {
        const defaults = defaultVisibility();
        const cloned = cloneObject(value, defaultVisibility);
        const result = ({});
        for (const name of elementNames)
            result[name] = name === "password" ? true
                : (typeof cloned[name] === "boolean" ? cloned[name] : defaults[name]);
        return result;
    }

    function clampPoint(name, x, y) {
        const password = name === "password";
        return ({
            x: Math.max(password ? 0.15 : 0.05, Math.min(password ? 0.85 : 0.95, x)),
            y: Math.max(password ? 0.20 : 0.08, Math.min(password ? 0.86 : 0.92, y))
        });
    }

    function setDraftPoint(name, x, y) {
        if (elementNames.indexOf(name) < 0)
            return;
        const next = cloneLayout(draftLayout);
        const point = clampPoint(name, Number(x), Number(y));
        next[name] = ({
            x: point.x,
            y: point.y,
            scale: next[name].scale,
            color: next[name].color
        });
        draftLayout = next;
        selectedElement = name;
        scheduleContrastRefresh();
    }

    function elementScale(name) {
        const point = draftLayout[name] || defaultLayout()[name];
        const value = Number(point.scale === undefined ? 1 : point.scale);
        return Number.isFinite(value) ? Math.max(0.50, Math.min(2.00, value)) : 1;
    }

    function elementColor(name) {
        const point = draftLayout[name] || defaultLayout()[name];
        const value = String(point.color === undefined ? "auto" : point.color);
        return value === "auto" || /^#[0-9a-fA-F]{6}$/.test(value)
            ? value.toLowerCase() : "auto";
    }

    function setDraftColor(name, colorValue) {
        if (elementNames.indexOf(name) < 0)
            return;
        const value = String(colorValue || "").trim().toLowerCase();
        if (value !== "auto" && !/^#[0-9a-f]{6}$/.test(value)) {
            statusMessage = "Color must be Auto or #RRGGBB";
            return;
        }
        const next = cloneLayout(draftLayout);
        next[name].color = value;
        draftLayout = next;
        selectedElement = name;
        statusMessage = "";
    }

    function setDraftScale(name, scale) {
        if (elementNames.indexOf(name) < 0)
            return;
        const next = cloneLayout(draftLayout);
        const value = Number(scale);
        if (!Number.isFinite(value))
            return;
        next[name].scale = Math.round(Math.max(0.50, Math.min(2.00, value)) * 100) / 100;
        draftLayout = next;
        selectedElement = name;
    }

    function elementCanHide(name) {
        return name !== "password";
    }

    function setDraftVisible(name, visible) {
        if (elementNames.indexOf(name) < 0 || !elementCanHide(name))
            return;
        const next = cloneVisibility(draftVisibility);
        next[name] = !!visible;
        draftVisibility = next;
        selectedElement = name;
    }

    function elementEnabled(name) {
        return draftVisibility[name] !== false;
    }

    function resetDraft() {
        draftLayout = defaultLayout();
        draftVisibility = defaultVisibility();
        draftBackgroundMode = "black";
        draftBackgroundColor = "#000000";
        draftWallpaperPath = "";
        draftAutoAccents = defaultAutoAccents();
        selectedElement = "logo";
        elementPaletteOpen = false;
        backgroundPaletteOpen = false;
        statusMessage = "Defaults loaded. Save to apply.";
        scheduleContrastRefresh();
    }

    function loadPersistedDraft() {
        draftLayout = cloneLayout(BarState.lockscreenLayout());
        draftVisibility = cloneVisibility(({
            logo: BarState.lockscreenShowLogo(),
            time: BarState.lockscreenShowTime(),
            date: BarState.lockscreenShowDate(),
            username: BarState.lockscreenShowUsername(),
            weather: BarState.lockscreenShowWeather(),
            password: true
        }));
        draftBackgroundMode = BarState.lockscreenBackground();
        draftBackgroundColor = BarState.lockscreenBackgroundColor();
        draftWallpaperPath = BarState.lockscreenWallpaperPath();
        draftAutoAccents = defaultAutoAccents();
        selectedElement = elementNames.indexOf(selectedElement) >= 0 ? selectedElement : "logo";
        elementPaletteOpen = false;
        backgroundPaletteOpen = false;
        statusMessage = "";
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; ++i) {
            if (screens[i] && screens[i].name === name)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    function openForScreen(target) {
        if (target)
            editorWindow.screen = target;
        loadPersistedDraft();
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        scheduleContrastRefresh();
        Qt.callLater(() => editorFocus.forceActiveFocus());
    }

    function openFocused() {
        openForScreen(focusedScreen());
    }

    function close() {
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        loadPersistedDraft();
    }

    function save() {
        if (saveProcess.running || contrastPersistProcess.running)
            return;
        statusMessage = "Saving…";
        saveProcess.exec([
            "bash",
            stateBackend,
            "save-lockscreen-editor",
            JSON.stringify(draftLayout),
            JSON.stringify(draftVisibility),
            draftBackgroundMode,
            draftBackgroundColor,
            draftWallpaperPath
        ]);
    }

    function elementLabel(name) {
        if (name === "logo") return "Logo";
        if (name === "time") return "Time";
        if (name === "date") return "Date";
        if (name === "username") return "Username";
        if (name === "weather") return "Weather";
        if (name === "password") return "Password";
        return name;
    }

    Process {
        id: saveProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                BarState.refresh();
                root.statusMessage = "Refreshing Auto contrast…";
                contrastPersistProcess.exec(["bash", root.contrastBackend]);
            } else {
                root.statusMessage = "Could not save lockscreen presentation";
            }
        }
    }

    Process {
        id: contrastPersistProcess
        onExited: (exitCode, exitStatus) => {
            root.statusMessage = exitCode === 0 ? "Saved"
                : "Saved; Auto contrast cache could not refresh";
            closeAfterSave.restart();
        }
    }

    Timer {
        id: closeAfterSave
        interval: 180
        repeat: false
        onTriggered: root.close()
    }

    LockPreviewWallpaperState {
        id: wallpaperState
        path: root.draftWallpaperPath
    }

    Timer {
        id: contrastRefreshDelay
        interval: 120
        repeat: false
        onTriggered: root.refreshPreviewContrast()
    }

    Process {
        id: previewContrastProcess
        stdout: SplitParser {
            onRead: line => root.applyPreviewContrastLine(line)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.contrastRefreshPending)
                contrastRefreshDelay.restart();
        }
    }

    Process {
        id: wallpaperPickerProcess
        stdout: SplitParser {
            onRead: line => root.acceptWallpaperSelection(line)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.open && exitCode !== 0 && root.statusMessage.length === 0)
                root.statusMessage = "Lockscreen wallpaper picker closed";
        }
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: root.open
        autoRepeat: false
        onActivated: root.close()
    }

    PanelWindow {
        id: editorWindow
        WlrLayershell.namespace: "awtarchy-lockscreen-editor"
        visible: false
        color: "transparent"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.left: true
        implicitWidth: Math.max(1, screen ? screen.width : 1920)
        implicitHeight: Math.max(1, screen ? screen.height : 1080)

        Rectangle {
            id: editorFocus
            anchors.fill: parent
            color: "#000000"
            focus: true

            LockPreviewScene {
                id: previewScene
                anchors.fill: parent
                theme: Theme
                animationPreference: BarState.lockscreenAnimationPreference()
                randomFormationMode: 3
                audioReactive: false
                audioLow: 0
                audioMid: 0
                audioHigh: 0
                audioOverall: 0
                mouseInteractive: BarState.lockscreenMouseInteractiveEnabled()
                showLogo: root.draftVisibility.logo
                showTime: root.draftVisibility.time
                showDate: root.draftVisibility.date
                showUsername: root.draftVisibility.username
                showWeather: root.draftVisibility.weather
                weatherText: "72°F · Clear"
                backgroundMode: root.draftBackgroundMode
                wallpaperSource: wallpaperState.source
                backgroundColor: root.draftBackgroundColor
                autoAccents: root.draftAutoAccents
                layout: root.draftLayout
                previewMode: true
                editorMode: true
                editorVisibility: root.draftVisibility
            }

            Repeater {
                model: root.elementNames

                Rectangle {
                    required property string modelData
                    readonly property string elementName: modelData
                    readonly property bool enabledElement: root.elementEnabled(elementName)
                    readonly property var point: root.draftLayout[elementName]
                        || root.defaultLayout()[elementName]
                    width: Math.max(30, previewScene.elementVisualWidth(elementName) + 14)
                    height: Math.max(26, previewScene.elementVisualHeight(elementName) + 12)
                    x: Math.max(0, Math.min(parent.width - width,
                        Number(point.x) * parent.width - width / 2))
                    y: Math.max(0, Math.min(parent.height - height,
                        Number(point.y) * parent.height - height / 2))
                    color: "transparent"
                    border.width: root.selectedElement === elementName ? 2 : 1
                    border.color: root.selectedElement === elementName ? Theme.focus : Theme.muted
                    opacity: 0.92
                    z: 200

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeAllCursor
                        preventStealing: true
                        property real pressOffsetX: 0
                        property real pressOffsetY: 0

                        onPressed: mouse => {
                            root.selectedElement = parent.elementName;
                            pressOffsetX = mouse.x;
                            pressOffsetY = mouse.y;
                        }

                        onPositionChanged: mouse => {
                            if (!pressed || editorFocus.width <= 0 || editorFocus.height <= 0)
                                return;
                            const scenePoint = parent.mapToItem(editorFocus,
                                mouse.x - pressOffsetX + parent.width / 2,
                                mouse.y - pressOffsetY + parent.height / 2);
                            root.setDraftPoint(parent.elementName,
                                scenePoint.x / editorFocus.width,
                                scenePoint.y / editorFocus.height);
                        }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 184 + ((root.elementPaletteOpen || root.backgroundPaletteOpen) ? 150 : 0)
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.muted
                z: 300

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: root.elementLabel(root.selectedElement)
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }

                        SettingsButton {
                            label: root.selectedElement === "logo"
                                ? (root.elementEnabled("logo") ? "Logo visible" : "Logo hidden")
                                : root.elementCanHide(root.selectedElement)
                                    ? (root.elementEnabled(root.selectedElement) ? "Visible" : "Hidden")
                                    : "Always visible"
                            active: root.elementEnabled(root.selectedElement)
                            available: root.elementCanHide(root.selectedElement)
                            textSize: 9
                            onClicked: root.setDraftVisible(root.selectedElement,
                                !root.elementEnabled(root.selectedElement))
                        }

                        Text {
                            text: "Scale"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        SettingsButton {
                            label: "−"
                            available: root.elementScale(root.selectedElement) > 0.50
                            textSize: 10
                            onClicked: root.setDraftScale(root.selectedElement,
                                root.elementScale(root.selectedElement) - 0.10)
                        }

                        Text {
                            text: Math.round(root.elementScale(root.selectedElement) * 100) + "%"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            Layout.preferredWidth: 42
                            horizontalAlignment: Text.AlignHCenter
                        }

                        SettingsButton {
                            label: "+"
                            available: root.elementScale(root.selectedElement) < 2.00
                            textSize: 10
                            onClicked: root.setDraftScale(root.selectedElement,
                                root.elementScale(root.selectedElement) + 0.10)
                        }

                        SettingsButton {
                            label: "Reset Position"
                            textSize: 9
                            onClicked: root.resetElementPosition(root.selectedElement)
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.statusMessage.length > 0
                                ? root.statusMessage
                                : "Drag the actual lockscreen visuals. Hidden items stay faded so they can be restored."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.maximumWidth: 470
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: "Element color"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        SettingsButton {
                            label: "Auto"
                            active: root.elementColor(root.selectedElement) === "auto"
                            textSize: 9
                            onClicked: root.setDraftColor(root.selectedElement, "auto")
                        }
                        SettingsButton {
                            label: "White"
                            active: root.elementColor(root.selectedElement) === "#ffffff"
                            textSize: 9
                            onClicked: root.setDraftColor(root.selectedElement, "#ffffff")
                        }
                        SettingsButton {
                            label: "Black"
                            active: root.elementColor(root.selectedElement) === "#000000"
                            textSize: 9
                            onClicked: root.setDraftColor(root.selectedElement, "#000000")
                        }
                        SettingsButton {
                            label: "Custom"
                            active: root.elementPaletteOpen
                            textSize: 9
                            onClicked: {
                                root.elementPaletteOpen = !root.elementPaletteOpen;
                                if (root.elementPaletteOpen)
                                    root.backgroundPaletteOpen = false;
                            }
                        }

                        Text {
                            text: "All:"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        SettingsButton { label: "Auto All"; textSize: 9; onClicked: root.setAllDraftColors("auto") }
                        SettingsButton { label: "White All"; textSize: 9; onClicked: root.setAllDraftColors("#ffffff") }
                        SettingsButton { label: "Black All"; textSize: 9; onClicked: root.setAllDraftColors("#000000") }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "Auto is calculated independently around each element."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: "Background"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        SettingsButton {
                            label: "Black"
                            active: root.draftBackgroundMode === "black"
                            textSize: 9
                            onClicked: root.setDraftBackgroundMode("black")
                        }
                        SettingsButton {
                            label: "Wallpaper"
                            active: root.draftBackgroundMode === "wallpaper"
                            textSize: 9
                            onClicked: {
                                if (root.draftWallpaperPath.length > 0)
                                    root.setDraftBackgroundMode("wallpaper");
                                else if (!wallpaperPickerProcess.running) {
                                    root.statusMessage = "Opening lockscreen wallpaper picker…";
                                    wallpaperPickerProcess.exec(["bash", root.wallpaperPickerBackend]);
                                }
                            }
                        }
                        SettingsButton {
                            label: "Choose Wallpaper"
                            textSize: 9
                            available: !wallpaperPickerProcess.running
                            onClicked: {
                                root.statusMessage = "Opening lockscreen wallpaper picker…";
                                wallpaperPickerProcess.exec(["bash", root.wallpaperPickerBackend]);
                            }
                        }
                        SettingsButton {
                            label: "Color"
                            active: root.draftBackgroundMode === "color"
                            textSize: 9
                            onClicked: {
                                root.setDraftBackgroundMode("color");
                                root.backgroundPaletteOpen = true;
                                root.elementPaletteOpen = false;
                            }
                        }
                        SettingsButton {
                            label: "Palette"
                            active: root.backgroundPaletteOpen
                            textSize: 9
                            onClicked: {
                                root.backgroundPaletteOpen = !root.backgroundPaletteOpen;
                                if (root.backgroundPaletteOpen)
                                    root.elementPaletteOpen = false;
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.draftWallpaperPath.length > 0
                                ? "Lockscreen wallpaper: " + root.draftWallpaperPath.split("/").pop()
                                : "Lockscreen wallpaper is independent from the desktop."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideMiddle
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 142 : 0
                        spacing: 12
                        visible: root.elementPaletteOpen || root.backgroundPaletteOpen

                        InlineColorPicker {
                            id: elementColorPicker
                            visible: root.elementPaletteOpen
                            Layout.preferredWidth: 320
                            Layout.preferredHeight: visible ? 142 : 0
                            colorValue: root.elementColor(root.selectedElement) === "auto"
                                ? String(root.draftAutoAccents[root.selectedElement] || "#ffffff")
                                : root.elementColor(root.selectedElement)
                            onColorEdited: hex => root.setDraftColor(root.selectedElement, hex)
                        }

                        InlineColorPicker {
                            id: backgroundColorPicker
                            visible: root.backgroundPaletteOpen
                            Layout.preferredWidth: 320
                            Layout.preferredHeight: visible ? 142 : 0
                            colorValue: root.draftBackgroundColor
                            onColorEdited: hex => root.setDraftBackgroundColor(hex)
                        }

                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Changes are live preview only until Save. Password cannot be hidden."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        SettingsButton {
                            label: "Restore Defaults"
                            textSize: 10
                            onClicked: root.resetDraft()
                        }
                        SettingsButton { label: "Cancel"; textSize: 10; onClicked: root.close() }
                        SettingsButton {
                            label: "Save"
                            active: true
                            textSize: 10
                            available: !saveProcess.running && !contrastPersistProcess.running
                            onClicked: root.save()
                        }
                    }
                }
            }
        }
    }
}
