#!/usr/bin/env bash
# Dedicated manager for the native Awtarchy Quickshell session locker.

set -euo pipefail
export LC_ALL=C.UTF-8

CONFIG_NAME="awtarchy-lock"
QS_BIN="${QS_BIN:-qs}"
POLL_INTERVAL="${AWTARCHY_LOCK_POLL_INTERVAL:-0.05}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG_DIR="${CACHE_HOME}/awtarchy"
LOG_FILE="${AWTARCHY_LOCK_LOG:-${LOG_DIR}/lockscreen.log}"

usage() {
    cat <<'EOF'
Usage: awtarchy_lock.sh <command>

Commands:
  lock                 Start the dedicated Awtarchy session locker.
  status               Print unlocked, starting, or secure.
  wait-secure [secs]   Wait until the compositor confirms the lock is secure.
  stop-test            Stop only a non-secure development lock instance.
EOF
}

need_qs() {
    command -v "$QS_BIN" >/dev/null 2>&1 || {
        printf 'awtarchy_lock.sh: missing command: %s\n' "$QS_BIN" >&2
        return 127
    }
}

ipc_state() {
    local state

    state="$(
        "$QS_BIN" -c "$CONFIG_NAME" ipc call lock state 2>/dev/null |
            tail -n1
    )" || return 1

    case "$state" in
        unlocked|starting|secure)
            printf '%s\n' "$state"
            ;;
        *)
            return 1
            ;;
    esac
}

status_lock() {
    local state

    state="$(ipc_state 2>/dev/null || true)"
    case "$state" in
        unlocked|starting|secure)
            printf '%s\n' "$state"
            ;;
        *)
            printf '%s\n' unlocked
            ;;
    esac
}

start_lock() {
    local state

    need_qs || return $?

    state="$(status_lock)"
    case "$state" in
        starting|secure)
            return 0
            ;;
    esac

    mkdir -p -- "$LOG_DIR"
    nohup "$QS_BIN" -c "$CONFIG_NAME" >>"$LOG_FILE" 2>&1 &
    disown 2>/dev/null || true

    for _ in {1..100}; do
        state="$(status_lock)"
        case "$state" in
            starting|secure)
                return 0
                ;;
        esac
        sleep "$POLL_INTERVAL"
    done

    printf 'awtarchy_lock.sh: awtarchy-lock did not become reachable; see %s\n' \
        "$LOG_FILE" >&2
    return 1
}

wait_secure() {
    local timeout_seconds="${1:-5}"
    local start_seconds state

    need_qs || return $?
    [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || {
        printf 'awtarchy_lock.sh: wait-secure timeout must be a positive integer.\n' >&2
        return 2
    }

    start_seconds=$SECONDS
    while (( SECONDS - start_seconds < timeout_seconds )); do
        state="$(status_lock)"
        if [[ "$state" == secure ]]; then
            return 0
        fi
        sleep "$POLL_INTERVAL"
    done

    [[ "$(status_lock)" == secure ]] && return 0

    printf 'awtarchy_lock.sh: compositor did not confirm a secure lock within %s second(s).\n' \
        "$timeout_seconds" >&2
    return 1
}

stop_test() {
    local state response

    need_qs || return $?
    state="$(status_lock)"

    if [[ "$state" == secure ]]; then
        printf 'awtarchy_lock.sh: refusing to stop a compositor-secure lock.\n' >&2
        return 1
    fi

    if [[ "$state" == unlocked ]]; then
        return 0
    fi

    response="$(
        "$QS_BIN" -c "$CONFIG_NAME" ipc call lock stopTest 2>/dev/null |
            tail -n1
    )" || return 1

    [[ "$response" == true ]]
}

command_name="${1:-}"
case "$command_name" in
    lock)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        start_lock
        ;;
    status)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        need_qs || exit $?
        status_lock
        ;;
    wait-secure)
        [[ $# -le 2 ]] || { usage >&2; exit 2; }
        wait_secure "${2:-5}"
        ;;
    stop-test)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        stop_test
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
