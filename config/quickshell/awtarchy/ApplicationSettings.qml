pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property int defaultWidth: 420
    readonly property int defaultHeight: 582
    readonly property int defaultTextSize: 14
    readonly property int defaultIconSize: 18

    property int selectedIndex: 0
    property string editingField: ""
    property var editingRow: null
    property string editBuffer: ""
    property int textSize: defaultTextSize
    property int iconSize: defaultIconSize
    property int lastLiveWidth: defaultWidth
    property int lastLiveHeight: defaultHeight
    property bool suppressGeometrySave: false
    property string statusText: ""

    function focusedScreen() {
        const focusedName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === focusedName);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, Math.round(value)));
    }

    function liveWidth() {
        return Launcher.liveWidth > 0 ? Launcher.liveWidth : defaultWidth;
    }

    function liveHeight() {
        return Launcher.liveHeight > 0 ? Launcher.liveHeight : defaultHeight;
    }

    function persistField(field, value) {
        Quickshell.execDetached([stateScript, "set", field, String(value)]);
    }

    function persistSize(width, height) {
        Quickshell.execDetached([stateScript, "set-size", String(width), String(height)]);
    }

    function setSize(width, height, persist) {
        const w = clamp(width, 420, 3840);
        const h = clamp(height, 360, 2160);
        suppressGeometrySave = true;
        releaseGeometrySuppression.restart();
        Launcher.setPreviewSize(w, h);
        lastLiveWidth = w;
        lastLiveHeight = h;
        if (persist)
            persistSize(w, h);
        statusText = "Spawn size: " + w + " × " + h + " px";
    }

    function applyField(field, value) {
        if (field === "width") {
            setSize(clamp(value, 420, 3840), liveHeight(), true);
        } else if (field === "height") {
            setSize(liveWidth(), clamp(value, 360, 2160), true);
        } else if (field === "text_size") {
            textSize = clamp(value, 10, 28);
            Launcher.setPreviewStyle(textSize, iconSize);
            persistField("text_size", textSize);
            statusText = "Application text: " + textSize + " px";
        } else if (field === "icon_size") {
            iconSize = clamp(value, 12, 48);
            Launcher.setPreviewStyle(textSize, iconSize);
            persistField("icon_size", iconSize);
            statusText = "Application icons: " + iconSize + " px";
        }
    }

    function adjustField(row, delta) {
        applyField(row.fieldName, clamp(row.value + delta, row.minimumValue, row.maximumValue));
    }

    function startEditing(row) {
        selectedIndex = row.fieldIndex;
        editingField = row.fieldName;
        editingRow = row;
        editBuffer = String(row.value);
        statusText = "Type a value, then press Enter to input value";
    }

    function cancelEditing() {
        editingField = "";
        editingRow = null;
        editBuffer = "";
        statusText = "Edit cancelled";
        Qt.callLater(() => settingsPanel.forceActiveFocus());
    }

    function commitEditing() {
        if (!editingRow)
            return;
        const parsed = Number(editBuffer);
        if (!Number.isFinite(parsed) || Math.round(parsed) !== parsed
                || parsed < editingRow.minimumValue || parsed > editingRow.maximumValue) {
            statusText = "Value must be " + editingRow.minimumValue + "-" + editingRow.maximumValue;
            return;
        }
        const row = editingRow;
        editingField = "";
        editingRow = null;
        editBuffer = "";
        applyField(row.fieldName, parsed);
        Qt.callLater(() => settingsPanel.forceActiveFocus());
    }

    function resetDefaults() {
        suppressGeometrySave = true;
        releaseGeometrySuppression.restart();
        Quickshell.execDetached([stateScript, "reset"]);
        textSize = defaultTextSize;
        iconSize = defaultIconSize;
        Launcher.setPreviewStyle(textSize, iconSize);
        Launcher.setPreviewSize(defaultWidth, defaultHeight);
        lastLiveWidth = defaultWidth;
        lastLiveHeight = defaultHeight;
        statusText = "Reset to default: 420 × 582 px";
    }

    function open() {
        const target = focusedScreen();
        const view = BarState.globalApplicationView();
        textSize = view.textSize;
        iconSize = view.iconSize;
        selectedIndex = 0;
        editingField = "";
        editingRow = null;
        statusText = "Scroll a field for ±1 px, or click it to type an exact value";

        if (target) {
            settingsWindow.screen = target;
            Launcher.previewMonitor(target.name, true);
        }
        Launcher.setPreviewStyle(textSize, iconSize);
        settingsWindow.visible = true;
        settingsWindow.raise();
        settingsWindow.requestActivate();
        Qt.callLater(() => {
            lastLiveWidth = liveWidth();
            lastLiveHeight = liveHeight();
            settingsPanel.forceActiveFocus();
        });
    }

    function close() {
        editingField = "";
        editingRow = null;
        geometrySave.stop();
        Launcher.close();
        settingsWindow.visible = false;
    }

    function toggle() {
        if (settingsWindow.visible)
            close();
        else
            open();
    }

    function activateSelected() {
        switch (selectedIndex) {
        case 0: startEditing(widthRow); break;
        case 1: startEditing(heightRow); break;
        case 2: startEditing(textRow); break;
        case 3: startEditing(iconRow); break;
        case 4: resetDefaults(); break;
        case 5: close(); break;
        }
    }

    function adjustSelected(delta) {
        switch (selectedIndex) {
        case 0: adjustField(widthRow, delta); break;
        case 1: adjustField(heightRow, delta); break;
        case 2: adjustField(textRow, delta); break;
        case 3: adjustField(iconRow, delta); break;
        }
    }

    Timer {
        id: geometryWatch
        interval: 100
        repeat: true
        running: settingsWindow.visible && Launcher.previewVisible
        onTriggered: {
            const width = root.liveWidth();
            const height = root.liveHeight();
            if (width === root.lastLiveWidth && height === root.lastLiveHeight)
                return;

            root.lastLiveWidth = width;
            root.lastLiveHeight = height;
            if (!root.suppressGeometrySave)
                geometrySave.restart();
        }
    }

    Timer {
        id: geometrySave
        interval: 350
        repeat: false
        onTriggered: {
            if (!settingsWindow.visible || root.suppressGeometrySave)
                return;
            const width = root.liveWidth();
            const height = root.liveHeight();
            root.persistSize(width, height);
            root.statusText = "Spawn size saved: " + width + " × " + height + " px";
        }
    }

    Timer {
        id: releaseGeometrySuppression
        interval: 450
        repeat: false
        onTriggered: {
            root.suppressGeometrySave = false;
            root.lastLiveWidth = root.liveWidth();
            root.lastLiveHeight = root.liveHeight();
        }
    }

    IpcHandler {
        target: "appsettings"
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        function toggle(): void { root.toggle(); }
        function reset(): void { root.resetDefaults(); }
    }

    component NumericRow: Rectangle {
        id: row
        required property string fieldName
        required property string labelText
        required property int fieldIndex
        required property int value
        required property int minimumValue
        required property int maximumValue

        readonly property bool editing: root.editingField === fieldName

        Layout.fillWidth: true
        Layout.preferredHeight: 44
        color: root.selectedIndex === fieldIndex
            ? Theme.subtleActive
            : (rowMouse.containsMouse ? Theme.subtleHover : "transparent")

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onEntered: root.selectedIndex = row.fieldIndex
            onClicked: root.startEditing(row)
            onWheel: wheel => {
                const delta = wheel.angleDelta.y > 0 ? 1 : -1;
                root.selectedIndex = row.fieldIndex;
                root.adjustField(row, delta);
                wheel.accepted = true;
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: row.labelText
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.editing
            text: row.value + " px"
            color: root.selectedIndex === row.fieldIndex ? Theme.foreground : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 104
            height: 30
            visible: row.editing
            color: Theme.active
            border.width: 1
            border.color: Theme.focus

            TextInput {
                id: fieldInput
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                text: row.editing ? root.editBuffer : ""
                color: Theme.foreground
                selectionColor: Theme.focus
                selectedTextColor: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 13
                horizontalAlignment: TextInput.AlignRight
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                cursorVisible: activeFocus

                onTextChanged: {
                    if (row.editing && root.editBuffer !== text)
                        root.editBuffer = text;
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.commitEditing();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.cancelEditing();
                        event.accepted = true;
                    }
                }
            }
        }

        onEditingChanged: {
            if (editing) {
                Qt.callLater(() => {
                    fieldInput.forceActiveFocus();
                    fieldInput.selectAll();
                });
            }
        }
    }

    FloatingWindow {
        id: settingsWindow
        visible: false
        title: "Awtarchy Application View"
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: 440
        implicitHeight: 386
        minimumSize: Qt.size(440, 386)
        maximumSize: Qt.size(440, 386)

        onClosed: root.close()

        Rectangle {
            id: settingsPanel
            anchors.fill: parent
            color: Theme.popupBackground
            focus: true

            Keys.onPressed: event => {
                if (root.editingField.length > 0)
                    return;

                if (event.key === Qt.Key_Up) {
                    root.selectedIndex = (root.selectedIndex + 5) % 6;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.selectedIndex = (root.selectedIndex + 1) % 6;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left && root.selectedIndex < 4) {
                    root.adjustSelected(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right && root.selectedIndex < 4) {
                    root.adjustSelected(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activateSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: "Application View"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "Edit spawn dimensions"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }

                Text {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 3
                    text: "Move/resize controls and live dimensions are shown on the launcher preview."
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }

                NumericRow {
                    id: widthRow
                    fieldName: "width"
                    labelText: "Window width"
                    fieldIndex: 0
                    value: root.liveWidth()
                    minimumValue: 420
                    maximumValue: 3840
                }

                NumericRow {
                    id: heightRow
                    fieldName: "height"
                    labelText: "Window height"
                    fieldIndex: 1
                    value: root.liveHeight()
                    minimumValue: 360
                    maximumValue: 2160
                }

                NumericRow {
                    id: textRow
                    fieldName: "text_size"
                    labelText: "Application text"
                    fieldIndex: 2
                    value: root.textSize
                    minimumValue: 10
                    maximumValue: 28
                }

                NumericRow {
                    id: iconRow
                    fieldName: "icon_size"
                    labelText: "Application icons"
                    fieldIndex: 3
                    value: root.iconSize
                    minimumValue: 12
                    maximumValue: 48
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: root.selectedIndex === 4
                        ? Theme.subtleActive
                        : (resetMouse.containsMouse ? Theme.subtleHover : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: "Reset to default  •  420 × 582 px"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: resetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.selectedIndex = 4
                        onClicked: root.resetDefaults()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    color: root.selectedIndex === 5
                        ? Theme.subtleActive
                        : (closeMouse.containsMouse ? Theme.subtleHover : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: "Close"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.selectedIndex = 5
                        onClicked: root.close()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 3
                    text: root.editingField.length > 0
                        ? "Type value  •  press Enter to input value  •  Esc cancels"
                        : root.statusText
                    color: root.editingField.length > 0 ? Theme.foreground : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }
    }
}
