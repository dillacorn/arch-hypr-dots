pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property int cpuUsage: 0
    property int memoryUsage: 0
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
    readonly property string temperatureTooltip: buildTemperatureTooltip()
    readonly property string audioOutputName: buildAudioOutputName()

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string cpuTempScript: configHome + "/hypr/scripts/cpu_temp.sh"
    readonly property string systemTempScript: configHome + "/hypr/scripts/system_temperatures.sh"
    readonly property string idleScript: configHome + "/hypr/scripts/idle_inhibitor_global.sh"

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Process {
        id: metricsProcess
        command: ["sh", "-lc", "grep -E '^cpu([0-9]+)? ' /proc/stat; awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{if(t>0)printf \"MEM %d\\n\",100*(t-a)/t}' /proc/meminfo; if [ -x '" + root.systemTempScript + "' ]; then '" + root.systemTempScript + "'; elif [ -x '" + root.cpuTempScript + "' ]; then printf 'CPU_TEMP '; '" + root.cpuTempScript + "'; printf 'GPU_TEMP N/A\\n'; else printf 'CPU_TEMP ?°\\nGPU_TEMP N/A\\n'; fi"]
        stdout: StdioCollector {
            onStreamFinished: root.parseMetrics(text)
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
        let row = [];

        for (let i = 0; i < names.length; ++i) {
            row.push(names[i].toUpperCase() + ": " + coreUsage[names[i]] + "%");
            if (row.length === 4) {
                lines.push(row.join("   "));
                row = [];
            }
        }
        if (row.length > 0)
            lines.push(row.join("   "));

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
