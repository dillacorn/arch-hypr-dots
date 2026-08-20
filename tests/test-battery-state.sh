#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${ROOT}/config/quickshell/awtarchy/BatteryState.qml"
BAR="${ROOT}/config/quickshell/awtarchy/Bar.qml"

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

printf '%s\n' 'PASS: battery telemetry and ETA tooltip are centralized through BatteryState.'
