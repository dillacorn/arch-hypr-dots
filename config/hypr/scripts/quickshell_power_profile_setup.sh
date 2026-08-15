#!/usr/bin/env bash
# Configure the power-profile D-Bus backend used by Awtarchy Quickshell.

set -euo pipefail

have() {
  command -v "$1" >/dev/null 2>&1
}

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

pause() {
  printf '\nPress Enter to close...'
  read -r _ || true
}

confirm_replace_ppd() {
  local answer=""
  printf '\nTLP and power-profiles-daemon are both installed.\n'
  printf 'Awtarchy uses TLP on laptops and should use tlp-pd for Power Mode.\n'
  printf 'Replace power-profiles-daemon with tlp-pd now? [Y/n] '
  IFS= read -r answer || return 1
  case "$answer" in
    ""|y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

is_laptop || {
  printf 'Power Mode setup is only intended for laptops.\n' >&2
  pause
  exit 1
}

have pacman || {
  printf 'pacman is required for Awtarchy Power Mode setup.\n' >&2
  pause
  exit 1
}

if pacman -Qq tlp >/dev/null 2>&1; then
  if pacman -Qq power-profiles-daemon >/dev/null 2>&1; then
    if ! confirm_replace_ppd; then
      printf '\nNo changes were made. Resolve the TLP/PPD conflict before using Power Mode.\n' >&2
      pause
      exit 2
    fi

    sudo systemctl disable --now power-profiles-daemon.service 2>/dev/null || true
    sudo pacman -Rns --noconfirm power-profiles-daemon
  fi

  printf 'Awtarchy detected TLP. Installing its Power Profiles D-Bus backend...\n'
  sudo pacman -S --needed --noconfirm tlp-pd
  sudo systemctl enable --now tlp.service tlp-pd.service
else
  printf 'TLP is not installed. Installing the standard Power Profiles backend...\n'
  sudo pacman -S --needed --noconfirm power-profiles-daemon
  sudo systemctl enable --now power-profiles-daemon.service
fi

printf '\nPower Mode backend is ready. Reopen Quick Settings if the controls do not appear immediately.\n'
pause
