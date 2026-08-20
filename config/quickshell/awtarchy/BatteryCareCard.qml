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
    property bool statusLoading: false
    property bool refreshPending: false

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string batteryCareScript: configHome + "/hypr/scripts/quickshell_battery_care.sh"

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
        batteryCareReader.exec([batteryCareScript, "--status-json"]);
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

    function capabilityText() {
        const mode = String(statusData.mode || "unsupported");
        if (mode === "range"
            && statusData.stop_min !== null && statusData.stop_min !== undefined
            && statusData.stop_max !== null && statusData.stop_max !== undefined) {
            return "Custom target range: " + statusData.stop_min + "–" + statusData.stop_max + "%";
        }
        if ((mode === "fixed" || mode === "presets")
            && Array.isArray(statusData.stop_presets)
            && statusData.stop_presets.length > 0) {
            return "Supported targets: " + statusData.stop_presets.map(value => value + "%").join(", ");
        }
        return String(statusData.detail || "");
    }

    function currentThresholdText() {
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
        if (lines.length > 0)
            return lines.join("\n");
        if (Boolean(statusData.supported))
            return "Current hardware threshold is not exposed through the standard battery path.";
        return "";
    }

    onActiveChanged: {
        if (active)
            refreshStatus();
    }

    Process {
        id: batteryCareReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "{}");
                    root.statusData = parsed && typeof parsed === "object"
                        ? parsed : root.emptyStatus();
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

    Timer {
        interval: 60000
        repeat: true
        running: root.active
        onTriggered: root.refreshStatus()
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 5

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

        Text {
            Layout.fillWidth: true
            text: "Read-only detection · charge-limit controls are not enabled yet"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
