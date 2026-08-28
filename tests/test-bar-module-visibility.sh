#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="${ROOT}/config/hypr/scripts/quickshell.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

# Existing installations and newly discovered monitors must preserve the stock
# bar by default: CPU usage, CPU temperature, and RAM usage all stay visible.
contains "$MANAGER" 'show_cpu:true' \
    'quickshell state normalization does not default CPU usage to visible'
contains "$MANAGER" 'show_temp:true' \
    'quickshell state normalization does not default CPU temperature to visible'
contains "$MANAGER" 'show_memory:true' \
    'quickshell state normalization does not default RAM usage to visible'

for command in getshowcpu getshowtemp getshowmemory setshowcpu setshowtemp setshowmemory; do
    contains "$MANAGER" "$command" \
        "quickshell manager is missing ${command}"
done
contains "$MANAGER" '.monitors[$monitor].show_cpu = $enabled' \
    'CPU visibility is not persisted per monitor'
contains "$MANAGER" '.monitors[$monitor].show_temp = $enabled' \
    'CPU temperature visibility is not persisted per monitor'
contains "$MANAGER" '.monitors[$monitor].show_memory = $enabled' \
    'RAM visibility is not persisted per monitor'

contains "$BAR_STATE" 'function cpuUsageVisibleFor(name)' \
    'BarState has no CPU usage visibility resolver'
contains "$BAR_STATE" 'function cpuTempVisibleFor(name)' \
    'BarState has no CPU temperature visibility resolver'
contains "$BAR_STATE" 'function memoryUsageVisibleFor(name)' \
    'BarState has no RAM visibility resolver'

[[ $(grep -Fc 'visible: BarState.cpuUsageVisibleFor(bar.monitorName)' "$BAR_QML") -eq 2 ]] \
    || fail 'CPU usage visibility is not applied to both horizontal and vertical bars'
[[ $(grep -Fc 'visible: BarState.cpuTempVisibleFor(bar.monitorName)' "$BAR_QML") -eq 2 ]] \
    || fail 'CPU temperature visibility is not applied to both horizontal and vertical bars'
[[ $(grep -Fc 'visible: BarState.memoryUsageVisibleFor(bar.monitorName)' "$BAR_QML") -eq 2 ]] \
    || fail 'RAM visibility is not applied to both horizontal and vertical bars'

contains "$BAR_SETTINGS" 'text: "System stats"' \
    'Bar Appearance has no System stats visibility row'
for label in 'label: "CPU"' 'label: "Temp"' 'label: "RAM"'; do
    contains "$BAR_SETTINGS" "$label" \
        "Bar Appearance is missing the ${label#*: } visibility toggle"
done
for command in setshowcpu setshowtemp setshowmemory; do
    contains "$BAR_SETTINGS" "\"${command}\"" \
        "Bar Appearance does not persist ${command}"
done

printf '%s\n' 'PASS: CPU, temperature, and RAM bar modules are independently optional while remaining visible by default.'
