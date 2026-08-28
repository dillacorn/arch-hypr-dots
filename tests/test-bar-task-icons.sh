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

absent() {
    ! grep -Fq -- "$2" "$1" || fail "$3"
}

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

absent "$BAR_QML" 'import QtQuick.Effects' \
    'task icons should keep their native application colors instead of importing a tint effect'
absent "$BAR_QML" 'layer.effect: MultiEffect {' \
    'task icons are still being recolored instead of using native application colors'
contains "$BAR_QML" 'source: bar.appIcon(task.modelData)' \
    'task icons no longer render the application icon source'

contains "$BAR_QML" 'acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton' \
    'task icon mouse actions were removed while fixing flyout filtering'
contains "$BAR_QML" 'wayland.close();' \
    'task icon middle-click close behavior disappeared'
contains "$BAR_QML" 'wayland.minimized = true;' \
    'task icon right-click minimize behavior disappeared'
contains "$BAR_QML" 'wayland.activate();' \
    'task icon activation behavior disappeared'

printf '%s\n' 'PASS: bar task icons exclude Awtarchy flyouts, keep native app colors, and preserve window actions.'
