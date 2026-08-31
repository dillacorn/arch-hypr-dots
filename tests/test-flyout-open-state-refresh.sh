#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

check_load_saved_view() {
    local path="$1"
    local label="$2"
    local body

    body="$(awk '
        /function loadSavedView\(targetScreen/ { in_fn = 1 }
        in_fn { print }
        in_fn && /^    }$/ { exit }
    ' "$path")"

    [[ -n "$body" ]] || fail "$label loadSavedView() was not found"
    if grep -Fq 'BarState.refresh();' <<<"$body"; then
        fail "$label forces BarState.refresh() during every open"
    fi
}

check_load_saved_view "$ROOT/config/quickshell/awtarchy/ClipboardMenu.qml" 'Clipboard'
check_load_saved_view "$ROOT/config/quickshell/awtarchy/QuickSettings.qml" 'Quick Settings'
check_load_saved_view "$ROOT/config/quickshell/awtarchy/NetworkMenu.qml" 'Network'
check_load_saved_view "$ROOT/config/quickshell/awtarchy/BluetoothMenu.qml" 'Bluetooth'
check_load_saved_view "$ROOT/config/quickshell/awtarchy/BatteryMenu.qml" 'Battery'
check_load_saved_view "$ROOT/config/quickshell/awtarchy/Notifications.qml" 'Notifications'

printf '%s\n' 'PASS: flyout open paths reuse watched BarState without forced refreshes.'
