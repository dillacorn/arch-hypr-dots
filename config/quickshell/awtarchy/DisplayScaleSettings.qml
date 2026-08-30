pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string monitorName: ""
    property bool active: false
    property string message: ""
    property real displayScale: 1
    property int monitorPixelWidth: 0
    property int monitorPixelHeight: 0
    property real pendingDisplayScale: 1
    property string displayScaleError: ""
    property bool customScaleOpen: false
    property string customScaleText: "1"

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string displayScaleScript: configHome
        + "/hypr/scripts/quickshell_display_scale.sh"
    readonly property var displayScalePresets: [1, 1.25, 1.5, 2]

    implicitHeight: active ? controls.implicitHeight + 12 : 0

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

    function resetTransientState() {
        customScaleOpen = false;
        customScaleText = displayScaleLabel(displayScale);
        message = "";
        displayScaleError = "";
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
        message = "";
        refreshDisplayScale();
    }
    onActiveChanged: {
        if (active)
            refreshDisplayScale();
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

            Text {
                Layout.fillWidth: true
                visible: root.message.length > 0
                Layout.preferredHeight: visible ? 18 : 0
                text: root.message
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}
