#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML_DIR="${ROOT}/config/quickshell/awtarchy"
SCRIPT_DIR="${ROOT}/config/hypr/scripts"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: ${1#"$ROOT"/}"
}

require_source() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail "$description"
}

require_not_source() {
  local file="$1" unexpected="$2" description="$3"
  if grep -Fq -- "$unexpected" "$file"; then
    fail "$description"
  fi
}

BATTERY_MENU="${QML_DIR}/BatteryMenu.qml"
BATTERY_STATE="${QML_DIR}/BatteryState.qml"
BAR="${QML_DIR}/Bar.qml"
POWER_MODE="${QML_DIR}/PowerModeCard.qml"
MANAGER="${QML_DIR}/FlyoutManager.qml"
SHELL="${QML_DIR}/shell.qml"
BAR_STATE="${QML_DIR}/BarState.qml"
QUICK_SETTINGS="${QML_DIR}/QuickSettings.qml"
PREPARE="${SCRIPT_DIR}/quickshell_flyout_prepare.sh"
POSITION="${SCRIPT_DIR}/quickshell_flyout_position.sh"
APP_STATE="${SCRIPT_DIR}/quickshell_application_state.sh"
RUNTIME_RULES="${SCRIPT_DIR}/quickshell_runtime_rules.sh"

for file in "$BATTERY_MENU" "$BATTERY_STATE" "$BAR" "$POWER_MODE" "$MANAGER" \
  "$SHELL" "$BAR_STATE" "$QUICK_SETTINGS" "$PREPARE" "$POSITION" \
  "$APP_STATE" "$RUNTIME_RULES"; do
  require_file "$file"
done

# Read-only battery telemetry is shared with the bar and flyout.
require_source "$BATTERY_STATE" 'readonly property bool healthSupported:' \
  'battery state does not expose UPower battery-health capability'
require_source "$BATTERY_STATE" 'readonly property int healthPercentage:' \
  'battery state does not expose battery health percentage'
require_source "$BATTERY_MENU" 'BatteryState.percentage' \
  'battery flyout does not use the shared battery percentage'
require_source "$BATTERY_MENU" 'BatteryState.barTooltip' \
  'battery flyout does not surface the shared runtime/charging estimate'
require_source "$BATTERY_MENU" 'PowerModeCard {' \
  'battery flyout does not contain the Power Mode controls'
require_source "$BATTERY_MENU" 'presentationEnabled: true' \
  'battery flyout does not activate the Power Mode presentation'
require_source "$POWER_MODE" 'property bool presentationEnabled: false' \
  'Power Mode does not default to an inert compatibility host'
require_source "$POWER_MODE" 'visible: root.presentationEnabled' \
  'Power Mode compatibility instance can still render in Quick Settings'

# Both bar layouts must open the Battery flyout.
count="$(grep -Fc -- 'onClicked: BatteryMenu.toggleForScreen(bar.screen)' "$BAR")"
[[ "$count" -eq 2 ]] || fail "battery flyout click binding must exist exactly twice, found $count"
count="$(grep -Fc -- 'onRightClicked: BatteryMenu.toggleForScreen(bar.screen)' "$BAR")"
[[ "$count" -eq 2 ]] || fail "battery flyout right-click binding must exist exactly twice, found $count"

# Battery participates in the same shared flyout lifecycle as the established surfaces.
require_source "$MANAGER" 'if (surface === "battery")' \
  'flyout manager has no Battery title mapping'
require_source "$MANAGER" 'return "Awtarchy Battery";' \
  'flyout manager Battery title is missing'
require_source "$SHELL" 'if (surface === "battery")' \
  'shell cannot resolve the Battery flyout'
require_source "$SHELL" 'return BatteryMenu;' \
  'shell Battery flyout mapping is missing'
require_source "$SHELL" 'readonly property bool batteryReady: BatteryMenu !== null' \
  'shell does not eagerly construct the Battery singleton'
require_source "$BATTERY_MENU" 'FlyoutManager.acceptToggle("battery")' \
  'Battery flyout bypasses shared toggle debounce'
require_source "$BATTERY_MENU" 'enabled: FlyoutManager.animationsEnabled' \
  'Battery flyout fade does not honor animation state'
require_source "$BATTERY_MENU" 'Keys.onEscapePressed: root.close()' \
  'Battery flyout is missing local Escape handling'
require_source "$BATTERY_MENU" 'CaptureEyeButton {' \
  'Battery flyout is missing capture privacy control'

# Battery view size, scaling and privacy persist per monitor.
require_source "$BAR_STATE" 'readonly property int referenceBatteryWidth:' \
  'BarState is missing Battery reference width'
require_source "$BAR_STATE" 'readonly property int referenceBatteryHeight:' \
  'BarState is missing Battery reference height'
require_source "$BAR_STATE" 'battery_views: {}' \
  'BarState default data is missing battery_views'
require_source "$BAR_STATE" 'function batteryViewFor(name)' \
  'BarState cannot load Battery view settings'
require_source "$APP_STATE" "battery) printf 'battery_views\\n'" \
  'application state helper cannot persist Battery flyout settings'
require_source "$APP_STATE" 'clipboard|notifications|launcher|network|bluetooth|battery)' \
  'application state helper cannot persist Battery capture state'
require_source "$BATTERY_MENU" '["save-flyout", "battery", activeMonitorName,' \
  'Battery flyout does not save per-monitor display settings'
require_source "$BATTERY_MENU" '["set-capture", "battery", next ? "true" : "false"]' \
  'Battery flyout does not persist capture visibility'

# Geometry and compositor runtime rules must know the new surface.
require_source "$PREPARE" $'    battery)\n        title=\x27Awtarchy Battery\x27' \
  'pre-map flyout preparation does not recognize Battery'
require_source "$POSITION" $'    battery)\n        title=\x27Awtarchy Battery\x27' \
  'post-map flyout positioning does not recognize Battery'
require_source "$RUNTIME_RULES" 'capture_allowed battery && battery_protected=false' \
  'Battery capture state is not applied to runtime rules'
require_source "$RUNTIME_RULES" 'match = { title = "^Awtarchy Battery$" }' \
  'Battery capture privacy window rule is missing'
require_source "$RUNTIME_RULES" 'Awtarchy Battery' \
  'Battery is absent from shared floating flyout runtime rules'
require_source "$RUNTIME_RULES" '["Awtarchy Battery"] = "battery"' \
  'outside-click/Escape runtime handler cannot close Battery'

# The Quick Settings source may keep an inert compatibility instance, but it
# must not be able to render or probe the Power Mode backend there.
require_source "$QUICK_SETTINGS" 'PowerModeCard {' \
  'expected compatibility PowerModeCard instance disappeared unexpectedly'
require_not_source "$QUICK_SETTINGS" 'presentationEnabled: true' \
  'Power Mode is still explicitly enabled inside Quick Settings'

printf '%s\n' 'Battery flyout integration regression checks passed.'
