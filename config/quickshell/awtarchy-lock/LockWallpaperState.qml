import QtQuick

Item {
    id: root

    property string path: ""
    readonly property string source: localFileSource(path)

    function localFileSource(candidatePath) {
        const value = String(candidatePath || "").trim();
        if (!value.startsWith("/") || value.indexOf("://") >= 0)
            return "";
        return encodeURI("file://" + value);
    }
}
