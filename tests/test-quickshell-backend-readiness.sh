#!/usr/bin/env bash

# This test intentionally matches literal shell source containing $ variables.
# shellcheck disable=SC2016

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "${file#"${REPO_ROOT}/"} is missing: ${needle}"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "${file#"${REPO_ROOT}/"} still contains: ${needle}"
}

POWER_CARD="${REPO_ROOT}/config/quickshell/awtarchy/PowerModeCard.qml"
POWER_RECONCILER="${REPO_ROOT}/local/share/awtarchy/awtarchy-power-profile.sh"
RUNTIME="${REPO_ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
READY_SOUND="${REPO_ROOT}/config/hypr/scripts/quickshell_ready_sound.sh"

# pacman can resolve a queried virtual provider such as power-profiles-daemon
# to tlp-pd. Backend conflict detection must inspect literal installed package
# names instead of querying the provider name directly.
assert_contains "$POWER_CARD" '/usr/bin/pacman -Qq 2>/dev/null | /usr/bin/grep -Fx -- power-profiles-daemon >/dev/null'
assert_not_contains "$POWER_CARD" 'pacman -Qq power-profiles-daemon'
assert_contains "$POWER_CARD" '"/usr/bin/bash", "-c"'
assert_not_contains "$POWER_CARD" '"bash", "-lc"'
assert_contains "$POWER_RECONCILER" 'pacman -Qq 2>/dev/null | grep -Fx -- "$1" >/dev/null'

# Laptop installs and updates must provision the TLP D-Bus compatibility
# backend as a pair. Installing only tlp leaves Quickshell PowerProfiles with
# no supported service even though TLP itself is installed.
assert_contains "$POWER_RECONCILER" 'newly_managed+=(tlp)'
assert_contains "$POWER_RECONCILER" 'newly_managed+=(tlp-pd)'
assert_contains "$POWER_RECONCILER" 'systemctl enable --now tlp.service tlp-pd.service'
assert_contains "$RUNTIME" 'reconcile_power_profile_backend "$REPO_DIR"'
assert_contains "$RUNTIME" 'reconcile_power_profile_backend "$repo_dir"'

# tlpui is now an official Arch Extra package. The laptop reconciler runs before
# the runtime AUR stage, so it must install tlpui with pacman even when a user
# keeps an existing power-profiles-daemon backend.
assert_contains "$POWER_RECONCILER" 'install_tlpui()'
assert_contains "$POWER_RECONCILER" 'run_root pacman -S --needed --noconfirm tlpui'
assert_contains "$POWER_RECONCILER" 'record_managed tlpui'

# A successful tlpctl command only proves the tlp-pd CLI path works. The
# Quickshell PowerProfiles singleton talks to the org.freedesktop D-Bus API,
# so the card must probe that exact service/interface before exposing controls.
assert_contains "$POWER_CARD" '/usr/bin/busctl'
assert_contains "$POWER_CARD" 'org.freedesktop.UPower.PowerProfiles'
assert_contains "$POWER_CARD" '/org/freedesktop/UPower/PowerProfiles'
assert_contains "$POWER_CARD" 'ActiveProfile'
assert_not_contains "$POWER_CARD" 'tlpctl get'

# Quickshell only constructs the PowerProfiles D-Bus interface when the
# singleton starts. In-session setup therefore needs a full shell restart after
# the helper succeeds instead of merely re-running the CLI backend probe.
assert_contains "$POWER_CARD" 'readonly property string quickshellManager:'
assert_contains "$POWER_CARD" 'Quickshell.execDetached([root.quickshellManager, "restart"]);'

# Quickshell 0.3 initializes its NetworkManager backend when the singleton is
# constructed. If Hyprland launches the shell before NetworkManager is active,
# the session must restart the shell once NetworkManager becomes ready.
assert_contains "$READY_SOUND" 'if network_manager_installed && ! network_manager_active; then'
assert_contains "$READY_SOUND" 'network_backend_may_need_restart=1'
assert_contains "$READY_SOUND" '"$QUICKSHELL_MANAGER" restart >/dev/null 2>&1 || exit 0'

printf 'Quickshell power/network backend readiness regression tests passed.\n'
