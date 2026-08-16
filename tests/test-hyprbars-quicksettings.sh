#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/hyprbars_toggle.sh"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
POWER_CARD="${ROOT}/config/quickshell/awtarchy/PowerModeCard.qml"
TITLE_CARD="${ROOT}/config/quickshell/awtarchy/TitleBarsCard.qml"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
HYPR_LUA="${ROOT}/config/hypr/hyprland.lua"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"

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

[[ -f "$TITLE_CARD" ]] || fail 'main Quick Settings Title Bars card is missing'

# Preserve the established keyboard workflow and behavior owner.
contains "$HYPR_LUA" '{ "SUPER + ALT + T", hyprbars_toggle },' \
  'existing SUPER+ALT+T hyprbars bind changed or disappeared'
contains "$SCRIPT" 'hyprpm disable' \
  'hyprbars disable behavior disappeared'
contains "$SCRIPT" 'hyprpm reload' \
  'hyprbars enable/reload behavior disappeared'
contains "$SCRIPT" 'Hot-unloading hyprbars can crash Hyprland.' \
  'hyprbars hot-unload safety behavior disappeared'

# Routine toggling must remain unprivileged. First-time setup gets a separate
# fixed machine-safe mode after Quick Settings validates sudo inline.
absent "$SCRIPT" 'sudo -v' \
  'hyprbars script performs unconditional sudo pre-authentication'
contains "$SCRIPT" '--status' \
  'hyprbars script has no machine-readable status mode'
contains "$SCRIPT" '--toggle' \
  'hyprbars script has no nonterminal toggle mode'
contains "$SCRIPT" '--setup-enable' \
  'hyprbars script has no noninteractive first-time setup mode'
contains "$SCRIPT" '"$HYPRPM_BIN" update' \
  'first-time setup no longer refreshes Hyprland plugin headers'
contains "$SCRIPT" '"$HYPRPM_BIN" add "$REPO_URL"' \
  'first-time setup no longer adds the official plugins repository'
contains "$SCRIPT" '"$HYPRPM_BIN" enable "$PLUGIN"' \
  'first-time setup no longer enables hyprbars'

# Title Bars belongs in the main Quick Settings content path, not behind the
# display appearance gear panel. PowerModeCard is already a direct child of the
# main Quick Settings list, so it may compose the always-visible Title Bars card.
contains "$QUICK_SETTINGS" 'PowerModeCard {' \
  'Quick Settings main list no longer contains the Power/Title Bars card host'
contains "$POWER_CARD" 'TitleBarsCard {' \
  'main Quick Settings content path does not contain the Title Bars card'
absent "$BAR_SETTINGS" 'text: "Title Bars"' \
  'duplicate Title Bars control is still hidden in Bar Appearance settings'
absent "$BAR_SETTINGS" 'hyprbarsScript' \
  'Bar Appearance settings still owns the hyprbars workflow'

# First-time setup must request the password inline, masked, and pass it only
# over stdin to sudo validation. The plugin setup itself then runs unprivileged
# through the fixed hyprbars machine mode.
contains "$TITLE_CARD" 'echoMode: TextInput.Password' \
  'Title Bars password entry is not masked'
contains "$TITLE_CARD" 'stdinEnabled: true' \
  'Title Bars sudo authorization does not use process stdin'
contains "$TITLE_CARD" '["/usr/bin/sudo", "-S", "-p", "", "-v"]' \
  'Title Bars does not validate sudo through the fixed inline command'
contains "$TITLE_CARD" 'authRunner.write(root.pendingPassword + "\\n\\n\\n")' \
  'Title Bars password is not written to sudo stdin'
contains "$TITLE_CARD" '[root.hyprbarsScript, "--setup-enable"]' \
  'Title Bars setup does not call the fixed noninteractive setup mode'
contains "$TITLE_CARD" '[root.hyprbarsScript, "--toggle"]' \
  'Title Bars normal toggle does not use the existing script'
contains "$TITLE_CARD" '[root.hyprbarsScript, "--status"]' \
  'Title Bars status does not use the existing script'
absent "$TITLE_CARD" 'Quickshell.execDetached([root.hyprbarsScript])' \
  'Title Bars still launches the old terminal setup path'

# Current-main users must have the old shipped script recognized as a managed
# file so an update replaces it instead of preserving the prior implementation.
contains "$HISTORY" $'708658656ab4672d010f49b54de099200d1ab6b42bebb822ec2e01d80fa81df3\t.config/hypr/scripts/hyprbars_toggle.sh' \
  'managed history is missing the pre-fix hyprbars script hash'

printf '%s\n' 'PASS: Title Bars is a main Quick Settings toggle with inline first-time authorization.'
