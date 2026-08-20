#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML_DIR="${ROOT}/config/quickshell/awtarchy"
MANAGER="${QML_DIR}/FlyoutManager.qml"
SHELL="${QML_DIR}/shell.qml"
LAUNCHER="${QML_DIR}/Launcher.qml"
TOGGLE="${ROOT}/config/hypr/scripts/toggle_animations.sh"

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

require_source "${QML_DIR}/BarSettingsSection.qml" \
  'label: "Themes"' \
  'bar appearance settings do not expose the theme picker'
require_source "${QML_DIR}/FlyoutSettings.qml" \
  'onThemePickerRequested: root.themePickerRequested()' \
  'flyout settings do not forward the theme-picker request'
require_source "${QML_DIR}/QuickSettings.qml" \
  'ThemePicker.openForScreen(activeScreen)' \
  'quick settings do not open the theme picker on their active display'
require_source "${QML_DIR}/ThemePicker.qml" \
  'function openForScreen(target)' \
  'theme picker cannot target the Quick Settings display'

require_source "$MANAGER" \
  'readonly property string animationStatePath: runtimeDir + "/hypr-animations-enabled"' \
  'shared animation-state path is missing'
require_source "$MANAGER" \
  'readonly property bool animationsEnabled: animationStateFile.text().trim() !== "0"' \
  'shared animation-state gate is missing'
require_source "$MANAGER" \
  'property FileView animationStateFile: FileView {' \
  'flyout manager must own FileView through an explicit QtObject property'
require_source "$MANAGER" \
  'path: root.animationStatePath' \
  'shared animation-state FileView does not use the Super+A state path'
require_source "$MANAGER" \
  'watchChanges: true' \
  'shared animation-state file is not watched for Super+A changes'

require_source "$SHELL" \
  'readonly property int managedFlyoutFadeDuration: 140' \
  'managed flyout fade duration does not match the launcher'
require_source "$SHELL" \
  'function managedFlyoutWindow(surface)' \
  'managed flyout window lookup is missing'
require_source "$SHELL" \
  'function runManagedFlyoutFade(window, animation)' \
  'shared managed flyout fade runner is missing'
require_source "$SHELL" \
  'if (!FlyoutManager.animationsEnabled)' \
  'managed flyout fade does not honor the Super+A animation gate'
require_source "$SHELL" \
  'animation.target = content' \
  'managed flyout fade does not target the flyout content item'
require_source "$SHELL" \
  'easing.type: Easing.OutCubic' \
  'managed flyout fade easing does not match the launcher'

for surface in clipboard notifications quick-settings network bluetooth; do
  require_source "$SHELL" \
    "root.managedFlyoutWindow(\"${surface}\")" \
    "${surface} is not wired to the shared fade"
done

require_source "$SHELL" \
  'function onAnimationsEnabledChanged()' \
  'managed flyout fades are not reset when Super+A disables animations'
require_source "$LAUNCHER" \
  'duration: 140' \
  'launcher reference fade duration changed unexpectedly'
require_source "$LAUNCHER" \
  'easing.type: Easing.OutCubic' \
  'launcher reference fade easing changed unexpectedly'
require_source "$TOGGLE" \
  'hypr-animations-enabled' \
  'Super+A animation state file changed unexpectedly'

printf '%s\n' 'Flyout toggle debounce and fade regression test passed.'
