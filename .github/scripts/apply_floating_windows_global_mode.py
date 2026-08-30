#!/usr/bin/env python3
from pathlib import Path
import hashlib

HELPER = Path("config/hypr/scripts/quickshell_floating_windows.sh")
HYPR = Path("config/hypr/hyprland.lua")
BAR = Path("config/quickshell/awtarchy/Bar.qml")
CARD = Path("config/quickshell/awtarchy/FloatingWindowsCard.qml")
STATE = Path("config/quickshell/awtarchy/FloatingWindowsState.qml")
HISTORY = Path("local/share/awtarchy/quickshell-managed-history.sha256")
DESIGN = Path("docs/superpowers/plans/2026-08-30-floating-spawn-mode-design.md")
PLAN = Path("docs/superpowers/plans/2026-08-30-floating-spawn-mode.md")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


helper = r'''#!/usr/bin/env bash
set -Eeuo pipefail

HYPR_LUA="${HYPRLAND_LUA:-${XDG_CONFIG_HOME:-${HOME}/.config}/hypr/hyprland.lua}"
HYPRCTL="${HYPRCTL:-hyprctl}"
STATE_FILE="${AWTARCHY_FLOATING_STATE_FILE:-${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}}/awtarchy-floating-windows-state}"
NOTIFY_SEND="${NOTIFY_SEND:-notify-send}"
MARKER_RE='^[[:space:]]*local awtarchy_floating_windows = (true|false) -- AWTARCHY_FLOATING_WINDOWS[[:space:]]*$'
GLOBAL_FLOAT='hl.window_rule({ match = { class = ".*" }, float = true })'
GAME_TILE='hl.window_rule({ match = { class = games }, tile = true })'
GAMES_ANCHOR_RE='^[[:space:]]*local games = '

die() {
    printf 'Floating Windows: %s\n' "$*" >&2
    exit 1
}

publish_state() {
    local state="$1" directory
    directory="$(dirname -- "$STATE_FILE")"
    mkdir -p -- "$directory" 2>/dev/null || return 0
    printf '%s\n' "$state" >"$STATE_FILE" 2>/dev/null || true
}

notify_state() {
    local state="$1"
    if [[ -x "$NOTIFY_SEND" ]] || command -v "$NOTIFY_SEND" >/dev/null 2>&1; then
        "$NOTIFY_SEND" -a Awtarchy -t 1500 "Floating windows" "$state" >/dev/null 2>&1 || true
    fi
}

emit_state() {
    local state="$1" notify="${2:-0}"
    publish_state "$state"
    if [[ "$notify" == 1 ]]; then
        notify_state "$state"
    fi
    printf '%s\n' "$state"
}

marker_count() {
    grep -Ec "$MARKER_RE" "$HYPR_LUA" || true
}

legacy_config_is_bootstrappable() {
    local marker global_float game_tile games_anchor
    marker="$(marker_count)"
    [[ "$marker" == "0" ]] || return 1

    global_float="$(grep -Fc "$GLOBAL_FLOAT" "$HYPR_LUA" || true)"
    game_tile="$(grep -Fc "$GAME_TILE" "$HYPR_LUA" || true)"
    games_anchor="$(grep -Ec "$GAMES_ANCHOR_RE" "$HYPR_LUA" || true)"

    [[ "$global_float" == "0" && "$game_tile" == "0" && "$games_anchor" == "1" ]]
}

current_state() {
    [[ -r "$HYPR_LUA" ]] || die "cannot read $HYPR_LUA"

    local count line
    count="$(marker_count)"
    case "$count" in
        0)
            if legacy_config_is_bootstrappable; then
                printf '%s\n' 'disabled'
                return 0
            fi
            die "Floating Windows is not initialized safely in $HYPR_LUA"
            ;;
        1)
            line="$(grep -E "$MARKER_RE" "$HYPR_LUA")"
            case "$line" in
                *'= true -- AWTARCHY_FLOATING_WINDOWS') printf '%s\n' 'enabled' ;;
                *'= false -- AWTARCHY_FLOATING_WINDOWS') printf '%s\n' 'disabled' ;;
                *) die 'could not parse Floating Windows state' ;;
            esac
            ;;
        *)
            die "expected at most one AWTARCHY_FLOATING_WINDOWS setting in $HYPR_LUA"
            ;;
    esac
}

rollback_config() {
    local backup="$1"
    cp -p -- "$backup" "$HYPR_LUA"
    "$HYPRCTL" reload >/dev/null 2>&1 || true
}

set_state() {
    local requested="$1"
    local target current pre_errors post_errors backup

    case "$requested" in
        on|enabled|true) target='true' ;;
        off|disabled|false) target='false' ;;
        *) die "invalid state '$requested' (expected on or off)" ;;
    esac

    current="$(current_state)"
    if [[ ( "$target" == 'true' && "$current" == 'enabled' ) \
        || ( "$target" == 'false' && "$current" == 'disabled' ) ]]; then
        printf '%s\n' "$current"
        return 0
    fi

    [[ -w "$HYPR_LUA" ]] || die "cannot write $HYPR_LUA"

    if ! pre_errors="$("$HYPRCTL" configerrors 2>&1)"; then
        die 'could not query current Hyprland config errors'
    fi
    if [[ -n "$pre_errors" ]]; then
        die "refusing to edit while Hyprland already reports config errors: $pre_errors"
    fi

    backup="$(mktemp --tmpdir="$(dirname -- "$HYPR_LUA")" '.awtarchy-floating-windows.backup.XXXXXX')"
    cp -p -- "$HYPR_LUA" "$backup"

    if ! python3 - "$HYPR_LUA" "$target" <<'PY'
import os
import re
import stat
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
target = sys.argv[2].encode()
data = path.read_bytes()
marker_pattern = re.compile(
    rb'(?m)^([ \t]*local awtarchy_floating_windows = )(true|false)( -- AWTARCHY_FLOATING_WINDOWS[ \t]*)$'
)
marker_matches = list(marker_pattern.finditer(data))

if len(marker_matches) == 1:
    replacement = rb'\g<1>' + target + rb'\g<3>'
    updated, count = marker_pattern.subn(replacement, data)
    if count != 1:
        raise SystemExit('expected exactly one AWTARCHY_FLOATING_WINDOWS setting')
elif len(marker_matches) == 0:
    if target != b'true':
        raise SystemExit('uninitialized Floating Windows config may only be bootstrapped while enabling')

    global_float = b'hl.window_rule({ match = { class = ".*" }, float = true })'
    game_tile = b'hl.window_rule({ match = { class = games }, tile = true })'
    if global_float in data or game_tile in data:
        raise SystemExit('refusing to bootstrap around partial Floating Windows rules')

    games_pattern = re.compile(rb'(?m)^([ \t]*local games = .*\n)')
    games_matches = list(games_pattern.finditer(data))
    if len(games_matches) != 1:
        raise SystemExit('expected exactly one games rule anchor for Floating Windows bootstrap')

    match = games_matches[0]
    games_line = match.group(1)
    block = (
        b'local awtarchy_floating_windows = true -- AWTARCHY_FLOATING_WINDOWS\n\n'
        + games_line
        + b'\n'
        + b'if awtarchy_floating_windows then\n'
        + b'    hl.window_rule({ match = { class = ".*" }, float = true })\n'
        + b'    hl.window_rule({ match = { class = games }, tile = true })\n'
        + b'end\n'
    )
    updated = data[:match.start()] + block + data[match.end():]
else:
    raise SystemExit('expected at most one AWTARCHY_FLOATING_WINDOWS setting')

mode = stat.S_IMODE(path.stat().st_mode)
with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.awtarchy-floating-windows.', delete=False) as handle:
    temp_path = Path(handle.name)
    handle.write(updated)
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temp_path, mode)
os.replace(temp_path, path)
PY
    then
        rm -f -- "$backup"
        die 'failed to update hyprland.lua'
    fi

    if ! "$HYPRCTL" reload >/dev/null 2>&1; then
        rollback_config "$backup"
        rm -f -- "$backup"
        die 'Hyprland reload failed; restored the previous configuration'
    fi

    if ! post_errors="$("$HYPRCTL" configerrors 2>&1)"; then
        rollback_config "$backup"
        rm -f -- "$backup"
        die 'could not validate Hyprland after reload; restored the previous configuration'
    fi
    if [[ -n "$post_errors" ]]; then
        rollback_config "$backup"
        rm -f -- "$backup"
        die "Hyprland reported config errors after reload; restored the previous configuration: $post_errors"
    fi

    rm -f -- "$backup"
    current_state
}

notify=0
case "${1:-}" in
    status)
        [[ $# -eq 1 ]] || die 'usage: quickshell_floating_windows.sh status'
        emit_state "$(current_state)" 0
        ;;
    set)
        if [[ $# -eq 3 && "${3:-}" == '--notify' ]]; then
            notify=1
        elif [[ $# -ne 2 ]]; then
            die 'usage: quickshell_floating_windows.sh set on|off [--notify]'
        fi
        emit_state "$(set_state "$2")" "$notify"
        ;;
    toggle)
        if [[ $# -eq 2 && "${2:-}" == '--notify' ]]; then
            notify=1
        elif [[ $# -ne 1 ]]; then
            die 'usage: quickshell_floating_windows.sh toggle [--notify]'
        fi
        if [[ "$(current_state)" == 'enabled' ]]; then
            emit_state "$(set_state off)" "$notify"
        else
            emit_state "$(set_state on)" "$notify"
        fi
        ;;
    *)
        die 'usage: quickshell_floating_windows.sh status | set on|off [--notify] | toggle [--notify]'
        ;;
esac
'''
HELPER.write_text(helper)

state_qml = r'''pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string state: "checking"
    property string message: ""
    property string errorMessage: ""

    readonly property bool enabled: state === "enabled"
    readonly property bool available: state === "enabled" || state === "disabled"
    readonly property bool busy: statusRunner.running || actionRunner.running
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string runtimeHome: Quickshell.env("XDG_RUNTIME_DIR")
        || Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")
    readonly property string helper: configHome + "/hypr/scripts/quickshell_floating_windows.sh"
    readonly property string statePath: Quickshell.env("AWTARCHY_FLOATING_STATE_FILE")
        || (runtimeHome + "/awtarchy-floating-windows-state")

    function acceptState(value) {
        const next = String(value || "").trim();
        if (next !== "enabled" && next !== "disabled")
            return false;
        state = next;
        return true;
    }

    function syncFromRuntimeFile() {
        acceptState(stateFile.text());
    }

    function clearFeedback() {
        message = "";
        errorMessage = "";
    }

    function refresh() {
        if (busy)
            return;
        errorMessage = "";
        statusRunner.exec([helper, "status"]);
    }

    function setEnabled(enabled) {
        if (busy)
            return;
        if (available && root.enabled === Boolean(enabled))
            return;
        errorMessage = "";
        message = enabled
            ? "Making new windows float by default…"
            : "Restoring tiled windows as the default…";
        actionRunner.exec([helper, "set", enabled ? "on" : "off"]);
    }

    function toggle() {
        if (!available) {
            refresh();
            return;
        }
        setEnabled(!enabled);
    }

    Component.onCompleted: Qt.callLater(root.refresh)

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: false
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.syncFromRuntimeFile()
    }

    Process {
        id: statusRunner
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.acceptState(text))
                    root.state = "unavailable";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const detail = text.trim();
                if (detail.length > 0)
                    root.errorMessage = detail.split("\n")[0];
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.state = "unavailable";
        }
    }

    Process {
        id: actionRunner
        stdout: StdioCollector {
            onStreamFinished: root.acceptState(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const detail = text.trim();
                if (detail.length > 0)
                    root.errorMessage = detail.split("\n")[0];
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.errorMessage = "";
                root.message = root.enabled
                    ? "Floating Windows enabled."
                    : "Floating Windows disabled.";
            } else {
                root.message = "";
                if (root.errorMessage.length === 0)
                    root.errorMessage = "Could not update the Floating Windows preference.";
            }
        }
    }
}
'''
STATE.write_text(state_qml)

card_qml = r'''import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100

    readonly property string floatingState: FloatingWindowsState.state
    readonly property bool operationBusy: FloatingWindowsState.busy

    Layout.fillWidth: true
    Layout.preferredHeight: content.implicitHeight + 16
    color: Theme.popupButton
    border.width: 1
    border.color: Theme.active

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * textScale / 100));
    }

    function statusLabel() {
        if (floatingState === "enabled")
            return "Enabled";
        if (floatingState === "disabled")
            return "Disabled";
        if (floatingState === "unavailable")
            return "Unavailable";
        return "Checking…";
    }

    function requestToggle() {
        FloatingWindowsState.toggle();
    }

    onActiveChanged: {
        if (!active)
            return;
        FloatingWindowsState.clearFeedback();
        if (!FloatingWindowsState.available)
            Qt.callLater(() => FloatingWindowsState.refresh());
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Window Behavior"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(12)
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "Floating Windows"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                }
            }

            Text {
                text: root.statusLabel()
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
            }

            SettingsButton {
                label: root.floatingState === "enabled" ? "Disable" : "Enable"
                active: root.floatingState === "enabled"
                textSize: root.scaledText(9)
                enabled: FloatingWindowsState.available && !root.operationBusy
                onClicked: root.requestToggle()
            }
        }

        Text {
            Layout.fillWidth: true
            text: FloatingWindowsState.errorMessage.length > 0
                ? FloatingWindowsState.errorMessage
                : (FloatingWindowsState.message.length > 0
                    ? FloatingWindowsState.message
                    : (root.floatingState === "enabled"
                        ? "New windows open floating by default. Existing windows keep their current state. Use SUPER+ALT+F to disable this mode or SUPER+F to tile/float the focused window."
                        : "New windows use Awtarchy's normal tiling behavior. Existing windows keep their current state. Use SUPER+ALT+F to toggle floating-spawn mode."))
            color: FloatingWindowsState.errorMessage.length > 0 ? Theme.urgent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
'''
CARD.write_text(card_qml)

hypr = HYPR.read_text()
hypr = replace_once(
    hypr,
    'local toggle_animations = "~/.config/hypr/scripts/toggle_animations.sh"\n',
    'local toggle_animations = "~/.config/hypr/scripts/toggle_animations.sh"\n'
    'local floating_windows_toggle = "~/.config/hypr/scripts/quickshell_floating_windows.sh toggle --notify"\n',
    "floating toggle command",
)
old_toggle = '    { "SUPER + A", toggle_animations },\n'
count = hypr.count(old_toggle)
if count != 2:
    raise SystemExit(f"floating bind contexts: expected two UI toggle arrays, found {count}")
hypr = hypr.replace(
    old_toggle,
    old_toggle + '    { "SUPER + ALT + F", floating_windows_toggle },\n',
)
HYPR.write_text(hypr)

bar = BAR.read_text()
horizontal_anchor = '''            BarControl {
                visible: submapFile.text().trim().length > 0
                label: submapFile.text().trim()
                tooltip: "Current submap: " + submapFile.text().trim() + " (click to reset)"
                onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
                onRightClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
            }

            BarControl {
                visible: bar.privacyLabel().length > 0
'''
horizontal_replacement = '''            BarControl {
                visible: submapFile.text().trim().length > 0
                label: submapFile.text().trim()
                tooltip: "Current submap: " + submapFile.text().trim() + " (click to reset)"
                onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
                onRightClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
            }

            BarControl {
                visible: FloatingWindowsState.enabled
                label: "Floating"
                tooltip: "New windows open floating by default\\nClick to restore normal tiling"
                normalBackground: Theme.subtleActive
                hoverBackground: Theme.strongHover
                onClicked: FloatingWindowsState.setEnabled(false)
                onRightClicked: FloatingWindowsState.setEnabled(false)
            }

            BarControl {
                visible: bar.privacyLabel().length > 0
'''
bar = replace_once(bar, horizontal_anchor, horizontal_replacement, "horizontal Floating indicator")
vertical_anchor = '''            BarControl {
                visible: submapFile.text().trim().length > 0
                vertical: true; fixedWidth: bar.barSize
                label: submapFile.text().trim()
                tooltip: "Current submap: " + submapFile.text().trim() + " (click to reset)"
                onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
            }
        }

        Column {
'''
vertical_replacement = '''            BarControl {
                visible: submapFile.text().trim().length > 0
                vertical: true; fixedWidth: bar.barSize
                label: submapFile.text().trim()
                tooltip: "Current submap: " + submapFile.text().trim() + " (click to reset)"
                onClicked: Quickshell.execDetached([bar.mouseSubmapScript, "reset"])
            }

            BarControl {
                visible: FloatingWindowsState.enabled
                vertical: true; fixedWidth: bar.barSize
                label: "Float"
                fontPixelSize: 9
                tooltip: "New windows open floating by default\\nClick to restore normal tiling"
                normalBackground: Theme.subtleActive
                hoverBackground: Theme.strongHover
                onClicked: FloatingWindowsState.setEnabled(false)
                onRightClicked: FloatingWindowsState.setEnabled(false)
            }
        }

        Column {
'''
bar = replace_once(bar, vertical_anchor, vertical_replacement, "vertical Floating indicator")
BAR.write_text(bar)

# Keep the implementation notes accurate: the runtime file is deliberately
# overwritten in place so FileView/inotify remains attached across toggles.
for path in (DESIGN, PLAN):
    text = path.read_text()
    text = text.replace("atomically writes exactly `enabled` or `disabled` plus a newline", "writes exactly `enabled` or `disabled` plus a newline")
    path.write_text(text)

history = HISTORY.read_text()
for path, managed in (
    (HELPER, ".config/hypr/scripts/quickshell_floating_windows.sh"),
    (BAR, ".config/quickshell/awtarchy/Bar.qml"),
    (CARD, ".config/quickshell/awtarchy/FloatingWindowsCard.qml"),
    (STATE, ".config/quickshell/awtarchy/FloatingWindowsState.qml"),
):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    entry = f"{digest}\t{managed}"
    if entry not in history.splitlines():
        if history and not history.endswith("\n"):
            history += "\n"
        history += entry + "\n"
HISTORY.write_text(history)
