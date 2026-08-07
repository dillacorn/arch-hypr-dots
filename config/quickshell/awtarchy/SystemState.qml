pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int cpuUsage: 0
    property int memoryUsage: 0
    property string cpuTemp: "?°"
    property bool idleInhibited: false
    property bool idleBroken: false

    property real previousCpuTotal: 0
    property real previousCpuIdle: 0

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string cpuTempScript: configHome + "/waybar/scripts/cpu_temp.sh"
    readonly property string idleScript: configHome + "/waybar/scripts/idle_inhibitor_global.sh"

    Process {
        id: metricsProcess
        command: ["sh", "-lc", "printf '%s\\n' \"$(head -n1 /proc/stat)\"; awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{if(t>0)printf \"MEM %d\\n\",100*(t-a)/t}' /proc/meminfo; if [ -x '" + root.cpuTempScript + "' ]; then '" + root.cpuTempScript + "'; else printf '?°\\n'; fi"]
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

    function parseMetrics(text) {
        const lines = text.split("\n").filter(line => line.length > 0);
        if (lines.length > 0 && lines[0].startsWith("cpu ")) {
            const parts = lines[0].trim().split(/\s+/).slice(1).map(Number);
            if (parts.length >= 4) {
                const idle = parts[3] + (parts.length > 4 ? parts[4] : 0);
                const total = parts.reduce((sum, value) => sum + value, 0);
                if (previousCpuTotal > 0 && total > previousCpuTotal) {
                    const totalDelta = total - previousCpuTotal;
                    const idleDelta = idle - previousCpuIdle;
                    root.cpuUsage = Math.max(0, Math.min(100, Math.round(100 * (totalDelta - idleDelta) / totalDelta)));
                }
                root.previousCpuTotal = total;
                root.previousCpuIdle = idle;
            }
        }

        for (let i = 1; i < lines.length; ++i) {
            if (lines[i].startsWith("MEM ")) {
                const value = Number(lines[i].slice(4));
                if (!Number.isNaN(value))
                    root.memoryUsage = Math.max(0, Math.min(100, Math.round(value)));
            } else if (lines[i].indexOf("°") >= 0) {
                root.cpuTemp = lines[i].trim();
            }
        }
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
