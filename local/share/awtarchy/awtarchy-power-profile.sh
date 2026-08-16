#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# Reconcile Awtarchy laptop power-profile support without stacking power managers.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd -P)"
MANAGED_FILE="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
POWER_PROFILE_HELPER_SOURCE="${REPO_ROOT}/local/libexec/awtarchy/power-profile-helper"
POWER_PROFILE_HELPER_DESTINATION="/usr/local/libexec/awtarchy/power-profile-helper"

log()  { printf '[awtarchy-power] %s\n' "$*"; }
warn() { printf '[awtarchy-power] WARN: %s\n' "$*" >&2; }
die()  { printf '[awtarchy-power] ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

is_laptop() {
  if [[ -d /sys/class/power_supply ]] \
    && find /sys/class/power_supply -maxdepth 1 \( -type l -o -type d \) \
      -name 'BAT*' -print -quit 2>/dev/null | grep -q .;
  then
    return 0
  fi

  case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || true)" in
    8|9|10|14|30|31|32) return 0 ;;
    *) return 1 ;;
  esac
}

run_root() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
    return
  fi
  have sudo || die "sudo is required to reconcile laptop power management."
  sudo -v || die "sudo authentication failed."
  sudo "$@"
}

package_installed() {
  pacman -Qq 2>/dev/null | grep -Fx -- "$1" >/dev/null
}

managed_package() {
  local pkg="$1"
  [[ -r $MANAGED_FILE ]] && grep -Fxq "$pkg" "$MANAGED_FILE"
}

record_managed() {
  local tmp pkg
  (( $# )) || return 0
  tmp="$(mktemp)"
  [[ -r $MANAGED_FILE ]] && cat "$MANAGED_FILE" >"$tmp" || : >"$tmp"
  for pkg in "$@"; do
    package_installed "$pkg" && printf '%s\n' "$pkg" >>"$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"
  run_root install -d -m 0755 "$(dirname "$MANAGED_FILE")"
  run_root install -m 0644 "$tmp" "$MANAGED_FILE"
  rm -f -- "$tmp"
}

forget_managed() {
  local pkg="$1" tmp
  [[ -r $MANAGED_FILE ]] || return 0
  tmp="$(mktemp)"
  grep -Fxv "$pkg" "$MANAGED_FILE" >"$tmp" || true
  run_root install -m 0644 "$tmp" "$MANAGED_FILE"
  rm -f -- "$tmp"
}

power_profile_helper_is_current() {
  local owner mode destination_dir dir_owner dir_mode
  destination_dir="$(dirname -- "$POWER_PROFILE_HELPER_DESTINATION")"

  [[ -f $POWER_PROFILE_HELPER_SOURCE && ! -L $POWER_PROFILE_HELPER_SOURCE ]] || return 1
  [[ -d $destination_dir && ! -L $destination_dir ]] || return 1
  [[ -f $POWER_PROFILE_HELPER_DESTINATION && ! -L $POWER_PROFILE_HELPER_DESTINATION \
    && -x $POWER_PROFILE_HELPER_DESTINATION ]] || return 1

  dir_owner="$(/usr/bin/stat -c %u -- "$destination_dir" 2>/dev/null)" || return 1
  dir_mode="$(/usr/bin/stat -c %a -- "$destination_dir" 2>/dev/null)" || return 1
  [[ $dir_owner == 0 && $dir_mode =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$dir_mode & 8#022) == 0 )) || return 1

  owner="$(/usr/bin/stat -c %u -- "$POWER_PROFILE_HELPER_DESTINATION" 2>/dev/null)" || return 1
  mode="$(/usr/bin/stat -c %a -- "$POWER_PROFILE_HELPER_DESTINATION" 2>/dev/null)" || return 1
  [[ $owner == 0 && $mode =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$mode & 8#022) == 0 )) || return 1
  /usr/bin/cmp -s -- "$POWER_PROFILE_HELPER_SOURCE" "$POWER_PROFILE_HELPER_DESTINATION"
}

install_power_profile_helper() {
  local destination_dir temporary source_hash installed_hash
  destination_dir="$(dirname -- "$POWER_PROFILE_HELPER_DESTINATION")"

  [[ -f $POWER_PROFILE_HELPER_SOURCE && ! -L $POWER_PROFILE_HELPER_SOURCE ]] \
    || die "Trusted Power Mode helper source is missing: $POWER_PROFILE_HELPER_SOURCE"
  [[ $(/usr/bin/head -n1 -- "$POWER_PROFILE_HELPER_SOURCE") == '#!/usr/bin/bash' ]] \
    || die "Trusted Power Mode helper must use /usr/bin/bash."
  /usr/bin/bash -n "$POWER_PROFILE_HELPER_SOURCE" \
    || die "Trusted Power Mode helper failed Bash syntax validation."

  power_profile_helper_is_current && return 0
  [[ ! -L $destination_dir ]] \
    || die "Refusing symlinked Power Mode helper directory: $destination_dir"

  run_root /usr/bin/install -d -m 0755 -o root -g root "$destination_dir"
  temporary="${POWER_PROFILE_HELPER_DESTINATION}.tmp.$$"
  run_root /usr/bin/rm -f -- "$temporary"
  run_root /usr/bin/install -m 0755 -o root -g root "$POWER_PROFILE_HELPER_SOURCE" "$temporary"

  source_hash="$(/usr/bin/sha256sum "$POWER_PROFILE_HELPER_SOURCE" | /usr/bin/awk '{print $1}')"
  installed_hash="$(/usr/bin/sha256sum "$temporary" | /usr/bin/awk '{print $1}')"
  if [[ $source_hash != "$installed_hash" ]]; then
    run_root /usr/bin/rm -f -- "$temporary"
    die "Trusted Power Mode helper staging hash mismatch."
  fi

  run_root /usr/bin/mv -Tf -- "$temporary" "$POWER_PROFILE_HELPER_DESTINATION"
  power_profile_helper_is_current \
    || die "Trusted Power Mode helper verification failed after install."
}

ask_replace_ppd() {
  local answer=""
  if [[ ! -t 0 || ! -t 1 ]]; then
    return 1
  fi
  printf 'TLP and power-profiles-daemon conflict. Replace power-profiles-daemon with tlp-pd? [Y/n] '
  IFS= read -r answer || return 1
  case "$answer" in
    ""|y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

remove_ppd_for_tlp() {
  package_installed power-profiles-daemon || return 0

  if managed_package power-profiles-daemon; then
    log "Replacing Awtarchy-owned power-profiles-daemon with tlp-pd."
  elif ! ask_replace_ppd; then
    warn "Leaving user-owned power-profiles-daemon installed. Power Mode remains disabled until the TLP/PPD conflict is resolved."
    return 1
  fi

  run_root systemctl disable --now power-profiles-daemon.service 2>/dev/null || true
  run_root pacman -Rns --noconfirm power-profiles-daemon
  forget_managed power-profiles-daemon
}

install_laptop_backend() {
  local -a newly_managed=()

  install_power_profile_helper

  if package_installed power-profiles-daemon; then
    remove_ppd_for_tlp || return 0
  fi

  if ! package_installed tlp; then
    newly_managed+=(tlp)
  fi
  if ! package_installed tlp-pd; then
    newly_managed+=(tlp-pd)
  fi

  if (( ${#newly_managed[@]} )); then
    log "Installing laptop power-profile backend: ${newly_managed[*]}"
    run_root pacman -S --needed --noconfirm "${newly_managed[@]}"
    record_managed "${newly_managed[@]}"
  fi

  if package_installed tlp && package_installed tlp-pd; then
    run_root systemctl enable --now tlp.service tlp-pd.service
  fi
}

cleanup_desktop_backend() {
  if managed_package tlp-pd && package_installed tlp-pd; then
    log "Removing Awtarchy-owned tlp-pd from non-laptop hardware."
    run_root systemctl disable --now tlp-pd.service 2>/dev/null || true
    run_root pacman -Rns --noconfirm tlp-pd
    forget_managed tlp-pd
  fi
}

main() {
  have pacman || return 0
  have systemctl || return 0

  if is_laptop; then
    install_laptop_backend
  else
    cleanup_desktop_backend
  fi
}

main "$@"
