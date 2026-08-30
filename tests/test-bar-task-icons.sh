#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"

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
contains "$BAR_QML" 'if (toplevel.wayland && toplevel.wayland.parent)' \
    'Parented transient/dialog toplevels are not filtered from task rendering'
contains "$BAR_QML" 'function isXwaylandPopupHelper(toplevel)' \
    'Bar has no focused XWayland popup-helper filter'
contains "$BAR_QML" 'if (isXwaylandPopupHelper(toplevel))' \
    'XWayland popup/helper clients are not rejected before task rendering'
contains "$BAR_QML" 'if (ipc.xwayland !== true || !titleEmpty)' \
    'XWayland helper filtering still depends on mutable/stale floating IPC metadata'
contains "$BAR_QML" 'String(toplevel.title || ipc.title || ipc.initialTitle || "").trim().length === 0' \
    'XWayland helper filtering is not restricted to untitled clients'
contains "$BAR_QML" 'siblingIpc.pid === ipc.pid' \
    'XWayland helper filtering does not require the same application process'
contains "$BAR_QML" 'siblingClass === cls' \
    'XWayland helper filtering does not require the same application class'

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