pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property var themes: []
    property string activeThemeName: ""
    property int selectedIndex: -1
    property string catalogError: ""

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    readonly property string catalogBackend: configHome + "/hypr/scripts/quickshell_theme_catalog.sh"
    readonly property string applyBackend: configHome + "/hypr/scripts/quickshell_theme_apply.sh"
    readonly property string activeThemePath: stateHome + "/awtarchy/active-theme"

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function filteredThemes() {
        const query = search.text.trim().toLowerCase();
        if (query.length === 0)
            return themes;
        return themes.filter(theme => {
            const name = String(theme.name || "").toLowerCase();
            const displayName = String(theme.display_name || theme.name || "").toLowerCase();
            return name.indexOf(query) >= 0 || displayName.indexOf(query) >= 0;
        });
    }

    function selectedTheme() {
        const values = filteredThemes();
        if (selectedIndex < 0 || selectedIndex >= values.length)
            return null;
        return values[selectedIndex];
    }

    function selectIndex(index) {
        const values = filteredThemes();
        if (values.length === 0) {
            selectedIndex = -1;
            return;
        }
        selectedIndex = Math.max(0, Math.min(values.length - 1, index));
        Qt.callLater(() => themeGrid.positionViewAtIndex(selectedIndex, GridView.Contain));
    }

    function resetSelection() {
        const values = filteredThemes();
        if (values.length === 0) {
            selectedIndex = -1;
            return;
        }

        let activeIndex = -1;
        if (activeThemeName.length > 0) {
            for (let index = 0; index < values.length; ++index) {
                if (String(values[index].name || "") === activeThemeName) {
                    activeIndex = index;
                    break;
                }
            }
        }
        selectIndex(activeIndex >= 0 ? activeIndex : 0);
    }

    function moveSelection(delta) {
        if (selectedIndex < 0) {
            resetSelection();
            return;
        }
        selectIndex(selectedIndex + delta);
    }

    function moveSelectionRow(delta) {
        if (selectedIndex < 0) {
            resetSelection();
            return;
        }
        selectIndex(selectedIndex + delta * themeGrid.columnCount);
    }

    function loadCatalog() {
        catalogError = "";
        catalogProcess.exec(["bash", catalogBackend]);
    }

    function loadActiveTheme() {
        activeThemeName = "";
        activeThemeReader.exec(["cat", activeThemePath]);
    }

    function openForScreen(target) {
        if (target)
            pickerWindow.screen = target;
        search.text = "";
        pickerWindow.visible = true;
        loadActiveTheme();
        loadCatalog();
        resetSelection();
        Qt.callLater(() => search.forceActiveFocus());
    }

    function openFocused() { openForScreen(focusedScreen()); }

    function close() {
        pickerWindow.visible = false;
        search.text = "";
    }

    function toggleFocused() { pickerWindow.visible ? close() : openFocused(); }

    function applySelectedTheme() {
        const selected = selectedTheme();
        if (!selected || applyProcess.running)
            return;
        applyProcess.exec([root.applyBackend, selected.name]);
        close();
    }

    IpcHandler {
        target: "themes"
        function toggle(): void { root.toggleFocused(); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
    }

    Process {
        id: catalogProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (!Array.isArray(parsed))
                        throw new Error("catalog root is not an array");
                    root.themes = parsed;
                    root.catalogError = "";
                } catch (error) {
                    root.themes = [];
                    root.catalogError = "Could not read theme catalog";
                    console.warn("Awtarchy ThemePicker: invalid catalog JSON:", error);
                }
                root.resetSelection();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message.length > 0)
                    root.catalogError = message.split("\n")[0];
            }
        }
    }

    Process {
        id: activeThemeReader

        stdout: StdioCollector {
            onStreamFinished: {
                root.activeThemeName = text.trim();
                root.resetSelection();
            }
        }

        stderr: StdioCollector {}
    }

    Process { id: applyProcess }

    PanelWindow {
        id: pickerWindow
        WlrLayershell.namespace: "awtarchy-theme-picker"
        visible: false
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: Math.max(1, Math.min(900, (screen ? screen.width : 1920) - 20))
        implicitHeight: Math.max(1, Math.min(600, (screen ? screen.height : 1080) - 20))
        anchors.top: true
        anchors.left: true
        margins {
            top: Math.max(10, Math.round(((screen ? screen.height : 1080) - implicitHeight) / 2))
            left: Math.max(10, Math.round(((screen ? screen.width : 1920) - implicitWidth) / 2))
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.muted
            radius: 6

            MouseArea {
                anchors.fill: parent
                onPressed: mouse => mouse.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    spacing: 12

                    Text {
                        text: "Themes"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        color: Theme.active
                        border.width: 1
                        border.color: search.activeFocus ? Theme.foreground : Theme.muted
                        radius: 4

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            text: "Search themes…"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            verticalAlignment: Text.AlignVCenter
                            visible: search.text.length === 0
                        }

                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            color: Theme.foreground
                            selectionColor: Theme.focus
                            selectedTextColor: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    root.close();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Left) {
                                    root.moveSelection(-1);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Right) {
                                    root.moveSelection(1);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    root.moveSelectionRow(-1);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Down) {
                                    root.moveSelectionRow(1);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Home) {
                                    root.selectIndex(0);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_End) {
                                    root.selectIndex(root.filteredThemes().length - 1);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.applySelectedTheme();
                                    event.accepted = true;
                                }
                            }

                            onTextChanged: root.resetSelection()
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: 165
                        spacing: 1

                        Text {
                            text: "Active theme"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.activeThemeName.length > 0 ? root.activeThemeName : "Unknown"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                    }
                }

                GridView {
                    id: themeGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 500
                    property int columnCount: Math.max(1, Math.floor(width / 245))
                    cellWidth: width / columnCount
                    cellHeight: 190
                    currentIndex: root.selectedIndex

                    model: ScriptModel {
                        values: root.filteredThemes()
                    }

                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property var theme: modelData
                        readonly property var palette: theme.palette || ({})
                        readonly property bool selected: index === root.selectedIndex
                        readonly property bool activeTheme: String(theme.name || "") === root.activeThemeName

                        width: themeGrid.cellWidth
                        height: themeGrid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 6
                            color: card.selected ? Theme.focus
                                : (cardMouse.containsMouse ? Theme.hover : Theme.active)
                            border.width: card.selected ? 2 : 1
                            border.color: card.selected ? Theme.foreground : Theme.muted
                            radius: 5

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 7
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: card.palette.background
                                    border.width: 1
                                    border.color: card.palette.focus
                                    radius: 3
                                    clip: true

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 24
                                        color: card.palette.active

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 7
                                            anchors.rightMargin: 7
                                            spacing: 5

                                            Repeater {
                                                model: ["1", "2", "3"]
                                                Text {
                                                    required property string modelData
                                                    text: modelData
                                                    color: card.palette.foreground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: "Awtarchy"
                                                color: card.palette.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 9
                                                font.weight: Font.Medium
                                            }
                                        }
                                    }

                                    Rectangle {
                                        x: 12
                                        y: 38
                                        width: Math.max(54, parent.width * 0.42)
                                        height: Math.max(42, parent.height - 52)
                                        color: card.palette.active
                                        border.width: 2
                                        border.color: card.palette.focus
                                        radius: 2

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            height: 13
                                            color: card.palette.focus
                                        }
                                    }

                                    Rectangle {
                                        x: Math.max(74, parent.width * 0.48)
                                        y: 48
                                        width: Math.max(48, parent.width * 0.38)
                                        height: Math.max(34, parent.height - 64)
                                        color: card.palette.hover
                                        border.width: 1
                                        border.color: card.palette.muted
                                        radius: 2
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5

                                    Repeater {
                                        model: [
                                            card.palette.foreground,
                                            card.palette.focus,
                                            card.palette.urgent,
                                            card.palette.charging,
                                            card.palette.muted
                                        ]

                                        Rectangle {
                                            required property color modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 8
                                            color: modelData
                                            radius: 1
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: String(card.theme.display_name || card.theme.name || "Theme")
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        visible: card.activeTheme
                                        Layout.preferredWidth: 48
                                        Layout.preferredHeight: 20
                                        color: Theme.charging
                                        radius: 3

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Active"
                                            color: Theme.dark
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.selectIndex(card.index)
                            }
                        }
                    }

                    onWidthChanged: Qt.callLater(() => {
                        if (root.selectedIndex >= 0)
                            positionViewAtIndex(root.selectedIndex, GridView.Contain);
                    })
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.catalogError.length > 0 || root.filteredThemes().length === 0
                    text: root.catalogError.length > 0
                        ? root.catalogError
                        : "No themes match this search."
                    color: root.catalogError.length > 0 ? Theme.critical : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.muted
                    opacity: 0.6
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        readonly property var selected: root.selectedTheme()

                        Text {
                            Layout.fillWidth: true
                            text: parent.selected
                                ? String(parent.selected.display_name || parent.selected.name || "Theme")
                                : "No theme selected"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                const selected = parent.selected;
                                if (!selected)
                                    return "";
                                const apps = selected.apps || ({});
                                return "Micro: " + String(apps.micro || "—")
                                    + "   Alacritty: " + String(apps.alacritty || "—")
                                    + "   SpeedCrunch: " + String(apps.speedcrunch || "—");
                            }
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 86
                        Layout.preferredHeight: 34
                        color: cancelMouse.containsMouse ? Theme.hover : Theme.active
                        border.width: 1
                        border.color: Theme.muted
                        radius: 4

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.close()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 116
                        Layout.preferredHeight: 34
                        color: applyMouse.containsMouse ? Theme.focus : Theme.active
                        border.width: 1
                        border.color: root.selectedTheme() ? Theme.foreground : Theme.muted
                        radius: 4
                        opacity: root.selectedTheme() ? 1 : 0.55

                        Text {
                            anchors.centerIn: parent
                            text: "Apply Theme"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: applyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.selectedTheme() !== null
                            onClicked: root.applySelectedTheme()
                        }
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => search.forceActiveFocus());
        }
    }
}
