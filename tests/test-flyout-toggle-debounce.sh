#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML_DIR="${ROOT}/config/quickshell/awtarchy"
MANAGER="${QML_DIR}/FlyoutManager.qml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_source() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail "$description"
}

require_source "$MANAGER" 'readonly property int toggleDebounceMs: 250' \
  'flyout manager is missing the switch-bounce cooldown'
require_source "$MANAGER" 'function acceptToggle(surface)' \
  'flyout manager is missing the shared toggle gate'
require_source "$MANAGER" 'now - previous < toggleDebounceMs' \
  'flyout manager does not reject implausibly fast repeated toggles'

require_source "${QML_DIR}/Launcher.qml" \
  'FlyoutManager.acceptToggle("launcher")' \
  'application launcher bypasses the toggle gate'
require_source "${QML_DIR}/QuickSettings.qml" \
  'FlyoutManager.acceptToggle("quick-settings")' \
  'quick settings bypasses the toggle gate'
require_source "${QML_DIR}/NetworkMenu.qml" \
  'FlyoutManager.acceptToggle("network")' \
  'network flyout bypasses the toggle gate'
require_source "${QML_DIR}/BluetoothMenu.qml" \
  'FlyoutManager.acceptToggle("bluetooth")' \
  'Bluetooth flyout bypasses the toggle gate'
require_source "${QML_DIR}/ClipboardMenu.qml" \
  'FlyoutManager.acceptToggle("clipboard")' \
  'clipboard flyout bypasses the toggle gate'
require_source "${QML_DIR}/Notifications.qml" \
  'FlyoutManager.acceptToggle("notifications")' \
  'notifications flyout bypasses the toggle gate'
require_source "${QML_DIR}/PowerMenu.qml" \
  'FlyoutManager.acceptToggle("power")' \
  'power menu bypasses the toggle gate'
require_source "${QML_DIR}/Bar.qml" \
  'onClicked: PowerMenu.toggleForScreen(bar.screen)' \
  'bar power button does not use the damped toggle path'

printf '%s\n' 'Flyout toggle debounce regression test passed.'
