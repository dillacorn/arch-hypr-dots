#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
CARD="${ROOT}/config/quickshell/awtarchy/BatteryCareCard.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_json() {
    local json="$1" filter="$2" description="$3"
    jq -e "$filter" <<<"$json" >/dev/null || fail "$description: $json"
}

make_battery() {
    local root="$1"
    mkdir -p -- "$root/BAT0"
    printf '%s\n' Battery >"$root/BAT0/type"
    printf '%s\n' TestVendor >"$root/BAT0/manufacturer"
    printf '%s\n' TestModel >"$root/BAT0/model_name"
}

command -v jq >/dev/null 2>&1 || fail 'jq is required'

# energy_* is the preferred laptop battery capacity source because it allows
# human-readable Wh reporting as well as the health ratio.
energy_root="$TMP/energy"
make_battery "$energy_root"
printf '%s\n' 25330000 >"$energy_root/BAT0/energy_full"
printf '%s\n' 62640000 >"$energy_root/BAT0/energy_full_design"
json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$energy_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/no-tlp" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.health.supported == true and .health.source == "sysfs-energy"' \
    'energy capacity health fallback was not detected'
assert_json "$json" '.health.percentage == 40' \
    'energy capacity health percentage was not rounded correctly'
assert_json "$json" '.health.full_wh == 25.33 and .health.design_wh == 62.64' \
    'energy capacity Wh values were not exposed'

# Some drivers expose charge_* rather than energy_*. The ratio remains valid
# even when voltage data is unavailable, so report the percentage without
# pretending the values are watt-hours.
charge_root="$TMP/charge"
make_battery "$charge_root"
printf '%s\n' 4500000 >"$charge_root/BAT0/charge_full"
printf '%s\n' 6000000 >"$charge_root/BAT0/charge_full_design"
json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$charge_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/no-tlp" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.health.supported == true and .health.source == "sysfs-charge"' \
    'charge capacity health fallback was not detected'
assert_json "$json" '.health.percentage == 75 and .health.full_ah == 4.5 and .health.design_ah == 6' \
    'charge capacity health values were not exposed correctly'

# Invalid or unavailable design capacity must fail closed instead of fabricating
# a battery-health percentage.
invalid_root="$TMP/invalid"
make_battery "$invalid_root"
printf '%s\n' 25000000 >"$invalid_root/BAT0/energy_full"
printf '%s\n' 0 >"$invalid_root/BAT0/energy_full_design"
json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$invalid_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/no-tlp" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.health.supported == false and .health.percentage == null' \
    'invalid design capacity produced fake health data'

grep -Fq 'text: "Battery Care"' "$CARD" \
    || fail 'charge-preservation controls are still mislabeled Battery Health'
grep -Fq 'text: "Battery Health"' "$CARD" \
    || fail 'physical battery health heading is missing from BatteryCareCard'
grep -Fq 'Capacity health:' "$CARD" \
    || fail 'BatteryCareCard does not present physical capacity health'
grep -Fq 'BatteryState.healthSupported' "$CARD" \
    || fail 'BatteryCareCard does not prefer native UPower health when available'

if grep -Eq '(^|[[:space:]])(sudo|pkexec)([[:space:]]|$)' "$SCRIPT"; then
    fail 'read-only battery health detection contains a privileged path'
fi

printf '%s\n' 'Battery capacity-health fallback regression tests passed.'
