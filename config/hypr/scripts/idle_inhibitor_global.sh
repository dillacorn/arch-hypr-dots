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
MODE_FILE="${RUNTIME_DIR}/awtarchy-global-idle-inhibitor.mode"
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

read_mode_file() {
    local mode
    [[ -r "$MODE_FILE" ]] || return 1
    mode="$(tr -d '[:space:]' <"$MODE_FILE")"
    case "$mode" in
        keep-awake|always-awake)
            printf '%s\n' "$mode"
            ;;
        *)
            return 1
            ;;
    esac
}

current_mode() {
    local mode
    if ! is_active; then
        printf '%s\n' off
        return 0
    fi

    mode="$(read_mode_file 2>/dev/null || true)"
    case "$mode" in
        always-awake)
            printf '%s\n' always-awake
            ;;
        *)
            # Legacy/manual active locks predate the mode file. Treat them as
            # normal Keep Awake so the four-hour display safeguard still works.
            printf '%s\n' keep-awake
            ;;
    esac
}

write_mode() {
    local mode="$1" temporary
    temporary="${MODE_FILE}.tmp.$$"
    printf '%s\n' "$mode" >"$temporary"
    mv -f -- "$temporary" "$MODE_FILE"
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
    local requested_mode="${1:-keep-awake}"
    local pid holder_pid

    case "$requested_mode" in
        keep-awake|always-awake) ;;
        *)
            printf 'Unknown idle inhibitor mode: %s\n' "$requested_mode" >&2
            return 2
            ;;
    esac

    command -v systemd-inhibit >/dev/null 2>&1 || {
        printf '%s\n' 'systemd-inhibit not found' >&2
        return 1
    }

    if is_active; then
        write_mode "$requested_mode"
        return 0
    fi

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
            write_mode "$requested_mode"
            return 0
        fi
        sleep 0.05
    done

    stop_managed_processes
    rm -f "$MODE_FILE"
    printf '%s\n' 'Failed to acquire a real systemd idle inhibitor lock' >&2
    return 1
}

stop_inhibitor() {
    stop_managed_processes
    for _ in {1..20}; do
        if ! real_inhibitor_active; then
            rm -f "$MODE_FILE"
            return 0
        fi
        sleep 0.05
    done
    printf '%s\n' 'Failed to release the systemd idle inhibitor lock' >&2
    return 1
}

set_mode() {
    local mode="${1:-}"
    case "$mode" in
        off)
            stop_inhibitor
            ;;
        keep-awake|always-awake)
            start_inhibitor "$mode"
            ;;
        *)
            printf 'usage: %s set-mode {off|keep-awake|always-awake}\n' "${0##*/}" >&2
            return 2
            ;;
    esac
}

print_status() {
    local mode
    mode="$(current_mode)"

    if [[ "$mode" == always-awake ]]; then
        printf '{"text":"","mode":"always-awake","tooltip":"Always Awake: activated\\nAll idle actions, including the 4-hour display safeguard, are blocked\\nUse Quick Settings or click the bar eye to deactivate","class":["activated","always-awake"]}\n'
    elif [[ "$mode" == keep-awake ]]; then
        printf '{"text":"","mode":"keep-awake","tooltip":"Keep Awake: activated\\nSleep is blocked; after 4 hours idle Awtarchy may lock and turn displays off\\nClick to deactivate","class":["activated","keep-awake"]}\n'
    elif managed_process_active; then
        printf '{"text":"","mode":"off","tooltip":"Idle inhibitor: broken state\\nProcess exists without a real idle lock","class":["error"]}\n'
    else
        printf '{"text":"","mode":"off","tooltip":"Idle inhibitor: deactivated\\nClick to activate Keep Awake","class":["deactivated"]}\n'
    fi
}

case "${1:-status}" in
    toggle)
        lock_control
        if is_active; then stop_inhibitor; else start_inhibitor keep-awake; fi
        ;;
    on)
        lock_control
        start_inhibitor keep-awake
        ;;
    off)
        lock_control
        stop_inhibitor
        ;;
    set-mode)
        lock_control
        set_mode "${2:-}"
        ;;
    mode)
        current_mode
        ;;
    is-active)
        is_active
        ;;
    is-always-awake)
        [[ "$(current_mode)" == always-awake ]]
        ;;
    diagnose)
        printf 'mode=%s\n' "$(current_mode)"
        printf 'real_idle_lock=%s\n' "$(is_active && printf yes || printf no)"
        printf 'managed_process=%s\n' "$(managed_process_active && printf yes || printf no)"
        printf 'pid_file=%s\n' "$(read_pid_file 2>/dev/null || printf none)"
        printf 'mode_file=%s\n' "$(read_mode_file 2>/dev/null || printf none)"
        printf 'hypridle_processes=%s\n' "$(pgrep -u "$uid" -x hypridle 2>/dev/null | wc -l)"
        printf '%s\n' 'matching_inhibitors:'
        inhibitor_lines
        ;;
    status|"")
        print_status
        ;;
    *)
        printf '{"text":"","mode":"off","tooltip":"Unknown idle inhibitor command: %s","class":["error"]}\n' "${1:-}"
        exit 1
        ;;
esac
