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

    function resetAppearance() {
        const targets = resolvedTargets();
        if (targets.length === 0)
            return;
        const next = commandQueue.slice();
        for (const target of targets) {
            next.push([managerScript, "setsize", target, "0"]);
            next.push([managerScript, "setscale", target, "100"]);
            next.push([managerScript, "settextscale", target, "100"]);
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

    Process {
        id: writer
        onExited: {
            BarState.refresh();
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
        }
    }
}
