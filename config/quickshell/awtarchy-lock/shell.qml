//@ pragma ShellId awtarchy-lock
//@ pragma CacheDir $BASE/awtarchy-lock
//@ pragma StateDir $BASE/awtarchy-lock

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property bool unlockRequested: false
    readonly property string statePath: (Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")) + "/awtarchy/quickshell-state.json"
    property string lockAnimationPreference: "random"
    property int randomFormationMode: Math.floor(Math.random() * 4)
    readonly property var allowedAnimationPreferences: [
        "random", "swarm", "edges", "center", "split", "off"
    ]

    function normalizedAnimationPreference(value) {
        const key = String(value || "");
        return allowedAnimationPreferences.indexOf(key) >= 0 ? key : "random";
    }

    function loadAnimationPreference() {
        const text = stateFile.text();
        if (!text || text.length === 0) {
            lockAnimationPreference = "random";
            return;
        }

        try {
            const parsed = JSON.parse(text);
            lockAnimationPreference = normalizedAnimationPreference(
                parsed && typeof parsed === "object" ? parsed.lockscreen_animation : "random");
        } catch (error) {
            lockAnimationPreference = "random";
        }
    }

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        root.loadAnimationPreference();
    }

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        printErrors: false
        onLoaded: root.loadAnimationPreference()
    }

    LockTheme {
        id: lockTheme
    }

    LockAuth {
        id: lockAuth

        onAuthenticated: {
            if (root.unlockRequested)
                return;

            root.unlockRequested = true;
            unlockFadeTimer.restart();
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: true

        surface: Component {
            LockSurface {
                auth: lockAuth
                theme: lockTheme
                unlocking: root.unlockRequested
                animationPreference: root.lockAnimationPreference
                randomFormationMode: root.randomFormationMode
            }
        }

        onSecureChanged: {
            if (root.unlockRequested && !secure)
                quitAfterUnlock.restart();
        }
    }

    IpcHandler {
        target: "lock"

        function state(): string {
            return sessionLock.secure ? "secure"
                : sessionLock.locked ? "starting" : "unlocked";
        }

        function stopTest(): bool {
            if (sessionLock.secure)
                return false;

            root.unlockRequested = true;
            sessionLock.locked = false;
            quitAfterUnlock.restart();
            return true;
        }
    }

    Timer {
        id: unlockFadeTimer
        interval: 170
        repeat: false
        onTriggered: {
            sessionLock.locked = false;
            if (!sessionLock.secure)
                quitAfterUnlock.restart();
        }
    }

    Timer {
        id: quitAfterUnlock
        interval: 150
        repeat: false
        onTriggered: Qt.quit()
    }
}
