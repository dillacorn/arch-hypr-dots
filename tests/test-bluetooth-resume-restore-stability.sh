#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_bluetooth_state.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/bluetooth/hci0" "$tmp/state/awtarchy"

cat >"$tmp/bin/rfkill" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == unblock && ${2:-} == bluetooth ]] || exit 2
FAKE

cat >"$tmp/bin/bluetoothctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${BLUETOOTHCTL_LOG:?}"

case "${1:-}" in
    show)
        state="$(<"${BLUETOOTH_POWER_STATE_FILE:?}")"
        printf 'Controller 00:11:22:33:44:55 test\n\tPowered: %s\n' "$state"
        if [[ "$state" == no ]]; then
            relapses="$(<"${BLUETOOTH_RELAPSES_FILE:?}")"
            if (( relapses > 0 )); then
                printf '%s\n' yes >"${BLUETOOTH_POWER_STATE_FILE:?}"
                printf '%s\n' "$((relapses - 1))" >"${BLUETOOTH_RELAPSES_FILE:?}"
            fi
        fi
        ;;
    power)
        case "${2:-}" in
            on) printf '%s\n' yes >"${BLUETOOTH_POWER_STATE_FILE:?}" ;;
            off) printf '%s\n' no >"${BLUETOOTH_POWER_STATE_FILE:?}" ;;
            *) exit 2 ;;
        esac
        ;;
    *)
        exit 2
        ;;
esac
FAKE

chmod 0755 "$tmp/bin/rfkill" "$tmp/bin/bluetoothctl"

export HOME="$tmp/home"
export XDG_STATE_HOME="$tmp/state"
export PATH="$tmp/bin:$PATH"
export AWTARCHY_BLUETOOTH_CLASS_DIR="$tmp/bluetooth"
export BLUETOOTHCTL_LOG="$tmp/bluetoothctl.log"
export BLUETOOTH_POWER_STATE_FILE="$tmp/bluetooth-power-state"
export BLUETOOTH_RELAPSES_FILE="$tmp/bluetooth-relapses"

printf '%s\n' disabled >"$XDG_STATE_HOME/awtarchy/bluetooth-state"
printf '%s\n' yes >"$BLUETOOTH_POWER_STATE_FILE"
printf '%s\n' 1 >"$BLUETOOTH_RELAPSES_FILE"
: >"$BLUETOOTHCTL_LOG"

# Real #146 evidence showed restore reporting success after observing Powered:no,
# followed by BlueZ/kernel returning the adapter to Powered:yes. Treat the resume
# retry period as a stability window and reassert the saved state after a relapse.
AWTARCHY_BLUETOOTH_POWER_RETRY_SECONDS=1 "$HELPER" restore

[[ "$(<"$BLUETOOTH_POWER_STATE_FILE")" == no ]] \
    || fail 'Bluetooth restore returned while the adapter had relapsed to enabled'

off_count="$(grep -Fxc 'power off' "$BLUETOOTHCTL_LOG" || true)"
(( off_count >= 2 )) \
    || fail 'Bluetooth restore did not reassert disabled after the simulated resume relapse'

printf '%s\n' 'Bluetooth resume restore stability regression test: PASS'
