from pathlib import Path
import hashlib

ROOT = Path.cwd()
STATE_SCRIPT = ROOT / "config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE = ROOT / "config/quickshell/awtarchy/BarState.qml"
BAR = ROOT / "config/quickshell/awtarchy/Bar.qml"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


state = STATE_SCRIPT.read_text()
state = replace_once(
    state,
    '''set_update_notifications() {
    local enabled
    enabled="$(parse_bool "$1" 'update notifications')"
    new_tmp
    jq --argjson enabled "$enabled" \\
        '.update_notifications_enabled = $enabled' \\
        "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_capture() {''',
    '''set_update_notifications() {
    local enabled
    enabled="$(parse_bool "$1" 'update notifications')"
    new_tmp
    jq --argjson enabled "$enabled" \\
        '.update_notifications_enabled = $enabled' \\
        "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_clock_date() {
    local monitor="$1" value="$2" clock_date
    [[ -n "$monitor" ]] || { printf 'monitor is required\\n' >&2; exit 2; }
    clock_date="$(parse_bool "$value" 'clock date')"
    new_tmp
    jq \\
        --arg monitor "$monitor" \\
        --argjson clock_date "$clock_date" '
        .monitors = (if (.monitors | type) == "object" then .monitors else {} end)
        | .monitors[$monitor] = ((if (.monitors[$monitor] | type) == "object"
            then .monitors[$monitor] else {} end) + {clock_date:$clock_date})
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_capture() {''',
    "state writer function insertion",
)
state = replace_once(
    state,
    '''    set-update-notifications)
        [[ -n ${2:-} ]] || exit 2
        set_update_notifications "$2"
        ;;
    set-notification-popup-limit)''',
    '''    set-update-notifications)
        [[ -n ${2:-} ]] || exit 2
        set_update_notifications "$2"
        ;;
    set-clock-date)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_clock_date "$2" "$3"
        ;;
    set-notification-popup-limit)''',
    "state writer dispatch insertion",
)
state = replace_once(
    state,
    '|set-update-notifications <true|false>|set-notification-popup-limit',
    '|set-update-notifications <true|false>|set-clock-date <MON> <true|false>|set-notification-popup-limit',
    "state writer usage insertion",
)
STATE_SCRIPT.write_text(state)

bar_state = BAR_STATE.read_text()
bar_state = replace_once(
    bar_state,
    '''    function positionFor(name) {
        const dependency = revision;
        if (livePositions[name] !== undefined)
            return livePositions[name];
        const mon = monitorState(name);
        const pos = mon.position || "top";
        return ["top", "bottom", "left", "right"].indexOf(pos) >= 0 ? pos : "top";
    }

    function barSizeFor(name, vertical) {''',
    '''    function positionFor(name) {
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

    function barSizeFor(name, vertical) {''',
    "BarState clock/date getter insertion",
)
BAR_STATE.write_text(bar_state)

bar = BAR.read_text()
bar = replace_once(
    bar,
    '    property bool clockDate: false\n',
    '    property bool clockDate: BarState.clockDateFor(monitorName)\n    property bool clockDatePersistPending: false\n',
    "Bar clock/date initial state",
)
bar = replace_once(
    bar,
    '    readonly property string ddcScript: configHome + "/hypr/scripts/ddc_brightness.sh"\n',
    '    readonly property string ddcScript: configHome + "/hypr/scripts/ddc_brightness.sh"\n    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"\n',
    "Bar state writer path",
)
bar = replace_once(
    bar,
    '''    function clockTooltip() {
        const base = Qt.formatDateTime(now, "dddd, MMMM d, yyyy")
            + "\\n24h: " + Qt.formatDateTime(now, "HH:mm")
            + "\\n12h: " + Qt.formatDateTime(now, "h:mm AP");
        return clockDate ? base + "\\n\\n" + calendarText(now) : base;
    }

    PwObjectTracker {''',
    '''    function clockTooltip() {
        const base = Qt.formatDateTime(now, "dddd, MMMM d, yyyy")
            + "\\n24h: " + Qt.formatDateTime(now, "HH:mm")
            + "\\n12h: " + Qt.formatDateTime(now, "h:mm AP");
        return clockDate ? base + "\\n\\n" + calendarText(now) : base;
    }

    function persistClockDate() {
        if (clockDateWriter.running) {
            clockDatePersistPending = true;
            return;
        }
        clockDatePersistPending = false;
        clockDateWriter.exec([stateScript, "set-clock-date", monitorName, clockDate ? "true" : "false"]);
    }

    function toggleClockDate() {
        clockDate = !clockDate;
        persistClockDate();
    }

    PwObjectTracker {''',
    "Bar toggle functions",
)
bar = replace_once(
    bar,
    '''    Process {
        id: ddcWatch
        running: bar.visible
        command: [bar.ddcScript, "watch"]
        environment: ({ AWTARCHY_OUTPUT_NAME: bar.monitorName })
        stdout: SplitParser {
            onRead: line => bar.parseBrightness(line)
        }
    }

    Timer {''',
    '''    Process {
        id: ddcWatch
        running: bar.visible
        command: [bar.ddcScript, "watch"]
        environment: ({ AWTARCHY_OUTPUT_NAME: bar.monitorName })
        stdout: SplitParser {
            onRead: line => bar.parseBrightness(line)
        }
    }

    Process {
        id: clockDateWriter
        onExited: {
            BarState.refresh();
            if (bar.clockDatePersistPending)
                bar.persistClockDate();
        }
    }

    Timer {''',
    "Bar clock/date writer process",
)
for old, new, expected in [
    ('onClicked: bar.clockDate = !bar.clockDate', 'onClicked: bar.toggleClockDate()', 2),
    ('onRightClicked: bar.clockDate = !bar.clockDate', 'onRightClicked: bar.toggleClockDate()', 2),
    ('onWheelUp: bar.clockDate = !bar.clockDate', 'onWheelUp: bar.toggleClockDate()', 2),
    ('onWheelDown: bar.clockDate = !bar.clockDate', 'onWheelDown: bar.toggleClockDate()', 2),
]:
    count = bar.count(old)
    if count != expected:
        raise SystemExit(f"Bar handler replacement {old!r}: expected {expected}, found {count}")
    bar = bar.replace(old, new)
BAR.write_text(bar)

# Ensure the focused regression is green before recording updater hashes.
# The workflow runs the test after this script; this section only records final bytes.
entries = []
for rel in [
    "config/hypr/scripts/quickshell_application_state.sh",
    "config/quickshell/awtarchy/Bar.qml",
    "config/quickshell/awtarchy/BarState.qml",
]:
    digest = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
    entries.append(f"{digest}\t.{rel[len('config'):] if rel.startswith('config/') else '/' + rel}")

# Convert repository paths to installed managed paths explicitly.
installed = [
    ("config/hypr/scripts/quickshell_application_state.sh", ".config/hypr/scripts/quickshell_application_state.sh"),
    ("config/quickshell/awtarchy/Bar.qml", ".config/quickshell/awtarchy/Bar.qml"),
    ("config/quickshell/awtarchy/BarState.qml", ".config/quickshell/awtarchy/BarState.qml"),
]
lines = ["", "# 2026-08-27 per-display clock/date state persistence."]
for rel, managed in installed:
    digest = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
    lines.append(f"{digest}\t{managed}")
append = "\n".join(lines) + "\n"
history = HISTORY.read_text()
marker = "# 2026-08-27 per-display clock/date state persistence."
if marker in history:
    raise SystemExit("managed-history marker already exists")
HISTORY.write_text(history.rstrip("\n") + append)
