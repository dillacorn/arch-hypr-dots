#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# Reconcile Awtarchy laptop power-profile support without stacking power managers.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

MANAGED_FILE="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"

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
  pacman -Qq "$1" >/dev/null 2>&1
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
