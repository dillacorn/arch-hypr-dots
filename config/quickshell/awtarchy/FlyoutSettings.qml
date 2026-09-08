pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string surfaceLabel: "Flyout"
    property string monitorName: ""
    property int panelWidth: 0
    property int panelHeight: 0
    property int minimumWidth: 320
    property int maximumWidth: 16384
    property int minimumHeight: 280
    property int maximumHeight: 16384
    property int textScale: 100
    property int iconScale: 100
    property bool captureAllowed: false
    property bool showCaptureControl: true
    property string message: ""
    property var otherMonitorNames: []
    property var quickSettingsOrder: []
    property var quickSettingsHidden: []
    property bool copyOpen: false
    property var copyTargets: ({})
    property int copySelectionRevision: 0
    property int managedCaptureOverride: -1
    property string managedMessage: ""

    readonly property bool inlineCopy: surfaceLabel === "Quick Settings"
    readonly property bool managedConnectivityCapture: surfaceLabel === "Network"
        || surfaceLabel === "Bluetooth"
    readonly property string managedCaptureKey: surfaceLabel === "Network" ? "network"
        : (surfaceLabel === "Bluetooth" ? "bluetooth" : "")
    readonly property bool effectiveCaptureAllowed: managedConnectivityCapture
        ? (managedCaptureOverride >= 0
            ? managedCaptureOverride === 1
            : BarState.captureAllowedFor(managedCaptureKey))
        : captureAllowed
    readonly property bool effectiveShowCaptureControl: showCaptureControl
        || managedConnectivityCapture
    readonly property string effectiveMessage: managedMessage.length > 0
        ? managedMessage : message
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string stateScript: configHome
        + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string runtimeRulesScript: configHome
        + "/hypr/scripts/quickshell_runtime_rules.sh"

    signal resetRequested()
    signal widthAdjustmentRequested(int delta)
    signal heightAdjustmentRequested(int delta)
    signal textScaleAdjustmentRequested(int delta)
    signal iconScaleAdjustmentRequested(int delta)
    signal captureToggleRequested()
    signal copyRequested(var monitorNames)
    signal themePickerRequested()
    signal layoutEditorRequested()
    signal quickSettingsVisibilityRequested(string sectionId, bool visible)
    signal quickSettingsLayoutResetRequested()

    implicitHeight: inlineCopy
        ? 139 + displayScaleSection.implicitHeight
            + cursorThemeSection.implicitHeight
            + quickSettingsSectionControls.implicitHeight + 3 + (copyOpen ? 31 : 0)
        : (copyOpen ? 104 : 139)

    function quickSettingsSectionLabel(sectionId) {
        const labels = {
            "brightness": "Brightness",
            "output-volume": "Max Volume",
            "bar": "Bar",
            "display-effects": "Night + Vibrance",
            "submap": "Submap",
            "wallpaper": "Wallpaper",
            "awtarchy": "Awtarchy",
            "smtty": "smtty",
            "scheduler": "sched-ext",
            "numlock": "Num Lock",
            "title-bars": "Title Bars"
        };
        return labels[sectionId] || sectionId;
    }

    function quickSettingsSectionVisible(sectionId) {
        return (quickSettingsHidden || []).indexOf(sectionId) < 0;
    }

    function quickSettingsVisibleCount() {
        let count = 0;
        for (const sectionId of quickSettingsOrder || []) {
            if (quickSettingsSectionVisible(String(sectionId)))
                count++;
        }
        return count;
    }

    function targetSelected(name) {
        const dependency = copySelectionRevision;
        return copyTargets[name] === true;
    }

    function selectedTargetNames() {
        return otherMonitorNames.filter(name => targetSelected(String(name)));
    }

    function allTargetsSelected() {
        return otherMonitorNames.length > 0
            && otherMonitorNames.every(name => targetSelected(String(name)));
    }

    function setTargetSelected(name, selected) {
        const next = Object.assign({}, copyTargets);
        if (selected)
            next[name] = true;
        else
            delete next[name];
        copyTargets = next;
        copySelectionRevision++;
    }

    function toggleAllTargets() {
        const next = {};
        if (!allTargetsSelected()) {
            for (const name of otherMonitorNames)
                next[String(name)] = true;
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
        displayScaleSection.resetTransientState();
    }

    function toggleCaptureControl() {
        if (!managedConnectivityCapture) {
            captureToggleRequested();
            return;
        }
        if (captureWriter.running)
            return;

        const next = !effectiveCaptureAllowed;
        managedCaptureOverride = next ? 1 : 0;
        managedMessage = next
            ? surfaceLabel + " is visible in captures"
            : surfaceLabel + " capture protection enabled";
        captureWriter.exec([
            stateScript,
            "set-capture",
            managedCaptureKey,
            next ? "true" : "false"
        ]);
    }

    Process {
        id: captureWriter
        onExited: {
            BarState.refresh();
            privacyUpdater.exec([root.runtimeRulesScript]);
        }
    }

    Process { id: privacyUpdater }

    ColumnLayout {
        anchors.fill: parent
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 6
            visible: root.inlineCopy || !root.copyOpen

            Text {
                Layout.fillWidth: true
                text: root.monitorName + "  " + root.panelWidth + " × " + root.panelHeight
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: Math.max(112, resetLabel.implicitWidth + 20)
                Layout.preferredHeight: 24
                color: resetMouse.containsMouse ? Theme.focus : Theme.subtleHover
                border.width: 0

                Text {
                    id: resetLabel
                    anchors.centerIn: parent
                    text: "Reset " + root.surfaceLabel
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                MouseArea {
                    id: resetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resetRequested()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 5
            visible: root.inlineCopy || !root.copyOpen

            Text {
                text: "Width"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                color: widthMinusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                opacity: root.panelWidth > root.minimumWidth ? 1 : 0.4
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    id: widthMinusMouse
                    anchors.fill: parent
                    enabled: root.panelWidth > root.minimumWidth
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.widthAdjustmentRequested(-40)
                }
            }

            Text {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignHCenter
                text: root.panelWidth
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                color: widthPlusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                opacity: root.panelWidth < root.maximumWidth ? 1 : 0.4
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    id: widthPlusMouse
                    anchors.fill: parent
                    enabled: root.panelWidth < root.maximumWidth
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.widthAdjustmentRequested(40)
                }
            }

            Item { Layout.preferredWidth: 8 }

            Text {
                text: "Height"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                color: heightMinusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                opacity: root.panelHeight > root.minimumHeight ? 1 : 0.4
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    id: heightMinusMouse
                    anchors.fill: parent
                    enabled: root.panelHeight > root.minimumHeight
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.heightAdjustmentRequested(-40)
                }
            }

            Text {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignHCenter
                text: root.panelHeight
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                color: heightPlusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                opacity: root.panelHeight < root.maximumHeight ? 1 : 0.4
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    id: heightPlusMouse
                    anchors.fill: parent
                    enabled: root.panelHeight < root.maximumHeight
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.heightAdjustmentRequested(40)
                }
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 5
            visible: root.inlineCopy || !root.copyOpen

            Text {
                text: "Icons"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                color: iconMinusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                opacity: root.iconScale > 50 ? 1 : 0.4
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    id: iconMinusMouse
                    anchors.fill: parent
                    enabled: root.iconScale > 50
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.iconScaleAdjustmentRequested(-10)
                }
            }

            Text {
                Layout.preferredWidth: 42
                horizontalAlignment: Text.AlignHCenter
                text: root.iconScale + "%"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                color: iconPlusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                opacity: root.iconScale < 200 ? 1 : 0.4
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    id: iconPlusMouse
                    anchors.fill: parent
                    enabled: root.iconScale < 200
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.iconScaleAdjustmentRequested(10)
                }
            }

            Item { Layout.preferredWidth: 8 }

            Text {
                text: "Text"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                color: textMinusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                opacity: root.textScale > 50 ? 1 : 0.4
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    id: textMinusMouse
                    anchors.fill: parent
                    enabled: root.textScale > 50
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.textScaleAdjustmentRequested(-10)
                }
            }

            Text {
                Layout.preferredWidth: 42
                horizontalAlignment: Text.AlignHCenter
                text: root.textScale + "%"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                color: textPlusMouse.containsMouse ? Theme.focus : Theme.subtleHover
                opacity: root.textScale < 200 ? 1 : 0.4
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                MouseArea {
                    id: textPlusMouse
                    anchors.fill: parent
                    enabled: root.textScale < 200
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.textScaleAdjustmentRequested(10)
                }
            }

            Item { Layout.fillWidth: true }
        }

        DisplayScaleSettings {
            id: displayScaleSection
            Layout.fillWidth: true
            visible: root.surfaceLabel === "Quick Settings"
            active: visible
            monitorName: root.monitorName
        }

        CursorThemeSettings {
            id: cursorThemeSection
            Layout.fillWidth: true
            visible: root.surfaceLabel === "Quick Settings"
            active: visible
        }

        ColumnLayout {
            id: quickSettingsSectionControls
            Layout.fillWidth: true
            visible: root.surfaceLabel === "Quick Settings"
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 5

                Text {
                    Layout.fillWidth: true
                    text: "Quick Settings sections"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                SettingsButton {
                    label: "Reorder…"
                    textSize: 8
                    onClicked: root.layoutEditorRequested()
                }

                SettingsButton {
                    label: "Stock Layout"
                    textSize: 8
                    onClicked: root.quickSettingsLayoutResetRequested()
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 5

                Repeater {
                    model: root.quickSettingsOrder

                    SettingsButton {
                        required property var modelData
                        readonly property string sectionId: String(modelData)
                        readonly property bool shown: root.quickSettingsSectionVisible(sectionId)

                        label: root.quickSettingsSectionLabel(String(modelData))
                        active: root.quickSettingsSectionVisible(String(modelData))
                        available: !shown || root.quickSettingsVisibleCount() > 1
                        textSize: 8
                        horizontalPadding: 9
                        onClicked: root.quickSettingsVisibilityRequested(sectionId, !shown)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 6
            visible: root.inlineCopy || !root.copyOpen

            Rectangle {
                Layout.preferredWidth: 142
                Layout.preferredHeight: 24
                color: copyOpenMouse.containsMouse ? Theme.focus : Theme.subtleHover
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: root.surfaceLabel === "Quick Settings" ? "Copy Quick Settings…" : "Copy to Displays…"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    id: copyOpenMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.inlineCopy && root.copyOpen) {
                            root.resetCopySelection();
                            return;
                        }
                        root.copyTargets = ({});
                        root.copySelectionRevision++;
                        root.copyOpen = true;
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.effectiveMessage.length > 0
                text: root.effectiveMessage
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 28 : 0
            spacing: 5
            visible: root.copyOpen && root.inlineCopy

            Text {
                text: "Copy to:"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            Repeater {
                model: root.otherMonitorNames
                delegate: SettingsButton {
                    required property string modelData
                    label: modelData
                    textSize: 9
                    horizontalPadding: 10
                    active: root.targetSelected(modelData)
                    onClicked: root.setTargetSelected(modelData,
                        !root.targetSelected(modelData))
                }
            }

            SettingsButton {
                label: root.allTargetsSelected() ? "Clear" : "All"
                textSize: 9
                available: root.otherMonitorNames.length > 0
                onClicked: root.toggleAllTargets()
            }

            Item { Layout.fillWidth: true }

            SettingsButton {
                label: "Back"
                textSize: 9
                onClicked: root.resetCopySelection()
            }

            SettingsButton {
                label: "Copy"
                textSize: 9
                available: root.selectedTargetNames().length > 0
                onClicked: {
                    const targets = root.selectedTargetNames();
                    root.copyRequested(targets);
                    root.resetCopySelection();
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 6
            visible: root.copyOpen && !root.inlineCopy

            Rectangle {
                Layout.preferredWidth: 62
                Layout.preferredHeight: 24
                color: copyBackMouse.containsMouse ? Theme.focus : Theme.subtleHover
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "Back"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    id: copyBackMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resetCopySelection()
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Copy current draft to displays"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 10
                horizontalAlignment: Text.AlignRight
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            visible: root.copyOpen && !root.inlineCopy
            clip: true
            contentWidth: Math.max(width, copyTargetRow.width)
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: copyTargetRow
                height: parent.height
                width: childrenRect.width
                spacing: 4

                Rectangle {
                    visible: root.otherMonitorNames.length > 0
                    width: visible ? 96 : 0
                    height: 24
                    color: root.allTargetsSelected() ? Theme.focus
                        : (allTargetsMouse.containsMouse ? Theme.subtleHover : "transparent")
                    border.width: 1
                    border.color: Theme.focus

                    Text {
                        anchors.centerIn: parent
                        text: (root.allTargetsSelected() ? "✓ " : "") + "All displays"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: allTargetsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleAllTargets()
                    }
                }

                Repeater {
                    model: root.otherMonitorNames

                    Rectangle {
                        id: targetButton
                        required property var modelData
                        readonly property string targetName: String(modelData)
                        width: Math.max(72, Math.min(140, targetLabel.implicitWidth + 24))
                        height: 24
                        color: root.targetSelected(targetName) ? Theme.focus
                            : (targetMouse.containsMouse ? Theme.subtleHover : "transparent")
                        border.width: 1
                        border.color: Theme.focus

                        Text {
                            id: targetLabel
                            anchors.centerIn: parent
                            width: parent.width - 12
                            text: (root.targetSelected(targetButton.targetName) ? "✓ " : "")
                                + targetButton.targetName
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: targetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setTargetSelected(targetButton.targetName,
                                !root.targetSelected(targetButton.targetName))
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.otherMonitorNames.length === 0
                text: "No other displays connected"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 6
            visible: root.copyOpen && !root.inlineCopy

            Text {
                Layout.fillWidth: true
                text: root.selectedTargetNames().length + " selected"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 10
                horizontalAlignment: Text.AlignRight
            }

            Rectangle {
                Layout.preferredWidth: 70
                Layout.preferredHeight: 24
                color: root.selectedTargetNames().length > 0
                    ? (copyApplyMouse.containsMouse ? Theme.focus : Theme.subtleHover)
                    : "transparent"
                opacity: root.selectedTargetNames().length > 0 ? 1 : 0.4
                border.width: 1
                border.color: Theme.focus

                Text {
                    anchors.centerIn: parent
                    text: "Apply"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    id: copyApplyMouse
                    anchors.fill: parent
                    enabled: root.selectedTargetNames().length > 0
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        const targets = root.selectedTargetNames();
                        root.copyRequested(targets);
                        root.resetCopySelection();
                    }
                }
            }
        }
    }
}
