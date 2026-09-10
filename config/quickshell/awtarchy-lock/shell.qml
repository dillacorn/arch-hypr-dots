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
    property bool lockShowLogo: true
    property bool lockShowTime: false
    property bool lockShowDate: false
    property bool lockShowUsername: false
    property bool lockShowWeather: false
    property string lockBackground: "black"
    property color lockBackgroundColor: "#000000"
    property string lockWallpaperPath: ""
    property string lockWeatherLocation: ""
    property var lockLayout: defaultLockLayout()
    property int randomFormationMode: Math.floor(Math.random() * 4)
    readonly property var allowedAnimationPreferences: [
        "random", "swarm", "edges", "center", "split", "off"
    ]

    function defaultLockLayout() {
        return ({
            logo: ({ x: 0.50, y: 0.34, scale: 1.0, color: "auto" }),
            time: ({ x: 0.50, y: 0.51, scale: 1.0, color: "auto" }),
            date: ({ x: 0.50, y: 0.555, scale: 1.0, color: "auto" }),
            username: ({ x: 0.50, y: 0.595, scale: 1.0, color: "auto" }),
            weather: ({ x: 0.50, y: 0.635, scale: 1.0, color: "auto" }),
            password: ({ x: 0.50, y: 0.70, scale: 1.0, color: "auto" })
        });
    }

    function normalizedAnimationPreference(value) {
        const key = String(value || "");
        return allowedAnimationPreferences.indexOf(key) >= 0 ? key : "split";
    }

    function normalizedBoolean(value, fallback) {
        return typeof value === "boolean" ? value : fallback;
    }

    function normalizedBackground(value) {
        const key = String(value || "");
        return ["black", "wallpaper", "color"].indexOf(key) >= 0 ? key : "black";
    }

    function normalizedBackgroundColor(value) {
        const key = String(value || "#000000").toLowerCase();
        return /^#[0-9a-f]{6}$/.test(key) ? key : "#000000";
    }

    function normalizedWallpaperPath(value) {
        const path = typeof value === "string" ? value : "";
        if (!path.startsWith("/") || path.indexOf("://") >= 0
                || /[\u0000-\u001f\u007f-\u009f]/.test(path))
            return "";
        return path;
    }

    function layoutPoint(value, fallback, password) {
        const fallbackColor = String(fallback.color || "auto");
        if (!value || typeof value !== "object" || Array.isArray(value))
            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, color: fallbackColor });
        const x = Number(value.x);
        const y = Number(value.y);
        const scale = Number(value.scale === undefined ? 1 : value.scale);
        const rawColor = String(value.color === undefined ? "auto" : value.color);
        const color = rawColor === "auto" || /^#[0-9a-fA-F]{6}$/.test(rawColor)
            ? rawColor.toLowerCase() : fallbackColor;
        const minX = password ? 0.15 : 0.05;
        const maxX = password ? 0.85 : 0.95;
        const minY = password ? 0.20 : 0.08;
        const maxY = password ? 0.86 : 0.92;
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(scale)
                || x < minX || x > maxX || y < minY || y > maxY
                || scale < 0.50 || scale > 2.00)
            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, color: fallbackColor });
        return ({ x: x, y: y, scale: scale, color: color });
    }
    function normalizedLayout(value) {
        const defaults = defaultLockLayout();
        if (!value || typeof value !== "object" || Array.isArray(value))
            return defaults;
        return ({
            logo: layoutPoint(value.logo, defaults.logo, false),
            time: layoutPoint(value.time, defaults.time, false),
            date: layoutPoint(value.date, defaults.date, false),
            username: layoutPoint(value.username, defaults.username, false),
            weather: layoutPoint(value.weather, defaults.weather, false),
            password: layoutPoint(value.password, defaults.password, true)
        });
    }

    function normalizedWeatherLocation(value) {
        if (typeof value !== "string")
            return "";
        const trimmed = value.trim();
        if (Array.from(trimmed).length > 96 || /[\u0000-\u001f\u007f-\u009f]/.test(trimmed))
            return "";
        return trimmed;
    }

    function resetPreferences() {
        lockAnimationPreference = "split";
        lockAudioReactive = true;
        lockMouseInteractive = true;
        lockShowLogo = true;
        lockShowTime = false;
        lockShowDate = false;
        lockShowUsername = false;
        lockShowWeather = false;
        lockBackground = "black";
        lockBackgroundColor = "#000000";
        lockWallpaperPath = "";
        lockWeatherLocation = "";
        lockLayout = defaultLockLayout();
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
            lockShowLogo = normalizedBoolean(parsed.lockscreen_show_logo, true);
            lockShowTime = normalizedBoolean(parsed.lockscreen_show_time, false);
            lockShowDate = normalizedBoolean(parsed.lockscreen_show_date, false);
            lockShowUsername = normalizedBoolean(parsed.lockscreen_show_username, false);
            lockShowWeather = normalizedBoolean(parsed.lockscreen_show_weather, false);
            lockBackground = normalizedBackground(parsed.lockscreen_background);
            lockBackgroundColor = normalizedBackgroundColor(parsed.lockscreen_background_color);
            lockWallpaperPath = normalizedWallpaperPath(parsed.lockscreen_wallpaper_path);
            lockWeatherLocation = normalizedWeatherLocation(parsed.lockscreen_weather_location);
            lockLayout = normalizedLayout(parsed.lockscreen_layout);
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

    LockWallpaperState {
        id: lockWallpaperState
        path: root.lockWallpaperPath
    }

    LockContrastCache {
        id: lockContrastCache
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
                showLogo: root.lockShowLogo
                showTime: root.lockShowTime
                showDate: root.lockShowDate
                showUsername: root.lockShowUsername
                showWeather: root.lockShowWeather
                weatherText: lockWeatherCache.summary
                backgroundMode: root.lockBackground
                wallpaperSource: lockWallpaperState.source
                backgroundColor: root.lockBackgroundColor
                autoAccents: lockContrastCache.colors
                layout: root.lockLayout
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
