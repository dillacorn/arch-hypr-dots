#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIAGNOSTIC="${ROOT}/config/hypr/scripts/quickshell_bluetooth_resume_diagnostic.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

[[ -f "$DIAGNOSTIC" ]] || {
    printf '%s\n' 'Bluetooth resume diagnostic script is missing.' >&2
    exit 1
}

mkdir -p "$tmp/bin" "$tmp/out" "$tmp/cache/awtarchy" "$tmp/cache/hypridle" "$tmp/bluetooth/hci0" "$tmp/rfkill/rfkill0"
printf '%s\n' '0' >"$tmp/rfkill/rfkill0/soft"
printf '%s\n' '0' >"$tmp/rfkill/rfkill0/hard"
printf '%s\n' '1' >"$tmp/rfkill/rfkill0/state"
printf '%s\n' 'bluetooth' >"$tmp/rfkill/rfkill0/type"
printf '%s\n' 'hci0' >"$tmp/rfkill/rfkill0/name"
printf '%s\n' 'old resume line' >"$tmp/cache/awtarchy/quickshell-resume.log"
printf '%s\n' 'old hypridle line' >"$tmp/cache/hypridle/actions.log"

cat >"$tmp/bluetooth-state-helper" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${HELPER_LOG:?}"
case "${1:-}" in
    status) printf '%s\n' "${FAKE_SAVED_STATE:-disabled}" ;;
    actual) printf '%s\n' "${FAKE_ACTUAL_STATE:-disabled}" ;;
    *) exit 88 ;;
esac
FAKE

cat >"$tmp/bin/systemctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${SYSTEMCTL_LOG:?}"
case "${1:-}" in
    suspend) exit 0 ;;
    status) printf '%s\n' 'bluetooth.service active (running)' ;;
    show) printf '%s\n' 'ActiveState=active' 'SubState=running' ;;
    *) exit 0 ;;
esac
FAKE

cat >"$tmp/bin/bluetoothctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    show)
        printf '%s\n' 'Controller AA:BB:CC:DD:EE:FF Test Adapter' '    Powered: no' '    Discovering: no'
        ;;
    --version|-v)
        printf '%s\n' 'bluetoothctl: 5.test'
        ;;
    *)
        printf '%s\n' 'bluetoothctl fake output'
        ;;
esac
FAKE

cat >"$tmp/bin/rfkill" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == event ]]; then
    printf '%s\n' '2026-09-05 20:00:00 rfkill event bluetooth soft=0 hard=0'
    sleep 5
else
    printf '%s\n' '0: hci0: Bluetooth' '    Soft blocked: no' '    Hard blocked: no'
fi
FAKE

cat >"$tmp/bin/dbus-monitor" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' \
    "signal time=1.000 sender=:1.9 path=/org/bluez/hci0; interface=org.freedesktop.DBus.Properties; member=PropertiesChanged" \
    '   string "org.bluez.Adapter1"' \
    '   string "Powered"' \
    '   boolean false' \
    "signal time=1.100 sender=:1.9 path=/org/bluez/hci0; interface=org.freedesktop.DBus.Properties; member=PropertiesChanged" \
    '   string "org.bluez.Adapter1"' \
    '   string "Discoverable"' \
    '   boolean true'
sleep 5
FAKE

cat >"$tmp/bin/udevadm" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == monitor ]]; then
    printf '%s\n' 'UDEV [1.000] change /devices/test/bluetooth/hci0 (bluetooth)'
    sleep 5
else
    printf '%s\n' 'udevadm fake output'
fi
FAKE

cat >"$tmp/bin/busctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *'get-property'* ]]; then
    printf '%s\n' 'b false'
elif [[ "$*" == *'tree'* ]]; then
    printf '%s\n' '`-/org/bluez/hci0'
else
    printf '%s\n' 'busctl fake output'
fi
FAKE

cat >"$tmp/bin/journalctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'Sep 05 20:00:01 host bluetoothd[100]: Adapter AA:BB:CC:DD:EE:FF resumed' 'Sep 05 20:00:01 host kernel: Bluetooth: hci0 resumed'
FAKE

cat >"$tmp/bin/loginctl" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' 'session-status fake'
FAKE

cat >"$tmp/bin/lsusb" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' 'Bus 001 Device 001: ID 1234:5678 Bluetooth Adapter'
FAKE

cat >"$tmp/bin/lspci" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' '00:14.0 Network controller: Test Bluetooth companion'
FAKE

cat >"$tmp/bin/pacman" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' 'bluez 5.test' 'bluez-utils 5.test'
FAKE

chmod 0755 "$tmp/bluetooth-state-helper" "$tmp/bin/"*

export PATH="$tmp/bin:$PATH"
export HELPER_LOG="$tmp/helper.log"
export SYSTEMCTL_LOG="$tmp/systemctl.log"
export XDG_CACHE_HOME="$tmp/cache"

# The diagnostic must refuse to start a suspend cycle unless both the saved
# Awtarchy preference and the actual BlueZ state are already disabled.
: >"$SYSTEMCTL_LOG"
FAKE_SAVED_STATE=enabled \
FAKE_ACTUAL_STATE=disabled \
AWTARCHY_BLUETOOTH_STATE_SCRIPT="$tmp/bluetooth-state-helper" \
AWTARCHY_BLUETOOTH_DIAGNOSTIC_OUTPUT="$tmp/out/refused.txt" \
AWTARCHY_BLUETOOTH_CLASS_DIR="$tmp/bluetooth" \
AWTARCHY_RFKILL_CLASS_DIR="$tmp/rfkill" \
AWTARCHY_BLUETOOTH_DIAGNOSTIC_START_DELAY=0.2 \
AWTARCHY_BLUETOOTH_DIAGNOSTIC_POST_SECONDS=0 \
AWTARCHY_BLUETOOTH_DIAGNOSTIC_SAMPLE_INTERVAL=0.01 \
    bash "$DIAGNOSTIC" --cycles 1 >/dev/null 2>&1 && {
        printf '%s\n' 'Diagnostic suspended even though saved Bluetooth preference was enabled.' >&2
        exit 1
    }
if grep -Fxq 'suspend' "$SYSTEMCTL_LOG"; then
    printf '%s\n' 'Diagnostic called systemctl suspend after failing its preflight.' >&2
    exit 1
fi

# A successful run may perform multiple suspend/resume cycles while remaining
# read-only with respect to Bluetooth state. It emits one sanitized report.
: >"$HELPER_LOG"
: >"$SYSTEMCTL_LOG"
rm -f -- "$tmp/out/"*
report="$tmp/out/report.txt"
FAKE_SAVED_STATE=disabled \
FAKE_ACTUAL_STATE=disabled \
AWTARCHY_BLUETOOTH_STATE_SCRIPT="$tmp/bluetooth-state-helper" \
AWTARCHY_BLUETOOTH_DIAGNOSTIC_OUTPUT="$report" \
AWTARCHY_BLUETOOTH_CLASS_DIR="$tmp/bluetooth" \
AWTARCHY_RFKILL_CLASS_DIR="$tmp/rfkill" \
AWTARCHY_BLUETOOTH_RESUME_LOG="$tmp/cache/awtarchy/quickshell-resume.log" \
AWTARCHY_HYPRIDLE_ACTION_LOG="$tmp/cache/hypridle/actions.log" \
AWTARCHY_BLUETOOTH_DIAGNOSTIC_START_DELAY=0.2 \
AWTARCHY_BLUETOOTH_DIAGNOSTIC_POST_SECONDS=0 \
AWTARCHY_BLUETOOTH_DIAGNOSTIC_SAMPLE_INTERVAL=0.01 \
    bash "$DIAGNOSTIC" --cycles 2 >/dev/null

[[ -s "$report" ]]
[[ "$(grep -Fxc 'suspend' "$SYSTEMCTL_LOG")" -eq 2 ]]
[[ "$(find "$tmp/out" -maxdepth 1 -type f | wc -l)" -eq 1 ]]

for marker in \
    'Awtarchy Bluetooth Suspend/Resume Diagnostic' \
    'CYCLE 1 PRE-SUSPEND' \
    'CYCLE 1 POST-RESUME' \
    'CYCLE 2 PRE-SUSPEND' \
    'CYCLE 2 POST-RESUME' \
    'SAVED AWTARCHY PREFERENCE' \
    'ACTUAL BLUEZ POWER STATE' \
    'BLUETOOTHCTL SHOW' \
    'RFKILL STATE' \
    'HIGH-RESOLUTION ADAPTER TIMELINE' \
    'BLUEZ ADAPTER DBUS EVENTS' \
    'RFKILL EVENTS' \
    'UDEV BLUETOOTH EVENTS' \
    'AWTARCHY RESUME RECOVERY LOG' \
    'HYPRIDLE ACTION LOG' \
    'BLUETOOTH SERVICE JOURNAL' \
    'KERNEL SUSPEND/BLUETOOTH JOURNAL' \
    'SYSTEM AND BLUETOOTH VERSIONS'
do
    grep -Fq "$marker" "$report" || {
        printf 'Diagnostic report is missing section: %s\n' "$marker" >&2
        exit 1
    }
done

grep -Fq 'disabled' "$report"
grep -Fq '<MAC>' "$report"
if grep -Fq 'AA:BB:CC:DD:EE:FF' "$report"; then
    printf '%s\n' 'Diagnostic report leaked an unsanitized Bluetooth MAC address.' >&2
    exit 1
fi
if grep -Fq 'adapter_powered_true_observed=yes' "$report"; then
    printf '%s\n' 'Diagnostic misclassified an unrelated Adapter1 boolean=true event as Bluetooth Powered=true.' >&2
    exit 1
fi
grep -Fq 'classification=no powered-on event observed in this cycle' "$report"
if grep -Eq '^(restore|set)([[:space:]]|$)' "$HELPER_LOG"; then
    printf '%s\n' 'Diagnostic changed Bluetooth state instead of remaining observational.' >&2
    exit 1
fi

grep -Fxq 'status' "$HELPER_LOG"
grep -Fxq 'actual' "$HELPER_LOG"

printf '%s\n' 'Bluetooth suspend/resume diagnostic regression test: PASS'
