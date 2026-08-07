import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Widgets

PanelWindow {
    id: bar
    required property var modelData

    screen: modelData
    readonly property string monitorName: modelData ? modelData.name : ""
    readonly property string position: BarState.positionFor(monitorName)
    readonly property bool vertical: position === "left" || position === "right"
    readonly property int barSize: vertical ? 36 : 28

    property string brightnessText: " ?"
    property string brightnessTooltip: "Brightness: DDC unavailable"
    property int brightnessValue: -1
    property bool clockDate: false
    property date now: new Date()
    property bool wsDrawerOpen: false

    visible: monitorName.length > 0 && BarState.enabledFor(monitorName)
    color: Theme.background
    aboveWindows: true
    focusable: false
    exclusiveZone: barSize
    implicitWidth: vertical ? 36 : 0
    implicitHeight: vertical ? 0 : 28

    anchors.top: position === "top" || vertical
    anchors.bottom: position === "bottom" || vertical
    anchors.left: position === "left" || !vertical
    anchors.right: position === "right" || !vertical

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string ddcScript: configHome + "/hypr/scripts/ddc_brightness.sh"
    readonly property string wiremixScript: configHome + "/hypr/scripts/wiremix-toggle.sh"
    readonly property string mouseSubmapScript: configHome + "/hypr/scripts/toggle_mouse_submap.sh"

    function focusWorkspace(selector) {
        Quickshell.execDetached([
            "hyprctl",
            "eval",
            "hl.dispatch(hl.dsp.focus({ workspace = \"" + selector + "\" }))"
        ]);
    }

    function workspaceIcon(id) {
        const icons = {
            1: "1 󰞷", 2: "2 ", 3: "3 ", 4: "4 ", 5: "5 ",
            6: "6 ", 7: "7 ", 8: "8 ", 9: "9 ", 10: "10 "
        };
        return icons[id] || String(id);
    }

    function appIcon(toplevel) {
        if (!toplevel)
            return Quickshell.iconPath("application-x-executable", true);

        const ipc = toplevel.lastIpcObject || {};
        const candidates = [
            toplevel.wayland ? toplevel.wayland.appId : "",
            ipc.class || "",
            ipc.initialClass || ""
        ].filter(value => value && value.length > 0).map(value => value.toLowerCase());

        const apps = DesktopEntries.applications.values;
        for (let i = 0; i < apps.length; ++i) {
            const app = apps[i];
            const ids = [app.id || "", app.startupClass || ""]
                .filter(value => value.length > 0)
                .map(value => value.toLowerCase().replace(/\.desktop$/, ""));
            for (let j = 0; j < candidates.length; ++j) {
                const candidate = candidates[j].replace(/\.desktop$/, "");
                if (ids.indexOf(candidate) >= 0 && app.icon)
                    return Quickshell.iconPath(app.icon, true);
            }
        }

        return Quickshell.iconPath("application-x-executable", true);
    }

    function toplevelVisibleHere(toplevel) {
        if (!toplevel || !toplevel.monitor || toplevel.monitor.name !== monitorName)
            return false;
        const ipc = toplevel.lastIpcObject || {};
        const cls = String(ipc.class || ipc.initialClass || "").toLowerCase();
        const ignored = ["wofi", "tofi", "rofi", "hyprlock", "swaylock", "swww", "mpvpaper", "pulsemixer", "org.waytrogen.waytrogen", "org.pulseaudio.pavucontrol", "wiremix", "quickshell"];
        return ignored.indexOf(cls) < 0;
    }

    function scratchpadCount() {
        return Hyprland.toplevels.values.filter(toplevel => toplevel.workspace && toplevel.workspace.id < 0).length;
    }

    function privacyLabel() {
        const types = Pipewire.nodes.values
            .filter(node => node.isStream)
            .map(node => String(node.type || ""));
        const camera = types.some(type => type.indexOf("Stream/Input/Video") >= 0);
        const mic = types.some(type => type.indexOf("Stream/Input/Audio") >= 0);
        if (camera && mic) return " ";
        if (camera) return "";
        if (mic) return "";
        return "";
    }

    function audioIcon(volume) {
        if (!Pipewire.defaultAudioSink || !Pipewire.defaultAudioSink.audio)
            return "";
        if (Pipewire.defaultAudioSink.audio.muted)
            return "";
        if (volume < 25) return "";
        if (volume < 60) return "";
        return "";
    }

    function batteryIcon(percent) {
        if (percent >= 90) return "";
        if (percent >= 65) return "";
        if (percent >= 40) return "";
        if (percent >= 15) return "";
        return "";
    }

    function parseBrightness(line) {
        try {
            const data = JSON.parse(line.trim());
            brightnessText = data.text || " ?";
            brightnessTooltip = data.tooltip || "Brightness";
            const match = brightnessText.match(/(-?\d+)\s*$/);
            brightnessValue = match ? Number(match[1]) : -1;
        } catch (error) {
            if (line.trim().length > 0)
                console.warn("Awtarchy DDC parse failed:", error);
        }
    }

    function ddcAction(action) {
        Quickshell.execDetached({
            command: [ddcScript, action],
            environment: ({ AWTARCHY_OUTPUT_NAME: monitorName })
        });
    }

    function toggleAudioMute() {
        const sink = Pipewire.defaultAudioSink;
        if (sink && sink.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function adjustAudio(delta) {
        const sink = Pipewire.defaultAudioSink;
        if (!sink || !sink.audio)
            return;
        sink.audio.volume = Math.max(0, Math.min(1.5, sink.audio.volume + delta));
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Process {
        id: ddcWatch
        running: bar.visible
        command: [bar.ddcScript, "watch"]
        environment: ({ AWTARCHY_OUTPUT_NAME: bar.monitorName })
        stdout: SplitParser {
            onRead: line => bar.parseBrightness(line)
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: bar.now = new Date()
    }

    FileView {
        id: submapFile
        path: "/tmp/hypr-submap"
        blockLoading: false
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: submapFile.reload()
    }

    Timer {
        id: wsDrawerClose
        interval: 250
        repeat: false
        onTriggered: bar.wsDrawerOpen = false
    }

    component WorkspaceStrip: Row {
        spacing: 0

        Repeater {
            model: ScriptModel {
                values: Hyprland.workspaces.values.filter(workspace =>
                    workspace.id >= 1 && workspace.id <= 10 && workspace.monitor && workspace.monitor.name === bar.monitorName)
            }

            delegate: BarButton {
                required property var modelData
                vertical: false
                label: bar.workspaceIcon(modelData.id)
                normalBackground: modelData.urgent ? Theme.urgent : (modelData.active ? Theme.subtleActive : "transparent")
                foreground: modelData.urgent ? Theme.dark : Theme.foreground
                tooltip: "Workspace " + modelData.name
                onClicked: bar.focusWorkspace(String(modelData.id))
                onWheelUp: bar.focusWorkspace("e-1")
                onWheelDown: bar.focusWorkspace("e+1")
            }
        }
    }

    component WorkspaceColumn: Column {
        spacing: 0

        Repeater {
            model: ScriptModel {
                values: Hyprland.workspaces.values.filter(workspace =>
                    workspace.id >= 1 && workspace.id <= 10 && workspace.monitor && workspace.monitor.name === bar.monitorName)
            }

            delegate: BarButton {
                required property var modelData
                vertical: true
                fixedWidth: 36
                label: bar.workspaceIcon(modelData.id).replace(" ", "\n")
                normalBackground: modelData.urgent ? Theme.urgent : (modelData.active ? Theme.subtleActive : "transparent")
                foreground: modelData.urgent ? Theme.dark : Theme.foreground
                tooltip: "Workspace " + modelData.name
                onClicked: bar.focusWorkspace(String(modelData.id))
                onWheelUp: bar.focusWorkspace("e-1")
                onWheelDown: bar.focusWorkspace("e+1")
            }
        }
    }

    component TaskStrip: Row {
        spacing: 0

        Repeater {
            model: ScriptModel {
                values: Hyprland.toplevels.values.filter(toplevel => bar.toplevelVisibleHere(toplevel))
            }

            delegate: Rectangle {
                id: task
                required property var modelData
                width: 26
                height: 28
                color: modelData.urgent ? Theme.urgent : (modelData.activated ? Theme.subtleActive : (taskMouse.containsMouse ? Theme.subtleHover : "transparent"))

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 14
                    source: bar.appIcon(task.modelData)
                }

                ToolTip.visible: taskMouse.containsMouse
                ToolTip.text: task.modelData.title || "Window"
                ToolTip.delay: 350

                MouseArea {
                    id: taskMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        const wayland = task.modelData.wayland;
                        if (!wayland)
                            return;
                        if (mouse.button === Qt.MiddleButton) {
                            wayland.close();
                        } else if (mouse.button === Qt.RightButton) {
                            if (wayland.minimized) {
                                wayland.minimized = false;
                                wayland.activate();
                            } else {
                                wayland.minimized = true;
                            }
                        } else {
                            wayland.minimized = false;
                            wayland.activate();
                        }
                    }
                }
            }
        }
    }

    component TaskColumn: Column {
        spacing: 0

        Repeater {
            model: ScriptModel {
                values: Hyprland.toplevels.values.filter(toplevel => bar.toplevelVisibleHere(toplevel))
            }

            delegate: Rectangle {
                id: task
                required property var modelData
                width: 36
                height: 28
                color: modelData.urgent ? Theme.urgent : (modelData.activated ? Theme.subtleActive : (taskMouse.containsMouse ? Theme.subtleHover : "transparent"))

                IconImage { anchors.centerIn: parent; implicitSize: 14; source: bar.appIcon(task.modelData) }
                ToolTip.visible: taskMouse.containsMouse
                ToolTip.text: task.modelData.title || "Window"
                ToolTip.delay: 350

                MouseArea {
                    id: taskMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        const wayland = task.modelData.wayland;
                        if (!wayland) return;
                        if (mouse.button === Qt.MiddleButton) wayland.close();
                        else if (mouse.button === Qt.RightButton) {
                            if (wayland.minimized) { wayland.minimized = false; wayland.activate(); }
                            else wayland.minimized = true;
                        } else { wayland.minimized = false; wayland.activate(); }
                    }
                }
            }
        }
    }

    component TrayStrip: Row {
        spacing: 10

        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: trayItem
                required property var modelData
                width: 14
                height: 28

                IconImage { anchors.centerIn: parent; implicitSize: 14; source: trayItem.modelData.icon }
                ToolTip.visible: trayMouse.containsMouse
                ToolTip.text: trayItem.modelData.tooltipTitle || trayItem.modelData.title || ""
                ToolTip.delay: 350

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) trayItem.modelData.secondaryActivate();
                        else if (mouse.button === Qt.RightButton || trayItem.modelData.onlyMenu) trayItem.modelData.display(bar, trayItem.x, trayItem.y + trayItem.height);
                        else trayItem.modelData.activate();
                    }
                    onWheel: wheel => trayItem.modelData.scroll(wheel.angleDelta.y, false)
                }
            }
        }
    }

    component TrayColumn: Column {
        spacing: 6

        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: trayItem
                required property var modelData
                width: 36
                height: 20
                IconImage { anchors.centerIn: parent; implicitSize: 14; source: trayItem.modelData.icon }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) trayItem.modelData.secondaryActivate();
                        else if (mouse.button === Qt.RightButton || trayItem.modelData.onlyMenu) trayItem.modelData.display(bar, 0, trayItem.y);
                        else trayItem.modelData.activate();
                    }
                    onWheel: wheel => trayItem.modelData.scroll(wheel.angleDelta.y, false)
                }
            }
        }
    }

    Item {
        id: horizontalLayout
        anchors.fill: parent
        visible: !bar.vertical

        Row {
            id: leftModules
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 0

            BarButton {
                label: ""
                tooltip: "app-launcher"
                onClicked: Launcher.openForScreen(bar.screen)
                onRightClicked: Launcher.openForScreen(bar.screen)
            }

            WorkspaceStrip {}

            Row {
                spacing: 0

                BarButton {
                    id: wsHub
                    label: "🖱"
                    tooltip: "Toggle mouse submap"
                    onHoveredChanged: {
                        if (hovered) { wsDrawerClose.stop(); bar.wsDrawerOpen = true; }
                        else wsDrawerClose.restart();
                    }
                    onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "toggle"])
                    onRightClicked: Quickshell.execDetached([bar.mouseSubmapScript, "toggle"])
                }

                Repeater {
                    model: bar.wsDrawerOpen ? [
                        { label: "↑", dir: "u", tip: "Move workspace UP" },
                        { label: "↓", dir: "d", tip: "Move workspace DOWN" },
                        { label: "←", dir: "l", tip: "Move workspace LEFT" },
                        { label: "→", dir: "r", tip: "Move workspace RIGHT" }
                    ] : []
                    delegate: BarButton {
                        required property var modelData
                        label: modelData.label
                        tooltip: modelData.tip
                        onHoveredChanged: {
                            if (hovered) { wsDrawerClose.stop(); bar.wsDrawerOpen = true; }
                            else wsDrawerClose.restart();
                        }
                        onClicked: Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.workspace.move({ monitor = \"" + modelData.dir + "\" }))"])
                    }
                }
            }

            TaskStrip {}

            BarButton {
                visible: bar.scratchpadCount() > 0
                label: " " + bar.scratchpadCount()
                tooltip: "Scratchpad windows: " + bar.scratchpadCount()
            }

            BarButton {
                visible: submapFile.text().trim().length > 0
                label: submapFile.text().trim()
                tooltip: "Current submap: " + submapFile.text().trim() + " (click to reset)"
                onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
                onRightClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
            }

            BarButton {
                visible: bar.privacyLabel().length > 0
                label: bar.privacyLabel()
                tooltip: "Privacy: active capture stream"
            }
        }

        Text {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.30, 520)
            text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontPixelSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        Row {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 0

            BarButton {
                label: SystemState.idleBroken ? "" : (SystemState.idleInhibited ? "" : "")
                tooltip: SystemState.idleInhibited ? "Idle inhibitor: activated\nClick to deactivate" : "Idle inhibitor: deactivated\nClick to activate"
                foreground: SystemState.idleBroken ? Theme.urgent : Theme.foreground
                onClicked: SystemState.toggleIdle()
                onRightClicked: SystemState.toggleIdle()
            }

            BarButton { label: SystemState.cpuUsage + " "; tooltip: "CPU usage: " + SystemState.cpuUsage + "%" }
            BarButton { label: SystemState.cpuTemp; tooltip: "CPU temperature" }
            BarButton { label: SystemState.memoryUsage + "  "; tooltip: "Memory usage: " + SystemState.memoryUsage + "%" }

            BarButton {
                label: bar.brightnessText
                tooltip: bar.brightnessTooltip
                onClicked: bar.ddcAction("menu")
                onRightClicked: bar.ddcAction("menu")
                onWheelUp: bar.ddcAction("up")
                onWheelDown: bar.ddcAction("down")
            }

            BarButton {
                visible: UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery
                readonly property int pct: Math.round(UPower.displayDevice.percentage * 100)
                label: (UPower.displayDevice.changeRate > 0 ? "" : bar.batteryIcon(pct)) + " " + pct
                foreground: pct <= 15 && UPower.displayDevice.changeRate <= 0 ? Theme.critical : (UPower.displayDevice.changeRate > 0 ? Theme.charging : Theme.foreground)
                tooltip: "Battery: " + pct + "%"
            }

            BarButton {
                readonly property int vol: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) : 0
                label: bar.audioIcon(vol) + "   " + (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? "mute" : vol)
                foreground: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? Theme.muted : Theme.foreground
                tooltip: "Audio volume"
                onClicked: bar.toggleAudioMute()
                onRightClicked: Quickshell.execDetached([bar.wiremixScript])
                onWheelUp: bar.adjustAudio(0.05)
                onWheelDown: bar.adjustAudio(-0.05)
            }

            BarButton {
                label: bar.clockDate ? " " + Qt.formatDateTime(bar.now, "ddd M/d") : " " + Qt.formatDateTime(bar.now, "HH:mm")
                tooltip: Qt.formatDateTime(bar.now, "dddd, MMMM d, yyyy") + "\n24h: " + Qt.formatDateTime(bar.now, "HH:mm") + "\n12h: " + Qt.formatDateTime(bar.now, "h:mm AP")
                onClicked: bar.clockDate = !bar.clockDate
                onRightClicked: bar.clockDate = !bar.clockDate
                onWheelUp: bar.clockDate = !bar.clockDate
                onWheelDown: bar.clockDate = !bar.clockDate
            }

            TrayStrip {}

            BarButton {
                label: ""
                tooltip: "Clipboard history"
                onClicked: ClipboardMenu.openFocused()
                onRightClicked: ClipboardMenu.openFocused()
            }

            BarButton {
                label: Notifications.dnd ? "" : ""
                foreground: Notifications.dnd ? Theme.critical : Theme.foreground
                tooltip: Notifications.dnd ? "Notifications disabled\nLeft: enable notifications" : "Notifications enabled\nLeft: disable notifications"
                onClicked: Notifications.toggleDnd()
            }

            BarButton {
                label: ""
                tooltip: "power menu"
                horizontalPadding: 10
                onClicked: PowerMenu.openForScreen(bar.screen)
                onRightClicked: PowerMenu.openForScreen(bar.screen)
            }
        }
    }

    Item {
        id: verticalLayout
        anchors.fill: parent
        visible: bar.vertical

        Column {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            BarButton {
                vertical: true; fixedWidth: 36; label: ""; tooltip: "app-launcher"
                onClicked: Launcher.openForScreen(bar.screen)
                onRightClicked: Launcher.openForScreen(bar.screen)
            }

            WorkspaceColumn {}

            BarButton {
                vertical: true; fixedWidth: 36; label: "🖱"; tooltip: "Toggle mouse submap"
                onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "toggle"])
                onRightClicked: Quickshell.execDetached([bar.mouseSubmapScript, "toggle"])
            }

            BarButton { vertical: true; fixedWidth: 36; label: "↑"; tooltip: "Move workspace UP"; onClicked: Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.workspace.move({ monitor = \"u\" }))"]) }
            BarButton { vertical: true; fixedWidth: 36; label: "↓"; tooltip: "Move workspace DOWN"; onClicked: Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.workspace.move({ monitor = \"d\" }))"]) }
            BarButton { vertical: true; fixedWidth: 36; label: "←"; tooltip: "Move workspace LEFT"; onClicked: Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.workspace.move({ monitor = \"l\" }))"]) }
            BarButton { vertical: true; fixedWidth: 36; label: "→"; tooltip: "Move workspace RIGHT"; onClicked: Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.workspace.move({ monitor = \"r\" }))"]) }

            TaskColumn {}

            BarButton {
                visible: bar.scratchpadCount() > 0
                vertical: true; fixedWidth: 36
                label: "\n" + bar.scratchpadCount()
            }

            BarButton {
                visible: submapFile.text().trim().length > 0
                vertical: true; fixedWidth: 36
                label: submapFile.text().trim()
                tooltip: "Current submap: " + submapFile.text().trim() + " (click to reset)"
                onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
            }
        }

        Column {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            BarButton {
                vertical: true; fixedWidth: 36
                label: SystemState.idleBroken ? "" : (SystemState.idleInhibited ? "" : "")
                foreground: SystemState.idleBroken ? Theme.urgent : Theme.foreground
                onClicked: SystemState.toggleIdle()
            }

            BarButton { vertical: true; fixedWidth: 36; label: "\n" + SystemState.cpuUsage; tooltip: "CPU usage: " + SystemState.cpuUsage + "%" }
            BarButton {
                vertical: true; fixedWidth: 36
                readonly property string temp: SystemState.cpuTemp
                label: temp.length > 1 ? temp.slice(-1) + "\n" + temp.slice(0, -1) : temp
                tooltip: "CPU temperature"
            }
            BarButton { vertical: true; fixedWidth: 36; label: "\n" + SystemState.memoryUsage; tooltip: "Memory usage: " + SystemState.memoryUsage + "%" }

            BarButton {
                vertical: true; fixedWidth: 36
                label: "\n" + (bar.brightnessValue >= 0 ? bar.brightnessValue : "?")
                tooltip: bar.brightnessTooltip
                onClicked: bar.ddcAction("menu")
                onRightClicked: bar.ddcAction("menu")
                onWheelUp: bar.ddcAction("up")
                onWheelDown: bar.ddcAction("down")
            }

            BarButton {
                visible: UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery
                vertical: true; fixedWidth: 36
                readonly property int pct: Math.round(UPower.displayDevice.percentage * 100)
                label: (UPower.displayDevice.changeRate > 0 ? "" : bar.batteryIcon(pct)) + "\n" + pct
                foreground: pct <= 15 && UPower.displayDevice.changeRate <= 0 ? Theme.critical : (UPower.displayDevice.changeRate > 0 ? Theme.charging : Theme.foreground)
            }

            BarButton {
                vertical: true; fixedWidth: 36
                readonly property int vol: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) : 0
                label: bar.audioIcon(vol) + "\n" + (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? "mute" : vol)
                foreground: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? Theme.muted : Theme.foreground
                onClicked: bar.toggleAudioMute()
                onRightClicked: Quickshell.execDetached([bar.wiremixScript])
                onWheelUp: bar.adjustAudio(0.05)
                onWheelDown: bar.adjustAudio(-0.05)
            }

            BarButton {
                vertical: true; fixedWidth: 36
                label: bar.clockDate
                    ? "\n" + Qt.formatDateTime(bar.now, "ddd") + "\n" + Qt.formatDateTime(bar.now, "M/d")
                    : "\n" + Qt.formatDateTime(bar.now, "HH") + "\n" + Qt.formatDateTime(bar.now, "mm")
                onClicked: bar.clockDate = !bar.clockDate
                onRightClicked: bar.clockDate = !bar.clockDate
                onWheelUp: bar.clockDate = !bar.clockDate
                onWheelDown: bar.clockDate = !bar.clockDate
            }

            TrayColumn {}

            BarButton {
                vertical: true; fixedWidth: 36; label: ""; tooltip: "Clipboard history"
                onClicked: ClipboardMenu.openFocused()
                onRightClicked: ClipboardMenu.openFocused()
            }
            BarButton {
                vertical: true; fixedWidth: 36
                label: Notifications.dnd ? "" : ""
                foreground: Notifications.dnd ? Theme.critical : Theme.foreground
                onClicked: Notifications.toggleDnd()
            }
            BarButton {
                vertical: true; fixedWidth: 36; label: ""; tooltip: "power menu"
                onClicked: PowerMenu.openForScreen(bar.screen)
                onRightClicked: PowerMenu.openForScreen(bar.screen)
            }
        }
    }
}
