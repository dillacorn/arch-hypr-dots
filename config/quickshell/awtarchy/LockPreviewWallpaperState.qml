import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string statePath:
        Quickshell.env("HOME") + "/.config/awtwall/backend_state.tsv"
    property string source: ""

    function localFileSource(path) {
        const value = String(path || "").trim();
        if (!value.startsWith("/") || value.indexOf("://") >= 0)
            return "";
        return encodeURI("file://" + path);
    }

    function refresh() {
        const text = stateFile.text();
        const lines = String(text || "").split(/\r?\n/);
        let nextSource = "";

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i];
            if (line.length === 0)
                continue;
            const fields = line.split("\t");
            if (fields.length < 2 || fields[0] === "backend")
                continue;

            const path = fields.length >= 3
                ? fields.slice(2).join("\t")
                : fields.slice(1).join("\t");
            const candidate = localFileSource(path);
            if (candidate.length > 0) {
                nextSource = candidate;
                break;
            }
        }

        root.source = nextSource;
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.refresh()
        onFileChanged: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
