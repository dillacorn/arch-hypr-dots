#!/usr/bin/env bash
# Persist only Bluetooth choices made through Awtarchy's Bluetooth UI.

set -euo pipefail

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="${STATE_HOME}/awtarchy"
STATE_FILE="${STATE_DIR}/bluetooth-state"

usage() {
    printf 'usage: quickshell_bluetooth_state.sh set <enabled|disabled> | restore | status\n' >&2
    exit 2
}

need_rfkill() {
    command -v rfkill >/dev/null 2>&1 || {
        printf 'quickshell_bluetooth_state.sh: rfkill is required\n' >&2
        return 127
    }
}

apply_state() {
    case "$1" in
        enabled) rfkill unblock bluetooth ;;
        disabled) rfkill block bluetooth ;;
        *) return 2 ;;
    esac
}

save_state() {
    local state="$1" tmp
    mkdir -p -- "$STATE_DIR"
    tmp="${STATE_FILE}.tmp.$$"
    printf '%s\n' "$state" >"$tmp"
    chmod 0600 -- "$tmp" 2>/dev/null || true
    mv -f -- "$tmp" "$STATE_FILE"
}

command_name="${1:-}"
case "$command_name" in
    set)
        state="${2:-}"
        [[ "$state" == "enabled" || "$state" == "disabled" ]] || usage
        [[ $# -eq 2 ]] || usage
        need_rfkill
        save_state "$state"
        apply_state "$state"
        ;;
    restore)
        [[ $# -eq 1 ]] || usage
        [[ -r "$STATE_FILE" ]] || exit 0
        IFS= read -r state <"$STATE_FILE" || state=""
        case "$state" in
            enabled|disabled) ;;
            *)
                printf 'quickshell_bluetooth_state.sh: ignoring invalid saved state\n' >&2
                exit 0
                ;;
        esac
        need_rfkill || exit 0
        apply_state "$state" || true
        ;;
    status)
        [[ $# -eq 1 ]] || usage
        if [[ -r "$STATE_FILE" ]]; then
            cat -- "$STATE_FILE"
        else
            printf 'unset\n'
        fi
        ;;
    *) usage ;;
esac
