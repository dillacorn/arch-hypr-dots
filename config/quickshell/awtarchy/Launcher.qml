pragma Singleton

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets

Singleton {
    id: root

    // Preserve the old Awtarchy/Fuzzel placement behavior:
    // - Bar button: pin to the corner beside that monitor's visible bar.
    // - Keyboard/desktop launcher: pin to the visible bar edge.
    // - Hidden bar: use a centered floating launcher on the focused monitor.
    property string placementMode: "center" // center | edge | corner
    property string placementPosition: "top"
    readonly property int horizontalBarSize: 28
    readonly property int verticalBarSize: 36

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function configurePlacement(targetScreen, fromBar) {
        if (!targetScreen || !BarState.enabledFor(targetScreen.name)) {
            placementMode = "center";
            placementPosition = "top";
            return;
        }

        placementPosition = BarState.positionFor(targetScreen.name);
        placementMode = fromBar ? "corner" : "edge";
    }

    function openWindow(targetScreen, fromBar) {
        if (targetScreen)
            launcherWindow.screen = targetScreen;
        configurePlacement(targetScreen, fromBar);
        search.text = "";
        appList.currentIndex = 0;
        launcherWindow.visible = true;
        Qt.callLater(() => search.forceActiveFocus());
    }

    // Bar.qml calls this directly. Treat it as the old --from-waybar path.
    function openForScreen(targetScreen) {
        openWindow(targetScreen, true);
    }

    // Hyprland binds and desktop launchers use this path.
    function openFocused() {
        openWindow(focusedScreen(), false);
    }

    function close() {
        launcherWindow.visible = false;
        search.text = "";
    }

    function toggleFocused() {
        if (launcherWindow.visible)
            close();
        else
            openFocused();
    }

    function panelX(panelWidth) {
        const width = launcherWindow.width;
        const centered = Math.max(0, Math.round((width - panelWidth) / 2));

        if (placementMode === "center")
            return centered;

        if (placementMode === "corner") {
            if (placementPosition === "right")
                return Math.max(0, width - panelWidth - verticalBarSize);
            if (placementPosition === "left")
                return verticalBarSize;
            return 0;
        }

        if (placementPosition === "left")
            return verticalBarSize;
        if (placementPosition === "right")
            return Math.max(0, width - panelWidth - verticalBarSize);
        return centered;
    }

    function panelY(panelHeight) {
        const height = launcherWindow.height;
        const centered = Math.max(0, Math.round((height - panelHeight) / 2));

        if (placementMode === "center")
            return centered;

        if (placementMode === "corner") {
            if (placementPosition === "bottom")
                return Math.max(0, height - panelHeight - horizontalBarSize);
            if (placementPosition === "top")
                return horizontalBarSize;
            return 0;
        }

        if (placementPosition === "top")
            return horizontalBarSize;
        if (placementPosition === "bottom")
            return Math.max(0, height - panelHeight - horizontalBarSize);
        return centered;
    }

    function filteredApps() {
        const query = search.text.trim().toLowerCase();
        const apps = [...DesktopEntries.applications.values]
            .filter(app => !app.noDisplay)
            .sort((a, b) => a.name.localeCompare(b.name));
        if (query.length === 0)
            return apps;

        return apps.filter(app => {
            const haystack = [app.name, app.genericName, app.comment, app.id]
                .filter(value => value && value.length > 0)
                .join(" ")
                .toLowerCase();
            return haystack.indexOf(query) >= 0;
        });
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleFocused(); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
    }

    PanelWindow {
        id: launcherWindow
        visible: false
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: panel
            width: Math.min(660, Math.max(420, launcherWindow.width * 0.52))
            height: Math.min(660, Math.max(360, launcherWindow.height * 0.68))
            x: root.panelX(width)
            y: root.panelY(height)
            color: Theme.popupBackground
            border.width: 0
            radius: 0

            MouseArea {
                anchors.fill: parent
                onPressed: mouse => mouse.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    color: Theme.active
                    border.width: 0

                    TextInput {
                        id: search
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        color: Theme.foreground
                        selectionColor: Theme.focus
                        selectedTextColor: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        focus: launcherWindow.visible

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text.length === 0
                            text: ">> "
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.close();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down) {
                                if (appList.count > 0)
                                    appList.currentIndex = Math.min(appList.count - 1, appList.currentIndex + 1);
                                appList.positionViewAtIndex(appList.currentIndex, ListView.Contain);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                if (appList.count > 0)
                                    appList.currentIndex = Math.max(0, appList.currentIndex - 1);
                                appList.positionViewAtIndex(appList.currentIndex, ListView.Contain);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (appList.currentItem && appList.currentItem.entry) {
                                    appList.currentItem.entry.execute();
                                    root.close();
                                }
                                event.accepted = true;
                            }
                        }

                        onTextChanged: appList.currentIndex = 0
                    }
                }

                ListView {
                    id: appList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0
                    currentIndex: 0

                    model: ScriptModel {
                        values: root.filteredApps()
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        property var entry: modelData

                        width: ListView.view.width
                        height: 46
                        color: ListView.isCurrentItem ? Theme.focus : (hover.containsMouse ? Theme.subtleHover : "transparent")
                        border.width: 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            IconImage {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                implicitSize: 24
                                source: row.entry.icon && row.entry.icon.length > 0
                                    ? Quickshell.iconPath(row.entry.icon, true)
                                    : Quickshell.iconPath("application-x-executable", true)
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    text: row.entry.name
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: row.entry.genericName && row.entry.genericName.length > 0
                                    text: row.entry.genericName
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: appList.currentIndex = index
                            onClicked: {
                                row.entry.execute();
                                root.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
