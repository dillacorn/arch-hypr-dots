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
    property var pendingCommands: []
    property var optimisticBarSizes: ({})
    property var optimisticIconScales: ({})

    function focusedScreen() {
        const focusedName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === focusedName);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function targetNames() {
        if (targetAll)
            return Quickshell.screens.map(screen => screen.name);
        return targetMonitorName.length > 0 ? [targetMonitorName] : [];
    }

    function selectMonitor(name) {
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
        Qt.callLater(() => settingsPanel.forceActiveFocus());
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

    function queueCommand(args) {
        const queue = pendingCommands.slice();
        queue.push(args);
        pendingCommands = queue;
        runNextCommand();
    }

    function runNextCommand() {
        if (stateWriter.running || pendingCommands.length === 0)
            return;

        const args = pendingCommands[0];
        pendingCommands = pendingCommands.slice(1);
        stateWriter.exec(args);
    }

    function commonValue(getter) {
        const names = targetNames();
        if (names.length === 0)
            return "";

        const first = getter(names[0]);
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

    function rawBarSize(name) {
        if (optimisticBarSizes[name] !== undefined)
            return Number(optimisticBarSizes[name]);
        return Number(BarState.monitorState(name).bar_size || 0);
    }

    function defaultBarSize(name) {
        const position = BarState.positionFor(name);
        return position === "left" || position === "right" ? 36 : 28;
    }

    function barSizeValue() {
        const names = targetNames();
        if (names.length === 0)
            return 0;

        const first = rawBarSize(names[0]);
        for (let i = 1; i < names.length; ++i) {
            if (rawBarSize(names[i]) !== first)
                return -1;
        }
        return first;
    }

    function defaultBarSizeForTarget() {
        const names = targetNames();
        if (names.length === 0)
            return 28;

        const first = defaultBarSize(names[0]);
        for (let i = 1; i < names.length; ++i) {
            if (defaultBarSize(names[i]) !== first)
                return 28;
        }
        return first;
    }

    function rawIconScale(name) {
        if (optimisticIconScales[name] !== undefined)
            return Number(optimisticIconScales[name]);
        const value = BarState.monitorState(name).icon_scale;
        return value === undefined ? 100 : Number(value);
    }

    function iconScaleValue() {
        const names = targetNames();
        if (names.length === 0)
            return 100;

        const first = rawIconScale(names[0]);
        for (let i = 1; i < names.length; ++i) {
            if (rawIconScale(names[i]) !== first)
                return -1;
        }
        return first;
    }

    function setPosition(position) {
        const names = targetNames();
        for (let i = 0; i < names.length; ++i) {
            BarState.setLivePosition(names[i], position);
            queueCommand([quickshellScript, "setpos", names[i], position]);
        }
    }

    function setVisible(visible) {
        const names = targetNames();
        for (let i = 0; i < names.length; ++i) {
            BarState.setLiveEnabled(names[i], visible);
            queueCommand([quickshellScript, "setenabled", names[i], visible ? "true" : "false"]);
        }
    }

    function changeBarSize(delta) {
        const names = targetNames();
        const nextOptimistic = Object.assign({}, optimisticBarSizes);

        for (let i = 0; i < names.length; ++i) {
            const name = names[i];
            let current = rawBarSize(name);
            if (current === 0)
                current = defaultBarSize(name);
            const value = Math.max(20, Math.min(80, current + delta));
            nextOptimistic[name] = value;
            BarState.setLiveBarSize(name, value);
            queueCommand([quickshellScript, "setsize", name, String(value)]);
        }

        optimisticBarSizes = nextOptimistic;
    }

    function resetBarSize() {
        const names = targetNames();
        const nextOptimistic = Object.assign({}, optimisticBarSizes);
        for (let i = 0; i < names.length; ++i) {
            nextOptimistic[names[i]] = 0;
            BarState.setLiveBarSize(names[i], 0);
            queueCommand([quickshellScript, "setsize", names[i], "0"]);
        }
        optimisticBarSizes = nextOptimistic;
    }

    function changeIconScale(delta) {
        const names = targetNames();
        const nextOptimistic = Object.assign({}, optimisticIconScales);

        for (let i = 0; i < names.length; ++i) {
            const name = names[i];
            const value = Math.max(50, Math.min(200, rawIconScale(name) + delta));
            nextOptimistic[name] = value;
            BarState.setLiveIconScale(name, value);
            queueCommand([quickshellScript, "setscale", name, String(value)]);
        }

        optimisticIconScales = nextOptimistic;
    }

    function resetIconScale() {
        const names = targetNames();
        const nextOptimistic = Object.assign({}, optimisticIconScales);
        for (let i = 0; i < names.length; ++i) {
            nextOptimistic[names[i]] = 100;
            BarState.setLiveIconScale(names[i], 100);
            queueCommand([quickshellScript, "setscale", names[i], "100"]);
        }
        optimisticIconScales = nextOptimistic;
    }

    function resetTargets() {
        const names = targetNames();
        const nextSizes = Object.assign({}, optimisticBarSizes);
        const nextScales = Object.assign({}, optimisticIconScales);

        for (let i = 0; i < names.length; ++i) {
            nextSizes[names[i]] = 0;
            nextScales[names[i]] = 100;
            BarState.setLivePosition(names[i], "top");
            BarState.setLiveEnabled(names[i], true);
            BarState.setLiveBarSize(names[i], 0);
            BarState.setLiveIconScale(names[i], 100);
            queueCommand([quickshellScript, "reset-mon", names[i]]);
        }

        optimisticBarSizes = nextSizes;
        optimisticIconScales = nextScales;
    }

    Process {
        id: stateWriter
        onExited: {
            BarState.refresh();
            stateRefreshFollowup.restart();
            root.runNextCommand();
        }
    }

    Timer {
        id: stateRefreshFollowup
        interval: 100
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

        onClosed: root.close()
        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => settingsPanel.forceActiveFocus());
        }

        Rectangle {
            id: settingsPanel
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 0
            radius: 0
            focus: settingsWindow.visible

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }

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
                    text: "ALT + left-drag the actual bar toward top, bottom, left, or right to move it."
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
