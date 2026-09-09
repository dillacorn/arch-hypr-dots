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
    readonly property bool open: editorWindow.visible
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]

    property var draftLayout: defaultLayout()
    property var draftVisibility: defaultVisibility()
    property string selectedElement: "logo"
    property string statusMessage: ""

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
        selectedElement = "logo";
        statusMessage = "Defaults loaded. Save to apply.";
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
        selectedElement = elementNames.indexOf(selectedElement) >= 0 ? selectedElement : "logo";
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
                root.statusMessage = "Saved";
                closeAfterSave.restart();
            } else {
                root.statusMessage = "Could not save lockscreen presentation";
            }
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
                backgroundMode: BarState.lockscreenBackground()
                wallpaperSource: wallpaperState.source
                autoAccent: BarState.lockscreenBackground() === "black"
                    ? "#ffffff" : LockscreenContrast.accent
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
                height: 138
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
                            label: root.elementCanHide(root.selectedElement)
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

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.statusMessage.length > 0
                                ? root.statusMessage
                                : "Drag the actual lockscreen visuals. Hidden items stay faded so they can be restored."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.maximumWidth: 520
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: "Color"
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

                        TextField {
                            id: customColorInput
                            Layout.preferredWidth: 118
                            placeholderText: "#RRGGBB"
                            text: root.elementColor(root.selectedElement) === "auto"
                                ? "" : root.elementColor(root.selectedElement)
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            selectByMouse: true
                            onEditingFinished: {
                                if (text.trim().length > 0)
                                    root.setDraftColor(root.selectedElement, text);
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Auto chooses black or white from the current wallpaper for contrast."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
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

                        SettingsButton {
                            label: "Cancel"
                            textSize: 10
                            onClicked: root.close()
                        }

                        SettingsButton {
                            label: "Save"
                            active: true
                            textSize: 10
                            available: !saveProcess.running
                            onClicked: root.save()
                        }
                    }
                }
            }
        }
    }
}
