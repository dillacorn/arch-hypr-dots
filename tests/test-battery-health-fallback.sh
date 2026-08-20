#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/quickshell_battery_health.sh"
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
[[ -f "$SCRIPT" ]] || fail 'battery health detector is missing'

# energy_* is preferred because it gives both a health ratio and useful Wh
# values such as the Sony test laptop's 25.3 Wh full vs 62.6 Wh design.
energy_root="$TMP/energy"
make_battery "$energy_root"
printf '%s\n' 25330000 >"$energy_root/BAT0/energy_full"
printf '%s\n' 62640000 >"$energy_root/BAT0/energy_full_design"
json="$(AWTARCHY_POWER_SUPPLY_ROOT="$energy_root" bash "$SCRIPT" --status-json)"
assert_json "$json" '.supported == true and .source == "sysfs-energy"' \
    'energy capacity health fallback was not detected'
assert_json "$json" '.percentage == 40' \
    'energy capacity health percentage was not rounded correctly'
assert_json "$json" '.full_wh == 25.33 and .design_wh == 62.64' \
    'energy capacity Wh values were not exposed'

# Some drivers expose charge_* rather than energy_*. The ratio remains valid
# without inventing watt-hours when voltage data is unavailable.
charge_root="$TMP/charge"
make_battery "$charge_root"
printf '%s\n' 4500000 >"$charge_root/BAT0/charge_full"
printf '%s\n' 6000000 >"$charge_root/BAT0/charge_full_design"
json="$(AWTARCHY_POWER_SUPPLY_ROOT="$charge_root" bash "$SCRIPT" --status-json)"
assert_json "$json" '.supported == true and .source == "sysfs-charge"' \
    'charge capacity health fallback was not detected'
assert_json "$json" '.percentage == 75 and .full_ah == 4.5 and .design_ah == 6' \
    'charge capacity health values were not exposed correctly'

# Invalid design capacity must fail closed instead of fabricating a percentage.
invalid_root="$TMP/invalid"
make_battery "$invalid_root"
printf '%s\n' 25000000 >"$invalid_root/BAT0/energy_full"
printf '%s\n' 0 >"$invalid_root/BAT0/energy_full_design"
json="$(AWTARCHY_POWER_SUPPLY_ROOT="$invalid_root" bash "$SCRIPT" --status-json)"
assert_json "$json" '.supported == false and .percentage == null' \
    'invalid design capacity produced fake health data'

grep -Fq 'text: "Battery Care"' "$CARD" \
    || fail 'charge-preservation controls are still mislabeled Battery Health'
grep -Fq 'text: "Battery Health"' "$CARD" \
    || fail 'physical battery health heading is missing from BatteryCareCard'
grep -Fq 'Capacity health:' "$CARD" \
    || fail 'BatteryCareCard does not present physical capacity health'
grep -Fq 'BatteryState.healthSupported' "$CARD" \
    || fail 'BatteryCareCard does not prefer native UPower health when available'
grep -Fq 'quickshell_battery_health.sh' "$CARD" \
    || fail 'BatteryCareCard does not load the sysfs health fallback'
grep -Fq 'Supported charge targets:' "$CARD" \
    || fail 'Battery Care does not label limiter percentages as charge targets'
if grep -Fq 'Supported health targets:' "$CARD"; then
    fail 'charge-limit percentages are still mislabeled as battery health'
fi

if grep -Eq '(^|[[:space:]])(sudo|pkexec)([[:space:]]|$)' "$SCRIPT"; then
    fail 'read-only battery health detection contains a privileged path'
fi

printf '%s\n' 'Battery capacity-health fallback regression tests passed.'
