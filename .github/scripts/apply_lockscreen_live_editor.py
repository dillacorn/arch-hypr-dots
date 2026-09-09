#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected exactly one target, found {text.count(old)}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    start_pos = text.find(start)
    if start_pos < 0:
        raise SystemExit(f"{label}: start target not found")
    end_pos = text.find(end, start_pos)
    if end_pos < 0:
        raise SystemExit(f"{label}: end target not found")
    return text[:start_pos] + replacement + text[end_pos:]


def editor_from_workflow() -> str:
    workflow = read(".github/workflows/apply-lockscreen-live-editor.yml")
    marker = "          cat > config/quickshell/awtarchy/LockscreenEditor.qml <<'EOF'\n"
    start = workflow.find(marker)
    if start < 0:
        raise SystemExit("editor heredoc start not found")
    start += len(marker)
    end = workflow.find("\n          EOF\n", start)
    if end < 0:
        raise SystemExit("editor heredoc end not found")
    lines = workflow[start:end].splitlines()
    normalized = []
    for line in lines:
        if line.startswith("          "):
            normalized.append(line[10:])
        else:
            raise SystemExit(f"editor heredoc line lost workflow indentation: {line!r}")
    return "\n".join(normalized) + "\n"


# The editor body was already reviewed in the RED/GREEN workflow. Extract it from
# that workflow verbatim so the temporary patch mechanism does not maintain a
# second copy of the QML.
write("config/quickshell/awtarchy/LockscreenEditor.qml", editor_from_workflow())

# Persist scale + editor visibility atomically while accepting legacy x/y-only
# layouts as scale=1.0.
state_path = "config/hypr/scripts/quickshell_application_state.sh"
state = read(state_path)
state = replace_once(
    state,
    "LOCKSCREEN_LAYOUT_DEFAULT_JSON='{\"logo\":{\"x\":0.5,\"y\":0.34},\"time\":{\"x\":0.5,\"y\":0.51},\"date\":{\"x\":0.5,\"y\":0.555},\"username\":{\"x\":0.5,\"y\":0.595},\"weather\":{\"x\":0.5,\"y\":0.635},\"password\":{\"x\":0.5,\"y\":0.7}}'",
    "LOCKSCREEN_LAYOUT_DEFAULT_JSON='{\"logo\":{\"x\":0.5,\"y\":0.34,\"scale\":1},\"time\":{\"x\":0.5,\"y\":0.51,\"scale\":1},\"date\":{\"x\":0.5,\"y\":0.555,\"scale\":1},\"username\":{\"x\":0.5,\"y\":0.595,\"scale\":1},\"weather\":{\"x\":0.5,\"y\":0.635,\"scale\":1},\"password\":{\"x\":0.5,\"y\":0.7,\"scale\":1}}'",
    "state layout defaults",
)
state = replace_once(
    state,
    "        lockscreen_audio_reactive|lockscreen_mouse_interactive|lockscreen_show_time|lockscreen_show_date|lockscreen_show_username|lockscreen_show_weather) ;;",
    "        lockscreen_audio_reactive|lockscreen_mouse_interactive|lockscreen_show_logo|lockscreen_show_time|lockscreen_show_date|lockscreen_show_username|lockscreen_show_weather) ;;",
    "state lockscreen option allowlist",
)
layout_functions = r'''normalize_lockscreen_layout_json() {
    local value="$1"
    jq -ce -n \
        --argjson candidate "$value" \
        --argjson keys "$LOCKSCREEN_LAYOUT_KEYS_JSON" '
        ($candidate | type) == "object"
        and (($candidate | keys | sort) == ($keys | sort))
        and all($keys[];
            . as $key
            | ($candidate[$key] | type) == "object"
            and ((($candidate[$key] | keys | sort) == ["x", "y"])
                or (($candidate[$key] | keys | sort) == ["scale", "x", "y"]))
            and ($candidate[$key].x | type) == "number"
            and ($candidate[$key].y | type) == "number"
            and (($candidate[$key] | has("scale") | not)
                or ($candidate[$key].scale | type) == "number")
            and (($candidate[$key].scale // 1) >= 0.50)
            and (($candidate[$key].scale // 1) <= 2.00)
            and (if $key == "password" then
                $candidate[$key].x >= 0.15 and $candidate[$key].x <= 0.85
                and $candidate[$key].y >= 0.20 and $candidate[$key].y <= 0.86
            else
                $candidate[$key].x >= 0.05 and $candidate[$key].x <= 0.95
                and $candidate[$key].y >= 0.08 and $candidate[$key].y <= 0.92
            end)
        )
        | reduce $keys[] as $key ({};
            .[$key] = {
                x: $candidate[$key].x,
                y: $candidate[$key].y,
                scale: ($candidate[$key].scale // 1)
            })
    '
}

validate_lockscreen_layout() {
    local normalized
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\n' >&2
        exit 2
    fi
}

save_lockscreen_layout() {
    local normalized
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\n' >&2
        exit 2
    fi
    new_tmp
    jq --argjson value "$normalized" '.lockscreen_layout = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

validate_lockscreen_editor_visibility() {
    local value="$1"
    if ! jq -e -n \
        --argjson candidate "$value" \
        --argjson keys "$LOCKSCREEN_LAYOUT_KEYS_JSON" '
        ($candidate | type) == "object"
        and (($candidate | keys | sort) == ($keys | sort))
        and all($keys[]; . as $key | ($candidate[$key] | type) == "boolean")
        and $candidate.password == true
    ' >/dev/null 2>&1; then
        printf 'invalid lockscreen editor visibility\n' >&2
        exit 2
    fi
}

save_lockscreen_editor() {
    local normalized visibility="$2"
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\n' >&2
        exit 2
    fi
    validate_lockscreen_editor_visibility "$visibility"
    new_tmp
    jq \
        --argjson layout "$normalized" \
        --argjson visibility "$visibility" '
        .lockscreen_layout = $layout
        | .lockscreen_show_logo = $visibility.logo
        | .lockscreen_show_time = $visibility.time
        | .lockscreen_show_date = $visibility.date
        | .lockscreen_show_username = $visibility.username
        | .lockscreen_show_weather = $visibility.weather
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
'''
state = replace_between(
    state,
    "validate_lockscreen_layout() {",
    "reset_lockscreen_presentation() {",
    layout_functions,
    "state layout functions",
)
state = replace_once(
    state,
    "        | .lockscreen_mouse_interactive = true\n        | .lockscreen_show_time = false\n",
    "        | .lockscreen_mouse_interactive = true\n        | .lockscreen_show_logo = true\n        | .lockscreen_show_time = false\n",
    "state reset logo visibility",
)
state = replace_once(
    state,
    "    set-lockscreen-show-time)\n        [[ -n ${2:-} ]] || exit 2\n        set_lockscreen_option lockscreen_show_time \"$2\" 'lockscreen show time'\n        ;;\n",
    "    set-lockscreen-show-logo)\n        [[ -n ${2:-} ]] || exit 2\n        set_lockscreen_option lockscreen_show_logo \"$2\" 'lockscreen show logo'\n        ;;\n    set-lockscreen-show-time)\n        [[ -n ${2:-} ]] || exit 2\n        set_lockscreen_option lockscreen_show_time \"$2\" 'lockscreen show time'\n        ;;\n",
    "state show-logo command",
)
state = replace_once(
    state,
    "    save-lockscreen-layout)\n        [[ -n ${2:-} ]] || exit 2\n        save_lockscreen_layout \"$2\"\n        ;;\n    reset-lockscreen-presentation)\n",
    "    save-lockscreen-layout)\n        [[ -n ${2:-} ]] || exit 2\n        save_lockscreen_layout \"$2\"\n        ;;\n    save-lockscreen-editor)\n        [[ $# -eq 3 ]] || exit 2\n        save_lockscreen_editor \"$2\" \"$3\"\n        ;;\n    reset-lockscreen-presentation)\n",
    "state atomic editor command",
)
state = replace_once(
    state,
    "set-lockscreen-mouse-interactive <true|false>|set-lockscreen-show-time",
    "set-lockscreen-mouse-interactive <true|false>|set-lockscreen-show-logo <true|false>|set-lockscreen-show-time",
    "state usage show-logo",
)
state = replace_once(
    state,
    "save-lockscreen-layout <json>|reset-lockscreen-presentation",
    "save-lockscreen-layout <json>|save-lockscreen-editor <layout_json> <visibility_json>|reset-lockscreen-presentation",
    "state usage atomic editor",
)
write(state_path, state)

# BarState normalizes the new schema while treating old saved points as scale=1.
bar_path = "config/quickshell/awtarchy/BarState.qml"
bar = read(bar_path)
bar = replace_once(
    bar,
    '''    readonly property var defaultLockscreenLayout: ({
        logo: ({ x: 0.50, y: 0.34 }),
        time: ({ x: 0.50, y: 0.51 }),
        date: ({ x: 0.50, y: 0.555 }),
        username: ({ x: 0.50, y: 0.595 }),
        weather: ({ x: 0.50, y: 0.635 }),
        password: ({ x: 0.50, y: 0.70 })
    })
''',
    '''    readonly property var defaultLockscreenLayout: ({
        logo: ({ x: 0.50, y: 0.34, scale: 1.0 }),
        time: ({ x: 0.50, y: 0.51, scale: 1.0 }),
        date: ({ x: 0.50, y: 0.555, scale: 1.0 }),
        username: ({ x: 0.50, y: 0.595, scale: 1.0 }),
        weather: ({ x: 0.50, y: 0.635, scale: 1.0 }),
        password: ({ x: 0.50, y: 0.70, scale: 1.0 })
    })
''',
    "BarState layout defaults",
)
bar = replace_once(
    bar,
    "            lockscreen_mouse_interactive: true,\n            lockscreen_show_time: false,\n",
    "            lockscreen_mouse_interactive: true,\n            lockscreen_show_logo: true,\n            lockscreen_show_time: false,\n",
    "BarState logo default",
)
bar = replace_once(
    bar,
    '''    function lockscreenShowTime() {
        return lockscreenBooleanPreference("lockscreen_show_time", false);
    }
''',
    '''    function lockscreenShowLogo() {
        return lockscreenBooleanPreference("lockscreen_show_logo", true);
    }

    function lockscreenShowTime() {
        return lockscreenBooleanPreference("lockscreen_show_time", false);
    }
''',
    "BarState logo reader",
)
bar_layout_point = '''    function lockscreenLayoutPoint(value, fallback, password) {
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
'''
bar = replace_between(
    bar,
    "    function lockscreenLayoutPoint(value, fallback, password) {",
    "    function lockscreenLayout() {",
    bar_layout_point,
    "BarState layout point",
)
write(bar_path, bar)

# Secure lock root gets the same schema and explicit logo visibility, without
# changing lock or PAM ownership.
lock_shell_path = "config/quickshell/awtarchy-lock/shell.qml"
lock_shell = read(lock_shell_path)
lock_shell = replace_once(
    lock_shell,
    "    property bool lockMouseInteractive: true\n    property bool lockShowTime: false\n",
    "    property bool lockMouseInteractive: true\n    property bool lockShowLogo: true\n    property bool lockShowTime: false\n",
    "lock shell logo property",
)
lock_shell = replace_once(
    lock_shell,
    '''        return ({
            logo: ({ x: 0.50, y: 0.34 }),
            time: ({ x: 0.50, y: 0.51 }),
            date: ({ x: 0.50, y: 0.555 }),
            username: ({ x: 0.50, y: 0.595 }),
            weather: ({ x: 0.50, y: 0.635 }),
            password: ({ x: 0.50, y: 0.70 })
        });
''',
    '''        return ({
            logo: ({ x: 0.50, y: 0.34, scale: 1.0 }),
            time: ({ x: 0.50, y: 0.51, scale: 1.0 }),
            date: ({ x: 0.50, y: 0.555, scale: 1.0 }),
            username: ({ x: 0.50, y: 0.595, scale: 1.0 }),
            weather: ({ x: 0.50, y: 0.635, scale: 1.0 }),
            password: ({ x: 0.50, y: 0.70, scale: 1.0 })
        });
''',
    "lock shell layout defaults",
)
lock_layout_point = '''    function layoutPoint(value, fallback, password) {
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
'''
lock_shell = replace_between(
    lock_shell,
    "    function layoutPoint(value, fallback, password) {",
    "    function normalizedLayout(value) {",
    lock_layout_point,
    "lock shell layout point",
)
lock_shell = replace_once(
    lock_shell,
    "        lockMouseInteractive = true;\n        lockShowTime = false;\n",
    "        lockMouseInteractive = true;\n        lockShowLogo = true;\n        lockShowTime = false;\n",
    "lock shell reset logo",
)
lock_shell = replace_once(
    lock_shell,
    "            lockMouseInteractive = normalizedBoolean(parsed.lockscreen_mouse_interactive, true);\n            lockShowTime = normalizedBoolean(parsed.lockscreen_show_time, false);\n",
    "            lockMouseInteractive = normalizedBoolean(parsed.lockscreen_mouse_interactive, true);\n            lockShowLogo = normalizedBoolean(parsed.lockscreen_show_logo, true);\n            lockShowTime = normalizedBoolean(parsed.lockscreen_show_time, false);\n",
    "lock shell load logo",
)
lock_shell = replace_once(
    lock_shell,
    "                mouseInteractive: root.lockMouseInteractive\n                showTime: root.lockShowTime\n",
    "                mouseInteractive: root.lockMouseInteractive\n                showLogo: root.lockShowLogo\n                showTime: root.lockShowTime\n",
    "lock shell surface logo",
)
write(lock_shell_path, lock_shell)

# Secure surface continues to own the real password input. Only its visual
# geometry consumes the saved scale.
surface_path = "config/quickshell/awtarchy-lock/LockSurface.qml"
surface = read(surface_path)
surface = replace_once(
    surface,
    "    required property bool mouseInteractive\n    required property bool showTime\n",
    "    required property bool mouseInteractive\n    required property bool showLogo\n    required property bool showTime\n",
    "surface logo property",
)
surface = replace_once(
    surface,
    "        mouseInteractive: root.mouseInteractive\n        showTime: root.showTime\n",
    "        mouseInteractive: root.mouseInteractive\n        showLogo: root.showLogo\n        showTime: root.showTime\n",
    "surface scene logo",
)
surface = replace_once(
    surface,
    "    readonly property real uiScale: scene.uiScale\n",
    "    readonly property real uiScale: scene.uiScale\n    readonly property real passwordScale: scene.elementScale(\"password\")\n",
    "surface password scale",
)
surface = replace_once(surface, "Math.round((24 + maskedCount * 14) * uiScale)", "Math.round((24 + maskedCount * 14) * uiScale * passwordScale)", "surface mask spread")
surface = replace_once(surface, "height: Math.round(14 * root.uiScale)", "height: Math.round(14 * root.uiScale * root.passwordScale)", "surface mask height")
surface = replace_once(surface, "spacing: Math.round(7 * root.uiScale)", "spacing: Math.round(7 * root.uiScale * root.passwordScale)", "surface password spacing")
surface = replace_once(surface, "width: Math.round(7 * root.uiScale)", "width: Math.round(7 * root.uiScale * root.passwordScale)", "surface password dot width")
surface = replace_once(surface, "height: Math.round(10 * root.uiScale)", "height: Math.round(10 * root.uiScale * root.passwordScale)", "surface password dot height")
surface = replace_once(surface, "font.pixelSize: Math.round(18 * root.uiScale)", "font.pixelSize: Math.round(18 * root.uiScale * root.passwordScale)", "surface input font")
write(surface_path, surface)

# Shared presentation scene is the one implementation used by preview and lock.
scene_path = "config/quickshell/awtarchy-lock/LockScene.qml"
scene = read(scene_path)
scene = replace_once(
    scene,
    "    required property bool mouseInteractive\n    required property bool showTime\n",
    "    required property bool mouseInteractive\n    required property bool showLogo\n    required property bool showTime\n",
    "scene logo property",
)
scene = replace_once(
    scene,
    '''    readonly property real passwordCenterX: normalizedX("password", 0.50) * width
    readonly property real passwordCenterY: normalizedY("password", 0.70) * height
    readonly property real passwordWidth: Math.round(320 * uiScale)
    readonly property real passwordHeight: Math.round(42 * uiScale)
''',
    '''    readonly property real passwordCenterX: normalizedX("password", 0.50) * width
    readonly property real passwordCenterY: normalizedY("password", 0.70) * height
    readonly property real passwordWidth: Math.round(320 * uiScale * elementScale("password"))
    readonly property real passwordHeight: Math.round(42 * uiScale * elementScale("password"))
''',
    "scene password scale",
)
scene = replace_once(
    scene,
    '''    function normalizedY(name, fallback) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.y) : Number.NaN;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
    }
''',
    '''    function normalizedY(name, fallback) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.y) : Number.NaN;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
    }

    function elementScale(name) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.scale === undefined ? 1 : point.scale) : 1;
        return Number.isFinite(value) ? Math.max(0.50, Math.min(2.00, value)) : 1;
    }
''',
    "scene element scale reader",
)
scene = replace_once(
    scene,
    '''    function updateClockText() {
        const now = new Date();
        timeText = Qt.formatTime(now, Locale.ShortFormat);
        dateText = Qt.formatDate(now, Locale.LongFormat);
    }
''',
    r'''    function minuteTimeFormat() {
        const localeFormat = String(Qt.locale().timeFormat(Locale.ShortFormat) || "");
        const withoutSeconds = localeFormat
            .replace(/([:.\-\s])s{1,2}(?:\.z{1,3})?/g, "")
            .replace(/s{1,2}([:.\-\s])/g, "")
            .replace(/z{1,3}/g, "")
            .replace(/\s{2,}/g, " ")
            .trim();
        return withoutSeconds.length > 0 ? withoutSeconds : "HH:mm";
    }

    function updateClockText() {
        const now = new Date();
        timeText = Qt.formatTime(now, minuteTimeFormat());
        dateText = Qt.formatDate(now, Locale.LongFormat);
    }
''',
    "scene minute-only time",
)
wordmark_anchor = "            id: wordmarkItem\n"
scene = replace_once(scene, wordmark_anchor, wordmark_anchor + "            visible: root.showLogo\n", "scene logo visibility")
wordmark_pos = scene.find(wordmark_anchor)
wordmark_height = "            height: root.wordmarkHeight\n"
height_pos = scene.find(wordmark_height, wordmark_pos)
if height_pos < 0:
    raise SystemExit("scene logo scale: wordmark height target not found")
height_end = height_pos + len(wordmark_height)
scene = scene[:height_end] + "            scale: root.elementScale(\"logo\")\n            transformOrigin: Item.Center\n" + scene[height_end:]
for name, visible_line in (
    ("time", "            visible: root.showTime\n"),
    ("date", "            visible: root.showDate\n"),
    ("username", "            visible: root.showUsername\n"),
    ("weather", "            visible: root.showWeather && root.weatherText.length > 0\n"),
):
    scene = replace_once(
        scene,
        visible_line,
        visible_line + f'            scale: root.elementScale("{name}")\n            transformOrigin: Item.Center\n',
        f"scene {name} scale",
    )
scene = replace_once(scene, "width: Math.round(80 * root.uiScale)", "width: Math.round(80 * root.uiScale * root.elementScale(\"password\"))", "scene preview mask width")
scene = replace_once(scene, "height: Math.round(14 * root.uiScale)", "height: Math.round(14 * root.uiScale * root.elementScale(\"password\"))", "scene preview mask height")
scene = replace_once(scene, "spacing: Math.round(7 * root.uiScale)", "spacing: Math.round(7 * root.uiScale * root.elementScale(\"password\"))", "scene preview spacing")
scene = replace_once(scene, "width: Math.round(7 * root.uiScale)", "width: Math.round(7 * root.uiScale * root.elementScale(\"password\"))", "scene preview dot width")
scene = replace_once(scene, "height: Math.round(10 * root.uiScale)", "height: Math.round(10 * root.uiScale * root.elementScale(\"password\"))", "scene preview dot height")
write(scene_path, scene)

print("live editor production patch applied")
