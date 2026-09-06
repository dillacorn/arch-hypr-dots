#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$HELPER" ]] || fail 'power-profile-helper is missing'

grep -Fq 'setcharge' "$HELPER" \
    || fail 'battery helper does not use TLP as the hardware write boundary'

if grep -Eq 'verify_enabled_state|verify_disabled_state|battery_observed_stop_values|battery_verify_' "$HELPER"; then
    fail 'Awtarchy still owns hardware-specific battery read-back verification'
fi

if grep -Eq 'charge_control_(start|end)_threshold.*>|battery_care_(limit|limiter).*>' "$HELPER"; then
    fail 'battery helper writes hardware sysfs instead of delegating to TLP'
fi

printf '%s\n' 'PASS: battery hardware read-back policy is delegated to TLP.'
