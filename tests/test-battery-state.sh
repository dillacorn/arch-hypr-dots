#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${ROOT}/config/quickshell/awtarchy/BatteryState.qml"
BAR="${ROOT}/config/quickshell/awtarchy/Bar.qml"
HELPER="${ROOT}/config/hypr/scripts/quickshell_battery_telemetry.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "$STATE" ]] || fail 'BatteryState.qml is missing'

grep -Fq 'pragma Singleton' "$STATE" || fail 'battery state is not a singleton'
grep -Fq 'import Quickshell.Services.UPower' "$STATE" || fail 'battery state does not use Quickshell UPower'
grep -Fq 'readonly property real timeToEmptySeconds:' "$STATE" || fail 'time-to-empty telemetry is missing'
grep -Fq 'readonly property real timeToFullSeconds:' "$STATE" || fail 'time-to-full telemetry is missing'
grep -Fq 'readonly property real energyWh:' "$STATE" || fail 'battery energy telemetry is missing'
grep -Fq 'readonly property real energyCapacityWh:' "$STATE" || fail 'battery capacity telemetry is missing'
grep -Fq 'readonly property real changeRateWatts:' "$STATE" || fail 'battery charge-rate telemetry is missing'
grep -Fq 'readonly property int defaultHealthTargetPercent: 80' "$STATE" || fail '80 percent health target foundation is missing'
grep -Fq 'function formatDuration(seconds)' "$STATE" || fail 'duration formatting helper is missing'
grep -Fq 'function estimateChargeSeconds(targetPercent)' "$STATE" || fail 'target charge ETA helper is missing'
grep -Fq 'timeToEmptySeconds > 0' "$STATE" || fail 'tooltip does not use UPower time-to-empty'
grep -Fq 'timeToFullSeconds > 0' "$STATE" || fail 'tooltip does not use UPower time-to-full'
grep -Fq '" remaining"' "$STATE" || fail 'discharge tooltip does not expose remaining time'
grep -Fq '" to 100%"' "$STATE" || fail 'charge tooltip does not expose full-charge ETA'

if grep -Fq 'import Quickshell.Services.UPower' "$BAR"; then
  fail 'Bar.qml still imports UPower directly instead of BatteryState'
fi
if grep -Fq 'UPower.' "$BAR"; then
  fail 'Bar.qml still reads UPower directly instead of BatteryState'
fi

[[ "$(grep -Fc 'visible: BatteryState.available' "$BAR")" -eq 2 ]] \
  || fail 'horizontal and vertical battery controls are not both using BatteryState availability'
[[ "$(grep -Fc 'readonly property int pct: BatteryState.percentage' "$BAR")" -eq 2 ]] \
  || fail 'horizontal and vertical battery controls are not both using BatteryState percentage'
[[ "$(grep -Fc 'readonly property bool pluggedIn: BatteryState.pluggedIn' "$BAR")" -eq 2 ]] \
  || fail 'horizontal and vertical battery controls are not both using BatteryState power state'
[[ "$(grep -Fc 'tooltip: BatteryState.barTooltip' "$BAR")" -eq 2 ]] \
  || fail 'horizontal and vertical battery controls are not both using the ETA tooltip'

# Regression contract for issue #150. The helper is deliberately read-only and
# must only override UPower DisplayDevice when raw sysfs evidence makes a dead
# or phantom pack unambiguous. A normal or uncertain system stays on UPower.
[[ -f "$HELPER" ]] || fail 'battery telemetry override helper is missing'
grep -Fq 'AWTARCHY_POWER_SUPPLY_ROOT' "$HELPER" \
  || fail 'battery telemetry helper cannot be exercised against fixture sysfs data'
grep -Fq 'readonly property bool telemetryOverrideActive:' "$STATE" \
  || fail 'BatteryState does not expose conservative telemetry override state'
grep -Fq 'quickshell_battery_telemetry.sh' "$STATE" \
  || fail 'BatteryState does not invoke the raw battery telemetry helper'
grep -Fq 'telemetryOverrideActive ? telemetryPercentage' "$STATE" \
  || fail 'BatteryState percentage does not use the validated override'
grep -Fq 'telemetryOverrideActive ? telemetryTimeToEmptySeconds' "$STATE" \
  || fail 'BatteryState time-to-empty does not use the validated override'
grep -Fq 'telemetryOverrideActive ? telemetryTimeToFullSeconds' "$STATE" \
  || fail 'BatteryState time-to-full does not use the validated override'

make_battery() {
  local root="$1" name="$2" present="$3" voltage="$4" energy_now="$5" energy_full="$6" power_now="$7"
  local dir="$root/$name"
  mkdir -p -- "$dir"
  printf '%s\n' Battery >"$dir/type"
  [[ "$present" == - ]] || printf '%s\n' "$present" >"$dir/present"
  [[ "$voltage" == - ]] || printf '%s\n' "$voltage" >"$dir/voltage_now"
  [[ "$energy_now" == - ]] || printf '%s\n' "$energy_now" >"$dir/energy_now"
  [[ "$energy_full" == - ]] || printf '%s\n' "$energy_full" >"$dir/energy_full"
  [[ "$power_now" == - ]] || printf '%s\n' "$power_now" >"$dir/power_now"
}

run_helper() {
  local root="$1"
  AWTARCHY_POWER_SUPPLY_ROOT="$root" /usr/bin/bash "$HELPER" --status-json
}

assert_json() {
  local json="$1" filter="$2" message="$3"
  jq -e "$filter" <<<"$json" >/dev/null || fail "$message: $json"
}

# 1. Two healthy batteries: UPower remains authoritative.
fixture="$TMP/healthy-dual"
mkdir -p -- "$fixture"
make_battery "$fixture" BAT0 1 12000000 20000000 40000000 6000000
make_battery "$fixture" BAT1 1 11800000 10000000 20000000 4000000
json="$(run_helper "$fixture")"
assert_json "$json" '.override == false and .excluded == []' \
  'healthy dual-battery fixture incorrectly enabled the override'

# 2. A genuinely empty battery still has plausible voltage and must stay in the
# aggregate. Zero percent/zero energy alone is never dead-pack evidence.
fixture="$TMP/healthy-empty"
mkdir -p -- "$fixture"
make_battery "$fixture" BAT0 1 11100000 0 40000000 0
make_battery "$fixture" BAT1 1 11900000 20000000 40000000 5000000
json="$(run_helper "$fixture")"
assert_json "$json" '.override == false and .excluded == []' \
  'healthy empty battery was mistaken for a phantom pack'

# 3. Electrically dead BAT0: present, stale full capacity, but zero volts,
# zero stored energy and zero electrical flow. Only healthy BAT1 may feed the
# correction. The helper also supplies corrected ETA inputs/estimates.
fixture="$TMP/dead-plus-healthy"
mkdir -p -- "$fixture"
make_battery "$fixture" BAT0 1 0 0 40000000 0
make_battery "$fixture" BAT1 1 12000000 20000000 40000000 10000000
json="$(run_helper "$fixture")"
assert_json "$json" '
  .override == true
  and .reason == "dead-or-phantom-pack"
  and .excluded == ["BAT0"]
  and .included == ["BAT1"]
  and .percentage == 50
  and .energy_wh == 20
  and .energy_capacity_wh == 40
  and .change_rate_watts == 10
  and .time_to_empty_seconds == 7200
  and .time_to_full_seconds == 7200
' 'dead battery did not produce the expected healthy-pack telemetry override'

# 4. Single-battery systems are never reinterpreted by this workaround, even
# when the lone pack looks electrically dead. There is no second pack proving
# that DisplayDevice is being poisoned by a phantom member.
fixture="$TMP/single"
mkdir -p -- "$fixture"
make_battery "$fixture" BAT0 1 0 0 40000000 0
json="$(run_helper "$fixture")"
assert_json "$json" '.override == false and .excluded == []' \
  'single-battery system incorrectly enabled phantom-pack override'

# 5. Missing raw evidence must fail closed to UPower. This pack lacks voltage,
# so the helper is not allowed to infer that zero energy/power means dead.
fixture="$TMP/unknown"
mkdir -p -- "$fixture"
make_battery "$fixture" BAT0 1 - 0 40000000 0
make_battery "$fixture" BAT1 1 12000000 20000000 40000000 10000000
json="$(run_helper "$fixture")"
assert_json "$json" '.override == false and .reason == "insufficient-telemetry" and .excluded == []' \
  'insufficient telemetry did not fall back to UPower'

printf '%s\n' 'PASS: battery telemetry and ETA are centralized with conservative phantom-pack correction.'
