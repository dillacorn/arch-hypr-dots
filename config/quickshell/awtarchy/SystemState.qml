pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int cpuUsage: 0
    property int memoryUsage: 0
    property string cpuTemp: "?°"
    property string gpuTemp: "N/A"
    property bool idleInhibited: false
    property bool idleBroken: false
    property var coreUsage: ({})

    property real previousCpuTotal: 0
    property real previousCpuIdle: 0
    property var previousCoreTotals: ({})
    property var previousCoreIdles: ({})

    readonly property string cpuTooltip: buildCpuTooltip()
    readonly property string temperatureTooltip: "CPU: " + plainTemp(cpuTemp) + "\nGPU: " + plainTemp(gpuTemp)

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string cpuTempScript: configHome + "/hypr/scripts/cpu_temp.sh"
    readonly property string idleScript: configHome + "/hypr/scripts/idle_inhibitor_global.sh"

    Process {
        id: metricsProcess
        command: ["sh", "-lc", "grep -E '^cpu([0-9]+)? ' /proc/stat; awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{if(t>0)printf \"MEM %d\\n\",100*(t-a)/t}' /proc/meminfo; if [ -x '" + root.cpuTempScript + "' ]; then printf 'CPU_TEMP '; '" + root.cpuTempScript + "'; else printf 'CPU_TEMP ?°\\n'; fi; gpu='N/A'; for d in /sys/class/hwmon/*; do [ -r \"$d/name\" ] || continue; name=$(cat \"$d/name\" 2>/dev/null || true); case \"$name\" in amdgpu|nouveau|nvidia) best=''; for f in \"$d\"/temp*_input; do [ -r \"$f\" ] || continue; v=$(cat \"$f\" 2>/dev/null || true); case \"$v\" in ''|*[!0-9]*) continue;; esac; c=$((v/1000)); if [ -z \"$best\" ] || [ \"$c\" -gt \"$best\" ]; then best=$c; fi; done; if [ -n \"$best\" ]; then gpu=\"${best}°\"; break; fi;; esac; done; printf 'GPU_TEMP %s\\n' \"$gpu\""]
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
        const match = String(text || "").match(/(?:\d+°|N\/A|\?°)/);
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
            }
        }

        root.previousCoreTotals = newCoreTotals;
        root.previousCoreIdles = newCoreIdles;
        root.coreUsage = newCoreUsage;
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
