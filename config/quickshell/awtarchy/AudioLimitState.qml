pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string configPath: configHome + "/wiremix/wiremix.toml"
    readonly property string volumeScript: configHome + "/hypr/scripts/quickshell_volume.sh"
    readonly property int minimumPercent: 100
    readonly property int maximumPercent: 200
    readonly property int stepPercent: 5
    property int limitPercent: 100

    function normalized(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return 100;
        const rounded = Math.round(numeric / stepPercent) * stepPercent;
        return Math.max(minimumPercent, Math.min(maximumPercent, rounded));
    }

    function parseLimit(text) {
        const match = String(text || "").match(
            /^[ \t]*max_volume_percent[ \t]*=[ \t]*([0-9]+(?:\.[0-9]+)?)[ \t]*$/m);
        return match ? normalized(Number(match[1])) : 100;
    }

    function replaceOrAppend(text, key, value) {
        const pattern = new RegExp("^[ \\t]*" + key + "[ \\t]*=[^\\n]*$", "m");
        const line = key + " = " + value;
        if (pattern.test(text))
            return text.replace(pattern, line);
        return text + (text.length > 0 && !text.endsWith("\n") ? "\n" : "")
            + line + "\n";
    }

    function clampCurrentOutput() {
        const sink = Pipewire.defaultAudioSink;
        const maximum = limitPercent / 100;
        if (sink && sink.audio && sink.audio.volume > maximum)
            Quickshell.execDetached([volumeScript, "set", String(limitPercent)]);
    }

    function setLimit(value) {
        const next = normalized(value);
        let text = String(configFile.text() || "");
        text = replaceOrAppend(text, "max_volume_percent", String(next));
        text = replaceOrAppend(text, "enforce_max_volume", "true");
        limitPercent = next;
        configFile.setText(text);
        clampCurrentOutput();
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.limitPercent = root.parseLimit(text())
        onFileChanged: reload()
    }
}
