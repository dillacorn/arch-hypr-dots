#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

contains "$BAR_QML" 'function isAwtarchyFlyout(toplevel)' \
    'Bar has no focused filter for Awtarchy flyout windows'
for title in \
    'Awtarchy Application Search' \
    'Awtarchy Clipboard History' \
    'Awtarchy Notification Center' \
    'Awtarchy Quick Settings' \
    'Awtarchy Network' \
    'Awtarchy Bluetooth' \
    'Awtarchy Battery'
do
    contains "$BAR_QML" "\"${title}\"" \
        "Bar flyout filter is missing ${title}"
done
contains "$BAR_QML" 'if (isAwtarchyFlyout(toplevel))' \
    'Awtarchy flyouts are not rejected before task rendering'
contains "$BAR_QML" 'const taskTitle = String(toplevel.title || "").trim();' \
    'Task filtering does not use HyprlandToplevel.title directly'
contains "$BAR_QML" 'if (taskTitle.length === 0)' \
    'Untitled toplevels can still become task-strip entries'

contains "$RUNTIME" 'repair_v343_transient_task_icons_target()' \
    'runtime is missing the v3.4.3 transient-task post-release repair'
contains "$RUNTIME" '[[ "$tag" == "v3.4.3" ]] || return 0' \
    'v3.4.3 transient-task repair is not scoped to the published release'
contains "$RUNTIME" 'repair_v343_transient_task_icons_target "$target_home" "$tag"' \
    'runtime does not apply the v3.4.3 transient-task repair to the generated target'

prepare_line="$(grep -nF 'prepare_quickshell_update_target "$target_home"' "$RUNTIME" | head -n1 | cut -d: -f1)"
repair_line="$(grep -nF 'repair_v343_transient_task_icons_target "$target_home" "$tag"' "$RUNTIME" | head -n1 | cut -d: -f1)"
baseline_line="$(grep -nF 'bootstrap_previous_baseline "$active_theme"' "$RUNTIME" | head -n1 | cut -d: -f1)"
[[ "$prepare_line" =~ ^[0-9]+$ && "$repair_line" =~ ^[0-9]+$ && "$baseline_line" =~ ^[0-9]+$ ]] \
    || fail 'could not locate v3.4.3 transient-task target-repair ordering'
(( prepare_line < repair_line && repair_line < baseline_line )) \
    || fail 'v3.4.3 transient-task target repair must run before baseline comparison'

functions_file="${TMP}/v343-transient-task-repair.sh"
awk '
    /^repair_v343_transient_task_icons_target\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' "$RUNTIME" >"$functions_file"
contains "$functions_file" 'repair_v343_transient_task_icons_target()' \
    'could not extract the real v3.4.3 transient-task repair function'

die() {
    printf 'TEST DIE: %s\n' "$*" >&2
    return 1
}
log() { :; }
source "$functions_file"

v343_home="${TMP}/v343"
v342_home="${TMP}/v342"
for home in "$v343_home" "$v342_home"; do
    mkdir -p "${home}/.config/quickshell/awtarchy"
    cat >"${home}/.config/quickshell/awtarchy/Bar.qml" <<'EOF_BAR_FIXTURE'
    function toplevelVisibleHere(toplevel) {
        if (!toplevel || !toplevel.monitor || toplevel.monitor.name !== monitorName)
            return false;
        if (isAwtarchyFlyout(toplevel))
            return false;
    }
EOF_BAR_FIXTURE
done

repair_v343_transient_task_icons_target "$v343_home" v3.4.3
v343_bar="${v343_home}/.config/quickshell/awtarchy/Bar.qml"
[[ $(grep -Fc 'const taskTitle = String(toplevel.title || "").trim();' "$v343_bar") -eq 1 ]] \
    || fail 'real v3.4.3 repair did not add the live title guard'
[[ $(grep -Fc 'if (taskTitle.length === 0)' "$v343_bar") -eq 1 ]] \
    || fail 'real v3.4.3 repair did not reject untitled task windows'

repair_v343_transient_task_icons_target "$v343_home" v3.4.3
[[ $(grep -Fc 'const taskTitle = String(toplevel.title || "").trim();' "$v343_bar") -eq 1 ]] \
    || fail 'v3.4.3 transient-task repair is not idempotent'

repair_v343_transient_task_icons_target "$v342_home" v3.4.2
v342_bar="${v342_home}/.config/quickshell/awtarchy/Bar.qml"
if grep -Fq 'const taskTitle = String(toplevel.title || "").trim();' "$v342_bar"; then
    fail 'v3.4.3 transient-task repair leaked into another release tag'
fi

# Native icon sources remain authoritative. Theme coloring is optional and is
# enabled only by the per-monitor state, so the stock false default preserves
# the existing application and tray colors.
contains "$BAR_QML" 'import QtQuick.Effects' \
    'Bar does not expose the optional icon colorization effect'
contains "$BAR_QML" 'source: bar.appIcon(task.modelData)' \
    'Running application icons no longer use their native application icon'
contains "$BAR_QML" 'source: trayItem.modelData.icon' \
    'System tray icons no longer use their native applet icon'
[[ $(grep -Fc 'layer.enabled: bar.taskIconsThemed(bar.monitorName)' "$BAR_QML") -eq 2 ]] \
    || fail 'optional running application icon theming is not applied to both bar orientations'
[[ $(grep -Fc 'layer.enabled: bar.trayIconsThemed(bar.monitorName)' "$BAR_QML") -eq 2 ]] \
    || fail 'optional tray icon theming is not applied to both bar orientations'
[[ $(grep -Fc 'colorizationColor: Theme.foreground' "$BAR_QML") -eq 4 ]] \
    || fail 'optional task/tray icon coloring does not consistently use the theme foreground'

contains "$BAR_QML" 'acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton' \
    'task icon mouse actions were removed while fixing flyout filtering'
contains "$BAR_QML" 'wayland.close();' \
    'task icon middle-click close behavior disappeared'
contains "$BAR_QML" 'wayland.minimized = true;' \
    'task icon right-click minimize behavior disappeared'
contains "$BAR_QML" 'wayland.activate();' \
    'task icon activation behavior disappeared'

printf '%s\n' 'PASS: Awtarchy keeps untitled transient/helper toplevels out of the task strip while real titled app windows remain eligible.'