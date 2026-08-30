pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: bar
    required property var modelData

    WlrLayershell.namespace: "awtarchy-bar"
    surfaceFormat.opaque: false

    screen: modelData
    readonly property string monitorName: modelData ? modelData.name : ""
    readonly property string position: BarState.positionFor(monitorName)
    readonly property bool vertical: position === "left" || position === "right"
    readonly property int barSize: BarState.barSizeFor(monitorName, vertical)
    readonly property real iconScale: BarState.iconScaleFor(monitorName)
    readonly property int smallIconSize: Math.max(8, Math.min(barSize - 6, Math.round(14 * iconScale)))
    readonly property int verticalItemSize: Math.max(28, smallIconSize + 8)
    readonly property bool microphoneMuted: Pipewire.defaultAudioSource
        && Pipewire.defaultAudioSource.audio
        && Pipewire.defaultAudioSource.audio.muted

    property string brightnessText: ""
    property string brightnessTooltip: "Brightness unavailable"
    property int brightnessValue: -1
    property bool clockDate: BarState.clockDateFor(monitorName)
    property bool clockDatePersistPending: false
    property date now: new Date()
    property bool wsDrawerOpen: false

    visible: monitorName.length > 0
        && BarState.enabledFor(monitorName)
        && !workspaceFullscreenForMonitor(monitorName)
    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b,
        1 - BarState.barTransparencyFor(monitorName) / 100)
    aboveWindows: true
    focusable: false
    exclusiveZone: barSize
    implicitWidth: vertical ? barSize : 0
    implicitHeight: vertical ? 0 : barSize

    anchors.top: position === "top" || vertical
    anchors.bottom: position === "bottom" || vertical
    anchors.left: position === "left" || !vertical
    anchors.right: position === "right" || !vertical

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string runtimeHome: Quickshell.env("XDG_RUNTIME_DIR")
        || Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")
    readonly property string submapStatePath: Quickshell.env("HYPR_SUBMAP_STATE_FILE") || (runtimeHome + "/awtarchy-hypr-submap")
    readonly property string ddcScript: configHome + "/hypr/scripts/ddc_brightness.sh"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string wiremixScript: configHome + "/hypr/scripts/wiremix-toggle.sh"
    readonly property string volumeScript: configHome + "/hypr/scripts/quickshell_volume.sh"
    readonly property string mouseSubmapScript: configHome + "/hypr/scripts/toggle_mouse_submap.sh"

    function workspaceFullscreenForMonitor(name) {
        return Hyprland.workspaces.values.some(workspace =>
            workspace.monitor && workspace.monitor.name === name
                && workspace.active && workspace.hasFullscreen);
    }

    function focusWorkspace(selector) {
        Quickshell.execDetached([
            "hyprctl",
            "eval",
            "hl.dispatch(hl.dsp.focus({ workspace = \"" + selector + "\" }))"
        ]);
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
            if (!app)
                continue;
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

    function isAwtarchyFlyout(toplevel) {
        if (!toplevel)
            return false;
        const ipc = toplevel.lastIpcObject || {};
        const title = String(toplevel.title || ipc.title || "");
        const flyoutTitles = [
            "Awtarchy Application Search",
            "Awtarchy Clipboard History",
            "Awtarchy Notification Center",
            "Awtarchy Quick Settings",
            "Awtarchy Network",
            "Awtarchy Bluetooth",
            "Awtarchy Battery"
        ];
        return flyoutTitles.indexOf(title) >= 0;
    }

    function toplevelVisibleHere(toplevel) {
        if (!toplevel || !toplevel.monitor || toplevel.monitor.name !== monitorName)
            return false;
        const taskTitle = String(toplevel.title || "").trim();
        if (taskTitle.length === 0)
            return false;
        if (isAwtarchyFlyout(toplevel))
            return false;
        const ipc = toplevel.lastIpcObject || {};
        const cls = String(ipc.class || ipc.initialClass || "").toLowerCase();
        const ignored = ["tofi", "rofi", "hyprlock", "swaylock", "swww", "mpvpaper", "pulsemixer", "org.waytrogen.waytrogen", "org.pulseaudio.pavucontrol", "wiremix", "quickshell", "awtarchy-polkit-agent"];
        return ignored.indexOf(cls) < 0;
    }

    function barModuleVisible(name, module) {
        const state = BarState.monitorState(name) || ({});
        if (module === "cpu")
            return state.show_cpu !== false;
        if (module === "temperature")
            return state.show_temp !== false;
        if (module === "memory")
            return state.show_memory !== false;
        return true;
    }

    function taskIconsVisible(name) {
        const state = BarState.monitorState(name) || ({});
        return state.show_tasks !== false;
    }

    function taskIconsThemed(name) {
        const state = BarState.monitorState(name) || ({});
        return state.theme_task_icons === true;
    }

    function trayIconsThemed(name) {
        const state = BarState.monitorState(name) || ({});
        return state.theme_tray_icons === true;
    }

    function scratchpadCount() {
        return Hyprland.toplevels.values.filter(toplevel =>
            toplevel.workspace && toplevel.workspace.id < 0).length;
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
            brightnessText = data.text || "";
            brightnessTooltip = data.tooltip || "Brightness";
            const percentage = Number(data.percentage);
            if (Number.isFinite(percentage))
                brightnessValue = Math.max(0, Math.min(100, Math.round(percentage)));
            else {
                const match = brightnessText.match(/(-?\d+)\s*%?\s*$/);
                brightnessValue = match ? Number(match[1]) : -1;
            }
        } catch (error) {
            if (line.trim().length > 0)
                console.warn("Awtarchy brightness parse failed:", error);
        }
    }

    function ddcAction(action) {
        Quickshell.execDetached({
            command: [ddcScript, action],
            environment: ({ AWTARCHY_OUTPUT_NAME: monitorName })
        });
    }

    function setWorkspaceDrawerHovered(hovered) {
        if (hovered) {
            wsDrawerClose.stop();
            wsDrawerOpen = true;
        } else {
            wsDrawerClose.restart();
        }
    }

    function toggleAudioMute() {
        const sink = Pipewire.defaultAudioSink;
        if (sink && sink.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function adjustAudio(delta) {
        if (delta === 0)
            return;
        Quickshell.execDetached([
            volumeScript,
            delta > 0 ? "up" : "down",
            String(AudioLimitState.limitPercent)
        ]);
    }

    function calendarText(date) {
        const monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
        const year = date.getFullYear();
        const month = date.getMonth();
        const firstDay = new Date(year, month, 1).getDay();
        const dayCount = new Date(year, month + 1, 0).getDate();
        const cells = [];

        for (let i = 0; i < firstDay; ++i)
            cells.push("  ");
        for (let day = 1; day <= dayCount; ++day)
            cells.push(String(day).padStart(2, " "));

        const lines = [monthNames[month] + " " + year, "Su Mo Tu We Th Fr Sa"];
        for (let i = 0; i < cells.length; i += 7)
            lines.push(cells.slice(i, i + 7).join(" "));
        return lines.join("\n");
    }

    function clockTooltip() {
        const base = Qt.formatDateTime(now, "dddd, MMMM d, yyyy")
            + "\n24h: " + Qt.formatDateTime(now, "HH:mm")
            + "\n12h: " + Qt.formatDateTime(now, "h:mm AP");
        return clockDate ? base + "\n\n" + calendarText(now) : base;
    }

    function persistClockDate() {
        if (clockDateWriter.running) {
            clockDatePersistPending = true;
            return;
        }
        clockDatePersistPending = false;
        clockDateWriter.exec([stateScript, "set-clock-date", monitorName, clockDate ? "true" : "false"]);
    }

    function toggleClockDate() {
        clockDate = !clockDate;
        persistClockDate();
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
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

    Process {
        id: clockDateWriter
        onExited: {
            BarState.refresh();
            if (bar.clockDatePersistPending)
                bar.persistClockDate();
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
        path: bar.submapStatePath
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
        interval: 500
        repeat: false
        onTriggered: bar.wsDrawerOpen = false
    }

    component BarControl: BarButton {
        monitorName: bar.monitorName
        iconScale: bar.iconScale
        barThickness: bar.barSize
    }

    component WorkspaceStrip: Row {
        spacing: 0

        Repeater {
            model: ScriptModel {
                values: Hyprland.workspaces.values.filter(workspace =>
                    workspace.id >= 1 && workspace.id <= 10 && workspace.monitor && workspace.monitor.name === bar.monitorName)
            }

            delegate: BarControl {
                required property var modelData
                vertical: false
                workspaceButton: true
                workspaceGlyphSize: BarState.workspaceIconPixelSize()
                workspaceGlyphYOffset: BarState.workspaceIconYOffset()
                label: BarState.workspaceLabelFor(modelData.id)
                normalBackground: modelData.urgent ? Theme.urgent : (modelData.focused ? Theme.subtleActive : "transparent")
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

            delegate: BarControl {
                required property var modelData
                vertical: true
                fixedWidth: bar.barSize
                workspaceButton: true
                workspaceGlyphSize: BarState.workspaceIconPixelSize()
                workspaceGlyphYOffset: BarState.workspaceIconYOffset()
                label: BarState.workspaceVerticalLabelFor(modelData.id)
                normalBackground: modelData.urgent ? Theme.urgent : (modelData.focused ? Theme.subtleActive : "transparent")
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
        visible: bar.taskIconsVisible(bar.monitorName)

        Repeater {
            model: ScriptModel {
                values: Hyprland.toplevels.values.filter(toplevel => bar.toplevelVisibleHere(toplevel))
            }

            delegate: Rectangle {
                id: task
                required property var modelData
                width: Math.max(26, bar.smallIconSize + 12)
                height: bar.barSize
                color: modelData.urgent ? Theme.urgent : (modelData.activated ? Theme.subtleActive : (taskMouse.containsMouse ? Theme.subtleHover : "transparent"))

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: bar.smallIconSize
                    source: bar.appIcon(task.modelData)
                    layer.enabled: bar.taskIconsThemed(bar.monitorName)
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.foreground
                    }
                }

                BarTooltip {
                    anchorItem: task
                    text: task.modelData && task.modelData.title ? task.modelData.title : "Window"
                    hovered: taskMouse.containsMouse
                    vertical: false
                }

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
        visible: bar.taskIconsVisible(bar.monitorName)

        Repeater {
            model: ScriptModel {
                values: Hyprland.toplevels.values.filter(toplevel => bar.toplevelVisibleHere(toplevel))
            }

            delegate: Rectangle {
                id: task
                required property var modelData
                width: bar.barSize
                height: bar.verticalItemSize
                color: modelData.urgent ? Theme.urgent : (modelData.activated ? Theme.subtleActive : (taskMouse.containsMouse ? Theme.subtleHover : "transparent"))

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: bar.smallIconSize
                    source: bar.appIcon(task.modelData)
                    layer.enabled: bar.taskIconsThemed(bar.monitorName)
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.foreground
                    }
                }

                BarTooltip {
                    anchorItem: task
                    text: task.modelData && task.modelData.title ? task.modelData.title : "Window"
                    hovered: taskMouse.containsMouse
                    vertical: true
                }

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
                width: Math.max(14, bar.smallIconSize)
                height: bar.barSize

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: bar.smallIconSize
                    source: trayItem.modelData.icon
                    layer.enabled: bar.trayIconsThemed(bar.monitorName)
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.foreground
                    }
                }

                BarTooltip {
                    anchorItem: trayItem
                    text: trayItem.modelData.tooltipTitle || trayItem.modelData.title || ""
                    hovered: trayMouse.containsMouse && !trayMenu.menuVisible
                    vertical: false
                }

                TrayMenu {
                    id: trayMenu
                    anchorItem: trayItem
                    menu: trayItem.modelData.menu
                    barPosition: bar.position
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate();
                        } else if (mouse.button === Qt.RightButton || trayItem.modelData.onlyMenu) {
                            if (trayItem.modelData.hasMenu)
                                trayMenu.open();
                            else
                                trayItem.modelData.secondaryActivate();
                        } else {
                            trayItem.modelData.activate();
                        }
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
                width: bar.barSize
                height: Math.max(20, bar.smallIconSize + 6)

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: bar.smallIconSize
                    source: trayItem.modelData.icon
                    layer.enabled: bar.trayIconsThemed(bar.monitorName)
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.foreground
                    }
                }

                BarTooltip {
                    anchorItem: trayItem
                    text: trayItem.modelData.tooltipTitle || trayItem.modelData.title || ""
                    hovered: trayMouse.containsMouse && !trayMenu.menuVisible
                    vertical: true
                }

                TrayMenu {
                    id: trayMenu
                    anchorItem: trayItem
                    menu: trayItem.modelData.menu
                    barPosition: bar.position
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate();
                        } else if (mouse.button === Qt.RightButton || trayItem.modelData.onlyMenu) {
                            if (trayItem.modelData.hasMenu)
                                trayMenu.open();
                            else
                                trayItem.modelData.secondaryActivate();
                        } else {
                            trayItem.modelData.activate();
                        }
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

        readonly property real titleMargin: 8
        readonly property real titlePreferredWidth: Math.min(width * 0.30, 520)
        readonly property real titleLeftBound: leftModules.x + leftModules.width + titleMargin
        readonly property real titleRightBound: rightModules.x - titleMargin
        readonly property real titleAvailableWidth: Math.max(0, titleRightBound - titleLeftBound)

        Row {
            id: leftModules
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 0

            BarControl {
                label: BarState.launcherIcon()
                tooltip: "app-launcher"
                hoverBackground: Theme.strongHover
                onClicked: Launcher.openForScreen(bar.screen)
                onRightClicked: Launcher.openForScreen(bar.screen)
            }

            WorkspaceStrip {}

            Row {
                id: wsDrawer
                spacing: 0

                HoverHandler {
                    onHoveredChanged: bar.setWorkspaceDrawerHovered(hovered)
                }

                BarControl {
                    id: wsHub
                    label: "󰍽"
                    tooltip: "Toggle mouse submap"
                    onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "toggle"])
                    onRightClicked: Quickshell.execDetached([bar.mouseSubmapScript, "toggle"])
                }

                Repeater {
                    model: [
                        { label: "↑", dir: "u", tip: "Move workspace UP" },
                        { label: "↓", dir: "d", tip: "Move workspace DOWN" },
                        { label: "←", dir: "l", tip: "Move workspace LEFT" },
                        { label: "→", dir: "r", tip: "Move workspace RIGHT" }
                    ]

                    delegate: Item {
                        id: arrowSlot
                        required property var modelData
                        height: bar.barSize
                        width: bar.wsDrawerOpen ? arrowButton.implicitWidth : 0
                        opacity: bar.wsDrawerOpen ? 1 : 0
                        clip: true

                        Behavior on width {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 120 }
                        }

                        BarControl {
                            id: arrowButton
                            anchors.left: parent.left
                            label: arrowSlot.modelData.label
                            tooltip: arrowSlot.modelData.tip
                            onClicked: Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.workspace.move({ monitor = \"" + arrowSlot.modelData.dir + "\" }))"])
                        }
                    }
                }
            }

            TaskStrip {}

            BarControl {
                visible: bar.scratchpadCount() > 0
                label: " " + bar.scratchpadCount()
                tooltip: "Scratchpad windows: " + bar.scratchpadCount()
            }

            BarControl {
                visible: submapFile.text().trim().length > 0
                label: submapFile.text().trim()
                tooltip: "Current submap: " + submapFile.text().trim() + " (click to reset)"
                onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
                onRightClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
            }

            BarControl {
                visible: bar.privacyLabel().length > 0
                label: bar.privacyLabel()
                tooltip: "Privacy: active capture stream"
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(horizontalLayout.titlePreferredWidth,
                horizontalLayout.titleAvailableWidth)
            x: {
                const centeredX = (horizontalLayout.width - width) / 2;
                const maximumX = horizontalLayout.titleRightBound - width;
                return Math.max(horizontalLayout.titleLeftBound,
                    Math.min(centeredX, maximumX));
            }
            visible: width > 0
            text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontPixelSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        Row {
            id: rightModules
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 0

            BarControl {
                label: SystemState.idleBroken ? "" : (SystemState.idleInhibited ? "" : "")
                tooltip: SystemState.idleInhibited ? "Idle inhibitor: activated\nClick to deactivate" : "Idle inhibitor: deactivated\nClick to activate"
                foreground: SystemState.idleBroken ? Theme.urgent : Theme.foreground
                hoverBackground: Theme.strongHover
                onClicked: SystemState.toggleIdle()
                onRightClicked: SystemState.toggleIdle()
            }

            BarControl {
                visible: bar.barModuleVisible(bar.monitorName, "cpu")
                label: SystemState.cpuUsage + " "
                tooltip: SystemState.cpuTooltip
            }
            BarControl {
                visible: bar.barModuleVisible(bar.monitorName, "temperature")
                label: SystemState.cpuTemp
                tooltip: SystemState.temperatureTooltip
            }
            BarControl {
                visible: bar.barModuleVisible(bar.monitorName, "memory")
                label: SystemState.memoryUsage + "  "
                tooltip: "Memory usage: " + SystemState.memoryUsage + "%"
            }

            BarControl {
                label: bar.brightnessText
                tooltip: bar.brightnessTooltip
                wheelActivationDelay: 400
                onClicked: QuickSettings.toggleForScreen(bar.screen)
                onRightClicked: QuickSettings.toggleForScreen(bar.screen)
                onWheelUp: bar.ddcAction("up")
                onWheelDown: bar.ddcAction("down")
            }

            BarControl {
                visible: BatteryState.available
                readonly property int pct: BatteryState.percentage
                readonly property bool pluggedIn: BatteryState.pluggedIn
                label: bar.batteryIcon(pct) + (pluggedIn ? "  " : " ") + pct
                foreground: pct <= 15 && !pluggedIn ? Theme.critical : Theme.foreground
                tooltip: BatteryState.barTooltip
                onClicked: BatteryMenu.toggleForScreen(bar.screen)
                onRightClicked: BatteryMenu.toggleForScreen(bar.screen)
            }

            BarControl {
                visible: bar.microphoneMuted
                label: ""
                foreground: Theme.critical
                tooltip: "Default microphone is muted"
            }

            BarControl {
                readonly property int vol: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) : 0
                label: bar.audioIcon(vol) + " " + (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? "mute" : vol)
                foreground: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? Theme.muted : Theme.foreground
                tooltip: "Audio volume · max " + AudioLimitState.limitPercent + "%"
                onClicked: bar.toggleAudioMute()
                onRightClicked: Quickshell.execDetached([bar.wiremixScript])
                onWheelUp: bar.adjustAudio(0.05)
                onWheelDown: bar.adjustAudio(-0.05)
            }

            BarControl {
                label: bar.clockDate ? " " + Qt.formatDateTime(bar.now, "ddd M/d") : " " + Qt.formatDateTime(bar.now, "HH:mm")
                tooltip: bar.clockTooltip()
                horizontalPadding: 6
                onClicked: bar.toggleClockDate()
                onRightClicked: bar.toggleClockDate()
                onWheelUp: bar.toggleClockDate()
                onWheelDown: bar.toggleClockDate()
            }

            BarControl {
                visible: NetworkMenu.available
                label: NetworkMenu.barLabel
                foreground: NetworkMenu.barForeground
                tooltip: NetworkMenu.barTooltip
                hoverBackground: Theme.strongHover
                onClicked: NetworkMenu.toggleForScreen(bar.screen)
                onRightClicked: NetworkMenu.toggleForScreen(bar.screen)
            }

            BarControl {
                visible: BluetoothMenu.available
                label: BluetoothMenu.barLabel
                foreground: BluetoothMenu.barForeground
                tooltip: BluetoothMenu.barTooltip
                hoverBackground: Theme.strongHover
                onClicked: BluetoothMenu.toggleForScreen(bar.screen)
                onRightClicked: BluetoothMenu.toggleForScreen(bar.screen)
            }

            TrayStrip {}

            BarControl {
                label: ""
                tooltip: "Clipboard history"
                hoverBackground: Theme.strongHover
                onClicked: ClipboardMenu.toggleForScreen(bar.screen)
                onRightClicked: ClipboardMenu.toggleForScreen(bar.screen)
            }

            BarControl {
                id: notificationButton
                label: Notifications.mutePopups ? "" : ""
                foreground: Notifications.mutePopups ? Theme.critical : Theme.foreground
                hoverBackground: Theme.strongHover
                tooltip: Notifications.mutePopups
                    ? "Notifications muted\nLeft: open · Right: unmute"
                    : "Notifications enabled\nLeft: open · Right: mute"
                onClicked: Notifications.toggleForItem(bar.screen, notificationButton)
                onRightClicked: Notifications.togglePopupMute()
            }

            BarControl {
                label: ""
                tooltip: "power menu"
                horizontalPadding: 10
                hoverBackground: Theme.strongHover
                onClicked: PowerMenu.toggleForScreen(bar.screen)
                onRightClicked: PowerMenu.openForScreen(bar.screen)
            }
        }
    }

    Item {
        id: verticalLayout
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        visible: bar.vertical

        Column {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            BarControl {
                vertical: true; fixedWidth: bar.barSize; label: BarState.launcherIcon(); tooltip: "app-launcher"
                hoverBackground: Theme.strongHover
                onClicked: Launcher.openForScreen(bar.screen)
                onRightClicked: Launcher.openForScreen(bar.screen)
            }

            WorkspaceColumn {}

            Column {
                id: wsDrawerVertical
                spacing: 0

                HoverHandler {
                    onHoveredChanged: bar.setWorkspaceDrawerHovered(hovered)
                }

                BarControl {
                    vertical: true
                    fixedWidth: bar.barSize
                    label: "󰍽"
                    tooltip: "Toggle mouse submap"
                    onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "toggle"])
                    onRightClicked: Quickshell.execDetached([bar.mouseSubmapScript, "toggle"])
                }

                Repeater {
                    model: [
                        { label: "↑", dir: "u", tip: "Move workspace UP" },
                        { label: "↓", dir: "d", tip: "Move workspace DOWN" },
                        { label: "←", dir: "l", tip: "Move workspace LEFT" },
                        { label: "→", dir: "r", tip: "Move workspace RIGHT" }
                    ]

                    delegate: Item {
                        id: arrowSlotVertical
                        required property var modelData
                        width: bar.barSize
                        height: bar.wsDrawerOpen ? bar.verticalItemSize : 0
                        opacity: bar.wsDrawerOpen ? 1 : 0
                        clip: true

                        Behavior on height {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 120 }
                        }

                        BarControl {
                            anchors.top: parent.top
                            vertical: true
                            fixedWidth: bar.barSize
                            fixedHeight: bar.verticalItemSize
                            label: arrowSlotVertical.modelData.label
                            tooltip: arrowSlotVertical.modelData.tip
                            onClicked: Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.workspace.move({ monitor = \"" + arrowSlotVertical.modelData.dir + "\" }))"])
                        }
                    }
                }
            }

            TaskColumn {}

            BarControl {
                visible: bar.scratchpadCount() > 0
                vertical: true; fixedWidth: bar.barSize
                label: "\n" + bar.scratchpadCount()
            }

            BarControl {
                visible: submapFile.text().trim().length > 0
                vertical: true; fixedWidth: bar.barSize
                label: submapFile.text().trim()
                tooltip: "Current submap: " + submapFile.text().trim() + " (click to reset)"
                onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
            }
        }

        Column {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            BarControl {
                vertical: true; fixedWidth: bar.barSize
                label: SystemState.idleBroken ? "" : (SystemState.idleInhibited ? "" : "")
                foreground: SystemState.idleBroken ? Theme.urgent : Theme.foreground
                tooltip: SystemState.idleInhibited ? "Idle inhibitor: activated\nClick to deactivate" : "Idle inhibitor: deactivated\nClick to activate"
                onClicked: SystemState.toggleIdle()
            }

            BarControl {
                visible: bar.barModuleVisible(bar.monitorName, "cpu")
                vertical: true; fixedWidth: bar.barSize
                label: "\n" + SystemState.cpuUsage
                tooltip: SystemState.cpuTooltip
            }
            BarControl {
                visible: bar.barModuleVisible(bar.monitorName, "temperature")
                vertical: true; fixedWidth: bar.barSize
                readonly property string temp: SystemState.cpuTemp
                label: temp.length > 1 ? temp.slice(-1) + "\n" + temp.slice(0, -1) : temp
                tooltip: SystemState.temperatureTooltip
            }
            BarControl {
                visible: bar.barModuleVisible(bar.monitorName, "memory")
                vertical: true; fixedWidth: bar.barSize
                label: "\n" + SystemState.memoryUsage
                tooltip: "Memory usage: " + SystemState.memoryUsage + "%"
            }

            BarControl {
                vertical: true; fixedWidth: bar.barSize
                label: bar.brightnessValue >= 0
                    ? "\n" + bar.brightnessValue + "%" : ""
                tooltip: bar.brightnessTooltip
                wheelActivationDelay: 400
                onClicked: QuickSettings.toggleForScreen(bar.screen)
                onRightClicked: QuickSettings.toggleForScreen(bar.screen)
                onWheelUp: bar.ddcAction("up")
                onWheelDown: bar.ddcAction("down")
            }

            BarControl {
                visible: BatteryState.available
                vertical: true; fixedWidth: bar.barSize
                readonly property int pct: BatteryState.percentage
                readonly property bool pluggedIn: BatteryState.pluggedIn
                label: bar.batteryIcon(pct) + (pluggedIn ? "\n" : "") + "\n" + pct
                foreground: pct <= 15 && !pluggedIn ? Theme.critical : Theme.foreground
                tooltip: BatteryState.barTooltip
                onClicked: BatteryMenu.toggleForScreen(bar.screen)
                onRightClicked: BatteryMenu.toggleForScreen(bar.screen)
            }

            BarControl {
                visible: bar.microphoneMuted
                vertical: true; fixedWidth: bar.barSize
                label: ""
                foreground: Theme.critical
                tooltip: "Default microphone is muted"
            }

            BarControl {
                vertical: true; fixedWidth: bar.barSize
                readonly property int vol: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) : 0
                label: bar.audioIcon(vol) + "\n" + (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? "mute" : vol)
                foreground: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted ? Theme.muted : Theme.foreground
                tooltip: "Audio volume · max " + AudioLimitState.limitPercent + "%"
                onClicked: bar.toggleAudioMute()
                onRightClicked: Quickshell.execDetached([bar.wiremixScript])
                onWheelUp: bar.adjustAudio(0.05)
                onWheelDown: bar.adjustAudio(-0.05)
            }

            BarControl {
                vertical: true; fixedWidth: bar.barSize
                label: bar.clockDate
                    ? "\n" + Qt.formatDateTime(bar.now, "ddd") + "\n" + Qt.formatDateTime(bar.now, "M/d")
                    : "\n" + Qt.formatDateTime(bar.now, "HH") + "\n" + Qt.formatDateTime(bar.now, "mm")
                tooltip: bar.clockTooltip()
                onClicked: bar.toggleClockDate()
                onRightClicked: bar.toggleClockDate()
                onWheelUp: bar.toggleClockDate()
                onWheelDown: bar.toggleClockDate()
            }

            BarControl {
                visible: NetworkMenu.available
                vertical: true; fixedWidth: bar.barSize
                label: NetworkMenu.verticalBarLabel
                foreground: NetworkMenu.barForeground
                tooltip: NetworkMenu.barTooltip
                hoverBackground: Theme.strongHover
                onClicked: NetworkMenu.toggleForScreen(bar.screen)
                onRightClicked: NetworkMenu.toggleForScreen(bar.screen)
            }

            BarControl {
                visible: BluetoothMenu.available
                vertical: true; fixedWidth: bar.barSize
                label: BluetoothMenu.verticalBarLabel
                foreground: BluetoothMenu.barForeground
                tooltip: BluetoothMenu.barTooltip
                hoverBackground: Theme.strongHover
                onClicked: BluetoothMenu.toggleForScreen(bar.screen)
                onRightClicked: BluetoothMenu.toggleForScreen(bar.screen)
            }

            TrayColumn {}

            BarControl {
                vertical: true; fixedWidth: bar.barSize; label: ""; tooltip: "Clipboard history"
                hoverBackground: Theme.strongHover
                onClicked: ClipboardMenu.toggleForScreen(bar.screen)
                onRightClicked: ClipboardMenu.toggleForScreen(bar.screen)
            }
            BarControl {
                id: notificationButtonVertical
                vertical: true; fixedWidth: bar.barSize
                label: Notifications.mutePopups ? "" : ""
                foreground: Notifications.mutePopups ? Theme.critical : Theme.foreground
                hoverBackground: Theme.strongHover
                tooltip: Notifications.mutePopups
                    ? "Notifications muted\nLeft: open · Right: unmute"
                    : "Notifications enabled\nLeft: open · Right: mute"
                onClicked: Notifications.toggleForItem(bar.screen, notificationButtonVertical)
                onRightClicked: Notifications.togglePopupMute()
            }
            BarControl {
                vertical: true; fixedWidth: bar.barSize; label: ""; tooltip: "power menu"
                hoverBackground: Theme.strongHover
                onClicked: PowerMenu.toggleForScreen(bar.screen)
                onRightClicked: PowerMenu.openForScreen(bar.screen)
            }
        }
    }
}