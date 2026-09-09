pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    readonly property string statePath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/awtarchy/quickshell-state.json"
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string idleStatePath: runtimeDir + "/awtarchy-quickshell-idle-hidden"
    readonly property int explicitSaveVersion: 2

    // Default window dimensions are reference values designed around a
    // 1920x1080 logical desktop at scale 1.0. Unsaved defaults are scaled from
    // the target monitor's logical size while explicit per-monitor saves remain
    // exact logical-pixel dimensions.
    readonly property int referenceScreenWidth: 1920
    readonly property int referenceScreenHeight: 1080
    readonly property int referenceLauncherWidth: 420
    readonly property int referenceLauncherHeight: 582
    readonly property int referenceClipboardWidth: 880
    readonly property int referenceClipboardHeight: 760
    readonly property int referenceNotificationWidth: 520
    readonly property int referenceNotificationHeight: 760
    readonly property int referenceQuickSettingsWidth: 860
    readonly property int referenceQuickSettingsHeight: 850
    readonly property int referenceNetworkWidth: 520
    readonly property int referenceNetworkHeight: 600
    readonly property int referenceBluetoothWidth: 500
    readonly property int referenceBluetoothHeight: 600
    readonly property int referenceBatteryWidth: 560
    readonly property int referenceBatteryHeight: 560

    // Compatibility properties used by the existing Reset buttons. Clicking a
    // Reset control focuses that flyout, so these resolve against its monitor.
    readonly property int defaultLauncherWidth: launcherDefaultSizeFor(focusedMonitorName()).width
    readonly property int defaultLauncherHeight: launcherDefaultSizeFor(focusedMonitorName()).height
    readonly property int defaultClipboardWidth: clipboardDefaultSizeFor(focusedMonitorName()).width
    readonly property int defaultClipboardHeight: clipboardDefaultSizeFor(focusedMonitorName()).height
    readonly property int defaultNotificationWidth: notificationDefaultSizeFor(focusedMonitorName()).width
    readonly property int defaultNotificationHeight: notificationDefaultSizeFor(focusedMonitorName()).height
    readonly property int defaultQuickSettingsWidth: quickSettingsDefaultSizeFor(focusedMonitorName()).width
    readonly property int defaultQuickSettingsHeight: quickSettingsDefaultSizeFor(focusedMonitorName()).height
    readonly property int defaultNetworkWidth: networkDefaultSizeFor(focusedMonitorName()).width
    readonly property int defaultNetworkHeight: networkDefaultSizeFor(focusedMonitorName()).height
    readonly property int defaultBluetoothWidth: bluetoothDefaultSizeFor(focusedMonitorName()).width
    readonly property int defaultBluetoothHeight: bluetoothDefaultSizeFor(focusedMonitorName()).height
    readonly property int defaultBatteryWidth: batteryDefaultSizeFor(focusedMonitorName()).width
    readonly property int defaultBatteryHeight: batteryDefaultSizeFor(focusedMonitorName()).height

    readonly property int defaultAppTextSize: 14
    readonly property int defaultAppIconSize: 18
    readonly property int defaultNotificationPopupLimit: 4
    readonly property var defaultQuickSettingsSectionOrder: [
        "brightness",
        "output-volume",
        "bar",
        "display-effects",
        "submap",
        "wallpaper",
        "awtarchy",
        "smtty",
        "scheduler",
        "numlock",
        "title-bars"
    ]

    readonly property var stockWorkspaceIcons: ({
        "1": "󰞷",
        "2": "",
        "3": "",
        "4": "",
        "5": "",
        "6": "",
        "7": "",
        "8": "",
        "9": "",
        "10": ""
    })
    readonly property var workspaceIconStylePresets: [
        { key: "off", label: "Off", symbols: [], glyphSize: 18, glyphYOffset: 0 },
        {
            key: "awtarchy",
            label: "Awtarchy",
            symbols: ["󰞷", "", "", "", "", "", "", "", "", ""],
            glyphSize: 20,
            glyphYOffset: 0
        },
        {
            key: "workflow",
            label: "Workflow",
            symbols: ["", "", "", "", "", "", "", "", "", ""],
            glyphSize: 20,
            glyphYOffset: -1
        },
        {
            key: "phases",
            label: "Phases",
            symbols: ["◐", "◑", "◒", "◓", "◔", "◕", "○", "●", "◉", "◎"],
            glyphSize: 22,
            glyphYOffset: -2
        },
        { key: "custom-symbol", label: "Custom", symbols: [], glyphSize: 18, glyphYOffset: 0 }
    ];
    readonly property var workspaceStylePresets: [
        { key: "awtarchy", label: "Awtarchy", sample: "1󰞷" },
        { key: "numbers", label: "Numbers", sample: "1" },
        { key: "icons", label: "Icons", sample: "󰞷" },
        { key: "workflow", label: "Workflow", sample: "" },
        { key: "phases", label: "Phases", sample: "◐◑" },
        { key: "custom-symbol", label: "Custom", sample: "…" }
    ]
    readonly property var launcherIconPresets: [
        { label: "Awtarchy", value: "" },
        { label: "Menu", value: "☰" },
        { label: "Tux", value: "" },
        { label: "Arch", value: "" },
        { label: "Diamond", value: "◆" },
        { label: "Circle", value: "●" }
    ]
    readonly property var lockscreenAnimationPresets: [
        { key: "random", label: "Random" },
        { key: "swarm", label: "Swarm" },
        { key: "edges", label: "Edges" },
        { key: "center", label: "Center" },
        { key: "split", label: "Split" },
        { key: "off", label: "Off" }
    ]
    readonly property var defaultLockscreenLayout: ({
        logo: ({ x: 0.50, y: 0.34, scale: 1.0 }),
        time: ({ x: 0.50, y: 0.51, scale: 1.0 }),
        date: ({ x: 0.50, y: 0.555, scale: 1.0 }),
        username: ({ x: 0.50, y: 0.595, scale: 1.0 }),
        weather: ({ x: 0.50, y: 0.635, scale: 1.0 }),
        password: ({ x: 0.50, y: 0.70, scale: 1.0 })
    })
    readonly property var workspaceLegacyStyleAliases: ({
        "filled-dot": "workflow",
        "filled-diamond": "workflow",
        "center-diamond": "workflow",
        "filled-square": "workflow",
        "small-square": "workflow",
        "filled-triangle": "workflow",
        "spark": "workflow",
        "minimal-bar": "workflow",
        "dots": "workflow",
        "diamonds": "workflow",
        "squares": "workflow",
        "triangles": "workflow",
        "minimal": "workflow"
    })


    property int revision: 0
    property int idleRevision: 0

    // Immediate in-process overrides keep bar geometry and icon sizing
    // responsive while persistent JSON writes complete in the background.
    property var livePositions: ({})
    property var liveEnabled: ({})
    property var liveBarSizes: ({})
    property var liveIconScales: ({})
    property var liveBarTransparencies: ({})

    function focusedMonitorName() {
        const monitor = Hyprland.focusedMonitor;
        return monitor && monitor.name ? String(monitor.name) : "";
    }

    function screenFor(name) {
        if (!name || name.length === 0)
            return null;
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; ++i) {
            const screen = screens[i];
            if (screen && screen.name === name)
                return screen;
        }
        return null;
    }

    function adaptiveDefaultSizeFor(name, referenceWidth, referenceHeight) {
        const screen = screenFor(name);
        const rawWidth = screen ? Number(screen.width) : referenceScreenWidth;
        const rawHeight = screen ? Number(screen.height) : referenceScreenHeight;
        const logicalWidth = Number.isFinite(rawWidth) && rawWidth > 0
            ? rawWidth : referenceScreenWidth;
        const logicalHeight = Number.isFinite(rawHeight) && rawHeight > 0
            ? rawHeight : referenceScreenHeight;
        const widthScale = logicalWidth / referenceScreenWidth;
        const heightScale = logicalHeight / referenceScreenHeight;
        const factor = Math.min(widthScale, heightScale);

        return ({
            width: Math.max(1, Math.round(referenceWidth * factor)),
            height: Math.max(1, Math.round(referenceHeight * factor))
        });
    }

    function launcherDefaultSizeFor(name) {
        return adaptiveDefaultSizeFor(name, referenceLauncherWidth, referenceLauncherHeight);
    }

    function clipboardDefaultSizeFor(name) {
        return adaptiveDefaultSizeFor(name, referenceClipboardWidth, referenceClipboardHeight);
    }

    function notificationDefaultSizeFor(name) {
        return adaptiveDefaultSizeFor(name, referenceNotificationWidth, referenceNotificationHeight);
    }

    function quickSettingsDefaultSizeFor(name) {
        return adaptiveDefaultSizeFor(name, referenceQuickSettingsWidth, referenceQuickSettingsHeight);
    }

    function networkDefaultSizeFor(name) {
        return adaptiveDefaultSizeFor(name, referenceNetworkWidth, referenceNetworkHeight);
    }

    function bluetoothDefaultSizeFor(name) {
        return adaptiveDefaultSizeFor(name, referenceBluetoothWidth, referenceBluetoothHeight);
    }

    function batteryDefaultSizeFor(name) {
        return adaptiveDefaultSizeFor(name, referenceBatteryWidth, referenceBatteryHeight);
    }

    function refresh() {
        stateFile.reload();
        revision++;
    }

    function refreshIdleState() {
        idleStateFile.reload();
        idleRevision++;
    }

    function setIdleHidden(hidden) {
        idleStateFile.setText(hidden ? "1\n" : "0\n");
        idleRevision++;
    }

    function idleHidden() {
        const dependency = idleRevision;
        return idleStateFile.text().trim() === "1";
    }

    function setLivePosition(name, value) {
        const next = Object.assign({}, livePositions);
        next[name] = value;
        livePositions = next;
        revision++;
    }

    function setLiveEnabled(name, value) {
        const next = Object.assign({}, liveEnabled);
        next[name] = !!value;
        liveEnabled = next;
        revision++;
    }

    function setLiveBarSize(name, value) {
        const next = Object.assign({}, liveBarSizes);
        next[name] = Number(value);
        liveBarSizes = next;
        revision++;
    }

    function setLiveIconScale(name, value) {
        const next = Object.assign({}, liveIconScales);
        next[name] = Number(value);
        liveIconScales = next;
        revision++;
    }

    function setLiveBarTransparency(name, value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return;
        const percent = Math.max(0, Math.min(100, Math.round(numeric)));
        if (liveBarTransparencies[name] === percent)
            return;
        const next = Object.assign({}, liveBarTransparencies);
        next[name] = percent;
        liveBarTransparencies = next;
        revision++;
    }

    function clearLiveBarTransparency(name) {
        if (liveBarTransparencies[name] === undefined)
            return;
        const next = Object.assign({}, liveBarTransparencies);
        delete next[name];
        liveBarTransparencies = next;
        revision++;
    }

    function clearLiveOverrides(name) {
        const positions = Object.assign({}, livePositions);
        const enabled = Object.assign({}, liveEnabled);
        const sizes = Object.assign({}, liveBarSizes);
        const scales = Object.assign({}, liveIconScales);
        const transparencies = Object.assign({}, liveBarTransparencies);
        delete positions[name];
        delete enabled[name];
        delete sizes[name];
        delete scales[name];
        delete transparencies[name];
        livePositions = positions;
        liveEnabled = enabled;
        liveBarSizes = sizes;
        liveIconScales = scales;
        liveBarTransparencies = transparencies;
        revision++;
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.revision++
        onFileChanged: root.refresh()
    }

    FileView {
        id: idleStateFile
        path: root.idleStatePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.idleRevision++
        onFileChanged: root.refreshIdleState()
    }

    IpcHandler {
        target: "barstate"
        function refresh(): void { root.refresh(); }
        function refreshIdle(): void { root.refreshIdleState(); }
        function setIdleHidden(hidden: bool): void { root.setIdleHidden(hidden); }
    }

    function emptyData() {
        return ({
            enabled: true,
            update_notifications_enabled: true,
            lockscreen_animation: "split",
            lockscreen_audio_reactive: true,
            lockscreen_mouse_interactive: true,
            lockscreen_show_logo: true,
            lockscreen_show_time: false,
            lockscreen_show_date: false,
            lockscreen_show_username: false,
            lockscreen_show_weather: false,
            lockscreen_background: "black",
            lockscreen_weather_location: "",
            lockscreen_layout: root.defaultLockscreenLayout,
            monitors: {},
            launcher_sizes: {},
            clipboard_views: {},
            notification_views: {},
            notification_popup_positions: {},
            quick_settings_views: {},
            quick_settings_layouts: {},
            network_views: {},
            bluetooth_views: {},
            battery_views: {},
            capture_allowed: {},
            bar_appearance: {}
        });
    }

    function data() {
        const dependency = revision;
        const text = stateFile.text();
        if (!text || text.length === 0)
            return emptyData();

        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
                return emptyData();
            if (!parsed.monitors || typeof parsed.monitors !== "object"
                || Array.isArray(parsed.monitors))
                parsed.monitors = {};
            if (!parsed.launcher_sizes || typeof parsed.launcher_sizes !== "object"
                || Array.isArray(parsed.launcher_sizes))
                parsed.launcher_sizes = {};
            for (const key of [
                "clipboard_views",
                "notification_views",
                "notification_popup_positions",
                "quick_settings_views",
                "quick_settings_layouts",
                "network_views",
                "bluetooth_views",
                "battery_views",
                "capture_allowed",
                "bar_appearance"
            ]) {
                if (!parsed[key] || typeof parsed[key] !== "object" || Array.isArray(parsed[key]))
                    parsed[key] = {};
            }
            if (!parsed.bar_appearance.workspace_overrides
                    || typeof parsed.bar_appearance.workspace_overrides !== "object"
                    || Array.isArray(parsed.bar_appearance.workspace_overrides))
                parsed.bar_appearance.workspace_overrides = {};
            if (parsed.enabled === undefined)
                parsed.enabled = true;
            if (parsed.update_notifications_enabled === undefined)
                parsed.update_notifications_enabled = true;
            return parsed;
        } catch (error) {
            console.warn("Awtarchy Quickshell: invalid shell state:", error);
            return emptyData();
        }
    }

    function identityLabelValid(value) {
        if (typeof value !== "string")
            return false;
        const points = Array.from(value);
        if (points.length < 1 || points.length > 8 || value.trim().length === 0)
            return false;
        if (value.indexOf("\n") >= 0 || value.indexOf("\r") >= 0)
            return false;
        for (const point of points) {
            const code = point.codePointAt(0);
            if ((code >= 0 && code <= 31) || (code >= 127 && code <= 159))
                return false;
        }
        return true;
    }

    function workspaceId(id) {
        const value = Math.round(Number(id));
        return Number.isFinite(value) && value >= 1 && value <= 10 ? value : 0;
    }

    function stockWorkspaceIconFor(id) {
        const value = workspaceId(id);
        return value > 0 ? String(stockWorkspaceIcons[String(value)] || "") : "";
    }

    function stockWorkspaceLabelFor(id, vertical) {
        const value = workspaceId(id);
        if (value === 0)
            return String(id);
        const icon = stockWorkspaceIconFor(value);
        if (icon.length === 0)
            return String(value);
        return vertical ? String(value) + icon : String(value) + " " + icon;
    }

    function workspaceIconStyleAllowed(style) {
        for (const preset of workspaceIconStylePresets) {
            if (preset.key === style)
                return true;
        }
        return false;
    }

    function normalizedWorkspaceIconStyle(style) {
        const value = String(style || "");
        if (workspaceIconStyleAllowed(value))
            return value;
        const alias = String(workspaceLegacyStyleAliases[value] || "");
        return workspaceIconStyleAllowed(alias) ? alias : "";
    }

    function workspaceNumbersEnabled() {
        const appearance = data().bar_appearance || ({});
        if (typeof appearance.workspace_numbers_enabled === "boolean")
            return appearance.workspace_numbers_enabled;
        const legacy = String(appearance.workspace_style || "awtarchy");
        return legacy === "awtarchy" || legacy === "numbers";
    }

    function workspaceIconStyle() {
        const appearance = data().bar_appearance || ({});
        const explicitStyle = normalizedWorkspaceIconStyle(appearance.workspace_icon_style);
        if (explicitStyle.length > 0)
            return explicitStyle;
        const legacy = String(appearance.workspace_style || "awtarchy");
        if (legacy === "numbers")
            return "off";
        if (legacy === "awtarchy" || legacy === "icons")
            return "awtarchy";
        const normalizedLegacy = normalizedWorkspaceIconStyle(legacy);
        return normalizedLegacy.length > 0 ? normalizedLegacy : "awtarchy";
    }

    function workspaceIconPackFor(style) {
        const normalized = normalizedWorkspaceIconStyle(style);
        for (const preset of workspaceIconStylePresets) {
            if (preset.key === normalized)
                return preset;
        }
        return null;
    }

    function workspaceIconPixelSize() {
        const pack = workspaceIconPackFor(workspaceIconStyle());
        const size = pack ? Number(pack.glyphSize) : 18;
        return Number.isFinite(size) ? Math.max(8, Math.round(size)) : 18;
    }

    function workspaceIconYOffset() {
        const pack = workspaceIconPackFor(workspaceIconStyle());
        const offset = pack ? Number(pack.glyphYOffset) : 0;
        return Number.isFinite(offset)
            ? Math.max(-4, Math.min(4, Math.round(offset))) : 0;
    }

    function workspaceIconFor(id) {
        const value = workspaceId(id);
        if (value === 0)
            return "";
        const style = workspaceIconStyle();
        if (style === "off")
            return "";
        if (style === "custom-symbol") {
            const custom = workspaceCustomLabel();
            return custom.length > 0 ? custom : stockWorkspaceIconFor(value);
        }
        const pack = workspaceIconPackFor(style);
        if (!pack || !Array.isArray(pack.symbols))
            return stockWorkspaceIconFor(value);
        return String(pack.symbols[value - 1] || "");
    }

    function composeWorkspaceLabel(id, vertical) {
        const value = workspaceId(id);
        if (value === 0)
            return String(id);
        const override = workspaceOverrideFor(value);
        if (override.length > 0)
            return override;
        const number = workspaceNumbersEnabled() ? String(value) : "";
        const icon = workspaceIconFor(value);
        if (number.length > 0 && icon.length > 0)
            return number + (vertical ? " " : " ") + icon;
        if (number.length > 0)
            return number;
        return icon;
    }

    function workspaceStyle() {
        const appearance = data().bar_appearance || ({});
        const value = String(appearance.workspace_style || "awtarchy");
        if (value === "awtarchy" || value === "numbers" || value === "icons"
                || value === "custom-symbol")
            return value;
        const normalized = normalizedWorkspaceIconStyle(value);
        return normalized.length > 0 ? normalized : "awtarchy";
    }

    function workspaceCustomLabel() {
        const appearance = data().bar_appearance || ({});
        const value = appearance.workspace_custom_label;
        return identityLabelValid(value) ? value : "";
    }

    function workspaceOverrideFor(id) {
        const value = workspaceId(id);
        if (value === 0)
            return "";
        const overrides = (data().bar_appearance || ({})).workspace_overrides || ({});
        const label = overrides[String(value)];
        return identityLabelValid(label) ? label : "";
    }

    function workspaceStyleLabelFor(id, vertical) {
        const value = workspaceId(id);
        if (value === 0)
            return String(id);
        const style = workspaceStyle();
        if (style === "awtarchy")
            return stockWorkspaceLabelFor(value, vertical);
        if (style === "numbers")
            return String(value);
        if (style === "icons") {
            const icon = stockWorkspaceIconFor(value);
            return icon.length > 0 ? icon : String(value);
        }
        if (style === "custom-symbol") {
            const custom = workspaceCustomLabel();
            return custom.length > 0 ? custom : stockWorkspaceLabelFor(value, vertical);
        }
        const pack = workspaceIconPackFor(style);
        const symbol = pack && Array.isArray(pack.symbols)
            ? String(pack.symbols[value - 1] || "") : "";
        return symbol.length > 0 ? symbol : stockWorkspaceLabelFor(value, vertical);
    }

    function workspaceLabelFor(id) {
        return composeWorkspaceLabel(id, false);
    }

    function workspaceVerticalLabelFor(id) {
        return composeWorkspaceLabel(id, true);
    }

    function launcherIcon() {
        const appearance = data().bar_appearance || ({});
        const value = appearance.launcher_icon;
        if (identityLabelValid(value))
            return value;
        return "";
    }

    function lockscreenAnimationPreference() {
        const value = String(data().lockscreen_animation || "split");
        for (const preset of lockscreenAnimationPresets) {
            if (preset.key === value)
                return value;
        }
        return "split";
    }

    function lockscreenBooleanPreference(field, fallback) {
        const value = data()[field];
        return typeof value === "boolean" ? value : fallback;
    }

    function lockscreenAudioReactiveEnabled() {
        return lockscreenBooleanPreference("lockscreen_audio_reactive", true);
    }

    function lockscreenMouseInteractiveEnabled() {
        return lockscreenBooleanPreference("lockscreen_mouse_interactive", true);
    }

    function lockscreenShowLogo() {
        return lockscreenBooleanPreference("lockscreen_show_logo", true);
    }

    function lockscreenShowTime() {
        return lockscreenBooleanPreference("lockscreen_show_time", false);
    }

    function lockscreenShowDate() {
        return lockscreenBooleanPreference("lockscreen_show_date", false);
    }

    function lockscreenShowUsername() {
        return lockscreenBooleanPreference("lockscreen_show_username", false);
    }

    function lockscreenShowWeather() {
        return lockscreenBooleanPreference("lockscreen_show_weather", false);
    }

    function lockscreenBackground() {
        return String(data().lockscreen_background || "") === "wallpaper"
            ? "wallpaper" : "black";
    }

    function lockscreenWeatherLocation() {
        const value = data().lockscreen_weather_location;
        if (typeof value !== "string")
            return "";
        const trimmed = value.trim();
        const points = Array.from(trimmed);
        if (points.length > 96)
            return "";
        for (const point of points) {
            const code = point.codePointAt(0);
            if ((code >= 0 && code <= 31) || (code >= 127 && code <= 159))
                return "";
        }
        return trimmed;
    }

    function lockscreenLayoutPoint(value, fallback, password) {
        if (!value || typeof value !== "object" || Array.isArray(value))
            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale });
        const x = Number(value.x);
        const y = Number(value.y);
        const scale = Number(value.scale === undefined ? 1 : value.scale);
        const minX = password ? 0.15 : 0.05;
        const maxX = password ? 0.85 : 0.95;
        const minY = password ? 0.20 : 0.08;
        const maxY = password ? 0.86 : 0.92;
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(scale)
                || x < minX || x > maxX || y < minY || y > maxY
                || scale < 0.50 || scale > 2.00)
            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale });
        return ({ x: x, y: y, scale: scale });
    }
    function lockscreenLayout() {
        const defaults = root.defaultLockscreenLayout;
        const value = data().lockscreen_layout;
        if (!value || typeof value !== "object" || Array.isArray(value))
            return defaults;
        return ({
            logo: lockscreenLayoutPoint(value.logo, defaults.logo, false),
            time: lockscreenLayoutPoint(value.time, defaults.time, false),
            date: lockscreenLayoutPoint(value.date, defaults.date, false),
            username: lockscreenLayoutPoint(value.username, defaults.username, false),
            weather: lockscreenLayoutPoint(value.weather, defaults.weather, false),
            password: lockscreenLayoutPoint(value.password, defaults.password, true)
        });
    }

    function updateNotificationsEnabled() {
        return data().update_notifications_enabled !== false;
    }

    function monitorState(name) {
        const d = data();
        return d.monitors[name] || ({});
    }

    function hiddenWorkspaceIds() {
        const appearance = data().bar_appearance || ({});
        const values = Array.isArray(appearance.hidden_workspaces)
            ? appearance.hidden_workspaces : [];
        const result = [];
        for (const raw of values) {
            const value = workspaceId(raw);
            if (value > 0 && result.indexOf(value) < 0)
                result.push(value);
        }
        return result;
    }

    function workspaceVisible(id) {
        const value = workspaceId(id);
        return value > 0 && hiddenWorkspaceIds().indexOf(value) < 0;
    }

    function activeWorkspaceIdForMonitor(name) {
        const workspaces = Hyprland.workspaces.values;
        for (const workspace of workspaces) {
            if (workspace && workspace.monitor && workspace.monitor.name === name
                    && workspace.active)
                return workspaceId(workspace.id);
        }
        return 0;
    }

    function workspaceHiddenForMonitor(name) {
        const workspace = activeWorkspaceIdForMonitor(name);
        return workspace > 0 && !workspaceVisible(workspace);
    }

    function enabledFor(name) {
        const dependency = revision;
        const idleDependency = idleRevision;
        if (idleHidden())
            return false;

        if (liveEnabled[name] !== undefined) {
            if (!liveEnabled[name])
                return false;
            if (workspaceHiddenForMonitor(name))
                return false;
            return true;
        }

        const d = data();
        if (!d.enabled)
            return false;
        const mon = d.monitors[name];
        const enabled = !mon || mon.enabled === undefined ? true : !!mon.enabled;
        if (!enabled)
            return false;
        if (workspaceHiddenForMonitor(name))
            return false;
        return true;
    }

    function autoHideFor(name) {
        const dependency = revision;
        return monitorState(name).auto_hide === true;
    }

    function positionFor(name) {
        const dependency = revision;
        if (livePositions[name] !== undefined)
            return livePositions[name];
        const mon = monitorState(name);
        const pos = mon.position || "top";
        return ["top", "bottom", "left", "right"].indexOf(pos) >= 0 ? pos : "top";
    }

    function clockDateFor(name) {
        const dependency = revision;
        return monitorState(name).clock_date === true;
    }

    function barSizeFor(name, vertical) {
        const dependency = revision;
        const override = liveBarSizes[name];
        const custom = override !== undefined
            ? Number(override)
            : Number(monitorState(name).bar_size || 0);
        if (Number.isFinite(custom) && custom >= 20 && custom <= 80)
            return Math.round(custom);
        return vertical ? 36 : 28;
    }

    function iconScaleFor(name) {
        const dependency = revision;
        const override = liveIconScales[name];
        const mon = monitorState(name);
        const percent = Number(override !== undefined
            ? override
            : (mon.icon_scale === undefined ? 100 : mon.icon_scale));
        if (!Number.isFinite(percent))
            return 1.0;
        return Math.max(50, Math.min(200, percent)) / 100.0;
    }

    function barTransparencyFor(name) {
        const dependency = revision;
        const override = liveBarTransparencies[name];
        const mon = monitorState(name);
        const percent = Number(override !== undefined
            ? override
            : (mon.bar_transparency === undefined ? 0 : mon.bar_transparency));
        if (!Number.isFinite(percent))
            return 0;
        return Math.max(0, Math.min(100, Math.round(percent)));
    }

    function launcherViewFor(name) {
        const d = data();
        const defaults = launcherDefaultSizeFor(name);
        const rawView = (d.launcher_sizes || ({}))[name];
        const view = rawView && typeof rawView === "object" && !Array.isArray(rawView)
            ? rawView : ({});
        // Only a save written by the current explicit-save implementation, or
        // the old intentional locked flag, may survive reopening the launcher.
        // Historical auto-written drafts are deliberately ignored.
        const saved = (view.saved === true
                && Number(view.save_version || 0) >= explicitSaveVersion)
            || view.locked === true;
        const rawWidth = Number(view.width);
        const rawHeight = Number(view.height);
        const validWidth = Number.isFinite(rawWidth) && rawWidth >= 1 && rawWidth <= 16384;
        const validHeight = Number.isFinite(rawHeight) && rawHeight >= 1 && rawHeight <= 16384;

        let rawTextScale = view.text_scale;
        if (rawTextScale === undefined && view.text_size !== undefined)
            rawTextScale = Number(view.text_size) * 100 / defaultAppTextSize;

        let rawIconScale = view.icon_scale;
        if (rawIconScale === undefined && view.icon_size !== undefined)
            rawIconScale = Number(view.icon_size) * 100 / defaultAppIconSize;

        const textScale = Number(rawTextScale === undefined ? 100 : rawTextScale);
        const iconScale = Number(rawIconScale === undefined ? 100 : rawIconScale);

        if (!saved) {
            return ({
                saved: false,
                locked: false,
                width: defaults.width,
                height: defaults.height,
                centered: false,
                textScale: 100,
                iconScale: 100
            });
        }

        return ({
            saved: true,
            locked: view.locked === true && validWidth && validHeight,
            width: validWidth ? Math.round(rawWidth) : defaults.width,
            height: validHeight ? Math.round(rawHeight) : defaults.height,
            centered: view.centered === true,
            textScale: Number.isFinite(textScale)
                ? Math.max(50, Math.min(200, Math.round(textScale))) : 100,
            iconScale: Number.isFinite(iconScale)
                ? Math.max(50, Math.min(200, Math.round(iconScale))) : 100
        });
    }

    function applicationSizeLockedFor(name) {
        return launcherViewFor(name).locked;
    }

    function launcherWidthFor(name, globalOnly) {
        return launcherViewFor(name).width;
    }

    function launcherHeightFor(name, globalOnly) {
        return launcherViewFor(name).height;
    }

    function appTextScaleFor(name) {
        return launcherViewFor(name).textScale;
    }

    function appIconScaleFor(name) {
        return launcherViewFor(name).iconScale;
    }

    function launcherCenteredFor(name) {
        return launcherViewFor(name).centered;
    }

    function flyoutViewFor(collection, name, referenceWidth, referenceHeight) {
        const d = data();
        const defaults = adaptiveDefaultSizeFor(name, referenceWidth, referenceHeight);
        const views = d[collection] && typeof d[collection] === "object"
            ? d[collection] : ({});
        const raw = views[name];
        const view = raw && typeof raw === "object" && !Array.isArray(raw)
            ? raw : ({});
        const explicitlySaved = view.saved === true
            && Number(view.save_version || 0) >= explicitSaveVersion;

        if (!explicitlySaved) {
            return ({
                saved: false,
                width: defaults.width,
                height: defaults.height,
                textScale: 100,
                iconScale: 100
            });
        }

        const width = Number(view.width);
        const height = Number(view.height);
        const textScale = Number(view.text_scale === undefined ? 100 : view.text_scale);
        const iconScale = Number(view.icon_scale === undefined ? 100 : view.icon_scale);

        return ({
            saved: true,
            width: Number.isFinite(width) && width >= 1 && width <= 16384
                ? Math.round(width) : defaults.width,
            height: Number.isFinite(height) && height >= 1 && height <= 16384
                ? Math.round(height) : defaults.height,
            textScale: Number.isFinite(textScale)
                ? Math.max(50, Math.min(200, Math.round(textScale))) : 100,
            iconScale: Number.isFinite(iconScale)
                ? Math.max(50, Math.min(200, Math.round(iconScale))) : 100
        });
    }

    function clipboardViewFor(name) {
        return flyoutViewFor("clipboard_views", name,
            referenceClipboardWidth, referenceClipboardHeight);
    }

    function notificationPopupLimit() {
        const d = data();
        if (Number(d.notification_popup_limit_save_version || 0) < explicitSaveVersion)
            return defaultNotificationPopupLimit;
        const value = Number(d.notification_popup_limit);
        if (!Number.isFinite(value))
            return defaultNotificationPopupLimit;
        return Math.max(1, Math.min(20, Math.round(value)));
    }

    function notificationPopupPositionFor(name) {
        const positions = data().notification_popup_positions || ({});
        const value = String(positions[name] || "automatic");
        return [
            "automatic",
            "top-left",
            "top-center",
            "top-right",
            "bottom-left",
            "bottom-center",
            "bottom-right"
        ].indexOf(value) >= 0 ? value : "automatic";
    }

    function notificationViewFor(name) {
        return flyoutViewFor("notification_views", name,
            referenceNotificationWidth, referenceNotificationHeight);
    }

    function quickSettingsViewFor(name) {
        return flyoutViewFor("quick_settings_views", name,
            referenceQuickSettingsWidth, referenceQuickSettingsHeight);
    }

    function quickSettingsLayoutFor(name) {
        const layouts = data().quick_settings_layouts || ({});
        const raw = layouts[name] && typeof layouts[name] === "object"
            && !Array.isArray(layouts[name]) ? layouts[name] : ({});
        const defaults = defaultQuickSettingsSectionOrder;
        const order = [];
        const rawOrder = Array.isArray(raw.order) ? raw.order : [];

        for (const value of rawOrder) {
            const sectionId = String(value || "");
            if (defaults.indexOf(sectionId) >= 0 && order.indexOf(sectionId) < 0)
                order.push(sectionId);
        }
        for (const sectionId of defaults) {
            if (order.indexOf(sectionId) < 0)
                order.push(sectionId);
        }

        const hidden = [];
        const rawHidden = Array.isArray(raw.hidden) ? raw.hidden : [];
        for (const value of rawHidden) {
            const sectionId = String(value || "");
            if (defaults.indexOf(sectionId) >= 0 && hidden.indexOf(sectionId) < 0)
                hidden.push(sectionId);
        }

        return ({
            order: order,
            hidden: hidden.length < order.length ? hidden : []
        });
    }

    function networkViewFor(name) {
        return flyoutViewFor("network_views", name,
            referenceNetworkWidth, referenceNetworkHeight);
    }

    function bluetoothViewFor(name) {
        return flyoutViewFor("bluetooth_views", name,
            referenceBluetoothWidth, referenceBluetoothHeight);
    }

    function batteryViewFor(name) {
        return flyoutViewFor("battery_views", name,
            referenceBatteryWidth, referenceBatteryHeight);
    }

    function captureAllowedFor(surface) {
        const allowed = data().capture_allowed || ({});
        return allowed[surface] === true;
    }

    function appTextSizeFor(name, globalOnly) {
        return Math.max(7, Math.round(defaultAppTextSize * appTextScaleFor(name) / 100));
    }

    function appIconSizeFor(name, globalOnly) {
        return Math.max(9, Math.round(defaultAppIconSize * appIconScaleFor(name) / 100));
    }
}
