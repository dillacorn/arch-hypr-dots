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
contains "$SCRIPT" 'will not hot-unload hyprbars because that can crash Hyprland.' \
  'hyprbars hot-unload safety behavior disappeared'
absent "$SCRIPT" 'sudo -v' 'keyboard hyprbars script performs unconditional sudo pre-authentication'

# The control belongs directly in Quick Settings immediately below the Num Lock
# session-start toggle, not inside the Power Mode card or Bar Appearance settings.
contains "$QUICK_SETTINGS" 'TitleBarsCard {' \
  'Quick Settings main list does not contain the Hyprland Plugin card'
absent "$POWER_CARD" 'TitleBarsCard {' \
  'Hyprland Plugin card is still nested inside Power Mode'
absent "$BAR_SETTINGS" 'text: "Title Bars"' \
  'duplicate Title Bars control is still hidden in Bar Appearance settings'
absent "$BAR_SETTINGS" 'hyprbarsScript' \
  'Bar Appearance settings still owns the hyprbars workflow'
numlock_line="$(grep -nF 'text: "Disable Num Lock at session start"' "$QUICK_SETTINGS" | head -n1 | cut -d: -f1)"
plugin_line="$(grep -nF 'TitleBarsCard {' "$QUICK_SETTINGS" | head -n1 | cut -d: -f1)"
[[ -n "$numlock_line" && -n "$plugin_line" && "$plugin_line" -gt "$numlock_line" ]] \
  || fail 'Hyprland Plugin card is not below the Num Lock session-start control'

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
contains "$TITLE_CARD" 'hyprbarsState === "not-loaded"' \
  'Hyprland Plugin UI does not represent persisted-enabled/runtime-not-loaded state'
contains "$TITLE_CARD" 'return "Enabled · Not loaded";' \
  'Hyprland Plugin UI does not label enabled-but-not-loaded state clearly'
contains "$TITLE_CARD" 'return "Load";' \
  'Hyprland Plugin UI does not offer a Load action for enabled-but-not-loaded state'
contains "$TITLE_CARD" 'hyprbarsState === "disabled-pending"' \
  'Hyprland Plugin UI does not represent a loaded plugin with persisted disable state'
contains "$TITLE_CARD" 'state === "enabled" || state === "not-loaded"' \
  'Hyprland Plugin status reader drops the not-loaded state'
contains "$TITLE_CARD" 'state === "disabled" || state === "disabled-pending"' \
  'Hyprland Plugin status reader drops the disabled-pending state'
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

# Both the keyboard-side machine status and Quick Settings must converge on the
# same trusted status implementation. The helper combines persisted hyprpm state
# with current Hyprland load state and has a loaded-state fallback if list parsing
# cannot determine the persisted value.
contains "$SCRIPT" 'TRUSTED_HELPER="/usr/local/libexec/awtarchy/scxctl-helper"' \
  'keyboard hyprbars script does not know the trusted shared status helper'
contains "$SCRIPT" '"$TRUSTED_HELPER" hyprbars-status' \
  'keyboard machine status does not use the same status source as Quick Settings'
contains "$TRUSTED_HELPER" 'hyprbars_persistent_state()' \
  'trusted helper lacks a canonical persisted hyprbars state parser'
contains "$TRUSTED_HELPER" 'Plugin[[:space:]]+hyprbars' \
  'trusted helper does not parse the hyprpm plugin record robustly'
contains "$TRUSTED_HELPER" "printf '%s\\n' 'not-loaded'" \
  'trusted helper does not expose persisted-enabled/runtime-not-loaded state'
contains "$TRUSTED_HELPER" 'disabled-pending' \
  'trusted helper does not expose persisted-disabled/runtime-loaded state'
contains "$TRUSTED_HELPER" 'hyprbars_loaded' \
  'trusted helper does not fall back to current Hyprland plugin load state'

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
contains "$TRUSTED_HELPER" 'print(f"AWTARCHY_{kind}' \
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

contains "$HISTORY" $'708658656ab4672d010f49b54de099200d1ab6b42bebb822ec2e01d80fa81df3\t.config/hypr/scripts/hyprbars_toggle.sh' \
  'managed history is missing the pre-fix hyprbars script hash'

# Keep current stock hashes in managed history so future updates can recognize
# this release's files as Awtarchy-owned instead of preserving them as user edits.
missing_history=0
for rel in \
  .config/quickshell/awtarchy/QuickSettings.qml \
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
    printf 'MISSING_MANAGED_HASH %s\t%s\n' "$digest"$'\t'"$rel" >&2
    missing_history=1
  fi
done
(( missing_history == 0 )) || fail 'managed history is missing current Hyprland Plugin stock hashes'

bash "${ROOT}/tests/test-hyprbars-runtime-state.sh"

printf '%s\n' 'PASS: Hyprland Plugin state is shared between keyboard and Quick Settings and placed below Num Lock.'
