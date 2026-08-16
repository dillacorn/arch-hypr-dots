#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/hyprbars_toggle.sh"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
HYPR_LUA="${ROOT}/config/hypr/hyprland.lua"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

absent() {
  local file="$1" needle="$2" message="$3"
  ! grep -Fq -- "$needle" "$file" || fail "$message"
}

# Preserve the established keyboard workflow and behavior owner.
contains "$HYPR_LUA" '{ "SUPER + ALT + T", hyprbars_toggle },' \
  'existing SUPER+ALT+T hyprbars bind changed or disappeared'
contains "$SCRIPT" 'hyprpm disable' \
  'hyprbars disable behavior disappeared'
contains "$SCRIPT" 'hyprpm reload' \
  'hyprbars enable/reload behavior disappeared'
contains "$SCRIPT" 'Hot-unloading hyprbars can crash Hyprland.' \
  'hyprbars hot-unload safety behavior disappeared'

# Routine toggling must not pre-authenticate or keep a sudo ticket alive.
absent "$SCRIPT" '"$SUDO_BIN" -v' \
  'hyprbars toggle still performs unconditional sudo pre-authentication'
absent "$SCRIPT" 'SUDO_KEEPALIVE_PID' \
  'hyprbars toggle still keeps a sudo credential alive'

# Quick Settings must reuse this script through fixed machine-safe modes rather
# than embedding a second plugin-management workflow.
contains "$SCRIPT" '--status' \
  'hyprbars script has no machine-readable status mode'
contains "$SCRIPT" '--toggle' \
  'hyprbars script has no nonterminal toggle mode'
contains "$BAR_SETTINGS" 'readonly property string hyprbarsScript:' \
  'Quick Settings bar section does not reference the existing hyprbars script'
contains "$BAR_SETTINGS" '[root.hyprbarsScript, "--status"]' \
  'Quick Settings does not query hyprbars through the existing script'
contains "$BAR_SETTINGS" '[root.hyprbarsScript, "--toggle"]' \
  'Quick Settings does not toggle hyprbars through the existing script'
contains "$BAR_SETTINGS" 'text: "Title Bars"' \
  'Quick Settings has no Title Bars control'
absent "$BAR_SETTINGS" 'sudo' \
  'Quick Settings directly invokes sudo for title-bar control'

printf '%s\n' 'PASS: title-bar bind and Quick Settings share a routine no-sudo hyprbars toggle path.'
