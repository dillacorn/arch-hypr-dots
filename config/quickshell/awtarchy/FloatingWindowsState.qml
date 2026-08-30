pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string state: "checking"
    property string message: ""
    property string errorMessage: ""

    readonly property bool enabled: state === "enabled"
    readonly property bool available: state === "enabled" || state === "disabled"
    readonly property bool busy: statusRunner.running || actionRunner.running
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string runtimeHome: Quickshell.env("XDG_RUNTIME_DIR")
        || Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")
    readonly property string helper: configHome + "/hypr/scripts/quickshell_floating_windows.sh"
    readonly property string statePath: Quickshell.env("AWTARCHY_FLOATING_STATE_FILE")
        || (runtimeHome + "/awtarchy-floating-windows-state")

    function acceptState(value) {
        const next = String(value || "").trim();
        if (next !== "enabled" && next !== "disabled")
            return false;
        state = next;
        return true;
    }

    function syncFromRuntimeFile() {
        acceptState(stateFile.text());
    }

    function clearFeedback() {
        message = "";
        errorMessage = "";
    }

    function refresh() {
        if (busy)
            return;
        errorMessage = "";
        statusRunner.exec([helper, "status"]);
    }

    function setEnabled(enabled) {
        if (busy)
            return;
        if (available && root.enabled === Boolean(enabled))
            return;
        errorMessage = "";
        message = enabled
            ? "Making new windows float by default…"
            : "Restoring tiled windows as the default…";
        actionRunner.exec([helper, "set", enabled ? "on" : "off"]);
    }

    function toggle() {
        if (!available) {
            refresh();
            return;
        }
        setEnabled(!enabled);
    }

    Component.onCompleted: Qt.callLater(root.refresh)

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: false
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.syncFromRuntimeFile()
    }

    Process {
        id: statusRunner
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.acceptState(text))
                    root.state = "unavailable";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const detail = text.trim();
                if (detail.length > 0)
                    root.errorMessage = detail.split("\n")[0];
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.state = "unavailable";
        }
    }

    Process {
        id: actionRunner
        stdout: StdioCollector {
            onStreamFinished: root.acceptState(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const detail = text.trim();
                if (detail.length > 0)
                    root.errorMessage = detail.split("\n")[0];
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.errorMessage = "";
                root.message = root.enabled
                    ? "Floating Windows enabled."
                    : "Floating Windows disabled.";
            } else {
                root.message = "";
                if (root.errorMessage.length === 0)
                    root.errorMessage = "Could not update the Floating Windows preference.";
            }
        }
    }
}
