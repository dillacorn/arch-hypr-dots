import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100
    property var statusData: emptyStatus()
    property var healthData: emptyHealth()
    property bool statusLoading: false
    property bool healthLoading: false
    property bool refreshPending: false
    property int targetDraft: 80
    property bool targetDirty: false
    property string pendingAction: ""
    property int pendingTarget: 80
    property string pendingPassword: ""
    property bool authOpen: false
    property bool authBusy: false
    property string authError: ""
    property string actionMessage: ""

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string batteryCareScript: configHome + "/hypr/scripts/quickshell_battery_care.sh"
    readonly property string batteryHealthScript: configHome + "/hypr/scripts/quickshell_battery_health.sh"
    readonly property string batteryCareHelper: "/usr/local/libexec/awtarchy/power-profile-helper"
    readonly property string pluginName: String(statusData.plugin || "").toLowerCase()
    readonly property bool fixedUnknownTarget: pluginName === "lenovo" || pluginName === "lenovo-legacy"
    readonly property bool limitEnabled: statusData.enabled === true
        || (statusData.enabled !== false && Boolean(statusData.managed_config))
    readonly property bool controlsAvailable: Boolean(statusData.supported)
        && String(statusData.backend || "") === "tlp"
        && !Boolean(statusData.config_conflict)
        && (fixedUnknownTarget || root.hasNumericControl())
    readonly property bool showFallbackHealth: !BatteryState.healthSupported
        && Boolean(healthData.supported)

    Layout.fillWidth: true
    Layout.preferredHeight: content.implicitHeight + 16
    color: Theme.popupButton
    border.width: 1
    border.color: Theme.active

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * textScale / 100));
    }

    function emptyStatus() {
        return ({
            supported: false,
            backend: "none",
            plugin: "",
            mode: "unsupported",
            summary: "Checking battery charge-limit support…",
            detail: "",
            start_min: null,
            start_max: null,
            stop_min: null,
            stop_max: null,
            stop_presets: [],
            current_start: null,
            current_stop: null,
            managed_config: false,
            managed_target: null,
            config_conflict: false,
            conflict_sources: [],
            enabled: null,
            target: null,
            batteries: []
        });
    }

    function emptyHealth() {
        return ({
            supported: false,
            source: "",
            percentage: null,
            full_wh: null,
            design_wh: null,
            full_ah: null,
            design_ah: null,
            batteries: []
        });
    }

    function refreshStatus() {
        if (!active)
            return;
        if (batteryCareReader.running) {
            refreshPending = true;
            return;
        }
        statusLoading = true;
        refreshPending = false;
        batteryCareReader.exec(["/usr/bin/bash", batteryCareScript, "--status-json"]);
    }

    function refreshHealth() {
        if (!active || batteryHealthReader.running)
            return;
        healthLoading = true;
        batteryHealthReader.exec(["/usr/bin/bash", batteryHealthScript, "--status-json"]);
    }

    function backendLabel() {
        if (statusData.backend === "tlp") {
            const plugin = String(statusData.plugin || "");
            return plugin.length > 0 ? "TLP · " + plugin : "TLP";
        }
        if (statusData.backend === "sysfs")
            return "Kernel";
        return "Unavailable";
    }

    function fallbackHealthPercentage() {
        const value = Number(healthData.percentage);
        return Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0;
    }

    function fallbackHealthDetail() {
        const source = String(healthData.source || "");
        if (source === "sysfs-energy") {
            const full = Number(healthData.full_wh);
            const design = Number(healthData.design_wh);
            if (Number.isFinite(full) && Number.isFinite(design))
                return full.toFixed(1) + " Wh full / " + design.toFixed(1) + " Wh design";
        }
        if (source === "sysfs-charge") {
            const full = Number(healthData.full_ah);
            const design = Number(healthData.design_ah);
            if (Number.isFinite(full) && Number.isFinite(design))
                return full.toFixed(1) + " Ah full / " + design.toFixed(1) + " Ah design";
        }
        return "";
    }

    function numericTargets() {
        const raw = Array.isArray(statusData.stop_presets) ? statusData.stop_presets : [];
        return raw.map(value => Number(value))
            .filter(value => Number.isFinite(value) && value >= 1 && value < 100);
    }

    function hasNumericControl() {
        if (String(statusData.mode || "") === "range")
            return statusData.stop_min !== null && statusData.stop_min !== undefined
                && statusData.stop_max !== null && statusData.stop_max !== undefined;
        return numericTargets().length > 0;
    }

    function minimumTarget() {
        const minimum = Number(statusData.stop_min);
        return Number.isFinite(minimum) ? Math.max(1, Math.round(minimum)) : 1;
    }

    function maximumTarget() {
        const maximum = Number(statusData.stop_max);
        return Number.isFinite(maximum) ? Math.min(99, Math.round(maximum)) : 99;
    }

    function normalizedTarget(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return targetDraft;
        const rounded = Math.round(numeric);
        if (String(statusData.mode || "") === "range")
            return Math.max(minimumTarget(), Math.min(maximumTarget(), rounded));
        const targets = numericTargets();
        if (targets.indexOf(rounded) >= 0)
            return rounded;
        return targets.length > 0 ? targets[0] : rounded;
    }

    function targetIsSupported(value) {
        const target = Number(value);
        if (!Number.isFinite(target) || target < 1 || target >= 100)
            return false;
        if (String(statusData.mode || "") === "range")
            return target >= minimumTarget() && target <= maximumTarget();
        return numericTargets().indexOf(Math.round(target)) >= 0;
    }

    function syncTargetDraft() {
        if (targetDirty || authOpen || authBusy)
            return;
        const observed = Number(statusData.target);
        const managed = Number(statusData.managed_target);
        if (Number.isFinite(observed) && observed >= 1 && observed < 100 && targetIsSupported(observed)) {
            targetDraft = Math.round(observed);
            return;
        }
        if (Number.isFinite(managed) && managed >= 1 && managed < 100 && targetIsSupported(managed)) {
            targetDraft = Math.round(managed);
            return;
        }
        if (targetIsSupported(80)) {
            targetDraft = 80;
            return;
        }
        if (String(statusData.mode || "") === "range") {
            targetDraft = normalizedTarget(80);
            return;
        }
        const targets = numericTargets();
        if (targets.length > 0)
            targetDraft = targets[0];
    }

    function capabilityText() {
        const mode = String(statusData.mode || "unsupported");
        if (mode === "range"
            && statusData.stop_min !== null && statusData.stop_min !== undefined
            && statusData.stop_max !== null && statusData.stop_max !== undefined) {
            return "Custom target range: " + statusData.stop_min + "–" + statusData.stop_max + "%";
        }
        if ((mode === "fixed" || mode === "presets")
            && numericTargets().length > 0) {
            return "Supported health targets: " + numericTargets().map(value => value + "%").join(", ");
        }
        return String(statusData.detail || "");
    }

    function currentThresholdText() {
        if (fixedUnknownTarget && statusData.enabled === true)
            return "Conservation mode: On · hardware-defined target";
        if (fixedUnknownTarget && statusData.enabled === false)
            return "Conservation mode: Off · full charge allowed";
        if (statusData.target !== null && statusData.target !== undefined) {
            const target = Number(statusData.target);
            if (Number.isFinite(target))
                return target >= 100 ? "Maximum charge: 100% · limit off" : "Maximum charge: " + target + "%";
        }

        const batteries = Array.isArray(statusData.batteries) ? statusData.batteries : [];
        const lines = [];
        for (const battery of batteries) {
            if (!battery)
                continue;
            const name = String(battery.name || "Battery");
            const start = battery.start_threshold;
            const stop = battery.stop_threshold;
            if (start !== null && start !== undefined && stop !== null && stop !== undefined)
                lines.push(name + ": start " + start + "% · stop " + stop + "%");
            else if (stop !== null && stop !== undefined)
                lines.push(name + ": stop " + stop + "%");
            else if (start !== null && start !== undefined)
                lines.push(name + ": start " + start + "%");
        }
        return lines.join("\n");
    }

    function statusControlLabel() {
        if (statusData.enabled === true)
            return "On";
        if (statusData.enabled === false)
            return "Off";
        if (statusData.managed_config)
            return "Managed";
        return "Off";
    }

    function openAuthorization(action, target, message) {
        if (authBusy)
            return;
        pendingAction = action;
        pendingTarget = target;
        authError = "";
        actionMessage = message;
        authOpen = true;
        Qt.callLater(() => authorizationPassword.forceActiveFocus());
    }

    function requestToggle() {
        if (!controlsAvailable)
            return;
        if (limitEnabled) {
            root.pendingAction = "battery-disable";
            openAuthorization(root.pendingAction, 100, "Authorize full charging to 100%.");
            return;
        }
        if (fixedUnknownTarget) {
            root.pendingAction = "battery-enable-fixed";
            openAuthorization(root.pendingAction, 0, "Authorize the hardware-defined conservation mode.");
            return;
        }
        root.pendingAction = "battery-set";
        const target = normalizedTarget(targetDraft);
        openAuthorization(root.pendingAction, target, "Authorize a " + target + "% maximum charge target.");
    }

    function requestTarget(value) {
        if (!controlsAvailable || fixedUnknownTarget)
            return;
        const target = normalizedTarget(value);
        if (!targetIsSupported(target)) {
            authError = "Unsupported charge target";
            return;
        }
        root.pendingAction = "battery-set";
        targetDraft = target;
        targetDirty = false;
        openAuthorization(root.pendingAction, target, "Authorize a " + target + "% maximum charge target.");
    }

    function cancelAuthorization() {
        if (authBusy)
            return;
        pendingPassword = "";
        authorizationPassword.text = "";
        authError = "";
        actionMessage = "";
        pendingAction = "";
        authOpen = false;
    }

    function submitAuthorization() {
        if (authBusy)
            return;
        if (authorizationPassword.text.length === 0) {
            authError = "Enter your sudo password";
            authorizationPassword.forceActiveFocus();
            return;
        }

        pendingPassword = authorizationPassword.text;
        authorizationPassword.text = "";
        authError = "";
        authBusy = true;

        const args = [
            "/usr/bin/sudo", "-S", "-p", "",
            batteryCareHelper, pendingAction
        ];
        if (pendingAction === "battery-set")
            args.push(String(pendingTarget));
        batteryCareWriter.exec(args);
    }

    onActiveChanged: {
        if (active) {
            refreshStatus();
            refreshHealth();
        } else if (!authBusy) {
            cancelAuthorization();
        }
    }

    Process {
        id: batteryCareReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "{}");
                    root.statusData = parsed && typeof parsed === "object"
                        ? parsed : root.emptyStatus();
                    root.syncTargetDraft();
                } catch (error) {
                    console.warn("Awtarchy battery care status parse failed:", error);
                    const fallback = root.emptyStatus();
                    fallback.summary = "Battery charge-limit status unavailable";
                    fallback.detail = "The read-only detector returned invalid data.";
                    root.statusData = fallback;
                }
            }
        }
        onExited: {
            root.statusLoading = false;
            if (root.refreshPending)
                Qt.callLater(() => root.refreshStatus());
        }
    }

    Process {
        id: batteryHealthReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "{}");
                    root.healthData = parsed && typeof parsed === "object"
                        ? parsed : root.emptyHealth();
                } catch (error) {
                    console.warn("Awtarchy battery health status parse failed:", error);
                    root.healthData = root.emptyHealth();
                }
            }
        }
        onExited: root.healthLoading = false
    }

    Process {
        id: batteryCareWriter
        stdinEnabled: true
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = text.trim();
                if (errorText.length > 0)
                    root.authError = errorText.split("\n")[0];
            }
        }
        onStarted: {
            batteryCareWriter.write(root.pendingPassword + "\n\n\n");
            root.pendingPassword = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.pendingPassword = "";
            root.authBusy = false;
            if (exitCode === 0) {
                root.authOpen = false;
                root.authError = "";
                root.actionMessage = root.pendingAction === "battery-disable"
                    ? "Full charging restored" : "Battery preservation updated";
                root.pendingAction = "";
                root.targetDirty = false;
                root.refreshStatus();
                return;
            }

            if (root.authError.length === 0)
                root.authError = "Battery preservation update failed";
            root.actionMessage = "";
            Qt.callLater(() => authorizationPassword.forceActiveFocus());
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.active && !root.authBusy
        onTriggered: {
            root.refreshStatus();
            root.refreshHealth();
        }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.showFallbackHealth
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Battery Health"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(12)
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    text: "Kernel"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Capacity health: " + root.fallbackHealthPercentage() + "%"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(9)
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                visible: root.fallbackHealthDetail().length > 0
                text: root.fallbackHealthDetail()
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
                wrapMode: Text.Wrap
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: root.showFallbackHealth
            color: Theme.active
            border.width: 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Battery Care"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(12)
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                text: root.statusLoading ? "Checking…" : root.backendLabel()
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
            }
        }

        Text {
            Layout.fillWidth: true
            text: String(root.statusData.summary || "")
            color: Boolean(root.statusData.supported) ? Theme.foreground : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(9)
            font.bold: Boolean(root.statusData.supported)
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            visible: root.currentThresholdText().length > 0
            text: root.currentThresholdText()
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(9)
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            visible: root.capabilityText().length > 0
            text: root.capabilityText()
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: conflictText.implicitHeight + 12
            visible: Boolean(root.statusData.config_conflict)
            color: Theme.active
            border.width: 1
            border.color: Theme.urgent

            Text {
                id: conflictText
                anchors.fill: parent
                anchors.margins: 6
                text: "Existing user-managed TLP charge thresholds detected. Awtarchy will not overwrite them."
                color: Theme.urgent
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.controlsAvailable
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.fixedUnknownTarget ? "Charge preservation" : "Limit charging"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(10)
                font.bold: true
            }

            SettingsButton {
                label: root.statusControlLabel()
                active: root.limitEnabled
                available: !root.authBusy
                textSize: root.scaledText(9)
                onClicked: root.requestToggle()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.controlsAvailable && String(root.statusData.mode || "") === "range"
            spacing: 6

            Text {
                text: "Maximum charge"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(9)
            }

            SettingsButton {
                label: "−5"
                available: !root.authBusy && root.targetDraft > root.minimumTarget()
                textSize: root.scaledText(9)
                onClicked: {
                    root.targetDraft = root.normalizedTarget(root.targetDraft - 5);
                    root.targetDirty = true;
                }
            }

            Rectangle {
                Layout.preferredWidth: 72
                Layout.preferredHeight: 28
                color: Theme.active
                border.width: 1
                border.color: targetInput.activeFocus ? Theme.focus : Theme.subtleHover

                TextInput {
                    id: targetInput
                    anchors.fill: parent
                    anchors.leftMargin: 7
                    anchors.rightMargin: 7
                    text: String(root.targetDraft)
                    enabled: !root.authBusy
                    color: Theme.foreground
                    selectionColor: Theme.focus
                    selectedTextColor: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(9)
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    validator: IntValidator {
                        bottom: root.minimumTarget()
                        top: root.maximumTarget()
                    }
                    onTextEdited: {
                        const value = Number(text);
                        if (Number.isFinite(value)) {
                            root.targetDraft = Math.round(value);
                            root.targetDirty = true;
                        }
                    }
                    onAccepted: root.requestTarget(root.targetDraft)
                }
            }

            Text {
                text: "%"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(9)
            }

            SettingsButton {
                label: "+5"
                available: !root.authBusy && root.targetDraft < root.maximumTarget()
                textSize: root.scaledText(9)
                onClicked: {
                    root.targetDraft = root.normalizedTarget(root.targetDraft + 5);
                    root.targetDirty = true;
                }
            }

            Item { Layout.fillWidth: true }

            SettingsButton {
                label: "Apply"
                available: !root.authBusy && root.targetIsSupported(root.targetDraft)
                textSize: root.scaledText(9)
                onClicked: root.requestTarget(root.targetDraft)
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            visible: root.controlsAvailable && !root.fixedUnknownTarget
                && String(root.statusData.mode || "") !== "range"
                && root.numericTargets().length > 0
            spacing: 5

            Repeater {
                model: root.numericTargets()

                SettingsButton {
                    required property var modelData
                    label: String(modelData) + "%"
                    active: Number(root.statusData.target) === Number(modelData) && root.limitEnabled
                    available: !root.authBusy
                    textSize: root.scaledText(9)
                    onClicked: root.requestTarget(Number(modelData))
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.controlsAvailable && root.fixedUnknownTarget
            text: "This hardware exposes only a conservation-mode switch. Linux does not report its model-specific charge target."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.authOpen
            spacing: 5

            Text {
                Layout.fillWidth: true
                text: root.actionMessage
                visible: text.length > 0
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                color: Theme.active
                border.width: 1
                border.color: authorizationPassword.activeFocus ? Theme.focus : Theme.subtleHover

                TextInput {
                    id: authorizationPassword
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.foreground
                    selectionColor: Theme.focus
                    selectedTextColor: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(9)
                    echoMode: TextInput.Password
                    enabled: !root.authBusy
                    clip: true
                    onAccepted: root.submitAuthorization()
                    Keys.onEscapePressed: root.cancelAuthorization()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.authError
                    visible: text.length > 0
                    color: Theme.urgent
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                    wrapMode: Text.Wrap
                }

                SettingsButton {
                    label: "Cancel"
                    available: !root.authBusy
                    textSize: root.scaledText(9)
                    onClicked: root.cancelAuthorization()
                }

                SettingsButton {
                    label: root.authBusy ? "Applying…" : "Authorize"
                    available: !root.authBusy && authorizationPassword.text.length > 0
                    textSize: root.scaledText(9)
                    onClicked: root.submitAuthorization()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.actionMessage.length > 0 && !root.authOpen
            text: root.actionMessage
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            text: root.controlsAvailable
                ? "Persistent through TLP · hardware state verified after every change"
                : (String(root.statusData.backend || "") === "sysfs"
                    ? "Read-only kernel status · managed controls require TLP battery-care support"
                    : "Charge-limit controls are unavailable on this hardware")
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
