#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/hyprbars_toggle.sh"
TRUSTED_HELPER="${ROOT}/local/libexec/awtarchy/scxctl-helper"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
POWER_CARD="${ROOT}/config/quickshell/awtarchy/PowerModeCard.qml"
TITLE_CARD="${ROOT}/config/quickshell/awtarchy/TitleBarsCard.qml"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
HYPR_LUA="${ROOT}/config/hypr/hyprland.lua"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$3"; }
absent() { ! grep -Fq -- "$2" "$1" || fail "$3"; }

[[ -f "$TITLE_CARD" ]] || fail 'main Quick Settings Title Bars card is missing'

# Preserve the existing keyboard workflow and hot-unload safety.
contains "$HYPR_LUA" '{ "SUPER + ALT + T", hyprbars_toggle },' \
  'existing SUPER+ALT+T hyprbars bind changed or disappeared'
contains "$SCRIPT" 'hyprpm disable' 'hyprbars disable behavior disappeared'
contains "$SCRIPT" 'hyprpm reload' 'hyprbars enable/reload behavior disappeared'
contains "$SCRIPT" 'Hot-unloading hyprbars can crash Hyprland.' \
  'hyprbars hot-unload safety behavior disappeared'
absent "$SCRIPT" 'sudo -v' 'keyboard hyprbars script performs unconditional sudo pre-authentication'

# Title Bars belongs directly in the Quick Settings content path, not in the
# Bar Appearance gear panel.
contains "$QUICK_SETTINGS" 'PowerModeCard {' \
  'Quick Settings main list no longer contains the Power/Title Bars card host'
contains "$POWER_CARD" 'TitleBarsCard {' \
  'main Quick Settings content path does not contain the Title Bars card'
absent "$BAR_SETTINGS" 'text: "Title Bars"' \
  'duplicate Title Bars control is still hidden in Bar Appearance settings'
absent "$BAR_SETTINGS" 'hyprbarsScript' \
  'Bar Appearance settings still owns the hyprbars workflow'

# Quick Settings must use the already root-owned Awtarchy helper, never the
# user-writable ~/.config script, for operations performed after password entry.
contains "$TITLE_CARD" 'readonly property string trustedHelper: "/usr/local/libexec/awtarchy/scxctl-helper"' \
  'Title Bars does not use the fixed root-owned trusted helper'
absent "$TITLE_CARD" 'hyprbars_toggle.sh' \
  'Title Bars still executes the user-writable hyprbars script'
contains "$TITLE_CARD" 'echoMode: TextInput.Password' \
  'Title Bars password entry is not masked'
contains "$TITLE_CARD" 'stdinEnabled: true' \
  'Title Bars action process does not accept password over stdin'
contains "$TITLE_CARD" 'actionRunner.write(root.pendingPassword + "\n")' \
  'Title Bars password is not sent only through helper stdin'
contains "$TITLE_CARD" '[root.trustedHelper, "hyprbars-status"]' \
  'Title Bars status does not use the trusted helper'
contains "$TITLE_CARD" '[root.trustedHelper, root.pendingAction]' \
  'Title Bars actions do not use the trusted helper'
absent "$TITLE_CARD" '"/usr/bin/sudo"' \
  'Title Bars QML should not cache sudo before handing control to another executable'

# The root-owned helper must expose only fixed hyprbars operations, use fixed
# binaries/repository, reject root execution for the user-session plugin path,
# and re-authorize internally before each hyprpm operation because hyprpm drops
# its sudo timestamp after privileged header/state work.
contains "$TRUSTED_HELPER" 'HYPRPM="/usr/bin/hyprpm"' \
  'trusted helper does not pin hyprpm to /usr/bin'
contains "$TRUSTED_HELPER" 'SUDO="/usr/bin/sudo"' \
  'trusted helper does not pin sudo to /usr/bin'
contains "$TRUSTED_HELPER" 'HYPRBARS_REPO="https://github.com/hyprwm/hyprland-plugins"' \
  'trusted helper does not pin the official plugin repository'
contains "$TRUSTED_HELPER" 'hyprbars-status)' \
  'trusted helper lacks hyprbars-status'
contains "$TRUSTED_HELPER" 'hyprbars-enable)' \
  'trusted helper lacks hyprbars-enable'
contains "$TRUSTED_HELPER" 'hyprbars-disable)' \
  'trusted helper lacks hyprbars-disable'
contains "$TRUSTED_HELPER" '(( EUID != 0 )) || die' \
  'trusted helper does not reject root execution for hyprbars operations'
contains "$TRUSTED_HELPER" 'IFS= read -r password' \
  'trusted helper does not receive the password from stdin'
contains "$TRUSTED_HELPER" '"$SUDO" -S -p "" -v' \
  'trusted helper does not perform fixed sudo validation'
absent "$TRUSTED_HELPER" 'NOPASSWD' \
  'trusted helper must not add passwordless sudo behavior'

# Existing install and update paths already deploy scxctl-helper root-owned.
contains "${ROOT}/awtarchy-install.sh" 'SCXCTL_HELPER_SOURCE=' \
  'installer no longer provisions the trusted helper'
contains "${ROOT}/local/share/awtarchy/awtarchy-runtime.sh" 'repair_scxctl_update_helper()' \
  'updater no longer repairs the trusted helper'

contains "$HISTORY" $'708658656ab4672d010f49b54de099200d1ab6b42bebb822ec2e01d80fa81df3\t.config/hypr/scripts/hyprbars_toggle.sh' \
  'managed history is missing the pre-fix hyprbars script hash'

# Keep current stock hashes in managed history so future updates can recognize
# this release's files as Awtarchy-owned instead of preserving them as user edits.
missing_history=0
for rel in \
  .config/quickshell/awtarchy/PowerModeCard.qml \
  .config/quickshell/awtarchy/BarSettingsSection.qml \
  .config/quickshell/awtarchy/TitleBarsCard.qml \
  .config/hypr/scripts/hyprbars_toggle.sh
do
  source_file="${ROOT}/${rel#.}"
  if [[ $rel == .config/* ]]; then
    source_file="${ROOT}/config/${rel#.config/}"
  fi
  digest="$(sha256sum "$source_file" | awk '{print $1}')"
  if ! grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY"; then
    printf 'MISSING_MANAGED_HASH %s\t%s\n' "$digest" "$rel" >&2
    missing_history=1
  fi
done
(( missing_history == 0 )) || fail 'managed history is missing current Title Bars stock hashes'

printf '%s\n' 'PASS: Title Bars is a main Quick Settings toggle using inline auth through the root-owned helper.'
