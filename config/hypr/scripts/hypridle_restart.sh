#!/usr/bin/env bash
# Restart Hypridle so managed callback changes take effect immediately.

set -Eeuo pipefail

# Descriptor 9 belongs to the Awtarchy updater when this helper is launched
# from an update. Never let Hypridle keep that lock alive after the updater
# exits.
exec 9>&-

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

CONFIG_FILE="${HYPRIDLE_CONFIG:-${CONFIG_HOME}/hypr/hypridle.conf}"
RESTORE_SCRIPT="${HYPRIDLE_RESTORE_SCRIPT:-${CONFIG_HOME}/hypr/scripts/quickshell_bar_restore.sh}"
LOCK_FILE="${HYPRIDLE_RESTART_LOCK:-${RUNTIME_DIR}/awtarchy-hypridle-restart.lock}"
LOG_FILE="${HYPRIDLE_RESTART_LOG:-${CACHE_HOME}/hypridle/hypridle.log}"

HYPRIDLE_BIN="${HYPRIDLE_BIN:-hypridle}"
HYPRIDLE_PROCESS_NAME="${HYPRIDLE_PROCESS_NAME:-hypridle}"
PGREP_BIN="${HYPRIDLE_PGREP_BIN:-pgrep}"
PKILL_BIN="${HYPRIDLE_PKILL_BIN:-pkill}"
NOHUP_BIN="${HYPRIDLE_NOHUP_BIN:-nohup}"
SLEEP_BIN="${HYPRIDLE_SLEEP_BIN:-sleep}"
FLOCK_BIN="${HYPRIDLE_FLOCK_BIN:-flock}"

STOP_ATTEMPTS="${HYPRIDLE_STOP_ATTEMPTS:-20}"
START_ATTEMPTS="${HYPRIDLE_START_ATTEMPTS:-50}"
START_STABLE_CHECKS="${HYPRIDLE_START_STABLE_CHECKS:-5}"
WAIT_INTERVAL="${HYPRIDLE_WAIT_INTERVAL:-0.1}"
USER_ID="$(id -u)"

fail() {
    printf 'hypridle_restart.sh: %s\n' "$*" >&2
    exit 1
}

valid_attempt_count() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

for attempts in "$STOP_ATTEMPTS" "$START_ATTEMPTS" "$START_STABLE_CHECKS"; do
    valid_attempt_count "$attempts" || fail "invalid attempt count: $attempts"
done

for command in \
    "$HYPRIDLE_BIN" \
    "$PGREP_BIN" \
    "$PKILL_BIN" \
    "$NOHUP_BIN" \
    "$SLEEP_BIN" \
    "$FLOCK_BIN"
do
    command -v "$command" >/dev/null 2>&1 || fail "required command is unavailable: $command"
done

[[ -r "$CONFIG_FILE" ]] || fail "Hypridle config is unavailable: $CONFIG_FILE"
[[ -f "$RESTORE_SCRIPT" ]] || fail "bar restore script is unavailable: $RESTORE_SCRIPT"

mkdir -p "$RUNTIME_DIR" "$(dirname "$LOG_FILE")"
exec 8>"$LOCK_FILE"
"$FLOCK_BIN" -x 8

hypridle_running() {
    "$PGREP_BIN" -u "$USER_ID" -x "$HYPRIDLE_PROCESS_NAME" >/dev/null 2>&1
}

wait_for_stop() {
    local attempt

    for ((attempt = 1; attempt <= STOP_ATTEMPTS; attempt++)); do
        hypridle_running || return 0
        "$SLEEP_BIN" "$WAIT_INTERVAL"
    done

    return 1
}

if hypridle_running; then
    "$PKILL_BIN" -TERM -u "$USER_ID" -x "$HYPRIDLE_PROCESS_NAME" >/dev/null 2>&1 || true
    if ! wait_for_stop; then
        "$PKILL_BIN" -KILL -u "$USER_ID" -x "$HYPRIDLE_PROCESS_NAME" >/dev/null 2>&1 || true
        wait_for_stop || fail "the previous Hypridle process did not stop"
    fi
fi

# Descriptor 8 owns this helper's serialization lock. Close both updater and
# helper locks in the long-lived process before it is detached.
"$NOHUP_BIN" "$HYPRIDLE_BIN" -c "$CONFIG_FILE" \
    >>"$LOG_FILE" 2>&1 </dev/null 8>&- 9>&- &
hypridle_pid=$!

stable_checks=0
started=0
for ((attempt = 1; attempt <= START_ATTEMPTS; attempt++)); do
    "$SLEEP_BIN" "$WAIT_INTERVAL"
    if kill -0 "$hypridle_pid" 2>/dev/null && hypridle_running; then
        ((stable_checks += 1))
        if (( stable_checks >= START_STABLE_CHECKS )); then
            started=1
            break
        fi
    else
        stable_checks=0
    fi
done

(( started == 1 )) || fail "Hypridle did not remain running; inspect $LOG_FILE"

bash "$RESTORE_SCRIPT" 8>&- 9>&- >/dev/null 2>&1 \
    || fail "Hypridle restarted, but the Quickshell bar state could not be restored"
