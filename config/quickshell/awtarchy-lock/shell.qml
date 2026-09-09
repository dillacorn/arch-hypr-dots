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
    property string lockAnimationPreference: "split"
    property bool lockAudioReactive: true
    property bool lockMouseInteractive: true
    property bool lockShowTime: false
    property bool lockShowDate: false
    property bool lockShowUsername: false
    property bool lockShowWeather: false
    property int randomFormationMode: Math.floor(Math.random() * 4)
    readonly property var allowedAnimationPreferences: [
        "random", "swarm", "edges", "center", "split", "off"
    ]

    function normalizedAnimationPreference(value) {
        const key = String(value || "");
        return allowedAnimationPreferences.indexOf(key) >= 0 ? key : "split";
    }

    function normalizedBoolean(value, fallback) {
        return typeof value === "boolean" ? value : fallback;
    }

    function resetPreferences() {
        lockAnimationPreference = "split";
        lockAudioReactive = true;
        lockMouseInteractive = true;
        lockShowTime = false;
        lockShowDate = false;
        lockShowUsername = false;
        lockShowWeather = false;
    }

    function loadPreferences() {
        const text = stateFile.text();
        if (!text || text.length === 0) {
            resetPreferences();
            return;
        }

        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
                resetPreferences();
                return;
            }

            lockAnimationPreference = normalizedAnimationPreference(parsed.lockscreen_animation);
            lockAudioReactive = normalizedBoolean(parsed.lockscreen_audio_reactive, true);
            lockMouseInteractive = normalizedBoolean(parsed.lockscreen_mouse_interactive, true);
            lockShowTime = normalizedBoolean(parsed.lockscreen_show_time, false);
            lockShowDate = normalizedBoolean(parsed.lockscreen_show_date, false);
            lockShowUsername = normalizedBoolean(parsed.lockscreen_show_username, false);
            lockShowWeather = normalizedBoolean(parsed.lockscreen_show_weather, false);
        } catch (error) {
            resetPreferences();
        }
    }

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        root.loadPreferences();
    }

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        printErrors: false
        onLoaded: root.loadPreferences()
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

    LockAudioAnalyzer {
        id: lockAudioAnalyzer
        enabled: root.lockAudioReactive
    }

    LockWeatherCache {
        id: lockWeatherCache
        enabled: root.lockShowWeather
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
                audioReactive: root.lockAudioReactive
                audioLow: lockAudioAnalyzer.low
                audioMid: lockAudioAnalyzer.mid
                audioHigh: lockAudioAnalyzer.high
                audioOverall: lockAudioAnalyzer.overall
                mouseInteractive: root.lockMouseInteractive
                showTime: root.lockShowTime
                showDate: root.lockShowDate
                showUsername: root.lockShowUsername
                showWeather: root.lockShowWeather
                weatherText: lockWeatherCache.summary
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
