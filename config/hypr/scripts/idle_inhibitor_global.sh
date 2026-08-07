#!/usr/bin/env bash
# Global Awtarchy idle inhibitor used by Quickshell and hypridle guards.

set -euo pipefail
export LC_ALL=C

WHY="${AWTARCHY_IDLE_WHY:-Awtarchy global idle inhibitor}"
WHO="${AWTARCHY_IDLE_WHO:-awtarchy}"
PROC_NAME="${AWTARCHY_IDLE_PROC_NAME:-awtarchy-global-idle-inhibitor}"

uid="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
PID_FILE="${RUNTIME_DIR}/awtarchy-global-idle-inhibitor.pid"
CONTROL_LOCK="${RUNTIME_DIR}/awtarchy-global-idle-inhibitor.lock"

mkdir -p "$RUNTIME_DIR"

lock_control() {
    if command -v flock >/dev/null 2>&1; then
        exec 9>"$CONTROL_LOCK"
        flock -x 9
    fi
}

read_pid_file() {
    [[ -r "$PID_FILE" ]] || return 1
    tr -d '[:space:]' <"$PID_FILE"
}

valid_pid() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

inhibitor_lines() {
    command -v systemd-inhibit >/dev/null 2>&1 || return 0
    systemd-inhibit --list --no-pager 2>/dev/null |
        awk -v why="$WHY" '
            index($0, why) && $0 ~ /(^|[[:space:]])idle([[:space:]]|$)/ && $NF == "block" { print }
        '
}

real_inhibitor_active() {
    [[ -n "$(inhibitor_lines)" ]]
}

inhibitor_pids() {
    inhibitor_lines | awk '{ print $4 }' | grep -E '^[0-9]+$' || true
}

pid_command_line() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//'
}

pid_is_managed() {
    local pid="${1:-}"
    valid_pid "$pid" || return 1
    inhibitor_pids | grep -qx "$pid" && return 0
    [[ "$(pid_command_line "$pid")" == "$PROC_NAME infinity" ]]
}

matching_inhibitor_pids() {
    local pid
    {
        pid="$(read_pid_file 2>/dev/null || true)"
        pid_is_managed "$pid" && printf '%s\n' "$pid"
        inhibitor_pids
        pgrep -u "$uid" -f "^${PROC_NAME} infinity$" 2>/dev/null || true
    } | awk '/^[0-9]+$/ && !seen[$0]++'
}

managed_process_active() {
    local pid
    pid="$(read_pid_file 2>/dev/null || true)"
    pid_is_managed "$pid" && return 0
    matching_inhibitor_pids | grep -qE '^[0-9]+$'
}

is_active() {
    real_inhibitor_active
}

kill_pid_and_group() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
    [[ "$pid" == "$$" ]] && return 0
    kill -- "-$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
}

stop_managed_processes() {
    local pid
    pid="$(read_pid_file 2>/dev/null || true)"
    kill_pid_and_group "$pid"

    while read -r pid; do
        kill_pid_and_group "$pid"
    done < <(matching_inhibitor_pids | sort -u)

    sleep 0.15

    while read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        [[ "$pid" == "$$" ]] && continue
        kill -9 -- "-$pid" 2>/dev/null || true
        kill -9 "$pid" 2>/dev/null || true
    done < <(matching_inhibitor_pids | sort -u)

    rm -f "$PID_FILE"
}

start_inhibitor() {
    local pid holder_pid

    command -v systemd-inhibit >/dev/null 2>&1 || {
        printf '%s\n' 'systemd-inhibit not found' >&2
        return 1
    }

    is_active && return 0
    stop_managed_processes

    # shellcheck disable=SC2016
    setsid systemd-inhibit \
        --what=idle \
        --who="$WHO" \
        --why="$WHY" \
        --mode=block \
        bash -c 'trap "exit 0" TERM INT HUP; exec -a "$0" sleep infinity' "$PROC_NAME" \
        9>&- >/dev/null 2>&1 &

    pid="$!"
    printf '%s\n' "$pid" >"$PID_FILE"

    for _ in {1..40}; do
        if is_active; then
            holder_pid="$(inhibitor_pids | sed -n '1p')"
            valid_pid "$holder_pid" && printf '%s\n' "$holder_pid" >"$PID_FILE"
            return 0
        fi
        sleep 0.05
    done

    stop_managed_processes
    printf '%s\n' 'Failed to acquire a real systemd idle inhibitor lock' >&2
    return 1
}

stop_inhibitor() {
    stop_managed_processes
    for _ in {1..20}; do
        real_inhibitor_active || return 0
        sleep 0.05
    done
    printf '%s\n' 'Failed to release the systemd idle inhibitor lock' >&2
    return 1
}

print_status() {
    if is_active; then
        printf '{"text":"","tooltip":"Idle inhibitor: activated\\nReal systemd idle lock verified\\nClick to deactivate","class":["activated"]}\n'
    elif managed_process_active; then
        printf '{"text":"","tooltip":"Idle inhibitor: broken state\\nProcess exists without a real idle lock","class":["error"]}\n'
    else
        printf '{"text":"","tooltip":"Idle inhibitor: deactivated\\nClick to activate","class":["deactivated"]}\n'
    fi
}

case "${1:-status}" in
    toggle)
        lock_control
        if is_active; then stop_inhibitor; else start_inhibitor; fi
        ;;
    on)
        lock_control
        start_inhibitor
        ;;
    off)
        lock_control
        stop_inhibitor
        ;;
    is-active)
        is_active
        ;;
    diagnose)
        printf 'real_idle_lock=%s\n' "$(is_active && printf yes || printf no)"
        printf 'managed_process=%s\n' "$(managed_process_active && printf yes || printf no)"
        printf 'pid_file=%s\n' "$(read_pid_file 2>/dev/null || printf none)"
        printf 'hypridle_processes=%s\n' "$(pgrep -u "$uid" -x hypridle 2>/dev/null | wc -l)"
        printf '%s\n' 'matching_inhibitors:'
        inhibitor_lines
        ;;
    status|"")
        print_status
        ;;
    *)
        printf '{"text":"","tooltip":"Unknown idle inhibitor command: %s","class":["error"]}\n' "${1:-}"
        exit 1
        ;;
esac
