#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_bluetooth_state.sh"
MENU="${ROOT}/config/quickshell/awtarchy/BluetoothMenu.qml"
MANAGER="${ROOT}/config/hypr/scripts/quickshell.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/home"
cat >"$tmp/bin/rfkill" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${RFKILL_LOG:?}"
FAKE
chmod 0755 "$tmp/bin/rfkill"

export HOME="$tmp/home"
export XDG_STATE_HOME="$tmp/state"
export RFKILL_LOG="$tmp/rfkill.log"
export PATH="$tmp/bin:$PATH"
state_file="$XDG_STATE_HOME/awtarchy/bluetooth-state"

"$HELPER" restore
[[ ! -e "$state_file" ]]
[[ ! -e "$RFKILL_LOG" ]]

"$HELPER" set disabled
grep -Fxq 'disabled' "$state_file"
[[ ! -e "$RFKILL_LOG" || ! -s "$RFKILL_LOG" ]] || {
    printf '%s\n' 'Disabling Bluetooth still rfkill-blocks the controller and can hide the HCI device.' >&2
    exit 1
}

: >"$RFKILL_LOG"
"$HELPER" prepare
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"

: >"$RFKILL_LOG"
"$HELPER" restore
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"

: >"$RFKILL_LOG"
"$HELPER" set enabled
grep -Fxq 'enabled' "$state_file"
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"

printf 'invalid\n' >"$state_file"
: >"$RFKILL_LOG"
"$HELPER" restore
[[ ! -s "$RFKILL_LOG" ]]

grep -Fq 'property string persistedBluetoothState: "unset"' "$MENU"
grep -Fq 'readonly property bool stateKnown: persistedBluetoothState === "enabled"' "$MENU"
grep -Fq 'readonly property bool available: adapter !== null || stateKnown' "$MENU"
grep -Fq 'current.enabled = false;' "$MENU"
grep -Fq 'current.enabled = true;' "$MENU"
grep -Fq 'bluetoothStateReader.exec([bluetoothStateScript, "status"]);' "$MENU"
if grep -Fq 'bluetoothDisable.exec([bluetoothStateScript, "set", "disabled"]);' "$MENU"; then
    printf '%s\n' 'Bluetooth disable still delegates radio blocking to the persistence helper.' >&2
    exit 1
fi

grep -Fq 'BLUETOOTH_STATE_HELPER=' "$MANAGER"
# shellcheck disable=SC2016
grep -Fq '"$BLUETOOTH_STATE_HELPER" prepare' "$MANAGER"
# shellcheck disable=SC2016
grep -Fq 'kill -TERM -- "$pid"' "$MANAGER"
if grep -Fq 'kill -KILL -- "$pid"' "$MANAGER"; then
    printf '%s\n' 'Quickshell updater still contains SIGKILL fallback.' >&2
    exit 1
fi

printf '%s\n' 'Bluetooth persistence/self-lockout regression test: PASS'
