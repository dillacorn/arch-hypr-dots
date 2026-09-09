#!/usr/bin/env bash
# Persist Bluetooth choices without rfkill-hiding adapters from Quickshell/BlueZ.

set -euo pipefail

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="${STATE_HOME}/awtarchy"
STATE_FILE="${STATE_DIR}/bluetooth-state"
BLUETOOTH_CLASS_DIR="${AWTARCHY_BLUETOOTH_CLASS_DIR:-/sys/class/bluetooth}"
BLUETOOTH_WAIT_ATTEMPTS="${AWTARCHY_BLUETOOTH_WAIT_ATTEMPTS:-20}"
BLUETOOTH_POWER_RETRY_SECONDS="${AWTARCHY_BLUETOOTH_POWER_RETRY_SECONDS:-0}"

if [[ ! "$BLUETOOTH_WAIT_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
    BLUETOOTH_WAIT_ATTEMPTS=20
fi
if [[ ! "$BLUETOOTH_POWER_RETRY_SECONDS" =~ ^[0-9]+$ ]]; then
    BLUETOOTH_POWER_RETRY_SECONDS=0
fi

usage() {
    printf 'usage: quickshell_bluetooth_state.sh set <enabled|disabled> | restore | status | actual\n' >&2
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
    local attempt
    for ((attempt = 1; attempt <= BLUETOOTH_WAIT_ATTEMPTS; attempt++)); do
        compgen -G "${BLUETOOTH_CLASS_DIR}/hci*" >/dev/null && return 0
        sleep 0.1
    done
    return 1
}

read_actual_power() {
    local output=""

    need_bluetoothctl
    wait_for_controller || return 1
    output="$(timeout 5 bluetoothctl show 2>/dev/null)" || return 1

    if grep -Eq '^[[:space:]]*Powered:[[:space:]]*yes[[:space:]]*$' <<<"$output"; then
        printf 'enabled\n'
        return 0
    fi
    if grep -Eq '^[[:space:]]*Powered:[[:space:]]*no[[:space:]]*$' <<<"$output"; then
        printf 'disabled\n'
        return 0
    fi

    return 1
}

adapter_power_matches() {
    local state="$1" expected="" output=""
    case "$state" in
        enabled) expected=yes ;;
        disabled) expected=no ;;
        *) return 2 ;;
    esac

    output="$(timeout 5 bluetoothctl show 2>/dev/null)" || return 1
    grep -Eq "^[[:space:]]*Powered:[[:space:]]*${expected}[[:space:]]*$" <<<"$output"
}

set_adapter_power() {
    local state="$1" deadline
    need_bluetoothctl
    wait_for_controller || return 1
    deadline=$((SECONDS + BLUETOOTH_POWER_RETRY_SECONDS))

    while true; do
        case "$state" in
            enabled) timeout 5 bluetoothctl power on >/dev/null 2>&1 || true ;;
            disabled) timeout 5 bluetoothctl power off >/dev/null 2>&1 || true ;;
            *) return 2 ;;
        esac

        if adapter_power_matches "$state"; then
            if (( BLUETOOTH_POWER_RETRY_SECONDS == 0 )); then
                return 0
            fi

            # Resume can briefly reach the requested BlueZ state before the
            # kernel/firmware finishes restoring the adapter and powers it back
            # on. Treat the retry period as a stability window, not merely a
            # retry-on-failure timeout. Reassert only if the state relapses.
            while (( SECONDS < deadline )); do
                sleep 0.1
                adapter_power_matches "$state" || break
            done

            if adapter_power_matches "$state"; then
                return 0
            fi
        fi

        if (( BLUETOOTH_POWER_RETRY_SECONDS == 0 || SECONDS >= deadline )); then
            return 1
        fi
        sleep 0.1
    done
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
            enabled|disabled) apply_state "$state" ;;
            unset) ;;
        esac
        ;;
    status)
        [[ $# -eq 1 ]] || usage
        if ! read_state; then
            printf 'unset\n'
        fi
        ;;
    actual)
        [[ $# -eq 1 ]] || usage
        read_actual_power
        ;;
    *) usage ;;
esac
