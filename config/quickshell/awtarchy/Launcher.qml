pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string positionScript: configHome + "/hypr/scripts/quickshell_launcher_position.sh"
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string animationStatePath: runtimeDir + "/hypr-animations-enabled"
    readonly property int minimumLauncherWidth: 420
    readonly property int minimumLauncherHeight: 360
    readonly property int applicationColumnMinimumWidth: 300
    readonly property string activeMonitorName: launcherWindow.screen && launcherWindow.screen.name
        ? launcherWindow.screen.name : targetMonitorName
    readonly property int configuredAppTextSize: BarState.appTextSizeFor(activeMonitorName, false)
    readonly property int configuredAppIconSize: BarState.appIconSizeFor(activeMonitorName, false)
    readonly property int liveWidth: Math.round(launcherWindow.width)
    readonly property int liveHeight: Math.round(launcherWindow.height)
    readonly property bool sizeLocked: activeMonitorName.length > 0
        && BarState.applicationSizeLockedFor(activeMonitorName)
    property string targetMonitorName: ""
    property string requestedPlacement: "center"
    property bool launcherPositioned: false

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

    function centeredPlacementForScreen(targetScreen) {
        if (!targetScreen || !BarState.enabledFor(targetScreen.name))
            return "center";
        return BarState.positionFor(targetScreen.name) + "-center";
    }

    function animationsEnabled() {
        const state = animationStateFile.text().trim();
        return state !== "0";
    }

    function resetSelection() {
        appList.currentIndex = 0;
        Qt.callLater(() => {
            appList.currentIndex = 0;
            appList.positionViewAtBeginning();
        });
    }

    function setWindowSize(width, height) {
        const targetScreen = launcherWindow.screen;
        const screenWidth = targetScreen ? targetScreen.width : 1920;
        const screenHeight = targetScreen ? targetScreen.height : 1080;
        const desiredWidth = Math.min(screenWidth,
            Math.max(minimumLauncherWidth, Math.round(width)));
        const desiredHeight = Math.min(screenHeight,
            Math.max(minimumLauncherHeight, Math.round(height)));

        launcherWindow.implicitWidth = desiredWidth;
        launcherWindow.implicitHeight = desiredHeight;
        launcherWindow.width = desiredWidth;
        launcherWindow.height = desiredHeight;
    }

    function applySpawnSize() {
        setWindowSize(
            BarState.launcherWidthFor(targetMonitorName, false),
            BarState.launcherHeightFor(targetMonitorName, false)
        );
    }

    function toggleSizeLock() {
        const monitor = activeMonitorName;
        if (monitor.length === 0 || sizeStateWriter.running)
            return;

        if (BarState.applicationSizeLockedFor(monitor)) {
            sizeStateWriter.exec([stateScript, "unlock-size", monitor]);
        } else {
            sizeStateWriter.exec([
                stateScript,
                "lock-size",
                monitor,
                String(liveWidth),
                String(liveHeight)
            ]);
        }
    }

    function showOnScreen(targetScreen, placement) {
        if (!targetScreen)
            return;

        focusGrab.active = false;
        targetMonitorName = targetScreen.name;
        requestedPlacement = placement || "center";
        launcherPositioned = false;
        launcherWindow.screen = targetScreen;
        applySpawnSize();
        search.text = "";
        launcherWindow.visible = true;
        resetSelection();
    }

    function openForScreen(targetScreen) {
        if (launcherWindow.visible) {
            close();
            return;
        }
        showOnScreen(targetScreen, placementForScreen(targetScreen));
    }

    function openFocused() {
        const target = focusedScreen();
        if (launcherWindow.visible) {
            search.forceActiveFocus();
            return;
        }
        showOnScreen(target, centeredPlacementForScreen(target));
    }

    function close() {
        focusGrab.active = false;
        launcherWindow.visible = false;
        launcherPositioned = false;
        search.text = "";
    }

    function toggleFocused() {
        if (launcherWindow.visible) {
            close();
            return;
        }
        const target = focusedScreen();
        showOnScreen(target, centeredPlacementForScreen(target));
    }

    function positionLauncher() {
        if (!launcherWindow.visible || targetMonitorName.length === 0)
            return;
        positionProcess.exec([positionScript, targetMonitorName, requestedPlacement]);
    }

    function searchText(entry) {
        if (!entry)
            return "";
        return [entry.name, entry.genericName, entry.comment, entry.id, ...(entry.keywords || [])]
            .filter(value => value && String(value).length > 0)
            .join(" ")
            .toLowerCase();
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
            const ch = query[i];
            const found = haystack.indexOf(ch, at);
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

    function visibleApps() {
        return [...DesktopEntries.applications.values].filter(app => app && !app.noDisplay);
    }

    function filteredApps() {
        const query = search.text.trim().toLowerCase();
        const apps = visibleApps()
            .map(app => ({ entry: app, score: fuzzyScore(searchText(app), query) }))
            .filter(item => item.entry && item.score >= 0);

        apps.sort((a, b) => {
            if (a.score !== b.score)
                return b.score - a.score;
            return String(a.entry.name || "").localeCompare(String(b.entry.name || ""));
        });
        return apps.map(item => item.entry).filter(entry => entry !== null && entry !== undefined);
    }

    function launchEntry(entry) {
        if (!entry)
            return;

        const workingDirectory = entry.workingDirectory || "";
        if (entry.runInTerminal) {
            Quickshell.execDetached({
                command: ["alacritty", "-e", ...entry.command],
                workingDirectory: workingDirectory
            });
        } else {
            Quickshell.execDetached({
                command: entry.command,
                workingDirectory: workingDirectory
            });
        }
        close();
    }

    FileView {
        id: animationStateFile
        path: root.animationStatePath
        blockLoading: false
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    Process {
        id: sizeStateWriter
        onExited: BarState.refresh()
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleFocused(); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
        function applyConfiguredSize(): void { root.applySpawnSize(); }
        function currentWidth(): int { return root.liveWidth; }
        function currentHeight(): int { return root.liveHeight; }
    }

    Timer {
        id: positionTimer
        interval: 0
        repeat: false
        onTriggered: root.positionLauncher()
    }

    Process {
        id: positionProcess
        onExited: {
            if (!launcherWindow.visible)
                return;
            root.launcherPositioned = true;
            focusGrab.active = true;
            Qt.callLater(() => search.forceActiveFocus());
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [launcherWindow]
        onCleared: {
            if (launcherWindow.visible)
                root.close();
        }
    }

    FloatingWindow {
        id: launcherWindow
        visible: false
        title: "Awtarchy Application Search"
        color: "transparent"
        surfaceFormat.opaque: false

        implicitWidth: BarState.defaultLauncherWidth
        implicitHeight: BarState.defaultLauncherHeight
        minimumSize: Qt.size(root.minimumLauncherWidth, root.minimumLauncherHeight)
        maximumSize: Qt.size(
            Math.max(root.minimumLauncherWidth, screen ? screen.width : 1920),
            Math.max(root.minimumLauncherHeight, screen ? screen.height : 1080)
        )

        onVisibleChanged: {
            if (visible) {
                root.launcherPositioned = false;
                positionTimer.restart();
            } else {
                focusGrab.active = false;
            }
        }

        onClosed: root.close()

        Rectangle {
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 0
            radius: 0
            opacity: root.launcherPositioned ? 1 : 0

            Behavior on opacity {
                enabled: root.animationsEnabled()
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            DragHandler {
                target: null
                acceptedButtons: Qt.LeftButton
                acceptedModifiers: Qt.AltModifier
                onActiveChanged: {
                    if (active) {
                        positionTimer.stop();
                        launcherWindow.startSystemMove();
                    }
                }
            }

            DragHandler {
                target: null
                acceptedButtons: Qt.RightButton
                acceptedModifiers: Qt.AltModifier
                onActiveChanged: {
                    if (active) {
                        positionTimer.stop();
                        launcherWindow.startSystemResize(Qt.RightEdge | Qt.BottomEdge);
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: Theme.active
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 6

                        Text {
                            text: ">>"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
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
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            focus: launcherWindow.visible && root.launcherPositioned

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    root.close();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down) {
                                    if (appList.count > 0)
                                        appList.currentIndex = Math.min(appList.count - 1,
                                            Math.max(0, appList.currentIndex) + appList.columnCount);
                                    appList.positionViewAtIndex(appList.currentIndex, GridView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    if (appList.count > 0)
                                        appList.currentIndex = Math.max(0,
                                            Math.max(0, appList.currentIndex) - appList.columnCount);
                                    appList.positionViewAtIndex(appList.currentIndex, GridView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Right && appList.columnCount > 1) {
                                    if (appList.count > 0)
                                        appList.currentIndex = Math.min(appList.count - 1,
                                            Math.max(0, appList.currentIndex) + 1);
                                    appList.positionViewAtIndex(appList.currentIndex, GridView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Left && appList.columnCount > 1) {
                                    if (appList.count > 0)
                                        appList.currentIndex = Math.max(0,
                                            Math.max(0, appList.currentIndex) - 1);
                                    appList.positionViewAtIndex(appList.currentIndex, GridView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    const values = root.filteredApps();
                                    if (appList.currentIndex >= 0 && appList.currentIndex < values.length)
                                        root.launchEntry(values[appList.currentIndex]);
                                    event.accepted = true;
                                }
                            }

                            onTextChanged: root.resetSelection()
                        }

                        Text {
                            readonly property int matches: appList.count
                            text: matches + "/" + root.visibleApps().length
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }

                        Rectangle {
                            Layout.preferredWidth: lockText.implicitWidth + 14
                            Layout.preferredHeight: 26
                            color: root.sizeLocked ? Theme.focus : (lockMouse.containsMouse ? Theme.subtleHover : "transparent")
                            border.width: 0

                            Text {
                                id: lockText
                                anchors.centerIn: parent
                                text: root.sizeLocked ? " Locked" : " Unlocked"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            MouseArea {
                                id: lockMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.toggleSizeLock();
                                    Qt.callLater(() => search.forceActiveFocus());
                                }
                            }
                        }
                    }
                }

                GridView {
                    id: appList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    currentIndex: 0
                    boundsBehavior: Flickable.StopAtBounds
                    flow: GridView.FlowLeftToRight
                    readonly property int columnCount: Math.max(1,
                        Math.floor(width / root.applicationColumnMinimumWidth))
                    cellWidth: width / columnCount
                    cellHeight: Math.max(28,
                        root.configuredAppIconSize + 10,
                        root.configuredAppTextSize + 14)

                    model: ScriptModel {
                        values: root.filteredApps()
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        property var entry: modelData

                        width: GridView.view.cellWidth
                        height: GridView.view.cellHeight
                        color: GridView.isCurrentItem ? Theme.focus : (hover.containsMouse ? Theme.subtleHover : "transparent")
                        border.width: 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: appScrollBar.visible ? 18 : 8
                            spacing: 8

                            IconImage {
                                Layout.preferredWidth: root.configuredAppIconSize
                                Layout.preferredHeight: root.configuredAppIconSize
                                implicitSize: root.configuredAppIconSize
                                source: row.entry && row.entry.icon && row.entry.icon.length > 0
                                    ? Quickshell.iconPath(row.entry.icon, true)
                                    : Quickshell.iconPath("application-x-executable", true)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.entry ? (row.entry.name || "Application") : "Application"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: root.configuredAppTextSize
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            onPositionChanged: mouse => {
                                appList.currentIndex = row.index;
                            }
                            onClicked: root.launchEntry(row.entry)
                            onWheel: wheel => {
                                const minY = appList.originY;
                                const maxY = Math.max(minY, minY + appList.contentHeight - appList.height);
                                appList.contentY = Math.max(minY,
                                    Math.min(maxY, appList.contentY - wheel.angleDelta.y));
                                wheel.accepted = true;
                            }
                        }
                    }

                    ListScrollBar {
                        id: appScrollBar
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        flickable: appList
                        z: 10
                    }
                }
            }
        }
    }
}
