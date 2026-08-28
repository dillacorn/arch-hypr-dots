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

        Item { Layout.fillWidth: true }

        Text {
            text: "Global · " + root.workspaceIconStyleLabel()
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 4
        columnSpacing: 4
        rowSpacing: 3

        Repeater {
            model: BarState.workspaceIconStylePresets

            delegate: SettingsButton {
                required property var modelData

                Layout.fillWidth: true
                label: modelData.sample + "  " + modelData.label
                textSize: 9
                horizontalPadding: 8
                active: BarState.workspaceIconStyle() === modelData.key
                onClicked: {
                    if (modelData.key === "custom-symbol"
                            && !BarState.identityLabelValid(root.customWorkspaceText)) {
                        root.message = "Enter a custom workspace symbol below";
                        return;
                    }
                    root.setWorkspaceIconStyle(modelData.key);
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
        columns: 5
        columnSpacing: 4
        rowSpacing: 3

        Repeater {
            model: BarState.launcherIconPresets

            delegate: SettingsButton {
                required property var modelData

                Layout.fillWidth: true
                label: modelData.value + "  " + modelData.label
                textSize: 9
                horizontalPadding: 8
                active: BarState.launcherIcon() === modelData.value
                onClicked: root.setLauncherIcon(modelData.value)
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
