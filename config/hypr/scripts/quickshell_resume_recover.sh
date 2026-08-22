#!/usr/bin/env bash
# Recover Quickshell's monitor-backed bars after a real system suspend.

set -euo pipefail

CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STATE_FILE="${QUICKSHELL_STATE_FILE:-${CACHE_HOME}/awtarchy/quickshell-state.json}"
RECOVERY_LOCK="${QUICKSHELL_RESUME_LOCK:-${RUNTIME_DIR}/awtarchy-quickshell-resume.lock}"
LOG_FILE="${QUICKSHELL_RESUME_LOG:-${CACHE_HOME}/awtarchy/quickshell-resume.log}"

RESTORE_SCRIPT="${QUICKSHELL_RESTORE_SCRIPT:-${CONFIG_HOME}/hypr/scripts/quickshell_bar_restore.sh}"
MANAGER_SCRIPT="${QUICKSHELL_MANAGER_SCRIPT:-${CONFIG_HOME}/hypr/scripts/quickshell.sh}"
BLUETOOTH_STATE_SCRIPT="${QUICKSHELL_BLUETOOTH_STATE_SCRIPT:-${CONFIG_HOME}/hypr/scripts/quickshell_bluetooth_state.sh}"
QS_BIN="${QS_BIN:-qs}"
HYPRCTL_BIN="${HYPRCTL_BIN:-hyprctl}"
JQ_BIN="${JQ_BIN:-jq}"
SLEEP_BIN="${SLEEP_BIN:-sleep}"

MONITOR_WAIT_ATTEMPTS="${QUICKSHELL_RESUME_MONITOR_ATTEMPTS:-100}"
NATURAL_WAIT_ATTEMPTS="${QUICKSHELL_RESUME_NATURAL_ATTEMPTS:-20}"
RELOAD_WAIT_ATTEMPTS="${QUICKSHELL_RESUME_RELOAD_ATTEMPTS:-50}"
BLUETOOTH_WAIT_ATTEMPTS="${QUICKSHELL_RESUME_BLUETOOTH_WAIT_ATTEMPTS:-50}"
BLUETOOTH_RETRY_SECONDS="${QUICKSHELL_RESUME_BLUETOOTH_RETRY_SECONDS:-3}"
WAIT_INTERVAL="${QUICKSHELL_RESUME_WAIT_INTERVAL:-0.1}"

MONITORS_JSON='[]'
EXPECTED_BAR_COUNT=0

log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

valid_attempt_count() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

for attempts in \
    "$MONITOR_WAIT_ATTEMPTS" \
    "$NATURAL_WAIT_ATTEMPTS" \
    "$RELOAD_WAIT_ATTEMPTS" \
    "$BLUETOOTH_WAIT_ATTEMPTS"
do
    if ! valid_attempt_count "$attempts"; then
        log "invalid recovery attempt count: $attempts"
        exit 2
    fi
done

if ! valid_attempt_count "$BLUETOOTH_RETRY_SECONDS"; then
    log "invalid Bluetooth retry window: $BLUETOOTH_RETRY_SECONDS"
    exit 2
fi

for command in "$QS_BIN" "$HYPRCTL_BIN" "$JQ_BIN" "$SLEEP_BIN"; do
    if ! command -v "$command" >/dev/null 2>&1; then
        log "required recovery command is unavailable: $command"
        exit 127
    fi
done

if [[ ! -x "$RESTORE_SCRIPT" && ! -f "$RESTORE_SCRIPT" ]]; then
    log "bar restore script is unavailable: $RESTORE_SCRIPT"
    exit 1
fi

if [[ ! -x "$MANAGER_SCRIPT" && ! -f "$MANAGER_SCRIPT" ]]; then
    log "Quickshell manager is unavailable: $MANAGER_SCRIPT"
    exit 1
fi

mkdir -p "$RUNTIME_DIR"
if command -v flock >/dev/null 2>&1; then
    exec 8>"$RECOVERY_LOCK"
    flock -x 8
fi

restore_idle_bar_state() {
    bash "$RESTORE_SCRIPT" >/dev/null 2>&1 || {
        log 'could not clear the temporary idle-hidden bar state'
        return 1
    }
}

restore_bluetooth_state() {
    if [[ ! -f "$BLUETOOTH_STATE_SCRIPT" ]]; then
        log "Bluetooth state helper is unavailable: $BLUETOOTH_STATE_SCRIPT"
        return 0
    fi

    if AWTARCHY_BLUETOOTH_WAIT_ATTEMPTS="$BLUETOOTH_WAIT_ATTEMPTS" \
        AWTARCHY_BLUETOOTH_POWER_RETRY_SECONDS="$BLUETOOTH_RETRY_SECONDS" \
        bash "$BLUETOOTH_STATE_SCRIPT" restore >/dev/null 2>&1
    then
        log 'Bluetooth preference restore completed after sleep'
    else
        # Bluetooth recovery must never prevent display/bar recovery.
        log 'Bluetooth preference restore failed after sleep'
    fi
}

shell_running() {
    "$QS_BIN" -c "$CONFIG_NAME" ipc call control ping >/dev/null 2>&1
}

read_connected_monitors() {
    local output

    output="$("$HYPRCTL_BIN" monitors -j 2>/dev/null || true)"
    if ! "$JQ_BIN" -e '
        type == "array"
        and any(
            .[];
            ((.disabled // false) == false)
            and ((.name // "") | length > 0)
        )
    ' <<<"$output" >/dev/null 2>&1; then
        return 1
    fi

    MONITORS_JSON="$output"
}

wait_for_connected_monitor() {
    local attempt

    for ((attempt = 1; attempt <= MONITOR_WAIT_ATTEMPTS; attempt++)); do
        if read_connected_monitors; then
            return 0
        fi
        "$SLEEP_BIN" "$WAIT_INTERVAL"
    done

    return 1
}

load_state_json() {
    if [[ -s "$STATE_FILE" ]] && "$JQ_BIN" -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
        "$JQ_BIN" -c '.' "$STATE_FILE"
    else
        printf '%s\n' '{"enabled":true,"monitors":{}}'
    fi
}

set_expected_bar_count() {
    local state_json

    state_json="$(load_state_json)"
    # $state is a jq variable, not a shell variable.
    # shellcheck disable=SC2016
    EXPECTED_BAR_COUNT="$("$JQ_BIN" -r --argjson state "$state_json" '
        def true_when_missing:
            if . == null then true else . end;

        ($state.monitors // {}) as $states
        | ($state.enabled | true_when_missing) as $globally_enabled
        | if $globally_enabled != true then
            0
          else
            [
                .[]
                | select((.disabled // false) == false)
                | (.name // "") as $name
                | select($name | length > 0)
                | select(($states[$name].enabled | true_when_missing) == true)
            ]
            | length
          end
    ' <<<"$MONITORS_JSON")"
}

visible_bar_count() {
    local layers

    layers="$("$HYPRCTL_BIN" layers -j 2>/dev/null || true)"
    "$JQ_BIN" -r '
        [
            ..
            | objects
            | select((.namespace? // "") == "awtarchy-bar")
        ]
        | length
    ' <<<"$layers" 2>/dev/null
}

all_expected_bars_visible() {
    local count

    (( EXPECTED_BAR_COUNT == 0 )) && return 0
    count="$(visible_bar_count)" || return 1
    [[ "$count" =~ ^[0-9]+$ ]] || return 1
    (( count >= EXPECTED_BAR_COUNT ))
}

wait_for_expected_bars() {
    local attempts="$1"
    local attempt

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if all_expected_bars_visible; then
            return 0
        fi
        "$SLEEP_BIN" "$WAIT_INTERVAL"
    done

    return 1
}

manager() {
    # Descriptor 8 owns the recovery lock. A newly started Quickshell process
    # must not inherit it and make all future resume recoveries block forever.
    bash "$MANAGER_SCRIPT" "$1" 8>&-
}

restore_idle_bar_state || true

if ! wait_for_connected_monitor; then
    log 'resume recovery timed out waiting for a connected Hyprland monitor'
    exit 1
fi

restore_bluetooth_state || true
set_expected_bar_count

if ! shell_running; then
    log 'Quickshell IPC was unavailable after resume; starting the shell'
    if ! manager start >/dev/null 2>&1; then
        log 'Quickshell failed to start after resume'
        exit 1
    fi
    restore_idle_bar_state || true
fi

if (( EXPECTED_BAR_COUNT == 0 )); then
    log 'resume recovery completed; no enabled monitor bars are configured'
    exit 0
fi

if wait_for_expected_bars "$NATURAL_WAIT_ATTEMPTS"; then
    log "resume recovery completed; ${EXPECTED_BAR_COUNT} expected bar(s) are visible"
    exit 0
fi

log 'Quickshell is running without all expected bars; recreating its windows'
"$QS_BIN" -c "$CONFIG_NAME" ipc call control hardReload >/dev/null 2>&1 || true

if wait_for_expected_bars "$RELOAD_WAIT_ATTEMPTS"; then
    log "hard reload restored ${EXPECTED_BAR_COUNT} expected bar(s)"
    exit 0
fi

log 'hard reload did not restore every bar; restarting the Awtarchy shell'
if ! manager restart >/dev/null 2>&1; then
    log 'Quickshell restart failed during resume recovery'
    exit 1
fi
restore_idle_bar_state || true

if wait_for_expected_bars "$RELOAD_WAIT_ATTEMPTS"; then
    log "full restart restored ${EXPECTED_BAR_COUNT} expected bar(s)"
    exit 0
fi

log 'resume recovery failed: expected bar layers are still absent'
exit 1
