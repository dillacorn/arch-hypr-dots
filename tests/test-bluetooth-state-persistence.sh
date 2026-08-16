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
printf '%s\n' "$*" >>"${BLUETOOTHCTL_LOG:?}"
FAKE
chmod 0755 "$tmp/bin/rfkill" "$tmp/bin/bluetoothctl"

export HOME="$tmp/home"
export XDG_STATE_HOME="$tmp/state"
export RFKILL_LOG="$tmp/rfkill.log"
export BLUETOOTHCTL_LOG="$tmp/bluetoothctl.log"
export AWTARCHY_BLUETOOTH_CLASS_DIR="$tmp/bluetooth"
export PATH="$tmp/bin:$PATH"
state_file="$XDG_STATE_HOME/awtarchy/bluetooth-state"

"$HELPER" restore
[[ ! -e "$state_file" ]]
[[ ! -e "$RFKILL_LOG" ]]
[[ ! -e "$BLUETOOTHCTL_LOG" ]]

"$HELPER" set disabled
grep -Fxq 'disabled' "$state_file"
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"
grep -Fxq 'power off' "$BLUETOOTHCTL_LOG"
if grep -Fxq 'block bluetooth' "$RFKILL_LOG"; then
    printf '%s\n' 'Disabling Bluetooth still rfkill-blocks the controller and can hide the HCI device.' >&2
    exit 1
fi

: >"$RFKILL_LOG"
: >"$BLUETOOTHCTL_LOG"
"$HELPER" restore
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"
grep -Fxq 'power off' "$BLUETOOTHCTL_LOG"

: >"$RFKILL_LOG"
: >"$BLUETOOTHCTL_LOG"
"$HELPER" set enabled
grep -Fxq 'enabled' "$state_file"
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"
grep -Fxq 'power on' "$BLUETOOTHCTL_LOG"

printf 'invalid\n' >"$state_file"
: >"$RFKILL_LOG"
: >"$BLUETOOTHCTL_LOG"
"$HELPER" restore
[[ ! -s "$RFKILL_LOG" ]]
[[ ! -s "$BLUETOOTHCTL_LOG" ]]

grep -Fq 'Component.onCompleted: bluetoothRestore.exec([bluetoothStateScript, "restore"])' "$MENU"
grep -Fq 'bluetoothEnable.exec([bluetoothStateScript, "set", "enabled"]);' "$MENU"
grep -Fq 'bluetoothDisable.exec([bluetoothStateScript, "set", "disabled"]);' "$MENU"
# shellcheck disable=SC2016
grep -Fq 'kill -TERM -- "$pid"' "$MANAGER"
if grep -Fq 'kill -KILL -- "$pid"' "$MANAGER"; then
    printf '%s\n' 'Quickshell updater still contains SIGKILL fallback.' >&2
    exit 1
fi

printf '%s\n' 'Bluetooth persistence/self-lockout regression test: PASS'
