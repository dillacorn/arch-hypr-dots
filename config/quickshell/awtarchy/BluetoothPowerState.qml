pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

Singleton {
    id: root

    property var savedEnabled: null
    property bool stateResolved: false
    property bool restoring: false

    readonly property var adapters: Bluetooth.adapters
        ? [...Bluetooth.adapters.values].filter(item => item !== null) : []
    readonly property var adapter: Bluetooth.defaultAdapter
        || (adapters.length > 0 ? adapters[0] : null)
    readonly property string stateFilePath: Quickshell.statePath("bluetooth-enabled")

    function parseSavedState(text) {
        const value = String(text || "").trim().toLowerCase();
        if (value === "1" || value === "true" || value === "on")
            return true;
        if (value === "0" || value === "false" || value === "off")
            return false;
        return null;
    }

    function remember(enabled) {
        const value = Boolean(enabled);
        savedEnabled = value;
        stateFile.setText(value ? "true\n" : "false\n");
    }

    function restoreOrInitialize() {
        const current = adapter;
        if (!stateResolved || !current)
            return;

        if (savedEnabled === null) {
            remember(current.enabled);
            return;
        }

        if (current.enabled === savedEnabled)
            return;

        restoring = true;
        if (!savedEnabled && current.discovering)
            current.discovering = false;
        current.enabled = savedEnabled;
        restoreGuard.restart();
    }

    function resolveLoadedState() {
        savedEnabled = parseSavedState(stateFile.text());
        stateResolved = true;
        restoreOrInitialize();
    }

    function resolveMissingState() {
        savedEnabled = null;
        stateResolved = true;
        restoreOrInitialize();
    }

    function recordBluetoothMenuChoice() {
        if (restoring)
            return;
        const message = String(BluetoothMenu.actionMessage || "");
        if (message === "Bluetooth enabled")
            remember(true);
        else if (message === "Bluetooth disabled")
            remember(false);
    }

    onAdapterChanged: Qt.callLater(() => root.restoreOrInitialize())
    Component.onCompleted: Qt.callLater(() => root.restoreOrInitialize())

    FileView {
        id: stateFile
        path: root.stateFilePath
        atomicWrites: true
        blockLoading: false
        blockWrites: false
        printErrors: false
        onLoaded: root.resolveLoadedState()
        onLoadFailed: root.resolveMissingState()
    }

    Timer {
        id: restoreGuard
        interval: 250
        repeat: false
        onTriggered: root.restoring = false
    }

    Connections {
        target: BluetoothMenu
        function onActionMessageChanged() {
            root.recordBluetoothMenuChoice();
        }
    }
}
