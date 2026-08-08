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
        // Selecting a target must not move/rescale the editor window. The
        // settings window stays on the display where it was opened.
        targetAll = false;
        targetMonitorName = name;
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

    function scheduleStateRefresh() {
        stateRefreshQuick.restart();
        stateRefreshFollowup.restart();
    }

    function runForTargets(command, value) {
        const names = targetNames();
        for (let i = 0; i < names.length; ++i) {
            const args = [quickshellScript, command, names[i]];
            if (value !== undefined && value !== null)
                args.push(String(value));
            Quickshell.execDetached(args);
        }
        scheduleStateRefresh();
    }

    function commonValue(getter) {
        const names = targetNames();
        if (names.length === 0)
            return "";

        let first = getter(names[0]);
        for (let i = 1; i < names.length; ++i) {
            if (getter(names[i]) !== first)
                return "mixed";
        }
        return first;
    }

    function positionLabel() {
        return commonValue(name => BarState.positionFor(name));
    }

    function enabledLabel() {
        return commonValue(name => BarState.enabledFor(name) ? "visible" : "hidden");
    }

    function barSizeValue() {
        const names = targetNames();
        if (names.length === 0)
            return 0;
        let first = BarState.monitorState(names[0]).bar_size || 0;
        for (let i = 1; i < names.length; ++i) {
            const next = BarState.monitorState(names[i]).bar_size || 0;
            if (next !== first)
                return -1;
        }
        return Number(first);
    }

    function defaultBarSizeForTarget() {
        const names = targetNames();
        if (names.length === 0)
            return 28;
        let vertical = ["left", "right"].indexOf(BarState.positionFor(names[0])) >= 0;
        for (let i = 1; i < names.length; ++i) {
            const nextVertical = ["left", "right"].indexOf(BarState.positionFor(names[i])) >= 0;
            if (nextVertical !== vertical)
                return 28;
        }
        return vertical ? 36 : 28;
    }

    function iconScaleValue() {
        const names = targetNames();
        if (names.length === 0)
            return 100;
        let first = BarState.monitorState(names[0]).icon_scale;
        first = first === undefined ? 100 : Number(first);
        for (let i = 1; i < names.length; ++i) {
            let next = BarState.monitorState(names[i]).icon_scale;
            next = next === undefined ? 100 : Number(next);
            if (next !== first)
                return -1;
        }
        return first;
    }

    function setPosition(position) {
        runForTargets("setpos", position);
    }

    function setVisible(visible) {
        runForTargets("setenabled", visible ? "true" : "false");
    }

    function changeBarSize(delta) {
        let current = barSizeValue();
        if (current < 0)
            current = defaultBarSizeForTarget();
        if (current === 0)
            current = defaultBarSizeForTarget();
        const value = Math.max(20, Math.min(80, current + delta));
        runForTargets("setsize", value);
    }

    function resetBarSize() {
        runForTargets("setsize", 0);
    }

    function changeIconScale(delta) {
        let current = iconScaleValue();
        if (current < 0)
            current = 100;
        const value = Math.max(50, Math.min(200, current + delta));
        runForTargets("setscale", value);
    }

    function resetIconScale() {
        runForTargets("setscale", 100);
    }

    function resetTargets() {
        const names = targetNames();
        for (let i = 0; i < names.length; ++i)
            Quickshell.execDetached([quickshellScript, "reset-mon", names[i]]);
        scheduleStateRefresh();
    }

    Timer {
        id: stateRefreshQuick
        interval: 100
        repeat: false
        onTriggered: BarState.refresh()
    }

    Timer {
        id: stateRefreshFollowup
        interval: 350
        repeat: false
        onTriggered: BarState.refresh()
    }

    IpcHandler {
        target: "barsettings"
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        function toggle(): void { root.toggle(); }
    }

    FloatingWindow {
        id: settingsWindow
        visible: false
        title: "Awtarchy Bar Settings"
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: 520
        implicitHeight: 560
        minimumSize: Qt.size(520, 560)
        maximumSize: Qt.size(520, 560)

        Rectangle {
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.subtleActive
            radius: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                Text {
                    Layout.fillWidth: true
                    text: "Bar Settings"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "ALT + left-drag the bar toward top, bottom, left, or right to move it."
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        width: allText.implicitWidth + 22
                        height: 32
                        color: root.targetAll ? Theme.focus : Theme.active
                        border.width: 0
                        Text { id: allText; anchors.centerIn: parent; text: "All displays"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectAll() }
                    }

                    Repeater {
                        model: Quickshell.screens
                        delegate: Rectangle {
                            required property var modelData
                            width: monitorText.implicitWidth + 22
                            height: 32
                            color: !root.targetAll && root.targetMonitorName === modelData.name ? Theme.focus : Theme.active
                            border.width: 0
                            Text { id: monitorText; anchors.centerIn: parent; text: modelData.name; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectMonitor(modelData.name) }
                        }
                    }
                }

                Text {
                    text: "Position"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: ["top", "bottom", "left", "right"]
                        delegate: Rectangle {
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            color: root.positionLabel() === modelData ? Theme.focus : Theme.active
                            border.width: 0
                            Text { anchors.centerIn: parent; text: modelData.charAt(0).toUpperCase() + modelData.slice(1); color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setPosition(modelData) }
                        }
                    }
                }

                Text {
                    text: "Visibility"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        color: root.enabledLabel() === "visible" ? Theme.focus : Theme.active
                        border.width: 0
                        Text { anchors.centerIn: parent; text: "Visible"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setVisible(true) }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        color: root.enabledLabel() === "hidden" ? Theme.focus : Theme.active
                        border.width: 0
                        Text { anchors.centerIn: parent; text: "Hidden"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setVisible(false) }
                    }
                }

                Text {
                    text: "Bar thickness"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 52; Layout.preferredHeight: 36; color: Theme.active
                        Text { anchors.centerIn: parent; text: "−"; color: Theme.foreground; font.pixelSize: 18 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.changeBarSize(-2) }
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            const value = root.barSizeValue();
                            return value < 0 ? "Mixed" : value === 0 ? "Default (" + root.defaultBarSizeForTarget() + " px)" : value + " px";
                        }
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    Rectangle {
                        Layout.preferredWidth: 52; Layout.preferredHeight: 36; color: Theme.active
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.foreground; font.pixelSize: 18 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.changeBarSize(2) }
                    }
                    Rectangle {
                        Layout.preferredWidth: 78; Layout.preferredHeight: 36; color: Theme.active
                        Text { anchors.centerIn: parent; text: "Default"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.resetBarSize() }
                    }
                }

                Text {
                    text: "Icon size"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 52; Layout.preferredHeight: 36; color: Theme.active
                        Text { anchors.centerIn: parent; text: "−"; color: Theme.foreground; font.pixelSize: 18 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.changeIconScale(-5) }
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            const value = root.iconScaleValue();
                            return value < 0 ? "Mixed" : value + "%";
                        }
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    Rectangle {
                        Layout.preferredWidth: 52; Layout.preferredHeight: 36; color: Theme.active
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.foreground; font.pixelSize: 18 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.changeIconScale(5) }
                    }
                    Rectangle {
                        Layout.preferredWidth: 78; Layout.preferredHeight: 36; color: Theme.active
                        Text { anchors.centerIn: parent; text: "100%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.resetIconScale() }
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        color: Theme.active
                        Text { anchors.centerIn: parent; text: "Reset selected"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.resetTargets() }
                    }

                    Rectangle {
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 40
                        color: Theme.focus
                        Text { anchors.centerIn: parent; text: "Close"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
                    }
                }
            }
        }
    }
}
