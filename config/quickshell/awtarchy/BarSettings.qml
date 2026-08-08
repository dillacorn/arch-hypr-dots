pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string quickshellScript: configHome + "/hypr/scripts/quickshell.sh"
    property string targetMonitorName: ""
    property bool targetAll: false

    function focusedScreen() {
        const focusedName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === focusedName);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function screenByName(name) {
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : null;
    }

    function targetNames() {
        if (targetAll)
            return Quickshell.screens.map(screen => screen.name);
        return targetMonitorName.length > 0 ? [targetMonitorName] : [];
    }

    function selectMonitor(name) {
        targetAll = false;
        targetMonitorName = name;
        const target = screenByName(name);
        if (target)
            settingsWindow.screen = target;
    }

    function selectAll() {
        targetAll = true;
    }

    function open() {
        const target = focusedScreen();
        if (target) {
            targetMonitorName = target.name;
            targetAll = false;
            settingsWindow.screen = target;
        }
        settingsWindow.visible = true;
        settingsWindow.raise();
        settingsWindow.requestActivate();
    }

    function close() {
        settingsWindow.visible = false;
    }

    function toggle() {
        if (settingsWindow.visible)
            close();
        else
            open();
    }

    function runForTargets(command, value) {
        const names = targetNames();
        for (let i = 0; i < names.length; ++i) {
            const args = [quickshellScript, command, names[i]];
            if (value !== undefined && value !== null)
                args.push(String(value));
            Quickshell.execDetached(args);
        }
    }

    function commonValue(getter) {
        const names = targetNames();
        if (names.length === 0)
            return null;
        let first = getter(names[0]);
        for (let i = 1; i < names.length; ++i) {
            if (getter(names[i]) !== first)
                return null;
        }
        return first;
    }

    function commonPosition() {
        return commonValue(name => BarState.positionFor(name));
    }

    function commonEnabled() {
        return commonValue(name => BarState.enabledFor(name));
    }

    function rawBarSize(name) {
        const state = BarState.monitorState(name);
        const value = Number(state.bar_size || 0);
        return Number.isFinite(value) ? Math.round(value) : 0;
    }

    function commonRawBarSize() {
        return commonValue(name => rawBarSize(name));
    }

    function iconScalePercent(name) {
        return Math.round(BarState.iconScaleFor(name) * 100);
    }

    function commonIconScale() {
        return commonValue(name => iconScalePercent(name));
    }

    function currentActualBarSize() {
        const names = targetNames();
        if (names.length === 0)
            return 28;
        const pos = BarState.positionFor(names[0]);
        return BarState.barSizeFor(names[0], pos === "left" || pos === "right");
    }

    function adjustBarSize(delta) {
        const raw = commonRawBarSize();
        let base = raw === null || raw === 0 ? currentActualBarSize() : raw;
        base = Math.max(20, Math.min(80, base + delta));
        runForTargets("setsize", base);
    }

    function adjustIconScale(delta) {
        const current = commonIconScale();
        let base = current === null ? 100 : current;
        base = Math.max(50, Math.min(200, base + delta));
        runForTargets("setscale", base);
    }

    function resetTargets() {
        if (targetAll) {
            Quickshell.execDetached([quickshellScript, "reset-all"]);
        } else if (targetMonitorName.length > 0) {
            Quickshell.execDetached([quickshellScript, "reset-mon", targetMonitorName]);
        }
    }

    IpcHandler {
        target: "barsettings"
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        function toggle(): void { root.toggle(); }
    }

    component ActionButton: Rectangle {
        required property string label
        property bool selected: false
        property bool destructive: false
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: 34
        radius: 0
        border.width: selected ? 1 : 0
        border.color: Theme.foreground
        color: selected ? Theme.focus : (buttonMouse.containsMouse ? Theme.subtleHover : Theme.active)

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.destructive ? Theme.urgent : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    FloatingWindow {
        id: settingsWindow
        visible: false
        title: "Awtarchy Bar Settings"
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: 560
        implicitHeight: 470
        minimumSize: Qt.size(520, 430)
        maximumSize: Qt.size(720, 620)

        Shortcut {
            sequence: "Esc"
            onActivated: root.close()
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.active
            radius: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Bar Settings"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                            font.bold: true
                        }

                        Text {
                            text: "Click controls below. ALT + left-drag a bar to snap it to another edge."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        color: closeMouse.containsMouse ? Theme.subtleHover : Theme.active

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                Text {
                    text: "Target"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ActionButton {
                        label: "All displays"
                        selected: root.targetAll
                        onClicked: root.selectAll()
                    }

                    Repeater {
                        model: Quickshell.screens

                        delegate: ActionButton {
                            required property var modelData
                            label: modelData.name
                            selected: !root.targetAll && root.targetMonitorName === modelData.name
                            onClicked: root.selectMonitor(modelData.name)
                        }
                    }
                }

                Text {
                    text: "Position"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ActionButton { label: "Top"; selected: root.commonPosition() === "top"; onClicked: root.runForTargets("setpos", "top") }
                    ActionButton { label: "Bottom"; selected: root.commonPosition() === "bottom"; onClicked: root.runForTargets("setpos", "bottom") }
                    ActionButton { label: "Left"; selected: root.commonPosition() === "left"; onClicked: root.runForTargets("setpos", "left") }
                    ActionButton { label: "Right"; selected: root.commonPosition() === "right"; onClicked: root.runForTargets("setpos", "right") }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: "Visibility"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }

                    ActionButton {
                        Layout.preferredWidth: 150
                        Layout.fillWidth: false
                        label: root.commonEnabled() === null ? "Mixed" : (root.commonEnabled() ? "Visible" : "Hidden")
                        selected: root.commonEnabled() === true
                        onClicked: {
                            const enabled = root.commonEnabled();
                            root.runForTargets("setenabled", enabled === true ? "false" : "true");
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.preferredWidth: 150
                        text: "Bar thickness"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    ActionButton {
                        Layout.preferredWidth: 42
                        Layout.fillWidth: false
                        label: "−"
                        onClicked: root.adjustBarSize(-2)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        color: Theme.active

                        Text {
                            anchors.centerIn: parent
                            text: {
                                const value = root.commonRawBarSize();
                                if (value === null) return "Mixed";
                                if (value === 0) return "Default";
                                return value + " px";
                            }
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }

                    ActionButton {
                        Layout.preferredWidth: 42
                        Layout.fillWidth: false
                        label: "+"
                        onClicked: root.adjustBarSize(2)
                    }

                    ActionButton {
                        Layout.preferredWidth: 80
                        Layout.fillWidth: false
                        label: "Default"
                        onClicked: root.runForTargets("setsize", 0)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.preferredWidth: 150
                        text: "Icon size"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    ActionButton {
                        Layout.preferredWidth: 42
                        Layout.fillWidth: false
                        label: "−"
                        onClicked: root.adjustIconScale(-5)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        color: Theme.active

                        Text {
                            anchors.centerIn: parent
                            text: root.commonIconScale() === null ? "Mixed" : root.commonIconScale() + "%"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }

                    ActionButton {
                        Layout.preferredWidth: 42
                        Layout.fillWidth: false
                        label: "+"
                        onClicked: root.adjustIconScale(5)
                    }

                    ActionButton {
                        Layout.preferredWidth: 80
                        Layout.fillWidth: false
                        label: "100%"
                        onClicked: root.runForTargets("setscale", 100)
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ActionButton {
                        label: "Reset selected target"
                        destructive: true
                        onClicked: root.resetTargets()
                    }

                    ActionButton {
                        label: "Done"
                        selected: true
                        onClicked: root.close()
                    }
                }
            }
        }
    }
}
