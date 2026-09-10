#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    file_path = Path(path)
    text = file_path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    file_path.write_text(text.replace(old, new, 1))


def replace_tail(path: str, marker: str, tail: str, label: str) -> None:
    file_path = Path(path)
    text = file_path.read_text()
    count = text.count(marker)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 tail marker, found {count}")
    index = text.index(marker)
    file_path.write_text(text[:index] + tail)


# BarState: expose the new persisted appearance fields safely to unlocked QML.
bar_state = "config/quickshell/awtarchy/BarState.qml"
replace_once(
    bar_state,
    '''            lockscreen_show_weather: false,
            lockscreen_background: "black",
            lockscreen_weather_location: "",
            lockscreen_layout: root.defaultLockscreenLayout,''',
    '''            lockscreen_show_weather: false,
            lockscreen_background: "black",
            lockscreen_background_color: "#000000",
            lockscreen_wallpaper_path: "",
            lockscreen_weather_location: "",
            lockscreen_layout: root.defaultLockscreenLayout,''',
    "BarState lockscreen appearance defaults",
)
replace_once(
    bar_state,
    '''    function lockscreenBackground() {
        return String(data().lockscreen_background || "") === "wallpaper"
            ? "wallpaper" : "black";
    }

    function lockscreenWeatherLocation() {''',
    '''    function lockscreenBackground() {
        const value = String(data().lockscreen_background || "");
        return ["black", "wallpaper", "color"].indexOf(value) >= 0 ? value : "black";
    }

    function lockscreenBackgroundColor() {
        const value = String(data().lockscreen_background_color || "#000000").toLowerCase();
        return /^#[0-9a-f]{6}$/.test(value) ? value : "#000000";
    }

    function lockscreenWallpaperPath() {
        const value = data().lockscreen_wallpaper_path;
        if (typeof value !== "string" || !value.startsWith("/")
                || value.indexOf("://") >= 0 || /[\\u0000-\\u001f\\u007f-\\u009f]/.test(value))
            return "";
        return value;
    }

    function lockscreenWeatherLocation() {''',
    "BarState lockscreen appearance readers",
)


# Shared presentation scene: custom background and per-element cached Auto colors.
def patch_scene(path: str) -> None:
    replace_once(
        path,
        '''    required property string backgroundMode
    required property string wallpaperSource
    required property color autoAccent
    required property var layout''',
        '''    required property string backgroundMode
    required property string wallpaperSource
    required property color backgroundColor
    required property var autoAccents
    required property var layout''',
        f"{path} appearance inputs",
    )
    replace_once(
        path,
        '''    function elementColor(name) {
        const point = normalizedPoint(name);
        const value = String(point && point.color !== undefined ? point.color : "auto");
        return value === "auto" ? root.autoAccent
            : /^#[0-9a-fA-F]{6}$/.test(value) ? value : root.autoAccent;
    }''',
        '''    function elementColor(name) {
        const point = normalizedPoint(name);
        const value = String(point && point.color !== undefined ? point.color : "auto");
        const automatic = String(root.autoAccents && root.autoAccents[name] !== undefined
            ? root.autoAccents[name] : "#ffffff");
        const safeAuto = /^#[0-9a-fA-F]{6}$/.test(automatic) ? automatic : "#ffffff";
        return value === "auto" ? safeAuto
            : /^#[0-9a-fA-F]{6}$/.test(value) ? value : safeAuto;
    }''',
        f"{path} per-element Auto color",
    )
    replace_once(
        path,
        '''    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }''',
        '''    Rectangle {
        anchors.fill: parent
        color: root.backgroundMode === "color" ? root.backgroundColor : "#000000"
    }''',
        f"{path} custom solid background",
    )


patch_scene("config/quickshell/awtarchy-lock/LockScene.qml")
patch_scene("config/quickshell/awtarchy/LockPreviewScene.qml")


# Secure surface remains the auth owner; only presentation values are threaded through.
lock_surface = "config/quickshell/awtarchy-lock/LockSurface.qml"
replace_once(
    lock_surface,
    '''    required property string backgroundMode
    required property string wallpaperSource
    required property color autoAccent
    required property var layout''',
    '''    required property string backgroundMode
    required property string wallpaperSource
    required property color backgroundColor
    required property var autoAccents
    required property var layout''',
    "LockSurface appearance inputs",
)
replace_once(
    lock_surface,
    '''        backgroundMode: root.backgroundMode
        wallpaperSource: root.wallpaperSource
        autoAccent: root.autoAccent
        layout: root.layout''',
    '''        backgroundMode: root.backgroundMode
        wallpaperSource: root.wallpaperSource
        backgroundColor: root.backgroundColor
        autoAccents: root.autoAccents
        layout: root.layout''',
    "LockSurface scene appearance wiring",
)


# Secure shell only reads local persisted state/cache. No editor, picker, network, or auth changes.
lock_shell = "config/quickshell/awtarchy-lock/shell.qml"
replace_once(
    lock_shell,
    '''    property bool lockShowWeather: false
    property string lockBackground: "black"
    property string lockWeatherLocation: ""
    property var lockLayout: defaultLockLayout()''',
    '''    property bool lockShowWeather: false
    property string lockBackground: "black"
    property color lockBackgroundColor: "#000000"
    property string lockWallpaperPath: ""
    property string lockWeatherLocation: ""
    property var lockLayout: defaultLockLayout()''',
    "secure shell appearance state",
)
replace_once(
    lock_shell,
    '''    function normalizedBackground(value) {
        const key = String(value || "");
        return key === "wallpaper" ? "wallpaper" : "black";
    }

    function layoutPoint(value, fallback, password) {''',
    '''    function normalizedBackground(value) {
        const key = String(value || "");
        return ["black", "wallpaper", "color"].indexOf(key) >= 0 ? key : "black";
    }

    function normalizedBackgroundColor(value) {
        const key = String(value || "#000000").toLowerCase();
        return /^#[0-9a-f]{6}$/.test(key) ? key : "#000000";
    }

    function normalizedWallpaperPath(value) {
        const path = typeof value === "string" ? value : "";
        if (!path.startsWith("/") || path.indexOf("://") >= 0
                || /[\\u0000-\\u001f\\u007f-\\u009f]/.test(path))
            return "";
        return path;
    }

    function layoutPoint(value, fallback, password) {''',
    "secure shell appearance normalizers",
)
replace_once(
    lock_shell,
    '''        lockShowWeather = false;
        lockBackground = "black";
        lockWeatherLocation = "";
        lockLayout = defaultLockLayout();''',
    '''        lockShowWeather = false;
        lockBackground = "black";
        lockBackgroundColor = "#000000";
        lockWallpaperPath = "";
        lockWeatherLocation = "";
        lockLayout = defaultLockLayout();''',
    "secure shell appearance reset",
)
replace_once(
    lock_shell,
    '''            lockShowWeather = normalizedBoolean(parsed.lockscreen_show_weather, false);
            lockBackground = normalizedBackground(parsed.lockscreen_background);
            lockWeatherLocation = normalizedWeatherLocation(parsed.lockscreen_weather_location);
            lockLayout = normalizedLayout(parsed.lockscreen_layout);''',
    '''            lockShowWeather = normalizedBoolean(parsed.lockscreen_show_weather, false);
            lockBackground = normalizedBackground(parsed.lockscreen_background);
            lockBackgroundColor = normalizedBackgroundColor(parsed.lockscreen_background_color);
            lockWallpaperPath = normalizedWallpaperPath(parsed.lockscreen_wallpaper_path);
            lockWeatherLocation = normalizedWeatherLocation(parsed.lockscreen_weather_location);
            lockLayout = normalizedLayout(parsed.lockscreen_layout);''',
    "secure shell appearance load",
)
replace_once(
    lock_shell,
    '''    LockWallpaperState {
        id: lockWallpaperState
    }''',
    '''    LockWallpaperState {
        id: lockWallpaperState
        path: root.lockWallpaperPath
    }''',
    "secure wallpaper path wiring",
)
replace_once(
    lock_shell,
    '''                backgroundMode: root.lockBackground
                wallpaperSource: lockWallpaperState.source
                autoAccent: root.lockBackground === "black" ? "#ffffff" : lockContrastCache.accent
                layout: root.lockLayout''',
    '''                backgroundMode: root.lockBackground
                wallpaperSource: lockWallpaperState.source
                backgroundColor: root.lockBackgroundColor
                autoAccents: lockContrastCache.colors
                layout: root.lockLayout''',
    "secure surface appearance wiring",
)


# Unlocked editor: draft-only appearance, selection-only Awtwall picker, live local contrast.
editor = "config/quickshell/awtarchy/LockscreenEditor.qml"
replace_once(
    editor,
    '''    readonly property string stateBackend: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property bool open: editorWindow.visible''',
    '''    readonly property string stateBackend: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string contrastBackend: configHome + "/hypr/scripts/quickshell_lockscreen_contrast.sh"
    readonly property string wallpaperPickerBackend: configHome + "/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
    readonly property bool open: editorWindow.visible''',
    "editor helper paths",
)
replace_once(
    editor,
    '''    property var draftLayout: defaultLayout()
    property var draftVisibility: defaultVisibility()
    property string selectedElement: "logo"
    property string statusMessage: ""''',
    '''    property var draftLayout: defaultLayout()
    property var draftVisibility: defaultVisibility()
    property string draftBackgroundMode: "black"
    property string draftBackgroundColor: "#000000"
    property string draftWallpaperPath: ""
    property var draftAutoAccents: defaultAutoAccents()
    property string selectedElement: "logo"
    property string statusMessage: ""
    property bool elementPaletteOpen: false
    property bool backgroundPaletteOpen: false
    property bool contrastRefreshPending: false''',
    "editor appearance draft state",
)
replace_once(
    editor,
    '''    function cloneObject(value, fallback) {''',
    '''    function defaultAutoAccents() {
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

    function cloneObject(value, fallback) {''',
    "editor appearance helper functions",
)
replace_once(
    editor,
    '''    function setDraftPoint(name, x, y) {
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
    }''',
    '''    function setDraftPoint(name, x, y) {
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
    }''',
    "editor drag contrast refresh",
)
replace_once(
    editor,
    '''    function resetDraft() {
        draftLayout = defaultLayout();
        draftVisibility = defaultVisibility();
        selectedElement = "logo";
        statusMessage = "Defaults loaded. Save to apply.";
    }''',
    '''    function resetDraft() {
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
    }''',
    "editor appearance reset",
)
replace_once(
    editor,
    '''    function loadPersistedDraft() {
        draftLayout = cloneLayout(BarState.lockscreenLayout());
        draftVisibility = cloneVisibility(({
            logo: BarState.lockscreenShowLogo(),
            time: BarState.lockscreenShowTime(),
            date: BarState.lockscreenShowDate(),
            username: BarState.lockscreenShowUsername(),
            weather: BarState.lockscreenShowWeather(),
            password: true
        }));
        selectedElement = elementNames.indexOf(selectedElement) >= 0 ? selectedElement : "logo";
        statusMessage = "";
    }''',
    '''    function loadPersistedDraft() {
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
    }''',
    "editor persisted appearance load",
)
replace_once(
    editor,
    '''        loadPersistedDraft();
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        Qt.callLater(() => editorFocus.forceActiveFocus());''',
    '''        loadPersistedDraft();
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        scheduleContrastRefresh();
        Qt.callLater(() => editorFocus.forceActiveFocus());''',
    "editor open contrast refresh",
)
replace_once(
    editor,
    '''    function save() {
        if (saveProcess.running)
            return;
        statusMessage = "Saving…";
        saveProcess.exec([
            "bash",
            stateBackend,
            "save-lockscreen-editor",
            JSON.stringify(draftLayout),
            JSON.stringify(draftVisibility)
        ]);
    }''',
    '''    function save() {
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
    }''',
    "editor atomic appearance save",
)
replace_once(
    editor,
    '''    Process {
        id: saveProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                BarState.refresh();
                root.statusMessage = "Saved";
                closeAfterSave.restart();
            } else {
                root.statusMessage = "Could not save lockscreen presentation";
            }
        }
    }''',
    '''    Process {
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
    }''',
    "editor post-save contrast cache",
)
replace_once(
    editor,
    '''    LockPreviewWallpaperState {
        id: wallpaperState
    }

    Shortcut {''',
    '''    LockPreviewWallpaperState {
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

    Shortcut {''',
    "editor local wallpaper and contrast processes",
)
replace_once(
    editor,
    '''                backgroundMode: BarState.lockscreenBackground()
                wallpaperSource: wallpaperState.source
                autoAccent: BarState.lockscreenBackground() === "black"
                    ? "#ffffff" : LockscreenContrast.accent
                layout: root.draftLayout''',
    '''                backgroundMode: root.draftBackgroundMode
                wallpaperSource: wallpaperState.source
                backgroundColor: root.draftBackgroundColor
                autoAccents: root.draftAutoAccents
                layout: root.draftLayout''',
    "editor live appearance preview",
)

panel_marker = '''            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 138
                color: Theme.popupBackground'''
panel_tail = '''            Rectangle {
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
'''
replace_tail(editor, panel_marker, panel_tail, "editor control panel")


# Quick Settings no longer performs desktop-wallpaper actions for lockscreen selection.
quick_settings = "config/quickshell/awtarchy/QuickSettings.qml"
replace_once(
    quick_settings,
    '''                                SettingsButton {
                                    label: "Choose with Awtwall"
                                    textSize: root.scaledText(9)
                                    onClicked: {
                                        root.queueStateCommand(["set-lockscreen-background", "wallpaper"]);
                                        root.queueAction(["wallpaper"], "Opening Awtwall wallpaper picker…");
                                        root.close();
                                    }
                                }
''',
    "",
    "remove duplicated Quick Settings wallpaper picker",
)


# Update the older editor test whose original picker requirement is now intentionally superseded.
editor_test = "tests/test-quickshell-lockscreen-editor.sh"
replace_once(
    editor_test,
    '''require_text "$QUICK_SETTINGS" 'label: "Choose with Awtwall"' \\
    'Quick Settings has no Awtwall-backed lockscreen picture picker'
require_text "$QUICK_SETTINGS" 'queueAction(["wallpaper"]' \\
    'lockscreen picture picker does not reuse the existing Awtwall action'
require_text "$QUICK_SETTINGS" 'queueStateCommand(["set-lockscreen-background", "wallpaper"])' \\
    'choosing a lockscreen picture does not switch the lockscreen to wallpaper mode'
''',
    '''reject_text "$QUICK_SETTINGS" 'label: "Choose with Awtwall"' \\
    'Quick Settings still duplicates lockscreen wallpaper selection outside the editor'
require_text "$EDITOR_QML" 'quickshell_lockscreen_wallpaper_picker.sh' \\
    'LockscreenEditor does not own the dedicated selection-only wallpaper flow'
''',
    "update superseded Quick Settings picker assertion",
)

# The secure and preview presentation files are deliberately mirrored source.
secure = Path("config/quickshell/awtarchy-lock/LockScene.qml").read_bytes()
preview = Path("config/quickshell/awtarchy/LockPreviewScene.qml").read_bytes()
if secure != preview:
    raise SystemExit("presentation parity: secure and preview LockScene files diverged")
