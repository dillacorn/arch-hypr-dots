#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="${ROOT}/config/hypr/scripts/quickshell.sh"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

# Existing installations and newly discovered monitors must preserve today's
# appearance: running applications stay visible and task/tray icons retain
# their original colors unless the user opts into theme coloring.
contains "$MANAGER" 'show_tasks:true' \
    'quickshell state normalization does not default running applications to visible'
contains "$MANAGER" 'theme_task_icons:false' \
    'quickshell state normalization does not default running application icons to original colors'
contains "$MANAGER" 'theme_tray_icons:false' \
    'quickshell state normalization does not default tray icons to original colors'

for command in \
    getshowtasks getthemetaskicons getthemetrayicons \
    setshowtasks setthemetaskicons setthemetrayicons
do
    contains "$MANAGER" "$command" \
        "quickshell manager is missing ${command}"
done
contains "$MANAGER" "set_monitor_icon_option \"\$2\" show_tasks \"\$3\"" \
    'running application visibility is not persisted per monitor'
contains "$MANAGER" "set_monitor_icon_option \"\$2\" theme_task_icons \"\$3\"" \
    'running application theme coloring is not persisted per monitor'
contains "$MANAGER" "set_monitor_icon_option \"\$2\" theme_tray_icons \"\$3\"" \
    'tray icon theme coloring is not persisted per monitor'

contains "$BAR_QML" 'import QtQuick.Effects' \
    'Bar does not import Qt Quick effects for optional icon colorization'
contains "$BAR_QML" 'function taskIconsVisible(name)' \
    'Bar has no per-display running application visibility resolver'
contains "$BAR_QML" 'function taskIconsThemed(name)' \
    'Bar has no per-display running application color resolver'
contains "$BAR_QML" 'function trayIconsThemed(name)' \
    'Bar has no per-display tray icon color resolver'
[[ $(grep -Fc 'visible: bar.taskIconsVisible(bar.monitorName)' "$BAR_QML") -eq 2 ]] \
    || fail 'running application visibility is not applied to both horizontal and vertical bars'
[[ $(grep -Fc 'layer.enabled: bar.taskIconsThemed(bar.monitorName)' "$BAR_QML") -eq 2 ]] \
    || fail 'running application theme coloring is not applied to both horizontal and vertical bars'
[[ $(grep -Fc 'layer.enabled: bar.trayIconsThemed(bar.monitorName)' "$BAR_QML") -eq 2 ]] \
    || fail 'tray icon theme coloring is not applied to both horizontal and vertical bars'
[[ $(grep -Fc 'colorizationColor: Theme.foreground' "$BAR_QML") -eq 4 ]] \
    || fail 'task and tray icon effects do not consistently use the current theme foreground color'

contains "$BAR_SETTINGS" 'text: "Running apps"' \
    'Bar Appearance has no running application controls'
contains "$BAR_SETTINGS" 'text: "Tray icons"' \
    'Bar Appearance has no tray icon controls'
for command in setshowtasks setthemetaskicons setthemetrayicons; do
    contains "$BAR_SETTINGS" "\"${command}\"" \
        "Bar Appearance does not persist ${command}"
done

# Exercise the real manager state path with only qs/hyprctl stubbed. This proves
# values remain per-monitor, old state gets safe defaults, and unrelated state
# survives every write.
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

[[ $(run_manager getshowtasks DP-1) == true ]] \
    || fail 'legacy monitor state did not default running applications to visible'
[[ $(run_manager getthemetaskicons DP-1) == false ]] \
    || fail 'legacy monitor state did not default running application icons to original colors'
[[ $(run_manager getthemetrayicons DP-1) == false ]] \
    || fail 'legacy monitor state did not default tray icons to original colors'

run_manager setshowtasks DP-1 false
run_manager setthemetaskicons DP-1 true
run_manager setthemetrayicons DP-2 true
[[ $(run_manager getshowtasks DP-1) == false ]] \
    || fail 'running application visibility did not persist false on DP-1'
[[ $(run_manager getshowtasks DP-2) == true ]] \
    || fail 'running application visibility leaked to DP-2'
[[ $(run_manager getthemetaskicons DP-1) == true ]] \
    || fail 'running application theme coloring did not persist true on DP-1'
[[ $(run_manager getthemetaskicons DP-2) == false ]] \
    || fail 'running application theme coloring leaked to DP-2'
[[ $(run_manager getthemetrayicons DP-1) == false ]] \
    || fail 'tray icon theme coloring leaked to DP-1'
[[ $(run_manager getthemetrayicons DP-2) == true ]] \
    || fail 'tray icon theme coloring did not persist true on DP-2'

jq -e '
    .monitors["DP-1"].position == "bottom"
    and .monitors["DP-1"].bar_size == 32
    and .monitors["DP-2"].position == "top"
    and .unrelated.preserve == "yes"
' "$STATE_FILE" >/dev/null || fail 'bar icon option writes changed unrelated state'

# These are managed stock files. Register each new stock revision so the
# updater can recognize it without deleting historical hashes.
missing_history=0
while IFS='|' read -r source_file rel; do
    digest="$(sha256sum "$source_file" | awk '{print $1}')"
    if ! grep -Fxq -- "${digest}"$'\t'"${rel}" "$HISTORY"; then
        printf 'MISSING_HISTORY_HASH: %s\t%s\n' "$digest" "$rel" >&2
        missing_history=1
    fi
done <<EOF_HISTORY
${MANAGER}|.config/hypr/scripts/quickshell.sh
${BAR_QML}|.config/quickshell/awtarchy/Bar.qml
${BAR_SETTINGS}|.config/quickshell/awtarchy/BarSettingsSection.qml
EOF_HISTORY
[[ $missing_history -eq 0 ]] \
    || fail 'managed history is missing current bar icon option stock hashes'

printf '%s\n' 'PASS: running application visibility and optional task/tray theme coloring are independent per-display settings with stock-safe defaults.'
