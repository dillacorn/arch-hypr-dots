//@ pragma ShellId awtarchy
//@ pragma CacheDir $BASE/awtarchy-quickshell
//@ pragma StateDir $BASE/awtarchy-quickshell
//@ pragma IconTheme Papirus-Dark
//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // Force singleton construction before the control IPC endpoint reports ready.
    readonly property bool notificationsReady: Notifications.dnd || !Notifications.dnd
    readonly property bool launcherReady: Launcher !== null
    readonly property bool clipboardReady: ClipboardMenu !== null
    readonly property bool powerReady: PowerMenu !== null
    readonly property bool themesReady: ThemePicker !== null

    Variants {
        model: Quickshell.screens
        Bar {
            implicitWidth: vertical ? BarState.barSizeFor(monitorName, true) : 0
            implicitHeight: vertical ? 0 : BarState.barSizeFor(monitorName, false)
            exclusiveZone: BarState.barSizeFor(monitorName, vertical)
        }
    }

    IpcHandler {
        target: "control"
        function ping(): string { return "ok"; }
        function reload(): void { Quickshell.reload(false); }
        function hardReload(): void { Quickshell.reload(true); }
        function quit(): void { Qt.quit(); }
    }
}
