pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string monitorName: ""
    property var monitorNames: []
    property bool active: false
    property string targetKey: "current"
    property var commandQueue: []
    property var activeCommand: []
    property string message: ""
    property int barTransparencyHoverPercent: -1
    property bool barTransparencyDragging: false
    property var barTransparencyDragTargets: []
    property bool copyOpen: false
    property var copyTargets: ({})
    property int copySelectionRevision: 0

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string managerScript: configHome + "/hypr/scripts/quickshell.sh"

    implicitHeight: active ? controls.implicitHeight + 12 : 0

    function uniqueMonitorNames() {
        const values = [];
        for (const value of monitorNames || []) {
            const name = String(value || "");
            if (name.length > 0 && values.indexOf(name) < 0)
                values.push(name);
        }
        if (monitorName.length > 0 && values.indexOf(monitorName) < 0)
            values.unshift(monitorName);
        return values;
    }

    function targetEntries() {
        const entries = [
            { key: "current", label: monitorName.length > 0
                ? "This display · " + monitorName : "This display" },
            { key: "all", label: "All displays" }
        ];
        for (const name of uniqueMonitorNames()) {
            if (name !== monitorName)
                entries.push({ key: name, label: name });
        }
        return entries;
    }

    function targetLabel() {
        for (const entry of targetEntries()) {
            if (entry.key === targetKey)
                return entry.label;
        }
        targetKey = "current";
        return monitorName.length > 0 ? "This display · " + monitorName : "This display";
    }

    function cycleTarget(delta) {
        const entries = targetEntries();
        if (entries.length === 0)
            return;
        let index = entries.findIndex(entry => entry.key === targetKey);
        if (index < 0)
            index = 0;
        index = (index + delta + entries.length) % entries.length;
        targetKey = entries[index].key;
        message = "Target: " + entries[index].label;
    }

    function resolvedTargets() {
        if (targetKey === "all")
            return uniqueMonitorNames();
        if (targetKey === "current")
            return monitorName.length > 0 ? [monitorName] : [];
        return uniqueMonitorNames().indexOf(targetKey) >= 0 ? [targetKey] : [];
    }

    function copyMonitorNames() {
        return uniqueMonitorNames().filter(name => name !== monitorName);
    }

    function copyTargetSelected(name) {
        const dependency = copySelectionRevision;
        return copyTargets[name] === true;
    }

    function selectedCopyTargets() {
        return copyMonitorNames().filter(name => copyTargetSelected(name));
    }

    function setCopyTargetSelected(name, selected) {
        const next = Object.assign({}, copyTargets);
        if (selected)
            next[name] = true;
        else
            delete next[name];
        copyTargets = next;
        copySelectionRevision++;
    }

    function allCopyTargetsSelected() {
        const names = copyMonitorNames();
        return names.length > 0 && names.every(name => copyTargetSelected(name));
    }

    function toggleAllCopyTargets() {
        const next = {};
        if (!allCopyTargetsSelected()) {
            for (const name of copyMonitorNames())
                next[name] = true;
        }
        copyTargets = next;
        copySelectionRevision++;
    }

    function resetCopySelection() {
        copyTargets = ({});
        copySelectionRevision++;
        copyOpen = false;
    }

    function resetTransientState() {
        resetCopySelection();
        targetKey = "current";
        message = "";
        cancelTransparencyDrag();
    }

    function copyBarSettings() {
        const targets = selectedCopyTargets();
        if (monitorName.length === 0 || targets.length === 0)
            return;
        const next = commandQueue.slice();
        next.push([managerScript, "copy-bar-settings", monitorName, ...targets]);
        commandQueue = next;
        message = "Copied bar settings to " + targets.length
            + (targets.length === 1 ? " display" : " displays");
        resetCopySelection();
        runNextCommand();
    }

    function rawBarSize(name) {
        const state = BarState.monitorState(name) || ({});
        const value = Number(state.bar_size === undefined ? 0 : state.bar_size);
        if (!Number.isFinite(value) || (value !== 0 && (value < 20 || value > 80)))
            return 0;
        return Math.round(value);
    }

    function rawIconScale(name) {
        const state = BarState.monitorState(name) || ({});
        const value = Number(state.icon_scale === undefined ? 100 : state.icon_scale);
        return Number.isFinite(value) ? Math.max(50, Math.min(200, Math.round(value))) : 100;
    }

    function rawTextScale(name) {
        const state = BarState.monitorState(name) || ({});
        const value = Number(state.text_scale === undefined ? 100 : state.text_scale);
        return Number.isFinite(value) ? Math.max(50, Math.min(200, Math.round(value))) : 100;
    }

    function rawBarTransparency(name) {
        const value = Number(BarState.barTransparencyFor(name));
        return Number.isFinite(value) ? Math.max(0, Math.min(100, Math.round(value))) : 0;
    }

    function rawModuleVisible(name, module) {
        const state = BarState.monitorState(name) || ({});
        if (module === "cpu")
            return state.show_cpu !== false;
        if (module === "temperature")
            return state.show_temp !== false;
        if (module === "memory")
            return state.show_memory !== false;
        return true;
    }

    function rawIconOption(name, option) {
        const state = BarState.monitorState(name) || ({});
        if (option === "runningApps")
            return state.show_tasks !== false;
        if (option === "themeRunningApps")
            return state.theme_task_icons === true;
        if (option === "themeTray")
            return state.theme_tray_icons === true;
        return false;
    }

    function moduleCommand(module) {
        if (module === "cpu")
            return "setshowcpu";
        if (module === "temperature")
            return "setshowtemp";
        if (module === "memory")
            return "setshowmemory";
        return "";
    }

    function iconOptionCommand(option) {
        if (option === "runningApps")
            return "setshowtasks";
        if (option === "themeRunningApps")
            return "setthemetaskicons";
        if (option === "themeTray")
            return "setthemetrayicons";
        return "";
    }

    function commonValue(reader) {
        const targets = resolvedTargets();
        if (targets.length === 0)
            return null;
        let value = reader(targets[0]);
        for (let i = 1; i < targets.length; ++i) {
            if (reader(targets[i]) !== value)
                return null;
        }
        return value;
    }

    function effectiveBarSize(name) {
        const position = BarState.positionFor(name);
        const vertical = position === "left" || position === "right";
        return BarState.barSizeFor(name, vertical);
    }

    function thicknessText() {
        const value = commonValue(rawBarSize);
        if (value === null)
            return "Mixed";
        return value === 0 ? "Auto" : value + " px";
    }

    function iconText() {
        const value = commonValue(rawIconScale);
        return value === null ? "Mixed" : value + "%";
    }

    function textText() {
        const value = commonValue(rawTextScale);
        return value === null ? "Mixed" : value + "%";
    }

    function transparencyText() {
        const value = commonValue(rawBarTransparency);
        return value === null ? "Mixed" : value + "%";
    }

    function transparencyPercent() {
        const value = commonValue(rawBarTransparency);
        return value === null ? -1 : value;
    }

    function moduleVisibilityActive(module) {
        return commonValue(name => rawModuleVisible(name, module)) === true;
    }

    function iconOptionActive(option) {
        return commonValue(name => rawIconOption(name, option)) === true;
    }

    function baseThickness() {
        const common = commonValue(rawBarSize);
        if (common !== null && common !== 0)
            return common;
        const targets = resolvedTargets();
        const name = targets.length > 0 ? targets[0] : monitorName;
        return name.length > 0 ? effectiveBarSize(name) : 28;
    }

    function baseIconScale() {
        const common = commonValue(rawIconScale);
        if (common !== null)
            return common;
        const targets = resolvedTargets();
        return targets.length > 0 ? rawIconScale(targets[0]) : 100;
    }

    function baseTextScale() {
        const common = commonValue(rawTextScale);
        if (common !== null)
            return common;
        const targets = resolvedTargets();
        return targets.length > 0 ? rawTextScale(targets[0]) : 100;
    }

    function baseBarTransparency() {
        const common = commonValue(rawBarTransparency);
        if (common !== null)
            return common;
        const targets = resolvedTargets();
        return targets.length > 0 ? rawBarTransparency(targets[0]) : 0;
    }

    function enqueue(command, value) {
        const targets = resolvedTargets();
        if (targets.length === 0)
            return;
        const next = commandQueue.slice();
        for (const target of targets)
            next.push([managerScript, command, target, String(value)]);
        commandQueue = next;
        runNextCommand();
    }

    function toggleModuleVisibility(module, label) {
        const command = moduleCommand(module);
        const targets = resolvedTargets();
        if (command.length === 0 || targets.length === 0)
            return;
        const current = commonValue(name => rawModuleVisible(name, module));
        const nextValue = current === true ? false : true;
        const next = commandQueue.slice();
        for (const target of targets)
            next.push([managerScript, command, target, nextValue ? "true" : "false"]);
        commandQueue = next;
        message = label + " " + (nextValue ? "visible" : "hidden");
        runNextCommand();
    }

    function toggleIconOption(option, enabledLabel, disabledLabel) {
        const command = iconOptionCommand(option);
        const targets = resolvedTargets();
        if (command.length === 0 || targets.length === 0)
            return;
        const current = commonValue(name => rawIconOption(name, option));
        const nextValue = current === true ? false : true;
        const next = commandQueue.slice();
        for (const target of targets)
            next.push([managerScript, command, target, nextValue ? "true" : "false"]);
        commandQueue = next;
        message = nextValue ? enabledLabel : disabledLabel;
        runNextCommand();
    }

    function resetAppearance() {
        const targets = resolvedTargets();
        if (targets.length === 0)
            return;
        const next = commandQueue.slice();
        for (const target of targets) {
            next.push([managerScript, "setsize", target, "0"]);
            next.push([managerScript, "setscale", target, "100"]);
            next.push([managerScript, "settextscale", target, "100"]);
            next.push([managerScript, "settransparency", target, "0"]);
            next.push([managerScript, "setshowtasks", target, "true"]);
            next.push([managerScript, "setthemetaskicons", target, "false"]);
            next.push([managerScript, "setthemetrayicons", target, "false"]);
            next.push([managerScript, "setshowcpu", target, "true"]);
            next.push([managerScript, "setshowtemp", target, "true"]);
            next.push([managerScript, "setshowmemory", target, "true"]);
        }
        commandQueue = next;
        message = "Resetting bar appearance…";
        runNextCommand();
    }

    function runNextCommand() {
        if (writer.running || commandQueue.length === 0)
            return;
        const next = commandQueue[0];
        commandQueue = commandQueue.slice(1);
        activeCommand = next;
        writer.exec(next);
    }

    function adjustThickness(delta) {
        const next = Math.max(20, Math.min(80, baseThickness() + delta));
        message = "Bar thickness " + next + " px";
        enqueue("setsize", next);
    }

    function adjustIconScale(delta) {
        const next = Math.max(50, Math.min(200, baseIconScale() + delta));
        message = "Bar icons " + next + "%";
        enqueue("setscale", next);
    }

    function adjustTextScale(delta) {
        const next = Math.max(50, Math.min(200, baseTextScale() + delta));
        message = "Bar text " + next + "%";
        enqueue("settextscale", next);
    }

    function clampTransparencyPercent(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return -1;
        return Math.max(0, Math.min(100, Math.round(numeric)));
    }

    function previewTransparencyPercent(value) {
        const next = clampTransparencyPercent(value);
        if (next < 0 || !barTransparencyDragging)
            return;
        barTransparencyHoverPercent = next;
        for (const target of barTransparencyDragTargets)
            BarState.setLiveBarTransparency(target, next);
    }

    function beginTransparencyDrag(value) {
        const targets = resolvedTargets();
        if (targets.length === 0)
            return;
        barTransparencyDragTargets = targets.slice();
        barTransparencyDragging = true;
        previewTransparencyPercent(value);
    }

    function commitTransparencyDrag() {
        if (!barTransparencyDragging)
            return;
        const value = clampTransparencyPercent(barTransparencyHoverPercent);
        const targets = barTransparencyDragTargets.slice();
        barTransparencyDragging = false;
        barTransparencyDragTargets = [];
        if (value < 0 || targets.length === 0)
            return;
        const next = commandQueue.slice();
        for (const target of targets)
            next.push([managerScript, "settransparency", target, String(value)]);
        commandQueue = next;
        message = "Bar transparency " + value + "%";
        runNextCommand();
    }

    function cancelTransparencyDrag() {
        for (const target of barTransparencyDragTargets)
            BarState.clearLiveBarTransparency(target);
        barTransparencyDragging = false;
        barTransparencyDragTargets = [];
        barTransparencyHoverPercent = -1;
    }

    function setTransparencyPercent(value) {
        const next = clampTransparencyPercent(value);
        if (next < 0)
            return;
        message = "Bar transparency " + next + "%";
        enqueue("settransparency", next);
    }

    function adjustTransparency(delta) {
        setTransparencyPercent(baseBarTransparency() + delta);
    }

    Process {
        id: writer
        onExited: {
            const completed = root.activeCommand;
            root.activeCommand = [];
            BarState.refresh();
            if (completed.length >= 3 && completed[1] === "settransparency")
                Qt.callLater(() => BarState.clearLiveBarTransparency(String(completed[2])));
            root.runNextCommand();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.active
        border.width: 1
        border.color: Theme.focus

        ColumnLayout {
            id: controls
            anchors.fill: parent
            anchors.margins: 6
            spacing: 3

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 26

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    SettingsButton {
                        label: "‹"
                        textSize: 11
                        onClicked: root.cycleTarget(-1)
                    }

                    Text {
                        width: 240
                        height: 24
                        text: "Apply to: " + root.targetLabel()
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                    }

                    SettingsButton {
                        label: "›"
                        textSize: 11
                        onClicked: root.cycleTarget(1)
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    SettingsButton {
                        label: "Reset"
                        textSize: 9
                        onClicked: root.resetAppearance()
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Thickness"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
                SettingsButton { label: "−"; textSize: 11; onClicked: root.adjustThickness(-2) }
                Text {
                    Layout.preferredWidth: 72
                    text: root.thicknessText()
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                }
                SettingsButton { label: "+"; textSize: 11; onClicked: root.adjustThickness(2) }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Transparency"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                SettingsButton {
                    label: "−5"
                    textSize: 9
                    onClicked: root.adjustTransparency(-5)
                }

                Rectangle {
                    id: barTransparencyTrack
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    color: Theme.popupBackground
                    border.width: 0

                    Rectangle {
                        width: root.transparencyPercent() >= 0
                            ? parent.width * root.transparencyPercent() / 100 : 0
                        height: parent.height
                        color: Theme.focus
                    }

                    Rectangle {
                        visible: root.barTransparencyHoverPercent >= 0
                        width: 46
                        height: 21
                        x: Math.max(0, Math.min(parent.width - width,
                            parent.width * root.barTransparencyHoverPercent / 100 - width / 2))
                        y: -25
                        color: Theme.background
                        border.width: 1
                        border.color: Theme.focus
                        z: 4

                        Text {
                            anchors.centerIn: parent
                            text: root.barTransparencyHoverPercent + "%"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: mouse => {
                            root.barTransparencyHoverPercent = Math.max(0,
                                Math.min(100, Math.round(mouse.x * 100 / width)));
                            if (pressed)
                                root.previewTransparencyPercent(root.barTransparencyHoverPercent);
                        }
                        onExited: {
                            if (!pressed)
                                root.barTransparencyHoverPercent = -1;
                        }
                        onPressed: mouse => root.beginTransparencyDrag(mouse.x * 100 / width)
                        onReleased: root.commitTransparencyDrag()
                        onCanceled: root.cancelTransparencyDrag()
                    }
                }

                SettingsButton {
                    label: "+5"
                    textSize: 9
                    onClicked: root.adjustTransparency(5)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Text size"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
                SettingsButton { label: "−"; textSize: 11; onClicked: root.adjustTextScale(-5) }
                Text {
                    Layout.preferredWidth: 72
                    text: root.textText()
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                }
                SettingsButton { label: "+"; textSize: 11; onClicked: root.adjustTextScale(5) }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Icon size"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
                SettingsButton { label: "−"; textSize: 11; onClicked: root.adjustIconScale(-5) }
                Text {
                    Layout.preferredWidth: 72
                    text: root.iconText()
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                }
                SettingsButton { label: "+"; textSize: 11; onClicked: root.adjustIconScale(5) }

                Text {
                    Layout.fillWidth: true
                    visible: root.message.length > 0
                    text: root.message
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Running apps"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                SettingsButton {
                    label: "Visible"
                    textSize: 9
                    horizontalPadding: 12
                    active: root.iconOptionActive("runningApps")
                    onClicked: root.toggleIconOption("runningApps", "Running apps visible", "Running apps hidden")
                }

                SettingsButton {
                    label: "Theme color"
                    textSize: 9
                    horizontalPadding: 12
                    active: root.iconOptionActive("themeRunningApps")
                    onClicked: root.toggleIconOption("themeRunningApps", "Running app icons use theme color", "Running app icons use original colors")
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Tray icons"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                SettingsButton {
                    label: "Theme color"
                    textSize: 9
                    horizontalPadding: 12
                    active: root.iconOptionActive("themeTray")
                    onClicked: root.toggleIconOption("themeTray", "Tray icons use theme color", "Tray icons use original colors")
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "System stats"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                SettingsButton {
                    label: "CPU"
                    textSize: 9
                    horizontalPadding: 12
                    active: root.moduleVisibilityActive("cpu")
                    onClicked: root.toggleModuleVisibility("cpu", "CPU usage")
                }

                SettingsButton {
                    label: "Temp"
                    textSize: 9
                    horizontalPadding: 12
                    active: root.moduleVisibilityActive("temperature")
                    onClicked: root.toggleModuleVisibility("temperature", "CPU temperature")
                }

                SettingsButton {
                    label: "RAM"
                    textSize: 9
                    horizontalPadding: 12
                    active: root.moduleVisibilityActive("memory")
                    onClicked: root.toggleModuleVisibility("memory", "RAM usage")
                }

                Item { Layout.fillWidth: true }
            }


            RowLayout {
                visible: !root.copyOpen
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 26 : 0
                spacing: 5

                SettingsButton {
                    label: "Copy Bar Settings…"
                    textSize: 9
                    horizontalPadding: 12
                    available: root.copyMonitorNames().length > 0
                    onClicked: {
                        root.copyTargets = ({});
                        root.copySelectionRevision++;
                        root.copyOpen = true;
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Copies bar appearance only · display scale stays per display"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                visible: root.copyOpen
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 26 : 0
                spacing: 5

                SettingsButton {
                    label: "Back"
                    textSize: 9
                    onClicked: root.resetCopySelection()
                }

                Repeater {
                    model: root.copyMonitorNames()
                    delegate: SettingsButton {
                        required property string modelData
                        label: modelData
                        textSize: 9
                        horizontalPadding: 10
                        active: root.copyTargetSelected(modelData)
                        onClicked: root.setCopyTargetSelected(modelData,
                            !root.copyTargetSelected(modelData))
                    }
                }

                SettingsButton {
                    label: root.allCopyTargetsSelected() ? "Clear" : "All"
                    textSize: 9
                    onClicked: root.toggleAllCopyTargets()
                }

                Item { Layout.fillWidth: true }

                SettingsButton {
                    label: "Copy"
                    textSize: 9
                    available: root.selectedCopyTargets().length > 0
                    onClicked: root.copyBarSettings()
                }
            }
        }
    }
}