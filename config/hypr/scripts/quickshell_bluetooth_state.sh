#!/usr/bin/env bash
# Persist Bluetooth choices without rfkill-hiding adapters from Quickshell/BlueZ.

set -euo pipefail

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="${STATE_HOME}/awtarchy"
STATE_FILE="${STATE_DIR}/bluetooth-state"
BLUETOOTH_CLASS_DIR="${AWTARCHY_BLUETOOTH_CLASS_DIR:-/sys/class/bluetooth}"

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

need_bluetoothctl() {
    command -v bluetoothctl >/dev/null 2>&1 || {
        printf 'quickshell_bluetooth_state.sh: bluetoothctl is required\n' >&2
        return 127
    }
}

unblock_controller() {
    need_rfkill
    rfkill unblock bluetooth
}

wait_for_controller() {
    local _
    for _ in {1..20}; do
        compgen -G "${BLUETOOTH_CLASS_DIR}/hci*" >/dev/null && return 0
        sleep 0.1
    done
    return 1
}

set_adapter_power() {
    local state="$1"
    need_bluetoothctl
    wait_for_controller || return 0
    case "$state" in
        enabled) timeout 5 bluetoothctl power on >/dev/null ;;
        disabled) timeout 5 bluetoothctl power off >/dev/null ;;
        *) return 2 ;;
    esac
}

apply_state() {
    local state="$1"
    # Never use rfkill to represent the normal disabled state. Some adapters
    # disappear from /sys/class/bluetooth while software-blocked, which makes
    # BlueZ and Quickshell incorrectly conclude that no Bluetooth hardware exists.
    unblock_controller
    set_adapter_power "$state"
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
        apply_state "$state"
        ;;
    restore)
        [[ $# -eq 1 ]] || usage
        [[ -r "$STATE_FILE" ]] || exit 0
        if ! state="$(read_state)"; then
            printf 'quickshell_bluetooth_state.sh: ignoring invalid saved state\n' >&2
            exit 0
        fi
        case "$state" in
            enabled|disabled) apply_state "$state" || true ;;
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
