import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property real low: 0
    property real mid: 0
    property real high: 0
    property real overall: 0

    property real targetLow: 0
    property real targetMid: 0
    property real targetHigh: 0
    property real targetOverall: 0

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string helper: root.configHome
        + "/hypr/scripts/quickshell_lockscreen_audio.sh"
    readonly property real silenceThreshold: 0.018

    function clampUnit(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return 0;
        return Math.max(0, Math.min(1, numeric));
    }

    function threshold(value) {
        const bounded = clampUnit(value);
        return bounded < silenceThreshold ? 0 : bounded;
    }

    function average(values, start, count) {
        let total = 0;
        let used = 0;
        for (let i = start; i < Math.min(values.length, start + count); ++i) {
            total += values[i];
            used++;
        }
        return used > 0 ? total / used : 0;
    }

    function ensureSmoothing() {
        if (!smoothingTimer.running)
            smoothingTimer.start();
    }

    function parseFrame(data) {
        const fields = String(data || "").trim().split(";");
        if (fields.length < 8)
            return;

        const values = [];
        for (let i = 0; i < 8; ++i)
            values.push(clampUnit(Number(fields[i]) / 1000));

        targetLow = threshold(average(values, 0, 3));
        targetMid = threshold(average(values, 3, 3));
        targetHigh = threshold(average(values, 6, 2));
        targetOverall = threshold(average(values, 0, 8));
        ensureSmoothing();
    }

    function smoothed(current, target) {
        const factor = target > current ? 0.42 : 0.16;
        const next = current + (target - current) * factor;
        return Math.abs(next - target) < 0.001 ? target : next;
    }

    function clearTargets() {
        targetLow = 0;
        targetMid = 0;
        targetHigh = 0;
        targetOverall = 0;
    }

    function startAnalyzer() {
        if (root.enabled && !audioProcess.running)
            audioProcess.running = true;
    }

    function settled() {
        return root.low === root.targetLow
            && root.mid === root.targetMid
            && root.high === root.targetHigh
            && root.overall === root.targetOverall;
    }

    onEnabledChanged: {
        if (enabled) {
            startAnalyzer();
        } else {
            if (audioProcess.running)
                audioProcess.running = false;
            clearTargets();
            ensureSmoothing();
        }
    }

    Component.onCompleted: root.startAnalyzer()

    Process {
        id: audioProcess
        command: [root.helper]
        stdout: SplitParser {
            onRead: data => root.parseFrame(data)
        }
        onExited: {
            root.clearTargets();
            root.ensureSmoothing();
        }
    }

    Timer {
        id: smoothingTimer
        interval: 33
        repeat: true
        running: false
        onTriggered: {
            root.low = root.smoothed(root.low, root.targetLow);
            root.mid = root.smoothed(root.mid, root.targetMid);
            root.high = root.smoothed(root.high, root.targetHigh);
            root.overall = root.smoothed(root.overall, root.targetOverall);

            if (root.settled())
                stop();
        }
    }
}
