#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MENU="${ROOT}/config/quickshell/awtarchy/BatteryMenu.qml"
CARD="${ROOT}/config/quickshell/awtarchy/BatteryCareCard.qml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_source() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

[[ -f "$MENU" ]] || fail 'BatteryMenu.qml is missing'
[[ -f "$CARD" ]] || fail 'BatteryCareCard.qml is missing'

require_source "$MENU" 'BatteryCareCard {' \
  'Battery Health controls are not hosted by the Battery flyout'
require_source "$MENU" 'active: batteryWindow.visible' \
  'Battery Health controls do not follow Battery flyout visibility'
require_source "$MENU" 'textScale: root.effectiveTextScale' \
  'Battery Health controls do not inherit Battery flyout text scaling'
require_source "$MENU" 'iconScale: root.effectiveIconScale' \
  'Battery Health controls do not inherit Battery flyout icon scaling'
require_source "$CARD" 'property bool active: false' \
  'Battery Health card has no explicit lifecycle gate'
require_source "$CARD" 'running: root.active && !root.authBusy' \
  'Battery Health status polling is not gated by flyout visibility'

printf '%s\n' 'Battery Health flyout host regression check passed.'
