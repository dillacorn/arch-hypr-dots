pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: root

    property var identityCommandQueue: []
    property string identityError: ""
    property string message: ""
    property string workspaceCopyFeedback: ""
    property string launcherCopyFeedback: ""
    property string copiedWorkspaceKey: ""
    property string copiedWorkspacePack: ""
    property string copiedLauncherValue: ""
    property string customWorkspaceText: BarState.workspaceCustomLabel()
    property string customLauncherText: BarState.launcherIcon()

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string identityStateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"

    spacing: 3

    function workspaceIconStyleLabel() {
        const style = BarState.workspaceIconStyle();
        for (const preset of BarState.workspaceIconStylePresets) {
            if (preset.key === style)
                return preset.label;
        }
        return "Awtarchy";
    }

    function copyText(text) {
        if (!text || text.length === 0)
            return false;
        Quickshell.execDetached(["wl-copy", text]);
        return true;
    }

    function copyWorkspaceSymbol(text, key) {
        if (!copyText(text))
            return;
        copiedWorkspaceKey = key;
        copiedWorkspacePack = "";
        workspaceCopyFeedback = "Copied · " + text;
        workspaceCopyFeedbackTimer.restart();
    }

    function copyWorkspacePack(pack) {
        if (!pack || !Array.isArray(pack.symbols) || pack.symbols.length === 0)
            return;
        const text = pack.symbols.join(" ");
        if (!copyText(text))
            return;
        copiedWorkspaceKey = "";
        copiedWorkspacePack = String(pack.key || "");
        workspaceCopyFeedback = "Copied all · " + pack.symbols.length + " symbols";
        workspaceCopyFeedbackTimer.restart();
    }

    function copyLauncherIcon(value) {
        const text = String(value || "");
        if (!copyText(text))
            return;
        copiedLauncherValue = text;
        launcherCopyFeedback = "Copied · " + text;
        launcherCopyFeedbackTimer.restart();
    }

    function enqueueIdentity(args, statusMessage) {
        const next = identityCommandQueue.slice();
        next.push({ args: args, message: statusMessage || "" });
        identityCommandQueue = next;
        runNextIdentityCommand();
    }

    function runNextIdentityCommand() {
        if (identityWriter.running || identityCommandQueue.length === 0)
            return;
        const next = identityCommandQueue[0];
        identityCommandQueue = identityCommandQueue.slice(1);
        identityError = "";
        message = next.message;
        identityWriter.exec([identityStateScript, ...next.args]);
    }

    function setWorkspaceNumbers(enabled) {
        enqueueIdentity(["set-workspace-numbers", enabled ? "on" : "off"],
            "Workspace numbers · " + (enabled ? "On" : "Off"));
    }

    function setWorkspaceIconStyle(style) {
        enqueueIdentity(["set-workspace-icon-style", style], "Workspace icons · " + style);
    }

    function applyWorkspaceCustomLabel() {
        if (!BarState.identityLabelValid(customWorkspaceText)) {
            message = "Custom workspace label must be 1–8 characters";
            return;
        }
        enqueueIdentity(["set-workspace-custom-label", customWorkspaceText],
            "Custom workspace symbol · " + customWorkspaceText);
        enqueueIdentity(["set-workspace-icon-style", "custom-symbol"],
            "Workspace icons · Custom");
    }

    function setWorkspaceOverride(workspaceId, value) {
        if (!BarState.identityLabelValid(value)) {
            message = "Workspace " + workspaceId + " label must be 1–8 characters";
            return;
        }
        enqueueIdentity(["set-workspace-override", String(workspaceId), value],
            "Workspace " + workspaceId + " · " + value);
    }

    function clearWorkspaceOverride(workspaceId) {
        enqueueIdentity(["clear-workspace-override", String(workspaceId)],
            "Workspace " + workspaceId + " override reset");
    }

    function setLauncherIcon(value) {
        if (!BarState.identityLabelValid(value)) {
            message = "Launcher icon must be 1–8 characters";
            return;
        }
        customLauncherText = value;
        enqueueIdentity(["set-launcher-icon", value], "Launcher icon · " + value);
    }

    function resetWorkspaceIcons() {
        customWorkspaceText = "";
        enqueueIdentity(["reset-workspace-icons"], "Workspace icons reset to Awtarchy");
    }

    function resetLauncherIcon() {
        customLauncherText = "";
        enqueueIdentity(["reset-launcher-icon"], "Launcher icon reset to Awtarchy");
    }

    function resetBarIcons() {
        customWorkspaceText = "";
        customLauncherText = "";
        enqueueIdentity(["reset-bar-icons"], "Bar icons reset to Awtarchy");
    }

    Timer {
        id: workspaceCopyFeedbackTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.workspaceCopyFeedback = "";
            root.copiedWorkspaceKey = "";
            root.copiedWorkspacePack = "";
        }
    }

    Timer {
        id: launcherCopyFeedbackTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.launcherCopyFeedback = "";
            root.copiedLauncherValue = "";
        }
    }

    Process {
        id: identityWriter
        stderr: StdioCollector {
            onStreamFinished: root.identityError = text.trim()
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                BarState.refresh();
            } else {
                root.message = root.identityError.length > 0
                    ? root.identityError.split("\n")[0]
                    : "Bar icon change failed";
            }
            root.runNextIdentityCommand();
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.muted
        opacity: 0.45
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        spacing: 5

        Text {
            text: "Numbers"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
        }

        Item { Layout.fillWidth: true }

        SettingsButton {
            label: "On"
            textSize: 9
            active: BarState.workspaceNumbersEnabled()
            onClicked: root.setWorkspaceNumbers(true)
        }

        SettingsButton {
            label: "Off"
            textSize: 9
            active: !BarState.workspaceNumbersEnabled()
            onClicked: root.setWorkspaceNumbers(false)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        spacing: 5

        Text {
            text: "Workspace icons"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
        }

        Text {
            visible: root.workspaceCopyFeedback.length > 0
            text: root.workspaceCopyFeedback
            color: Theme.focus
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "Global · " + root.workspaceIconStyleLabel()
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            model: BarState.workspaceIconStylePresets

            delegate: Rectangle {
                id: packRow
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: packRow.modelData.symbols.length > 0 ? 34 : 28
                color: BarState.workspaceIconStyle() === packRow.modelData.key
                    ? Theme.subtleActive : "transparent"
                border.width: 1
                border.color: BarState.workspaceIconStyle() === packRow.modelData.key
                    ? Theme.focus : Theme.muted
                radius: 0

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 4

                    SettingsButton {
                        Layout.preferredWidth: 88
                        label: packRow.modelData.label
                        textSize: 9
                        active: BarState.workspaceIconStyle() === packRow.modelData.key
                        onClicked: {
                            if (packRow.modelData.key === "custom-symbol"
                                    && !BarState.identityLabelValid(root.customWorkspaceText)) {
                                root.message = "Enter a custom workspace symbol below";
                                return;
                            }
                            root.setWorkspaceIconStyle(packRow.modelData.key);
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        visible: packRow.modelData.symbols.length > 0

                        Repeater {
                            model: packRow.modelData.symbols

                            delegate: Rectangle {
                                id: symbolCell
                                required property int index
                                required property var modelData
                                readonly property string copyKey: packRow.modelData.key + ":" + index

                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                color: root.copiedWorkspaceKey === symbolCell.copyKey
                                    ? Theme.subtleActive
                                    : (symbolMouse.containsMouse ? Theme.subtleHover : "transparent")
                                border.width: 1
                                border.color: root.copiedWorkspaceKey === symbolCell.copyKey
                                    ? Theme.focus : Theme.muted
                                radius: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: String(symbolCell.modelData)
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Math.max(11, packRow.modelData.glyphSize - 2)
                                }

                                MouseArea {
                                    id: symbolMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.copyWorkspaceSymbol(
                                        String(symbolCell.modelData), symbolCell.copyKey)
                                }
                            }
                        }
                    }

                    SettingsButton {
                        visible: packRow.modelData.symbols.length > 0
                        label: root.copiedWorkspacePack === packRow.modelData.key
                            ? "✓ Copied all" : " Copy all"
                        textSize: 9
                        horizontalPadding: 8
                        active: root.copiedWorkspacePack === packRow.modelData.key
                        onClicked: root.copyWorkspacePack(packRow.modelData)
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        spacing: 5

        Text {
            Layout.preferredWidth: 112
            text: "Custom symbol"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }

        Rectangle {
            Layout.preferredWidth: 120
            Layout.preferredHeight: 24
            color: Theme.popupBackground
            border.width: 1
            border.color: customWorkspaceInput.activeFocus ? Theme.focus : Theme.muted
            radius: 0

            TextInput {
                id: customWorkspaceInput
                anchors.fill: parent
                anchors.margins: 5
                text: root.customWorkspaceText
                color: Theme.foreground
                selectionColor: Theme.focus
                selectedTextColor: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                selectByMouse: true
                onTextEdited: root.customWorkspaceText = text
                Keys.onReturnPressed: root.applyWorkspaceCustomLabel()
            }
        }

        SettingsButton {
            label: "Apply"
            textSize: 9
            available: BarState.identityLabelValid(root.customWorkspaceText)
            onClicked: root.applyWorkspaceCustomLabel()
        }

        Item { Layout.fillWidth: true }

        SettingsButton {
            label: "Reset Workspace Icons"
            textSize: 9
            onClicked: root.resetWorkspaceIcons()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        spacing: 5

        Text {
            text: "Find more icons"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }

        Item { Layout.fillWidth: true }

        SettingsButton {
            label: "Nerd Fonts ↗"
            textSize: 9
            onClicked: Qt.openUrlExternally("https://www.nerdfonts.com/cheat-sheet")
        }

        SettingsButton {
            label: "Unicode ↗"
            textSize: 9
            onClicked: Qt.openUrlExternally("https://symbl.cc/en/unicode/")
        }
    }

    Text {
        text: "Workspace overrides"
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.bold: true
    }

    Repeater {
        model: 10

        delegate: RowLayout {
            id: workspaceRow
            required property int index
            property int workspaceId: index + 1
            property string draft: BarState.workspaceOverrideFor(workspaceId)

            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 5

            Text {
                Layout.preferredWidth: 34
                text: String(workspaceRow.workspaceId)
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                Layout.preferredWidth: 48
                text: BarState.workspaceLabelFor(workspaceRow.workspaceId)
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 120
                Layout.preferredHeight: 24
                color: Theme.popupBackground
                border.width: 1
                border.color: overrideInput.activeFocus ? Theme.focus : Theme.muted
                radius: 0

                TextInput {
                    id: overrideInput
                    anchors.fill: parent
                    anchors.margins: 5
                    text: workspaceRow.draft
                    color: Theme.foreground
                    selectionColor: Theme.focus
                    selectedTextColor: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    selectByMouse: true
                    onTextEdited: workspaceRow.draft = text
                    Keys.onReturnPressed: root.setWorkspaceOverride(
                        workspaceRow.workspaceId, workspaceRow.draft)
                }
            }

            SettingsButton {
                label: "Apply"
                textSize: 9
                available: BarState.identityLabelValid(workspaceRow.draft)
                onClicked: root.setWorkspaceOverride(workspaceRow.workspaceId, workspaceRow.draft)
            }

            SettingsButton {
                label: "Reset"
                textSize: 9
                available: BarState.workspaceOverrideFor(workspaceRow.workspaceId).length > 0
                onClicked: {
                    workspaceRow.draft = "";
                    root.clearWorkspaceOverride(workspaceRow.workspaceId);
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.muted
        opacity: 0.45
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        spacing: 5

        Text {
            text: "Application launcher"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
        }

        Text {
            visible: root.launcherCopyFeedback.length > 0
            text: root.launcherCopyFeedback
            color: Theme.focus
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "Current · " + BarState.launcherIcon()
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 4
        rowSpacing: 3

        Repeater {
            model: BarState.launcherIconPresets

            delegate: RowLayout {
                id: launcherPreset
                required property var modelData

                Layout.fillWidth: true
                spacing: 3

                SettingsButton {
                    Layout.fillWidth: true
                    label: launcherPreset.modelData.value + "  " + launcherPreset.modelData.label
                    textSize: 9
                    horizontalPadding: 8
                    active: BarState.launcherIcon() === launcherPreset.modelData.value
                    onClicked: root.setLauncherIcon(launcherPreset.modelData.value)
                }

                SettingsButton {
                    label: " Copy"
                    textSize: 8
                    horizontalPadding: 6
                    active: root.copiedLauncherValue === launcherPreset.modelData.value
                    onClicked: root.copyLauncherIcon(launcherPreset.modelData.value)
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        spacing: 5

        Text {
            Layout.preferredWidth: 112
            text: "Custom launcher"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }

        Rectangle {
            Layout.preferredWidth: 120
            Layout.preferredHeight: 24
            color: Theme.popupBackground
            border.width: 1
            border.color: customLauncherInput.activeFocus ? Theme.focus : Theme.muted
            radius: 0

            TextInput {
                id: customLauncherInput
                anchors.fill: parent
                anchors.margins: 5
                text: root.customLauncherText
                color: Theme.foreground
                selectionColor: Theme.focus
                selectedTextColor: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                selectByMouse: true
                onTextEdited: root.customLauncherText = text
                Keys.onReturnPressed: root.setLauncherIcon(root.customLauncherText)
            }
        }

        SettingsButton {
            label: "Apply"
            textSize: 9
            available: BarState.identityLabelValid(root.customLauncherText)
            onClicked: root.setLauncherIcon(root.customLauncherText)
        }

        SettingsButton {
            label: "Reset Launcher Icon"
            textSize: 9
            onClicked: root.resetLauncherIcon()
        }

        Item { Layout.fillWidth: true }

        SettingsButton {
            label: "Reset Bar Icons"
            textSize: 9
            onClicked: root.resetBarIcons()
        }
    }

    Text {
        Layout.fillWidth: true
        visible: root.message.length > 0
        text: root.message
        color: root.identityError.length > 0 ? Theme.critical : Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: 9
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }
}
