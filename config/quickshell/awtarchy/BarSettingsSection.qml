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
    property string message: ""
    property real displayScale: 1
    property int monitorPixelWidth: 0
    property int monitorPixelHeight: 0
    property real pendingDisplayScale: 1
    property string displayScaleError: ""
    property bool customScaleOpen: false
    property string customScaleText: "1"

    signal themePickerRequested()

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string managerScript: configHome + "/hypr/scripts/quickshell.sh"
    readonly property string displayScaleScript: configHome + "/hypr/scripts/quickshell_display_scale.sh"
    readonly property var displayScalePresets: [1, 1.25, 1.5, 2]

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

    function rawModuleVisible(name, module) {
        if (module === "cpu")
            return BarState.cpuUsageVisibleFor(name);
        if (module === "temperature")
            return BarState.cpuTempVisibleFor(name);
        if (module === "memory")
            return BarState.memoryUsageVisibleFor(name);
        return true;
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

    function moduleVisibilityActive(module) {
        return commonValue(name => rawModuleVisible(name, module)) === true;
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

    function resetAppearance() {
        const targets = resolvedTargets();
        if (targets.length === 0)
            return;
        const next = commandQueue.slice();
        for (const target of targets) {
            next.push([managerScript, "setsize", target, "0"]);
            next.push([managerScript, "setscale", target, "100"]);
            next.push([managerScript, "settextscale", target, "100"]);
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

    function displayScaleLabel(value) {
        const scale = Number(value);
        if (!Number.isFinite(scale))
            return "";
        return String(Math.round(scale * 1000) / 1000);
    }

    function displayScaleIsPreset(value) {
        const scale = Number(value);
        return displayScalePresets.some(preset => Math.abs(Number(preset) - scale) < 0.001);
    }

    function displayScaleValid(value) {
        const scale = Number(value);
        const width = Number(monitorPixelWidth);
        const height = Number(monitorPixelHeight);
        if (!Number.isFinite(scale) || scale < 1 || scale > 4 || width <= 0 || height <= 0)
            return false;
        const logicalWidth = width / scale;
        const logicalHeight = height / scale;
        return Math.abs(logicalWidth - Math.round(logicalWidth)) < 0.0001
            && Math.abs(logicalHeight - Math.round(logicalHeight)) < 0.0001;
    }

    function toggleCustomDisplayScale() {
        customScaleOpen = !customScaleOpen;
        if (customScaleOpen)
            customScaleText = displayScaleLabel(displayScale);
    }

    function applyCustomDisplayScale() {
        const scale = Number(String(customScaleText || "").trim());
        if (!Number.isFinite(scale) || scale < 1 || scale > 4) {
            message = "Custom display scale must be between 1 and 4";
            return;
        }
        if (!displayScaleValid(scale)) {
            message = "Display scale " + displayScaleLabel(scale) + " is invalid for "
                + monitorPixelWidth + "×" + monitorPixelHeight;
            return;
        }
        setDisplayScale(scale);
        customScaleOpen = false;
    }

    function refreshDisplayScale() {
        if (!active || monitorName.length === 0 || scaleStatusRunner.running || scaleWriter.running)
            return;
        scaleStatusRunner.exec(["bash", root.displayScaleScript, "status", root.monitorName]);
    }

    function setDisplayScale(value) {
        const scale = Number(value);
        if (monitorName.length === 0 || scaleWriter.running || !displayScaleValid(scale)
                || Math.abs(displayScale - scale) < 0.001)
            return;
        pendingDisplayScale = scale;
        displayScaleError = "";
        message = "Display scale " + displayScaleLabel(scale) + " · " + monitorName;
        scaleWriter.exec(["bash", root.displayScaleScript, "set", root.monitorName, String(scale)]);
    }

    onMonitorNameChanged: {
        customScaleOpen = false;
        refreshDisplayScale();
    }
    onActiveChanged: {
        if (active)
            refreshDisplayScale();
    }

    Process {
        id: writer
        onExited: {
            BarState.refresh();
            root.runNextCommand();
        }
    }

    Process {
        id: scaleStatusRunner
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text.trim());
                    root.displayScale = Number(status.scale || 1);
                    root.monitorPixelWidth = Number(status.width || 0);
                    root.monitorPixelHeight = Number(status.height || 0);
                } catch (error) {
                    root.monitorPixelWidth = 0;
                    root.monitorPixelHeight = 0;
                }
            }
        }
    }

    Process {
        id: scaleWriter
        stderr: StdioCollector {
            onStreamFinished: root.displayScaleError = text.trim()
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.displayScale = root.pendingDisplayScale;
                root.message = "Display scale " + root.displayScaleLabel(root.displayScale)
                    + " · " + root.monitorName;
                root.refreshDisplayScale();
                return;
            }
            const errorText = root.displayScaleError.length > 0
                ? root.displayScaleError.split("\n")[0]
                : "Display scale change failed";
            root.message = errorText;
            root.refreshDisplayScale();
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

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    text: "Bar Appearance"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                SettingsButton {
                    label: "‹"
                    textSize: 11
                    onClicked: root.cycleTarget(-1)
                }

                Text {
                    Layout.preferredWidth: 180
                    text: root.targetLabel()
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                SettingsButton {
                    label: "›"
                    textSize: 11
                    onClicked: root.cycleTarget(1)
                }

                SettingsButton {
                    label: "Themes"
                    textSize: 9
                    onClicked: root.themePickerRequested()
                }

                SettingsButton {
                    label: "Reset"
                    textSize: 9
                    onClicked: root.resetAppearance()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Display scale"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Repeater {
                    model: root.displayScalePresets
                    delegate: SettingsButton {
                        required property var modelData

                        label: root.displayScaleLabel(Number(modelData))
                        textSize: 9
                        horizontalPadding: 10
                        active: Math.abs(root.displayScale - Number(modelData)) < 0.001
                        available: !scaleWriter.running
                            && root.displayScaleValid(Number(modelData))
                        onClicked: root.setDisplayScale(Number(modelData))
                    }
                }

                SettingsButton {
                    label: "Custom"
                    textSize: 9
                    horizontalPadding: 10
                    active: root.customScaleOpen || !root.displayScaleIsPreset(root.displayScale)
                    available: !scaleWriter.running && root.monitorPixelWidth > 0
                        && root.monitorPixelHeight > 0
                    onClicked: root.toggleCustomDisplayScale()
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.monitorName.length > 0 ? "Focused · " + root.monitorName : "Focused display"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 120
                }
            }

            RowLayout {
                visible: root.customScaleOpen
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 26 : 0
                spacing: 5

                Text {
                    Layout.preferredWidth: 78
                    text: "Custom scale"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Rectangle {
                    Layout.preferredWidth: 82
                    Layout.preferredHeight: 24
                    color: Theme.popupBackground
                    border.width: 1
                    border.color: customScaleInput.activeFocus ? Theme.focus : Theme.muted
                    radius: 0

                    TextInput {
                        id: customScaleInput
                        anchors.fill: parent
                        anchors.margins: 5
                        text: root.customScaleText
                        color: Theme.foreground
                        selectionColor: Theme.focus
                        selectedTextColor: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        selectByMouse: true
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        onTextEdited: root.customScaleText = text
                        Keys.onReturnPressed: root.applyCustomDisplayScale()
                    }
                }

                SettingsButton {
                    label: "Apply"
                    textSize: 9
                    available: !scaleWriter.running && root.monitorName.length > 0
                    onClicked: root.applyCustomDisplayScale()
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        const scale = Number(root.customScaleText);
                        if (root.displayScaleValid(scale))
                            return Math.round(root.monitorPixelWidth / scale) + "×"
                                + Math.round(root.monitorPixelHeight / scale) + " logical";
                        return "1–4 · whole logical pixels only";
                    }
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    elide: Text.ElideRight
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
        }
    }
}
