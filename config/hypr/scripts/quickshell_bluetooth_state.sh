#!/usr/bin/env bash
# Persist Bluetooth choices without rfkill-hiding adapters from Quickshell/BlueZ.

set -euo pipefail

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="${STATE_HOME}/awtarchy"
STATE_FILE="${STATE_DIR}/bluetooth-state"

usage() {
    printf 'usage: quickshell_bluetooth_state.sh set <enabled|disabled> | prepare | restore | status\n' >&2
    exit 2
}

need_rfkill() {
    command -v rfkill >/dev/null 2>&1 || {
        printf 'quickshell_bluetooth_state.sh: rfkill is required\n' >&2
        return 127
    }
}

unblock_controller() {
    need_rfkill
    rfkill unblock bluetooth
}

save_state() {
    local state="$1" tmp
    mkdir -p -- "$STATE_DIR"
    tmp="${STATE_FILE}.tmp.$$"
    printf '%s\n' "$state" >"$tmp"
    chmod 0600 -- "$tmp" 2>/dev/null || true
    mv -f -- "$tmp" "$STATE_FILE"
}

read_state() {
    local state="unset"
    if [[ -r "$STATE_FILE" ]]; then
        IFS= read -r state <"$STATE_FILE" || state="unset"
    fi
    case "$state" in
        enabled|disabled|unset) printf '%s\n' "$state" ;;
        *) return 1 ;;
    esac
}

command_name="${1:-}"
case "$command_name" in
    set)
        state="${2:-}"
        [[ "$state" == "enabled" || "$state" == "disabled" ]] || usage
        [[ $# -eq 2 ]] || usage
        save_state "$state"
        if [[ "$state" == "enabled" ]]; then
            unblock_controller
        fi
        ;;
    prepare)
        [[ $# -eq 1 ]] || usage
        # Always clear a stale software rfkill block before Quickshell starts.
        # Some adapters disappear from /sys/class/bluetooth while blocked, which
        # otherwise makes BlueZ and Quickshell treat the machine as Bluetooth-less.
        unblock_controller
        ;;
    restore)
        [[ $# -eq 1 ]] || usage
        [[ -r "$STATE_FILE" ]] || exit 0
        if ! state="$(read_state)"; then
            printf 'quickshell_bluetooth_state.sh: ignoring invalid saved state\n' >&2
            exit 0
        fi
        case "$state" in
            enabled|disabled)
                # Keep the HCI controller enumerated. The QML layer applies the
                # remembered enabled/disabled state through the BlueZ adapter.
                unblock_controller || true
                ;;
            unset) ;;
        esac
        ;;
    status)
        [[ $# -eq 1 ]] || usage
        if ! read_state; then
            printf 'unset\n'
        fi
        ;;
    *) usage ;;
esac
