#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="${ROOT}/config/hypr/scripts/quickshell.sh"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

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
contains "$MANAGER" 'set_monitor_stat_visibility "$2" show_cpu "$3"' \
    'CPU visibility is not persisted per monitor'
contains "$MANAGER" 'set_monitor_stat_visibility "$2" show_temp "$3"' \
    'CPU temperature visibility is not persisted per monitor'
contains "$MANAGER" 'set_monitor_stat_visibility "$2" show_memory "$3"' \
    'RAM visibility is not persisted per monitor'

contains "$BAR_QML" 'function barModuleVisible(name, module)' \
    'Bar has no per-display system-stat visibility resolver'
[[ $(grep -Fc 'visible: bar.barModuleVisible(bar.monitorName, "cpu")' "$BAR_QML") -eq 2 ]] \
    || fail 'CPU usage visibility is not applied to both horizontal and vertical bars'
[[ $(grep -Fc 'visible: bar.barModuleVisible(bar.monitorName, "temperature")' "$BAR_QML") -eq 2 ]] \
    || fail 'CPU temperature visibility is not applied to both horizontal and vertical bars'
[[ $(grep -Fc 'visible: bar.barModuleVisible(bar.monitorName, "memory")' "$BAR_QML") -eq 2 ]] \
    || fail 'RAM visibility is not applied to both horizontal and vertical bars'

contains "$BAR_SETTINGS" 'function rawModuleVisible(name, module)' \
    'Bar Appearance cannot read per-display system-stat visibility'
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

# Exercise the real manager state path with only qs/hyprctl stubbed. This proves
# values stay per-monitor and unrelated state survives each write.
FAKE_BIN="${TMP}/bin"
CACHE_HOME="${TMP}/cache"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
mkdir -p "$FAKE_BIN" "$(dirname -- "$STATE_FILE")" "$TMP/home"

cat >"${FAKE_BIN}/qs" <<'SH'
#!/usr/bin/env bash
:
SH
chmod +x "${FAKE_BIN}/qs"

cat >"${FAKE_BIN}/hyprctl" <<'SH'
#!/usr/bin/env bash
if [[ ${1:-} == monitors && ${2:-} == -j ]]; then
    printf '%s\n' '[{"name":"DP-1","focused":true},{"name":"DP-2","focused":false}]'
elif [[ ${1:-} == activeworkspace && ${2:-} == -j ]]; then
    printf '%s\n' '{"monitor":"DP-1"}'
fi
SH
chmod +x "${FAKE_BIN}/hyprctl"

cat >"$STATE_FILE" <<'JSON'
{
  "enabled": true,
  "monitors": {
    "DP-1": {"position":"bottom","bar_size":32},
    "DP-2": {"position":"top"}
  },
  "unrelated": {"preserve":"yes"}
}
JSON

run_manager() {
    env PATH="${FAKE_BIN}:$PATH" HOME="$TMP/home" XDG_CACHE_HOME="$CACHE_HOME" \
        XDG_DATA_HOME="$TMP/data" bash "$MANAGER" "$@"
}

run_manager setshowcpu DP-1 false
run_manager setshowtemp DP-1 false
run_manager setshowmemory DP-2 false
[[ $(run_manager getshowcpu DP-1) == false ]] || fail 'CPU visibility did not persist false on DP-1'
[[ $(run_manager getshowtemp DP-1) == false ]] || fail 'temperature visibility did not persist false on DP-1'
[[ $(run_manager getshowmemory DP-1) == true ]] || fail 'RAM visibility default on DP-1 was changed unexpectedly'
[[ $(run_manager getshowmemory DP-2) == false ]] || fail 'RAM visibility did not persist false on DP-2'
jq -e '
    .monitors["DP-1"].position == "bottom"
    and .monitors["DP-1"].bar_size == 32
    and .monitors["DP-2"].position == "top"
    and .unrelated.preserve == "yes"
' "$STATE_FILE" >/dev/null || fail 'system-stat writes changed unrelated state'

printf '%s\n' 'PASS: CPU, temperature, and RAM bar modules are independently optional per display while remaining visible by default.'
