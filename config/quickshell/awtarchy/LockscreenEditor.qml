pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../awtarchy-lock" as LockUi

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string stateBackend: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property bool open: editorWindow.visible
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]

    property var draftLayout: defaultLayout()
    property string statusMessage: ""
    property string wallpaperSource: ""

    function defaultLayout() {
        return ({
            logo: ({ x: 0.50, y: 0.34 }),
            time: ({ x: 0.50, y: 0.51 }),
            date: ({ x: 0.50, y: 0.555 }),
            username: ({ x: 0.50, y: 0.595 }),
            weather: ({ x: 0.50, y: 0.635 }),
            password: ({ x: 0.50, y: 0.70 })
        });
    }

    function cloneLayout(value) {
        try {
            const parsed = JSON.parse(JSON.stringify(value));
            return parsed && typeof parsed === "object" ? parsed : defaultLayout();
        } catch (error) {
            return defaultLayout();
        }
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
        next[name] = clampPoint(name, Number(x), Number(y));
        draftLayout = next;
    }

    function resetDraft() {
        draftLayout = defaultLayout();
        statusMessage = "Defaults loaded. Save to apply.";
    }

    function loadPersistedDraft() {
        draftLayout = cloneLayout(BarState.lockscreenLayout());
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
            "save-lockscreen-layout",
            JSON.stringify(draftLayout)
        ]);
    }

    function elementEnabled(name) {
        if (name === "time")
            return BarState.lockscreenShowTime();
        if (name === "date")
            return BarState.lockscreenShowDate();
        if (name === "username")
            return BarState.lockscreenShowUsername();
        if (name === "weather")
            return BarState.lockscreenShowWeather();
        return true;
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
                root.statusMessage = "Could not save lockscreen layout";
            }
        }
    }

    Timer {
        id: closeAfterSave
        interval: 180
        repeat: false
        onTriggered: root.close()
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

            LockUi.LockScene {
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
                showTime: BarState.lockscreenShowTime()
                showDate: BarState.lockscreenShowDate()
                showUsername: BarState.lockscreenShowUsername()
                showWeather: BarState.lockscreenShowWeather()
                weatherText: "Weather preview"
                backgroundMode: BarState.lockscreenBackground()
                wallpaperSource: root.wallpaperSource
                layout: root.draftLayout
                previewMode: true
            }

            Repeater {
                model: root.elementNames

                Rectangle {
                    required property string modelData
                    readonly property string elementName: modelData
                    readonly property bool enabledElement: root.elementEnabled(elementName)
                    readonly property var point: root.draftLayout[elementName]
                        || root.defaultLayout()[elementName]
                    width: Math.max(58, label.implicitWidth + 18)
                    height: 24
                    x: Math.max(0, Math.min(parent.width - width,
                        Number(point.x) * parent.width - width / 2))
                    y: Math.max(0, Math.min(parent.height - height,
                        Number(point.y) * parent.height - height / 2))
                    visible: enabledElement
                    color: dragArea.pressed ? Theme.focus : Theme.popupBackground
                    border.width: 1
                    border.color: Theme.foreground
                    opacity: 0.86
                    z: 200

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: root.elementLabel(parent.elementName)
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeAllCursor
                        preventStealing: true
                        property real pressOffsetX: 0
                        property real pressOffsetY: 0

                        onPressed: mouse => {
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
                height: 62
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.muted
                z: 300

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: root.statusMessage.length > 0
                            ? root.statusMessage
                            : "Drag enabled elements. Save applies globally to every lock surface."
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
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
