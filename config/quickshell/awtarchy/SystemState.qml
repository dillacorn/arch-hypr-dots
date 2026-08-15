pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property int cpuUsage: 0
    property int memoryUsage: 0
    property int memoryPopulatedSlots: -1
    property int memoryTotalSlots: -1
    property int memoryEmptySlots: -1
    property string memoryTopologySource: "unavailable"
    property string cpuTemp: "?°"
    property string gpuTemp: "N/A"
    property var driveTemps: []
    property var otherTemps: []
    property bool idleInhibited: false
    property bool idleBroken: false
    property var coreUsage: ({})

    property real previousCpuTotal: 0
    property real previousCpuIdle: 0
    property var previousCoreTotals: ({})
    property var previousCoreIdles: ({})

    readonly property string cpuTooltip: buildCpuTooltip()
    readonly property string memoryTooltip: buildMemoryTooltip()
    readonly property string temperatureTooltip: buildTemperatureTooltip()
    readonly property string audioOutputName: buildAudioOutputName()

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string cpuTempScript: configHome + "/hypr/scripts/cpu_temp.sh"
    readonly property string systemTempScript: configHome + "/hypr/scripts/system_temperatures.sh"
    readonly property string memoryTopologyScript: configHome + "/hypr/scripts/memory_topology.sh"
    readonly property string idleScript: configHome + "/hypr/scripts/idle_inhibitor_global.sh"

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            Qt.callLater(root.clampAudioVolume);
        }
    }

    Connections {
        target: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio
            ? Pipewire.defaultAudioSink.audio
            : null
        function onVolumeChanged() {
            root.clampAudioVolume();
        }
    }

    Component.onCompleted: Qt.callLater(root.clampAudioVolume)

    Process {
        id: metricsProcess
        command: ["sh", "-lc", "grep -E '^cpu([0-9]+)? ' /proc/stat; awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{if(t>0)printf \"MEM %d\\n\",100*(t-a)/t}' /proc/meminfo; if [ -x '" + root.systemTempScript + "' ]; then '" + root.systemTempScript + "'; elif [ -x '" + root.cpuTempScript + "' ]; then printf 'CPU_TEMP '; '" + root.cpuTempScript + "'; printf 'GPU_TEMP N/A\\n'; else printf 'CPU_TEMP ?°\\nGPU_TEMP N/A\\n'; fi"]
        stdout: StdioCollector {
            onStreamFinished: root.parseMetrics(text)
        }
    }

    Process {
        id: memoryTopologyProcess
        running: true
        command: ["sh", "-lc", "if [ -x '" + root.memoryTopologyScript + "' ]; then '" + root.memoryTopologyScript + "'; else printf 'MEMORY_SLOTS\\t?\\t?\\t?\\tunavailable\\n'; fi"]
        stdout: StdioCollector {
            onStreamFinished: root.parseMemoryTopology(text)
        }
    }

    Process {
        id: idleStatusProcess
        command: ["sh", "-lc", "if [ -x '" + root.idleScript + "' ]; then '" + root.idleScript + "'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text.trim());
                    const classes = status.class || [];
                    root.idleInhibited = classes.indexOf("activated") >= 0;
                    root.idleBroken = classes.indexOf("error") >= 0;
                } catch (error) {
                    root.idleInhibited = false;
                    root.idleBroken = false;
                }
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!metricsProcess.running)
                metricsProcess.running = true;
            if (!idleStatusProcess.running)
                idleStatusProcess.running = true;
        }
    }

    function clampAudioVolume() {
        const sink = Pipewire.defaultAudioSink;
        if (!sink || !sink.audio)
            return;

        if (sink.audio.volume > 1.0)
            sink.audio.volume = 1.0;
    }

    function plainTemp(text) {
        const match = String(text || "").match(/(?:-?\d+°|N\/A|\?°)/);
        return match ? match[0] : String(text || "N/A");
    }

    function parseCpuLine(line) {
        const parts = line.trim().split(/\s+/);
        if (parts.length < 5)
            return null;
        const name = parts[0];
        const values = parts.slice(1).map(Number);
        const idle = values[3] + (values.length > 4 ? values[4] : 0);
        const total = values.reduce((sum, value) => sum + value, 0);
        return ({ name: name, idle: idle, total: total });
    }

    function parseSlotCount(value) {
        if (value === "?" || value === "")
            return -1;
        const parsed = Number(value);
        return Number.isNaN(parsed) ? -1 : Math.max(0, Math.round(parsed));
    }

    function parseMemoryTopology(text) {
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; ++i) {
            if (!lines[i].startsWith("MEMORY_SLOTS\t"))
                continue;

            const parts = lines[i].split("\t");
            if (parts.length < 5)
                continue;

            root.memoryPopulatedSlots = parseSlotCount(parts[1]);
            root.memoryTotalSlots = parseSlotCount(parts[2]);
            root.memoryEmptySlots = parseSlotCount(parts[3]);
            root.memoryTopologySource = parts[4].trim() || "unavailable";
            return;
        }

        root.memoryPopulatedSlots = -1;
        root.memoryTotalSlots = -1;
        root.memoryEmptySlots = -1;
        root.memoryTopologySource = "unavailable";
    }

    function parseMetrics(text) {
        const lines = text.split("\n").filter(line => line.length > 0);
        const newCoreTotals = Object.assign({}, previousCoreTotals);
        const newCoreIdles = Object.assign({}, previousCoreIdles);
        const newCoreUsage = Object.assign({}, coreUsage);
        const newDriveTemps = [];
        const newOtherTemps = [];

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i];

            if (line.startsWith("cpu ")) {
                const cpu = parseCpuLine(line);
                if (cpu && previousCpuTotal > 0 && cpu.total > previousCpuTotal) {
                    const totalDelta = cpu.total - previousCpuTotal;
                    const idleDelta = cpu.idle - previousCpuIdle;
                    root.cpuUsage = Math.max(0, Math.min(100, Math.round(100 * (totalDelta - idleDelta) / totalDelta)));
                }
                if (cpu) {
                    root.previousCpuTotal = cpu.total;
                    root.previousCpuIdle = cpu.idle;
                }
            } else if (/^cpu\d+ /.test(line)) {
                const cpu = parseCpuLine(line);
                if (!cpu)
                    continue;
                const oldTotal = previousCoreTotals[cpu.name] || 0;
                const oldIdle = previousCoreIdles[cpu.name] || 0;
                if (oldTotal > 0 && cpu.total > oldTotal) {
                    const totalDelta = cpu.total - oldTotal;
                    const idleDelta = cpu.idle - oldIdle;
                    newCoreUsage[cpu.name] = Math.max(0, Math.min(100, Math.round(100 * (totalDelta - idleDelta) / totalDelta)));
                }
                newCoreTotals[cpu.name] = cpu.total;
                newCoreIdles[cpu.name] = cpu.idle;
            } else if (line.startsWith("MEM ")) {
                const value = Number(line.slice(4));
                if (!Number.isNaN(value))
                    root.memoryUsage = Math.max(0, Math.min(100, Math.round(value)));
            } else if (line.startsWith("CPU_TEMP ")) {
                root.cpuTemp = line.slice(9).trim();
            } else if (line.startsWith("GPU_TEMP ")) {
                root.gpuTemp = line.slice(9).trim();
            } else if (line.startsWith("TEMP\t")) {
                const parts = line.split("\t");
                if (parts.length < 4)
                    continue;
                const entry = ({
                    label: parts[2].trim(),
                    value: parts.slice(3).join("\t").trim()
                });
                if (!entry.label || !entry.value)
                    continue;
                if (parts[1] === "Drive")
                    newDriveTemps.push(entry);
                else if (parts[1] === "Other")
                    newOtherTemps.push(entry);
            }
        }

        root.previousCoreTotals = newCoreTotals;
        root.previousCoreIdles = newCoreIdles;
        root.coreUsage = newCoreUsage;
        root.driveTemps = newDriveTemps;
        root.otherTemps = newOtherTemps;
    }

    function buildCpuTooltip() {
        const names = Object.keys(coreUsage).sort((a, b) => Number(a.slice(3)) - Number(b.slice(3)));
        let lines = ["CPU usage: " + cpuUsage + "%"];

        for (let i = 0; i < names.length; ++i)
            lines.push(names[i].toUpperCase() + ": " + coreUsage[names[i]] + "%");

        return lines.join("\n");
    }

    function buildMemoryTooltip() {
        const lines = ["Memory usage: " + memoryUsage + "%"];

        if (memoryPopulatedSlots >= 0 && memoryTotalSlots >= 0 && memoryEmptySlots >= 0) {
            lines.push("DIMMs: " + memoryPopulatedSlots + " populated / " + memoryTotalSlots + " slots");
            lines.push("Empty slots: " + memoryEmptySlots);
        } else if (memoryPopulatedSlots >= 0) {
            lines.push("DIMMs detected: " + memoryPopulatedSlots + " populated");
            lines.push("Empty slots: unavailable");
        } else {
            lines.push("DIMM slots: unavailable");
        }

        return lines.join("\n");
    }

    function buildTemperatureTooltip() {
        const lines = [
            "CPU: " + plainTemp(cpuTemp),
            "GPU: " + plainTemp(gpuTemp)
        ];

        if (driveTemps.length > 0) {
            lines.push("", "Drives:");
            for (let i = 0; i < driveTemps.length; ++i)
                lines.push(driveTemps[i].label + ": " + plainTemp(driveTemps[i].value));
        }

        if (otherTemps.length > 0) {
            lines.push("", "Other:");
            for (let i = 0; i < otherTemps.length; ++i)
                lines.push(otherTemps[i].label + ": " + plainTemp(otherTemps[i].value));
        }

        return lines.join("\n");
    }

    function buildAudioOutputName() {
        const sink = Pipewire.defaultAudioSink;
        if (!sink)
            return "No audio output";

        const description = String(sink.description || "").trim();
        if (description.length > 0)
            return description;

        const nickname = String(sink.nickname || "").trim();
        if (nickname.length > 0)
            return nickname;

        const name = String(sink.name || "").trim();
        return name.length > 0 ? name : "Default audio output";
    }

    function toggleIdle() {
        Quickshell.execDetached([idleScript, "toggle"]);
        refreshIdleTimer.restart();
    }

    Timer {
        id: refreshIdleTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!idleStatusProcess.running)
                idleStatusProcess.running = true;
        }
    }
}
