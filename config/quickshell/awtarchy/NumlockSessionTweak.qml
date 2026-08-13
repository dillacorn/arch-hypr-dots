pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell

Singleton {
    readonly property bool enabled: QuickSettings.disableNumlockAtSessionStart
}
