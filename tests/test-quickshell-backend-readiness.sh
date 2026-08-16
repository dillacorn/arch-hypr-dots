#!/usr/bin/env bash

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
POWER_SETUP="${REPO_ROOT}/config/hypr/scripts/quickshell_power_profile_setup.sh"
POWER_RECONCILER="${REPO_ROOT}/local/share/awtarchy/awtarchy-power-profile.sh"
READY_SOUND="${REPO_ROOT}/config/hypr/scripts/quickshell_ready_sound.sh"

# pacman can resolve a queried virtual provider such as power-profiles-daemon
# to tlp-pd. Backend conflict detection must inspect literal installed package
# names instead of querying the provider name directly.
assert_contains "$POWER_CARD" 'pacman -Qq 2>/dev/null | grep -Fx -- power-profiles-daemon >/dev/null'
assert_not_contains "$POWER_CARD" 'pacman -Qq power-profiles-daemon'
assert_contains "$POWER_SETUP" 'pacman -Qq 2>/dev/null | grep -Fx -- "$1" >/dev/null'
assert_not_contains "$POWER_SETUP" 'pacman -Qq power-profiles-daemon'
assert_contains "$POWER_RECONCILER" 'pacman -Qq 2>/dev/null | grep -Fx -- "$1" >/dev/null'

# Quickshell 0.3 initializes its NetworkManager backend when the singleton is
# constructed. If Hyprland launches the shell before NetworkManager is active,
# the session must restart the shell once NetworkManager becomes ready.
assert_contains "$READY_SOUND" 'if network_manager_installed && ! network_manager_active; then'
assert_contains "$READY_SOUND" 'network_backend_may_need_restart=1'
assert_contains "$READY_SOUND" '"$QUICKSHELL_MANAGER" restart >/dev/null 2>&1 || exit 0'

printf 'Quickshell backend readiness regression tests passed.\n'
