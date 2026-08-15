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
grep -Fxq 'block bluetooth' "$RFKILL_LOG"

: >"$RFKILL_LOG"
"$HELPER" restore
grep -Fxq 'block bluetooth' "$RFKILL_LOG"

: >"$RFKILL_LOG"
"$HELPER" set enabled
grep -Fxq 'enabled' "$state_file"
grep -Fxq 'unblock bluetooth' "$RFKILL_LOG"

printf 'invalid\n' >"$state_file"
: >"$RFKILL_LOG"
"$HELPER" restore
[[ ! -s "$RFKILL_LOG" ]]

grep -Fq 'bluetoothStateScript' "$MENU"
grep -Fq 'bluetoothEnable.exec([bluetoothStateScript, "set", "enabled"]);' "$MENU"
grep -Fq 'bluetoothDisable.exec([bluetoothStateScript, "set", "disabled"]);' "$MENU"
grep -Fq 'Component.onCompleted: bluetoothRestore.exec([bluetoothStateScript, "restore"])' "$MENU"
if grep -Fq 'current.enabled = nextEnabled;' "$MENU"; then
    printf '%s\n' 'Legacy non-persistent Bluetooth toggle is still present.' >&2
    exit 1
fi
# shellcheck disable=SC2016
grep -Fq 'kill -KILL -- "$pid"' "$MANAGER"

printf '%s\n' 'Bluetooth persistence regression test: PASS'
