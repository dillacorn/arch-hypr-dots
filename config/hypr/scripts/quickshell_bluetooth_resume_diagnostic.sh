#!/usr/bin/env bash
# Capture one self-contained, read-only Bluetooth suspend/resume diagnostic report.

set -u -o pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_SCRIPT="${AWTARCHY_BLUETOOTH_STATE_SCRIPT:-${CONFIG_HOME}/hypr/scripts/quickshell_bluetooth_state.sh}"
RESUME_LOG="${AWTARCHY_BLUETOOTH_RESUME_LOG:-${CACHE_HOME}/awtarchy/quickshell-resume.log}"
HYPRIDLE_LOG="${AWTARCHY_HYPRIDLE_ACTION_LOG:-${CACHE_HOME}/hypridle/actions.log}"
BLUETOOTH_CLASS_DIR="${AWTARCHY_BLUETOOTH_CLASS_DIR:-/sys/class/bluetooth}"
RFKILL_CLASS_DIR="${AWTARCHY_RFKILL_CLASS_DIR:-/sys/class/rfkill}"
START_DELAY="${AWTARCHY_BLUETOOTH_DIAGNOSTIC_START_DELAY:-2}"
POST_SECONDS="${AWTARCHY_BLUETOOTH_DIAGNOSTIC_POST_SECONDS:-10}"
SAMPLE_INTERVAL="${AWTARCHY_BLUETOOTH_DIAGNOSTIC_SAMPLE_INTERVAL:-0.10}"
DEFAULT_OUTPUT="${CACHE_HOME}/awtarchy/bluetooth-resume-diagnostic-$(date '+%Y%m%d-%H%M%S').txt"
OUTPUT_FILE="${AWTARCHY_BLUETOOTH_DIAGNOSTIC_OUTPUT:-$DEFAULT_OUTPUT}"

CYCLES=1
WORK_DIR=""
RAW_REPORT=""
FINALIZED=0
WATCHER_PIDS=()

usage() {
    printf '%s\n' 'usage: quickshell_bluetooth_resume_diagnostic.sh [--cycles 1-10]' >&2
    exit 2
}

is_nonnegative_number() {
    [[ "$1" =~ ^([0-9]+)(\.[0-9]+)?$ ]]
}

while (( $# > 0 )); do
    case "$1" in
        --cycles)
            [[ $# -ge 2 ]] || usage
            CYCLES="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

if [[ ! "$CYCLES" =~ ^[1-9][0-9]*$ ]] || (( CYCLES > 10 )); then
    printf '%s\n' 'Bluetooth diagnostic cycle count must be between 1 and 10.' >&2
    exit 2
fi
if ! is_nonnegative_number "$START_DELAY"; then
    printf '%s\n' 'Bluetooth diagnostic start delay must be a non-negative number.' >&2
    exit 2
fi
if ! is_nonnegative_number "$POST_SECONDS"; then
    printf '%s\n' 'Bluetooth diagnostic post-resume window must be a non-negative number.' >&2
    exit 2
fi
if ! is_nonnegative_number "$SAMPLE_INTERVAL" || [[ "$SAMPLE_INTERVAL" == 0 || "$SAMPLE_INTERVAL" == 0.0 || "$SAMPLE_INTERVAL" == 0.00 ]]; then
    printf '%s\n' 'Bluetooth diagnostic sample interval must be greater than zero.' >&2
    exit 2
fi

command_available() {
    command -v "$1" >/dev/null 2>&1
}

state_helper() {
    local operation="$1"
    [[ -f "$STATE_SCRIPT" ]] || return 1
    bash "$STATE_SCRIPT" "$operation"
}

preflight_disabled() {
    local saved actual

    if [[ ! -f "$STATE_SCRIPT" ]]; then
        printf 'Bluetooth state helper is unavailable: %s\n' "$STATE_SCRIPT" >&2
        return 1
    fi
    if ! command_available systemctl; then
        printf '%s\n' 'systemctl is required for the suspend diagnostic.' >&2
        return 1
    fi

    saved="$(state_helper status 2>/dev/null || true)"
    actual="$(state_helper actual 2>/dev/null || true)"

    if [[ "$saved" != disabled || "$actual" != disabled ]]; then
        printf '%s\n' 'Bluetooth resume diagnostic was not armed.' >&2
        printf 'Saved Awtarchy preference: %s\n' "${saved:-unknown}" >&2
        printf 'Actual BlueZ power state: %s\n' "${actual:-unknown}" >&2
        printf '%s\n' 'Disable Bluetooth from the Awtarchy flyout, then run the diagnostic again.' >&2
        return 1
    fi

    return 0
}

section() {
    local title="$1"
    printf '\n===== %s =====\n' "$title" >>"$RAW_REPORT"
}

append_command() {
    local title="$1"
    shift
    section "$title"
    if ! command_available "$1"; then
        printf 'unavailable command: %s\n' "$1" >>"$RAW_REPORT"
        return 0
    fi
    "$@" >>"$RAW_REPORT" 2>&1 || printf '[command exited %d]\n' "$?" >>"$RAW_REPORT"
}

append_state_helper() {
    local title="$1" operation="$2"
    section "$title"
    if [[ ! -f "$STATE_SCRIPT" ]]; then
        printf 'unavailable helper: %s\n' "$STATE_SCRIPT" >>"$RAW_REPORT"
        return 0
    fi
    state_helper "$operation" >>"$RAW_REPORT" 2>&1 || printf '[helper exited %d]\n' "$?" >>"$RAW_REPORT"
}

line_count() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -l <"$file" 2>/dev/null || printf '0\n'
    else
        printf '0\n'
    fi
}

append_log_delta() {
    local title="$1" file="$2" previous_lines="$3"
    local first_new

    section "$title"
    if [[ ! -r "$file" ]]; then
        printf 'log unavailable: %s\n' "$file" >>"$RAW_REPORT"
        return 0
    fi

    first_new=$((previous_lines + 1))
    if (( $(line_count "$file") >= first_new )); then
        tail -n "+${first_new}" "$file" >>"$RAW_REPORT" 2>&1 || true
    else
        printf '%s\n' '(no new lines; recent context follows)' >>"$RAW_REPORT"
        tail -n 80 "$file" >>"$RAW_REPORT" 2>&1 || true
    fi
}

append_file() {
    local title="$1" file="$2"
    section "$title"
    if [[ -s "$file" ]]; then
        cat -- "$file" >>"$RAW_REPORT"
    else
        printf '%s\n' '(no events captured)' >>"$RAW_REPORT"
    fi
}

capture_sysfs() {
    local path name value property

    section 'BLUETOOTH/RFKILL SYSFS SNAPSHOT'
    printf 'bluetooth_class_dir=%s\n' "$BLUETOOTH_CLASS_DIR" >>"$RAW_REPORT"
    for path in "$BLUETOOTH_CLASS_DIR"/hci*; do
        [[ -e "$path" ]] || continue
        name="${path##*/}"
        printf 'adapter=%s\n' "$name" >>"$RAW_REPORT"
        printf '  resolved_path=%s\n' "$(readlink -f -- "$path" 2>/dev/null || true)" >>"$RAW_REPORT"
        printf '  driver=%s\n' "$(readlink -f -- "$path/device/driver" 2>/dev/null || true)" >>"$RAW_REPORT"
        for property in address name; do
            if [[ -r "$path/$property" ]]; then
                value="$(cat -- "$path/$property" 2>/dev/null || true)"
                printf '  %s=%s\n' "$property" "$value" >>"$RAW_REPORT"
            fi
        done
        for property in power/control power/runtime_status power/runtime_suspended_time power/runtime_active_time; do
            if [[ -r "$path/device/$property" ]]; then
                value="$(cat -- "$path/device/$property" 2>/dev/null || true)"
                printf '  device_%s=%s\n' "${property//\//_}" "$value" >>"$RAW_REPORT"
            fi
        done
    done

    printf 'rfkill_class_dir=%s\n' "$RFKILL_CLASS_DIR" >>"$RAW_REPORT"
    for path in "$RFKILL_CLASS_DIR"/rfkill*; do
        [[ -d "$path" ]] || continue
        [[ -r "$path/type" ]] || continue
        [[ "$(cat -- "$path/type" 2>/dev/null || true)" == bluetooth ]] || continue
        printf 'rfkill=%s' "${path##*/}" >>"$RAW_REPORT"
        for property in name state soft hard; do
            value="unavailable"
            [[ -r "$path/$property" ]] && value="$(cat -- "$path/$property" 2>/dev/null || true)"
            printf ' %s=%s' "$property" "$value" >>"$RAW_REPORT"
        done
        printf '\n' >>"$RAW_REPORT"
    done
}

capture_snapshot() {
    local label="$1"

    section "$label"
    printf 'wall_time=%s\n' "$(date --iso-8601=ns 2>/dev/null || date '+%F %T.%N %z')" >>"$RAW_REPORT"
    printf 'uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime 2>/dev/null || printf unknown)" >>"$RAW_REPORT"
    append_state_helper 'SAVED AWTARCHY PREFERENCE' status
    append_state_helper 'ACTUAL BLUEZ POWER STATE' actual
    append_command 'BLUETOOTHCTL SHOW' bluetoothctl show
    append_command 'RFKILL STATE' rfkill list bluetooth
    capture_sysfs
    append_command 'BLUETOOTH SERVICE STATUS' systemctl status bluetooth.service --no-pager
    if command_available busctl; then
        append_command 'BLUEZ OBJECT TREE' busctl --system tree org.bluez
    else
        section 'BLUEZ OBJECT TREE'
        printf '%s\n' 'busctl unavailable' >>"$RAW_REPORT"
    fi
}

adapter_sample_once() {
    local timestamp path name powered soft hard rf_name

    timestamp="$(date '+%s.%N')"
    for path in "$BLUETOOTH_CLASS_DIR"/hci*; do
        [[ -e "$path" ]] || continue
        name="${path##*/}"
        powered="unknown"
        if command_available busctl; then
            powered="$(timeout 1 busctl --system get-property org.bluez "/org/bluez/${name}" org.bluez.Adapter1 Powered 2>/dev/null | awk '{print $2}' || true)"
            [[ -n "$powered" ]] || powered="unavailable"
        fi
        printf '%s adapter=%s bluez_powered=%s\n' "$timestamp" "$name" "$powered"
    done

    for path in "$RFKILL_CLASS_DIR"/rfkill*; do
        [[ -d "$path" && -r "$path/type" ]] || continue
        [[ "$(cat -- "$path/type" 2>/dev/null || true)" == bluetooth ]] || continue
        rf_name="$(cat -- "$path/name" 2>/dev/null || printf unknown)"
        soft="$(cat -- "$path/soft" 2>/dev/null || printf unknown)"
        hard="$(cat -- "$path/hard" 2>/dev/null || printf unknown)"
        printf '%s rfkill=%s soft=%s hard=%s\n' "$timestamp" "$rf_name" "$soft" "$hard"
    done
}

sample_loop() {
    while true; do
        adapter_sample_once
        sleep "$SAMPLE_INTERVAL"
    done
}

start_background() {
    local output="$1"
    shift

    if command_available stdbuf; then
        stdbuf -oL -eL "$@" >"$output" 2>&1 &
    else
        "$@" >"$output" 2>&1 &
    fi
    WATCHER_PIDS+=("$!")
}

start_watchers() {
    local cycle_dir="$1"
    WATCHER_PIDS=()

    if command_available dbus-monitor; then
        start_background "$cycle_dir/dbus.log" dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Adapter1'"
    else
        printf '%s\n' 'dbus-monitor unavailable' >"$cycle_dir/dbus.log"
    fi

    if command_available rfkill; then
        start_background "$cycle_dir/rfkill.log" rfkill event
    else
        printf '%s\n' 'rfkill unavailable' >"$cycle_dir/rfkill.log"
    fi

    if command_available udevadm; then
        start_background "$cycle_dir/udev.log" udevadm monitor --kernel --udev --property --subsystem-match=bluetooth
    else
        printf '%s\n' 'udevadm unavailable' >"$cycle_dir/udev.log"
    fi

    sample_loop >"$cycle_dir/timeline.log" 2>&1 &
    WATCHER_PIDS+=("$!")
}

stop_watchers() {
    local pid
    for pid in "${WATCHER_PIDS[@]:-}"; do
        [[ -n "$pid" ]] || continue
        kill "$pid" 2>/dev/null || true
    done
    for pid in "${WATCHER_PIDS[@]:-}"; do
        [[ -n "$pid" ]] || continue
        wait "$pid" 2>/dev/null || true
    done
    WATCHER_PIDS=()
}

append_journals() {
    local since="$1" output

    section 'BLUETOOTH SERVICE JOURNAL'
    if command_available journalctl; then
        journalctl -b --since "$since" --no-pager -o short-precise -u bluetooth.service >>"$RAW_REPORT" 2>&1 || true
    else
        printf '%s\n' 'journalctl unavailable' >>"$RAW_REPORT"
    fi

    section 'KERNEL SUSPEND/BLUETOOTH JOURNAL'
    if command_available journalctl; then
        output="$(journalctl -b --since "$since" --no-pager -o short-precise 2>&1 || true)"
        if ! grep -Ei 'bluetooth|bluez|rfkill|btusb|hci[0-9]|suspend|systemd-sleep|PM: ' <<<"$output" >>"$RAW_REPORT"; then
            printf '%s\n' '(no matching journal lines)' >>"$RAW_REPORT"
        fi
    else
        printf '%s\n' 'journalctl unavailable' >>"$RAW_REPORT"
    fi
}

capture_versions() {
    section 'SYSTEM AND BLUETOOTH VERSIONS'
    printf 'captured_at=%s\n' "$(date --iso-8601=ns 2>/dev/null || date '+%F %T.%N %z')" >>"$RAW_REPORT"
    printf 'kernel=%s\n' "$(uname -a 2>/dev/null || printf unknown)" >>"$RAW_REPORT"
    printf 'state_helper=%s\n' "$STATE_SCRIPT" >>"$RAW_REPORT"
    if command_available sha256sum && [[ -f "$STATE_SCRIPT" ]]; then
        sha256sum "$STATE_SCRIPT" >>"$RAW_REPORT" 2>&1 || true
    fi
    command_available bluetoothctl && bluetoothctl --version >>"$RAW_REPORT" 2>&1 || true
    command_available rfkill && rfkill --version >>"$RAW_REPORT" 2>&1 || true
    command_available systemctl && systemctl --version >>"$RAW_REPORT" 2>&1 || true
    command_available pacman && pacman -Q bluez bluez-utils >>"$RAW_REPORT" 2>&1 || true
    command_available loginctl && loginctl session-status >>"$RAW_REPORT" 2>&1 || true

    printf '\n-- USB devices --\n' >>"$RAW_REPORT"
    command_available lsusb && lsusb >>"$RAW_REPORT" 2>&1 || printf '%s\n' 'lsusb unavailable' >>"$RAW_REPORT"
    printf '\n-- PCI network/wireless devices --\n' >>"$RAW_REPORT"
    if command_available lspci; then
        lspci 2>&1 | grep -Ei 'network|wireless|bluetooth' >>"$RAW_REPORT" || printf '%s\n' '(no matching PCI lines)' >>"$RAW_REPORT"
    else
        printf '%s\n' 'lspci unavailable' >>"$RAW_REPORT"
    fi
}

dbus_powered_true_observed() {
    local file="$1"
    [[ -s "$file" ]] || return 1

    awk '
        /^[[:space:]]*string "Powered"[[:space:]]*$/ {
            waiting_for_powered_value = 1
            next
        }
        waiting_for_powered_value && /boolean true/ {
            found = 1
            exit
        }
        waiting_for_powered_value && /boolean false/ {
            waiting_for_powered_value = 0
            next
        }
        waiting_for_powered_value && /^[[:space:]]*string "/ {
            waiting_for_powered_value = 0
        }
        END {
            exit(found ? 0 : 1)
        }
    ' "$file"
}

append_cycle_observation() {
    local cycle_dir="$1" saved actual transient=no

    saved="$(state_helper status 2>/dev/null || true)"
    actual="$(state_helper actual 2>/dev/null || true)"
    if grep -Fq 'bluez_powered=true' "$cycle_dir/timeline.log" 2>/dev/null \
        || dbus_powered_true_observed "$cycle_dir/dbus.log"; then
        transient=yes
    fi

    section 'AUTOMATIC OBSERVATION'
    printf 'post_saved=%s\n' "${saved:-unknown}" >>"$RAW_REPORT"
    printf 'post_actual=%s\n' "${actual:-unknown}" >>"$RAW_REPORT"
    printf 'adapter_powered_true_observed=%s\n' "$transient" >>"$RAW_REPORT"

    if [[ "$saved" == enabled && "$actual" == enabled ]]; then
        printf '%s\n' 'classification=persisted preference changed to enabled or was rewritten during resume' >>"$RAW_REPORT"
    elif [[ "$saved" == disabled && "$actual" == enabled ]]; then
        printf '%s\n' 'classification=resume restore failed or lost a race; final actual state is enabled' >>"$RAW_REPORT"
    elif [[ "$saved" == disabled && "$actual" == disabled && "$transient" == yes ]]; then
        printf '%s\n' 'classification=transient adapter-powered-on event observed before final disabled state' >>"$RAW_REPORT"
    elif [[ "$saved" == disabled && "$actual" == disabled ]]; then
        printf '%s\n' 'classification=no powered-on event observed in this cycle' >>"$RAW_REPORT"
    else
        printf '%s\n' 'classification=state became indeterminate; inspect raw evidence' >>"$RAW_REPORT"
    fi

    [[ "$saved" == disabled && "$actual" == disabled ]]
}

sanitize_report() {
    sed -E \
        -e 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/<MAC>/g' \
        -e 's/(dev_)?([[:xdigit:]]{2}_){5}[[:xdigit:]]{2}/<MAC_PATH>/g' \
        "$RAW_REPORT"
}

finalize_report() {
    local output_dir output_tmp
    (( FINALIZED == 0 )) || return 0
    [[ -n "$RAW_REPORT" && -f "$RAW_REPORT" ]] || return 0

    output_dir="$(dirname -- "$OUTPUT_FILE")"
    mkdir -p -- "$output_dir"
    output_tmp="${OUTPUT_FILE}.tmp.$$"
    sanitize_report >"$output_tmp"
    chmod 0600 -- "$output_tmp" 2>/dev/null || true
    mv -f -- "$output_tmp" "$OUTPUT_FILE"
    FINALIZED=1
}

cleanup() {
    stop_watchers
    finalize_report || true
    [[ -n "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

preflight_disabled || exit 1

WORK_DIR="$(mktemp -d)"
RAW_REPORT="$WORK_DIR/report.raw"
printf '%s\n' 'Awtarchy Bluetooth Suspend/Resume Diagnostic' >"$RAW_REPORT"
printf 'requested_cycles=%d\n' "$CYCLES" >>"$RAW_REPORT"
printf 'start_delay_seconds=%s\n' "$START_DELAY" >>"$RAW_REPORT"
printf 'post_resume_capture_seconds=%s\n' "$POST_SECONDS" >>"$RAW_REPORT"
printf 'sample_interval_seconds=%s\n' "$SAMPLE_INTERVAL" >>"$RAW_REPORT"
printf 'output=%s\n' "$OUTPUT_FILE" >>"$RAW_REPORT"
capture_versions

printf 'Bluetooth resume diagnostic armed for %d cycle(s).\n' "$CYCLES"
printf '%s\n' 'Bluetooth state will only be observed; the diagnostic does not toggle it.'

for ((cycle = 1; cycle <= CYCLES; cycle++)); do
    cycle_dir="$WORK_DIR/cycle-${cycle}"
    mkdir -p -- "$cycle_dir"

    if ! preflight_disabled; then
        section "CYCLE ${cycle} ABORTED BEFORE SUSPEND"
        printf '%s\n' 'Bluetooth was not disabled at cycle preflight; no additional suspend was attempted.' >>"$RAW_REPORT"
        break
    fi

    resume_lines="$(line_count "$RESUME_LOG")"
    hypridle_lines="$(line_count "$HYPRIDLE_LOG")"
    cycle_since="$(date --iso-8601=seconds 2>/dev/null || date '+%F %T')"

    capture_snapshot "CYCLE ${cycle} PRE-SUSPEND"
    start_watchers "$cycle_dir"

    if [[ "$START_DELAY" != 0 ]]; then
        printf 'Cycle %d/%d: capturing baseline for %s second(s), then suspending.\n' "$cycle" "$CYCLES" "$START_DELAY"
        sleep "$START_DELAY"
    else
        printf 'Cycle %d/%d: suspending now.\n' "$cycle" "$CYCLES"
    fi

    section "CYCLE ${cycle} SUSPEND BOUNDARY"
    printf 'suspend_requested_wall=%s\n' "$(date --iso-8601=ns 2>/dev/null || date '+%F %T.%N %z')" >>"$RAW_REPORT"
    printf 'suspend_requested_uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime 2>/dev/null || printf unknown)" >>"$RAW_REPORT"

    if ! systemctl suspend; then
        printf '%s\n' 'systemctl suspend failed; stopping diagnostic.' >&2
        printf '%s\n' 'systemctl_suspend_result=failed' >>"$RAW_REPORT"
        stop_watchers
        break
    fi

    printf 'suspend_returned_wall=%s\n' "$(date --iso-8601=ns 2>/dev/null || date '+%F %T.%N %z')" >>"$RAW_REPORT"
    printf 'suspend_returned_uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime 2>/dev/null || printf unknown)" >>"$RAW_REPORT"

    if [[ "$POST_SECONDS" != 0 ]]; then
        printf 'Cycle %d/%d: awake; capturing the resume window for %s second(s).\n' "$cycle" "$CYCLES" "$POST_SECONDS"
        sleep "$POST_SECONDS"
    fi

    stop_watchers
    capture_snapshot "CYCLE ${cycle} POST-RESUME"
    append_file 'HIGH-RESOLUTION ADAPTER TIMELINE' "$cycle_dir/timeline.log"
    append_file 'BLUEZ ADAPTER DBUS EVENTS' "$cycle_dir/dbus.log"
    append_file 'RFKILL EVENTS' "$cycle_dir/rfkill.log"
    append_file 'UDEV BLUETOOTH EVENTS' "$cycle_dir/udev.log"
    append_log_delta 'AWTARCHY RESUME RECOVERY LOG' "$RESUME_LOG" "$resume_lines"
    append_log_delta 'HYPRIDLE ACTION LOG' "$HYPRIDLE_LOG" "$hypridle_lines"
    append_journals "$cycle_since"

    if ! append_cycle_observation "$cycle_dir"; then
        printf '%s\n' 'Bluetooth no longer finished disabled; stopping additional cycles to preserve the evidence.'
        break
    fi

    if (( cycle < CYCLES )) && [[ -t 0 ]]; then
        printf 'Cycle %d complete. Press Enter when ready for the next suspend, or Ctrl+C to finish with the current report.\n' "$cycle"
        IFS= read -r _ || true
    fi
done

section 'DIAGNOSTIC COMPLETE'
printf 'completed_at=%s\n' "$(date --iso-8601=ns 2>/dev/null || date '+%F %T.%N %z')" >>"$RAW_REPORT"
finalize_report
printf 'Bluetooth resume diagnostic report: %s\n' "$OUTPUT_FILE"
