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

[[ -f "$TITLE_CARD" ]] || fail 'main Quick Settings Hyprland Plugin card is missing'

# Preserve the existing keyboard workflow and hot-unload safety.
contains "$HYPR_LUA" '{ "SUPER + ALT + T", hyprbars_toggle },' \
  'existing SUPER+ALT+T hyprbars bind changed or disappeared'
contains "$SCRIPT" 'hyprpm disable' 'hyprbars disable behavior disappeared'
contains "$SCRIPT" 'hyprpm reload' 'hyprbars enable/reload behavior disappeared'
contains "$SCRIPT" 'Hot-unloading hyprbars can crash Hyprland.' \
  'hyprbars hot-unload safety behavior disappeared'
absent "$SCRIPT" 'sudo -v' 'keyboard hyprbars script performs unconditional sudo pre-authentication'

# The control belongs directly in Quick Settings, not the Bar Appearance gear panel.
contains "$QUICK_SETTINGS" 'PowerModeCard {' \
  'Quick Settings main list no longer contains the Power/Hyprland Plugin host'
contains "$POWER_CARD" 'TitleBarsCard {' \
  'main Quick Settings content path does not contain the Hyprland Plugin card'
absent "$BAR_SETTINGS" 'text: "Title Bars"' \
  'duplicate Title Bars control is still hidden in Bar Appearance settings'
absent "$BAR_SETTINGS" 'hyprbarsScript' \
  'Bar Appearance settings still owns the hyprbars workflow'

# The UI must clearly identify this as a Hyprland plugin control, provide live
# progress instead of a dead Working label, and keep password entry masked.
contains "$TITLE_CARD" 'text: "Hyprland Plugin"' \
  'Quick Settings card is not labeled Hyprland Plugin'
contains "$TITLE_CARD" 'text: "Title Bars (hyprbars)"' \
  'Quick Settings card does not identify the hyprbars title-bar plugin'
contains "$TITLE_CARD" 'echoMode: TextInput.Password' \
  'Hyprland Plugin password entry is not masked'
contains "$TITLE_CARD" 'stdinEnabled: true' \
  'Hyprland Plugin action process does not accept password over stdin'
contains "$TITLE_CARD" 'actionRunner.write(root.pendingPassword + "\n")' \
  'Hyprland Plugin password is not sent through helper stdin'
contains "$TITLE_CARD" 'stdout: SplitParser {' \
  'Hyprland Plugin UI does not consume live helper progress'
contains "$TITLE_CARD" 'AWTARCHY_STAGE\t' \
  'Hyprland Plugin UI does not understand helper stage messages'
contains "$TITLE_CARD" 'Authentication failed' \
  'Hyprland Plugin UI does not expose a useful authentication failure'
contains "$TITLE_CARD" 'Updating Hyprland plugin headers' \
  'Hyprland Plugin UI does not tell the user that plugin setup may take time'
absent "$TITLE_CARD" 'label: root.operationBusy ? "Working…"' \
  'Hyprland Plugin UI still hides setup behind a generic Working label'

# Quick Settings must use the already root-owned Awtarchy helper, never a
# user-writable ~/.config script, for password-backed operations.
contains "$TITLE_CARD" 'readonly property string trustedHelper: "/usr/local/libexec/awtarchy/scxctl-helper"' \
  'Hyprland Plugin does not use the fixed root-owned trusted helper'
absent "$TITLE_CARD" 'hyprbars_toggle.sh' \
  'Hyprland Plugin still executes the user-writable hyprbars script'
contains "$TITLE_CARD" '[root.trustedHelper, "hyprbars-status"]' \
  'Hyprland Plugin status does not use the trusted helper'
contains "$TITLE_CARD" '[root.trustedHelper, root.pendingAction]' \
  'Hyprland Plugin actions do not use the trusted helper'
absent "$TITLE_CARD" '"/usr/bin/sudo"' \
  'Hyprland Plugin QML should not execute sudo directly'

# hyprpm expects an interactive terminal for its own sudo cache/update flow.
# The trusted helper must provide a PTY, wait for the real sudo password prompt,
# and only then write the transient stdin password. It must never pre-feed or log it.
contains "$TRUSTED_HELPER" 'HYPRPM="/usr/bin/hyprpm"' \
  'trusted helper does not pin hyprpm to /usr/bin'
contains "$TRUSTED_HELPER" 'HYPRBARS_REPO="https://github.com/hyprwm/hyprland-plugins"' \
  'trusted helper does not pin the official plugin repository'
contains "$TRUSTED_HELPER" 'import pty' \
  'trusted helper does not allocate a PTY for hyprpm'
contains "$TRUSTED_HELPER" 'pty.fork()' \
  'trusted helper does not run hyprpm inside a PTY'
contains "$TRUSTED_HELPER" 'password = sys.stdin.readline()' \
  'trusted helper does not receive the password from stdin'
contains "$TRUSTED_HELPER" 'print(f"AWTARCHY_{kind}\\t' \
  'trusted helper does not stream structured setup records'
contains "$TRUSTED_HELPER" 'emit("STAGE",' \
  'trusted helper does not emit live setup stages'
contains "$TRUSTED_HELPER" 'Sorry, try again.' \
  'trusted helper does not detect sudo password rejection'
contains "$TRUSTED_HELPER" 'Authentication failed: sudo rejected the password.' \
  'trusted helper does not return a useful authentication error'
contains "$TRUSTED_HELPER" 'hyprbars-status)' \
  'trusted helper lacks hyprbars-status'
contains "$TRUSTED_HELPER" 'hyprbars-enable)' \
  'trusted helper lacks hyprbars-enable'
contains "$TRUSTED_HELPER" 'hyprbars-disable)' \
  'trusted helper lacks hyprbars-disable'
contains "$TRUSTED_HELPER" '(( EUID != 0 )) || die' \
  'trusted helper does not reject root execution for hyprbars operations'
absent "$TRUSTED_HELPER" 'NOPASSWD' \
  'trusted helper must not add passwordless sudo behavior'
absent "$TRUSTED_HELPER" 'printf '\''%s\\n\\n\\n'\'' "$password" | "$SUDO"' \
  'trusted helper still relies on fragile sudo timestamp pre-authentication'

# Existing install and update paths deploy scxctl-helper root-owned.
contains "${ROOT}/awtarchy-install.sh" 'SCXCTL_HELPER_SOURCE=' \
  'installer no longer provisions the trusted helper'
contains "${ROOT}/local/share/awtarchy/awtarchy-runtime.sh" 'repair_scxctl_update_helper()' \
  'updater no longer repairs the trusted helper'

contains "$HISTORY" $'708658656ab4672d010f49b54de099200d1ab6b42bebbec2e01d80fa81df3\t.config/hypr/scripts/hyprbars_toggle.sh' \
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
(( missing_history == 0 )) || fail 'managed history is missing current Hyprland Plugin stock hashes'

printf '%s\n' 'PASS: Hyprland Plugin title-bar control uses PTY-backed auth with live progress feedback.'
