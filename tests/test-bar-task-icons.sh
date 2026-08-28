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

contains "$BAR_QML" 'import QtQuick.Effects' \
    'Bar task icons do not import the Qt Quick effect used for theme tinting'
contains "$BAR_QML" 'function toplevelIdentity(toplevel)' \
    'Bar task filtering does not normalize Wayland and Hyprland window identity'
contains "$BAR_QML" 'toplevel.wayland.appId' \
    'Bar task filtering still ignores the Wayland app id used by Quickshell flyouts'
contains "$BAR_QML" 'function awtarchyOwnedToplevel(toplevel)' \
    'Bar has no focused filter for Awtarchy-owned Quickshell windows'
contains "$BAR_QML" 'identity.title.indexOf("Awtarchy ") === 0' \
    'Awtarchy floating-window titles are not excluded from the task strip'
contains "$BAR_QML" 'if (awtarchyOwnedToplevel(toplevel))' \
    'Awtarchy-owned flyouts are not rejected before task rendering'

[[ $(grep -Fc 'layer.effect: MultiEffect {' "$BAR_QML") -eq 2 ]] \
    || fail 'horizontal and vertical task icons are not both theme-tinted'
[[ $(grep -Fc 'colorization: 1.0' "$BAR_QML") -eq 2 ]] \
    || fail 'horizontal and vertical task icons do not both use full theme colorization'
[[ $(grep -Fc 'colorizationColor: task.modelData.urgent ? Theme.dark : Theme.foreground' "$BAR_QML") -eq 2 ]] \
    || fail 'task icon tint does not preserve urgent-state contrast on both bar orientations'

contains "$BAR_QML" 'acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton' \
    'task icon mouse actions were removed while restyling task icons'
contains "$BAR_QML" 'wayland.close();' \
    'task icon middle-click close behavior disappeared'
contains "$BAR_QML" 'wayland.minimized = true;' \
    'task icon right-click minimize behavior disappeared'
contains "$BAR_QML" 'wayland.activate();' \
    'task icon activation behavior disappeared'

printf '%s\n' 'PASS: bar task icons exclude Awtarchy flyouts, follow the theme, and preserve window actions.'
