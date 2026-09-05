#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_bluetooth_state.sh"
MENU="${ROOT}/config/quickshell/awtarchy/BluetoothMenu.qml"
MANAGER="${ROOT}/config/hypr/scripts/quickshell.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/bluetooth/hci0"
cat >"$tmp/bin/rfkill" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${RFKILL_LOG:?}"
FAKE
cat >"$tmp/bin/bluetoothctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${BLUETOOTHCTL_LOG:?}"
case "${1:-}" in
    show)
        printf 'Controller 00:11:22:33:44:55 test\n\tPowered: %s\n' "$(<"${BLUETOOTH_POWER_STATE_FILE:?}")"
        ;;
    power)
        failures="$(<"${BLUETOOTH_POWER_FAILURES_FILE:?}")"
        if (( failures > 0 )); then
            printf '%s\n' "$((failures - 1))" >"${BLUETOOTH_POWER_FAILURES_FILE:?}"
            exit 1
        fi
        case "${2:-}" in
            on) printf '%s\n' yes >"${BLUETOOTH_POWER_STATE_FILE:?}" ;;
            off) printf '%s\n' no >"${BLUETOOTH_POWER_STATE_FILE:?}" ;;
            *) exit 2 ;;
        esac
        ;;
esac
FAKE
chmod 0755 "$tmp/bin/rfkill" "$tmp/bin/bluetoothctl"

export HOME="$tmp/home"
export XDG_STATE_HOME="$tmp/state"
export RFKILL_LOG="$tmp/rfkill.log"
export BLUETOOTHCTL_LOG="$tmp/bluetoothctl.log"
export BLUETOOTH_POWER_STATE_FILE="$tmp/bluetooth-power-state"
export BLUETOOTH_POWER_FAILURES_FILE="$tmp/bluetooth-power-failures"
export AWTARCHY_BLUETOOTH_CLASS_DIR="$tmp/bluetooth"
export PATH="$tmp/bin:$PATH"
state_file="$XDG_STATE_HOME/awtarchy/bluetooth-state"
printf '%s\n' yes >"$BLUETOOTH_POWER_STATE_FILE"
printf '%s\n' 0 >"$BLUETOOTH_POWER_FAILURES_FILE"

"$HELPER" restore
[[ ! -e "$state_file" ]]
[[ ! -e "$RFKILL_LOG" ]]
[[ ! -e "$BLUETOOTHCTL_LOG" ]]

"$HELPER" set disabled
grep -Fxq 'disabled' "$state_file"
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"
grep -Fxq 'power off' "$BLUETOOTHCTL_LOG"
[[ "$("$HELPER" actual)" == disabled ]]
if grep -Fxq 'block bluetooth' "$RFKILL_LOG"; then
    printf '%s\n' 'Disabling Bluetooth still rfkill-blocks the controller and can hide the HCI device.' >&2
    exit 1
fi

: >"$RFKILL_LOG"
: >"$BLUETOOTHCTL_LOG"
"$HELPER" restore
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"
grep -Fxq 'power off' "$BLUETOOTHCTL_LOG"
[[ "$("$HELPER" actual)" == disabled ]]

: >"$RFKILL_LOG"
: >"$BLUETOOTHCTL_LOG"
"$HELPER" set enabled
grep -Fxq 'enabled' "$state_file"
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"
grep -Fxq 'power on' "$BLUETOOTHCTL_LOG"
[[ "$("$HELPER" actual)" == enabled ]]

printf 'invalid\n' >"$state_file"
: >"$RFKILL_LOG"
: >"$BLUETOOTHCTL_LOG"
"$HELPER" restore
[[ ! -s "$RFKILL_LOG" ]]
[[ ! -s "$BLUETOOTHCTL_LOG" ]]

# After resume the HCI device can exist before BlueZ accepts adapter power changes.
# A failed first power command must be retried until the requested state is observed.
printf '%s\n' disabled >"$state_file"
printf '%s\n' yes >"$BLUETOOTH_POWER_STATE_FILE"
printf '%s\n' 1 >"$BLUETOOTH_POWER_FAILURES_FILE"
: >"$RFKILL_LOG"
: >"$BLUETOOTHCTL_LOG"
AWTARCHY_BLUETOOTH_POWER_RETRY_SECONDS=2 "$HELPER" restore
[[ "$(<"$BLUETOOTH_POWER_STATE_FILE")" == no ]]
[[ "$(grep -Fxc 'power off' "$BLUETOOTHCTL_LOG")" -eq 2 ]]
grep -Fxq 'show' "$BLUETOOTHCTL_LOG"
[[ "$("$HELPER" actual)" == disabled ]]

grep -Fq 'Component.onCompleted: bluetoothRestore.exec([bluetoothStateScript, "restore"])' "$MENU"
grep -Fq 'bluetoothEnable.exec([bluetoothStateScript, "set", "enabled"]);' "$MENU"
grep -Fq 'bluetoothDisable.exec([bluetoothStateScript, "set", "disabled"]);' "$MENU"
grep -Fq 'property int actualAdapterEnabled: -1' "$MENU"
grep -Fq 'actualAdapterEnabled >= 0' "$MENU"
grep -Fq 'bluetoothPowerProbe.exec([bluetoothStateScript, "actual"])' "$MENU"
grep -Fq 'id: bluetoothPowerProbe' "$MENU"
grep -Fq 'stdout: StdioCollector' "$MENU"

grep -Fq 'property bool bluetoothPowerProbePending: false' "$MENU" || {
    printf '%s\n' 'Bluetooth power-state refreshes can still be dropped while a probe is already running.' >&2
    exit 1
}
probe_refresh_block="$(sed -n '/function refreshActualAdapterPower()/,/^    }/p' "$MENU")"
grep -Fq 'if (bluetoothPowerProbe.running)' <<<"$probe_refresh_block" || {
    printf '%s\n' 'Bluetooth refresh does not detect an in-flight power probe.' >&2
    exit 1
}
grep -Fq 'bluetoothPowerProbePending = true;' <<<"$probe_refresh_block" || {
    printf '%s\n' 'Bluetooth refresh does not preserve a refresh requested during an in-flight probe.' >&2
    exit 1
}
grep -Fq 'bluetoothPowerProbePending = false;' <<<"$probe_refresh_block" || {
    printf '%s\n' 'Bluetooth refresh does not clear the pending marker before starting the authoritative probe.' >&2
    exit 1
}
grep -Fq 'if (root.bluetoothPowerProbePending)' "$MENU" || {
    printf '%s\n' 'Bluetooth power probe does not schedule a queued authoritative refresh after it exits.' >&2
    exit 1
}
grep -Fq 'Qt.callLater(() => root.refreshActualAdapterPower());' "$MENU" || {
    printf '%s\n' 'Bluetooth power probe does not re-run the queued authoritative refresh.' >&2
    exit 1
}

open_block="$(sed -n '/function openForScreen(targetScreen)/,/^    }/p' "$MENU")"
grep -Fq 'refreshActualAdapterPower();' <<<"$open_block" || {
    printf '%s\n' 'Bluetooth flyout does not refresh the authoritative BlueZ power state when opened.' >&2
    exit 1
}
grep -Fq 'function onStateChanged() { root.refreshActualAdapterPower(); }' "$MENU" || {
    printf '%s\n' 'Quickshell adapter state changes do not re-probe the authoritative BlueZ power state.' >&2
    exit 1
}
if grep -Fq 'if (root.adapter.state === BluetoothAdapterState.Enabled)' "$MENU"; then
    printf '%s\n' 'Bluetooth UI can overwrite the probed BlueZ power state with stale Quickshell adapter state.' >&2
    exit 1
fi

grep -Fq 'signal.pidfd_send_signal(pidfd, signal.SIGTERM)' "$MANAGER"
if grep -Fq 'signal.SIGKILL' "$MANAGER" || grep -Fq 'kill -KILL' "$MANAGER"; then
    printf '%s\n' 'Quickshell updater still contains a SIGKILL fallback.' >&2
    exit 1
fi

printf '%s\n' 'Bluetooth persistence/state-sync regression test: PASS'
