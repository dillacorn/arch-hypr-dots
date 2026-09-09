#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# awtarchy-runtime.sh
# Internal Awtarchy install and maintenance runtime.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

# ──────────────────────────────────────────────────────────────────────────────
# Colors / logging
# ──────────────────────────────────────────────────────────────────────────────
COLOR_RED=$'\033[1;31m'
COLOR_GREEN=$'\033[1;32m'
COLOR_YELLOW=$'\033[1;33m'
COLOR_BLUE=$'\033[1;34m'
COLOR_MAGENTA=$'\033[1;35m'
COLOR_CYAN=$'\033[1;36m'
COLOR_DIM=$'\033[2m'
COLOR_RESET=$'\033[0m'

log()  { printf '%s\n' "${COLOR_BLUE}$*${COLOR_RESET}"; }
ok()   { printf '%s\n' "${COLOR_GREEN}$*${COLOR_RESET}"; }
warn() { printf '%s\n' "${COLOR_YELLOW}WARN: $*${COLOR_RESET}" >&2; }
die()  { printf '%s\n' "${COLOR_RED}ERROR: $*${COLOR_RESET}" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ──────────────────────────────────────────────────────────────────────────────
# Package defaults
# ──────────────────────────────────────────────────────────────────────────────
declare -a PKG_GROUPS=(
  "Window Management:hyprland hyprpaper hypridle hyprpicker hyprsunset quickshell grim satty slurp wl-clipboard cliphist zbar wf-recorder zenity qt5ct qt5-wayland kvantum-qt5 qt6ct qt6-wayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk libnotify nwg-look"
  "Fonts:woff2-font-awesome otf-font-awesome ttf-dejavu ttf-liberation ttf-noto-nerd noto-fonts-emoji"
  "Themes:papirus-icon-theme materia-gtk-theme kvantum-theme-materia"
  "Terminal Apps:nano micro fastfetch btop htop curl passt devtools wget git dos2unix brightnessctl ipcalc cmatrix asciiquarium figlet espeak-ng cava man-db man-pages unzip xarchiver ncdu ddcutil scx-scheds scx-tools"
  "Utilities:upower polkit python-gobject gnome-keyring networkmanager bluez bluez-utils wiremix pcmanfm-qt gvfs gvfs-smb gvfs-mtp gvfs-afc speedcrunch imagemagick pipewire pipewire-pulse pipewire-alsa ufw jq earlyoom libsixel xdg-utils python usbutils awww"
  "Multimedia:ffmpeg avahi nss-mdns mpv snapshot exiv2 zathura zathura-pdf-mupdf"
  "Development:base-devel archlinux-keyring bubblewrap gnupg coreutils clang ninja go rust dmidecode nftables"
  "Network Tools:firefox wireguard-tools wireplumber openssh iptables systemd-resolvconf qemu-guest-agent dnsmasq dhcpcd inetutils openbsd-netcat"
)

# Optional Arch packages are shown first and start unchecked.
declare -a OPTIONAL_ARCH_PACKAGES=(
  moonlight-qt
  mousai
  gamemode
  gamescope
  virt-manager
  qemu
  qemu-hw-usb-host
  virt-viewer
  vde2
  libguestfs
  swtpm
)

# Selecting virt-manager toggles this explicit virtualization stack together.
declare -a VIRT_MANAGER_PACKAGES=(
  virt-manager
  qemu
  qemu-hw-usb-host
  virt-viewer
  vde2
  libguestfs
  swtpm
)

declare -a PACKAGES_AUR=(
  smtty
  awtwall
  hyprmoncfg-bin
  bibata-cursor-theme-bin
  mpvpaper
  qimgv
  alacritty-graphics
  obs-pipewire-audio-capture-bin
)

# Optional AUR packages are shown first and start unchecked.
declare -a OPTIONAL_AUR_PACKAGES=(
  vesktop-bin
)

# Format: selected|friendly name|Flathub app ID
# Flatseal is available as an opt-in Flatpak; native apps live in Arch/AUR.
declare -a FLATPAK_CATALOG=(
  "0|Flatseal|com.github.tchx84.Flatseal"
)

# ──────────────────────────────────────────────────────────────────────────────
# Install settings populated by the beginning-of-install UI
# ──────────────────────────────────────────────────────────────────────────────
TARGET_USER=""
HOME_DIR=""
REPO_DIR=""
IS_VM=false
IS_LAPTOP=false
NO_REBOOT=0
DRY_RUN=0
TOP_MENU_ACTIVE=0

INSTALL_ARCH=1
INSTALL_AUR=1
INSTALL_FLATPAK=1
INSTALL_GPU=1
INSTALL_LY=0
ENABLE_KEYRING_PAM=0
OVERWRITE_BASHRC=0
OVERWRITE_BASH_PROFILE=0

ARCH_SELECTED=()
AUR_SELECTED=()
FLATPAK_SELECTED_IDS=()
FLATPAK_SELECTED_NAMES=()

cleanup_install_temp() {
  :
}
trap cleanup_install_temp EXIT

# ──────────────────────────────────────────────────────────────────────────────
# Generic helpers
# ──────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage:
  awtarchy.sh
  awtarchy.sh dry-run
  awtarchy.sh install [--no-reboot] [--dry-run]
  awtarchy.sh update-reset-backup [--tag <tag>] [--mode preserve|clean] [--review-only]
  awtarchy.sh update-backup-cleaner [options]
  awtarchy.sh clean-backups [options]
  awtarchy.sh troubleshoot
  awtarchy.sh help

Top-level no-arg mode opens the built-in terminal menu.
No fzf/gum/dialog/whiptail dependency is used.
EOF
}

retry_command() {
  local retries=3 count=0 exit_code=0
  until "$@"; do
    exit_code=$?
    ((count++)) || true
    printf '%s\n' "${COLOR_RED}Attempt ${count}/${retries} failed:${COLOR_RESET}"
    printf '  '
    printf '%q ' "$@"
    printf '\n'
    if (( count < retries )); then
      sleep 2
    else
      return "$exit_code"
    fi
  done
}

require_root() {
  if (( DRY_RUN == 1 )); then
    return 0
  fi
  [[ "${EUID}" -eq 0 ]] || die "Run this command with sudo/root."
}

detect_target_user_install() {
  if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
  elif [[ "${EUID}" -eq 0 ]]; then
    TARGET_USER="$(awk -F: '$3>=1000 && $1!="nobody"{print $1; exit}' /etc/passwd || true)"
  else
    TARGET_USER="${USER:-}"
    if [[ -z "${TARGET_USER}" ]]; then
      TARGET_USER="$(id -un 2>/dev/null || true)"
    fi
  fi
  [[ -n "${TARGET_USER}" ]] || die "Could not determine target user. Run with sudo from the user account to install for."
  HOME_DIR="$(getent passwd "${TARGET_USER}" | cut -d: -f6 || true)"
  [[ -n "${HOME_DIR}" && -d "${HOME_DIR}" ]] || die "Home directory for ${TARGET_USER} not found."
  REPO_DIR="${AWTARCHY_REPO_DIR:-${HOME_DIR}/awtarchy}"
}

user_config_has_no_files() {
  local config_dir="${HOME_DIR}/.config"
  [[ -d "$config_dir" ]] || return 0

  local first_file
  first_file="$(find "$config_dir" -mindepth 1 \( -type f -o -type l \) -print -quit 2>/dev/null || true)"
  [[ -z "$first_file" ]]
}

run_as_target() {
  if [[ "${EUID}" -eq 0 ]]; then
    runuser -u "${TARGET_USER}" -- "$@"
  else
    "$@"
  fi
}

create_directory() {
  local dir="$1"
  retry_command run_as_target install -d -m 0755 -- "$dir" \
    || die "Failed to create target-user directory: $dir"
}

pacman_install_one() {
  local package="$1" was_installed=0
  pacman -Qi "$package" >/dev/null 2>&1 && was_installed=1

  if (( was_installed == 0 )); then
    printf '%s\n' "${COLOR_CYAN}Installing ${package}...${COLOR_RESET}"
    pacman -S --needed --noconfirm "$package"
    if pacman -Qi "$package" >/dev/null 2>&1; then
      install -d -m 0755 /var/lib/awtarchy
      touch /var/lib/awtarchy/managed-packages
      grep -Fxq "$package" /var/lib/awtarchy/managed-packages \
        || printf '%s\n' "$package" >>/var/lib/awtarchy/managed-packages
      LC_ALL=C sort -u -o /var/lib/awtarchy/managed-packages /var/lib/awtarchy/managed-packages
      chmod 0644 /var/lib/awtarchy/managed-packages
    fi
  else
    printf '%s\n' "${COLOR_YELLOW}${package} already installed. Skipping...${COLOR_RESET}"
  fi
}

array_contains_exact() {
  local needle="$1" item
  shift || true
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

migrate_cheese_to_snapshot_stage() {
  local reconciler="$1" runtime_source="$2"
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"

  [[ -f "$reconciler" && ! -L "$reconciler" ]] \
    || die "Package replacement reconciler is unavailable or unsafe: ${reconciler}"
  [[ -r "$runtime_source" && ! -L "$runtime_source" ]] \
    || die "Package replacement runtime is unavailable or unsafe: ${runtime_source}"

  AWTARCHY_RUNTIME="$runtime_source" \
    AWTARCHY_MANAGED_PACKAGES_FILE="$managed_file" \
    bash "$reconciler" --migrate-replacements
}

runtime_catalog_has_exact_package() {
  local runtime_source="$1" package="$2"
  awk -v package="$package" '
    /^declare -a PKG_GROUPS=\(/ {
      if (seen)
        invalid=1
      seen=1
      in_groups=1
      next
    }
    in_groups && /^[[:space:]]*\)[[:space:]]*$/ {
      closed=1
      in_groups=0
      next
    }
    in_groups {
      line=$0
      sub(/^[[:space:]]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      sub(/^[^:]*:/, "", line)
      count=split(line, fields, /[[:space:]]+/)
      for (i=1; i<=count; i++) {
        if (fields[i] == package)
          found=1
      }
    }
    END {
      if (!seen || !closed || in_groups || invalid)
        exit 2
      exit(found ? 0 : 1)
    }
  ' "$runtime_source"
}

lockscreen_target_retires_hyprlock() {
  local repo_dir="$1"
  local runtime_source="${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh"
  local config_root="${repo_dir}/config"
  local catalog_rc scan_rc

  [[ -f "${repo_dir}/config/quickshell/awtarchy-lock/shell.qml" \
    && ! -L "${repo_dir}/config/quickshell/awtarchy-lock/shell.qml" ]] || return 1
  [[ -f "${repo_dir}/config/hypr/scripts/awtarchy_lock.sh" \
    && ! -L "${repo_dir}/config/hypr/scripts/awtarchy_lock.sh" ]] || return 1
  [[ ! -e "${repo_dir}/config/hypr/hyprlock.conf" \
    && ! -L "${repo_dir}/config/hypr/hyprlock.conf" ]] || return 1
  [[ -r "$runtime_source" && ! -L "$runtime_source" ]] || return 1
  [[ -d "$config_root" && ! -L "$config_root" ]] || return 1

  if runtime_catalog_has_exact_package "$runtime_source" hyprlock; then
    return 1
  else
    catalog_rc=$?
    [[ $catalog_rc -eq 1 ]] || return 1
  fi

  if grep -R -I -w -q -- hyprlock "$config_root"; then
    return 1
  else
    scan_rc=$?
    [[ $scan_rc -eq 1 ]] || return 1
  fi
  return 0
}

retired_hyprlock_backup_path() {
  local stamp candidate suffix=0
  stamp="$(date '+%Y%m%d-%H%M%S')"
  candidate="${HOME_DIR}/.config/hypr/hyprlock.conf.backup.${stamp}"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    ((suffix += 1))
    candidate="${HOME_DIR}/.config/hypr/hyprlock.conf.backup.${stamp}.${suffix}"
  done
  printf '%s\n' "$candidate"
}

migrate_live_hyprlock_hyprland() {
  local repo_dir="$1"
  local helper="${repo_dir}/local/share/awtarchy/awtarchy-lockscreen-hyprland-migrate.py"
  local live="${HOME_DIR}/.config/hypr/hyprland.lua"
  local dir="" tmp="" backup="" stamp="" suffix=0

  [[ -e "$live" || -L "$live" ]] || return 0
  [[ -f "$live" && ! -L "$live" ]] \
    || die "Live Hyprland config is unavailable or unsafe during Hyprlock retirement: ${live}"
  if ! grep -Fqi -- hyprlock "$live" \
    && ! grep -Fq -- 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' "$live"; then
    return 0
  fi
  [[ -f "$helper" && ! -L "$helper" ]] \
    || die "Live Hyprland lockscreen migration helper is unavailable or unsafe: ${helper}"

  dir="$(dirname -- "$live")"
  tmp="$(run_as_target mktemp --tmpdir="$dir" '.awtarchy-hyprland-lock.tmp.XXXXXX')" \
    || die "Could not stage the personalized Hyprland lockscreen migration."

  if ! run_as_target python3 "$helper" "$live" "$tmp"; then
    run_as_target rm -f -- "$tmp" >/dev/null 2>&1 || true
    die "Personalized hyprland.lua contains an unknown Hyprlock reference; Hyprlock was not retired."
  fi

  stamp="$(date '+%Y%m%d-%H%M%S')"
  backup="${live}.backup.${stamp}"
  while [[ -e "$backup" || -L "$backup" ]]; do
    ((suffix += 1))
    backup="${live}.backup.${stamp}.${suffix}"
  done

  retry_command run_as_target cp -a -- "$live" "$backup" \
    || die "Could not back up personalized Hyprland config before lockscreen migration."
  retry_command run_as_target chmod --reference="$live" "$tmp" \
    || die "Could not preserve personalized Hyprland config permissions during lockscreen migration."
  retry_command run_as_target mv -f -- "$tmp" "$live" \
    || die "Could not install the personalized Hyprland lockscreen migration."

  log "Migrated known Hyprlock references in personalized hyprland.lua; backup: ${backup}"
}

migrate_screenshare_guard_hyprland_stage() {
  local repo_dir="$1" target_home="$2"
  local helper="${repo_dir}/local/share/awtarchy/migrate-screenshare-guard-hyprland.sh"
  local live="${HOME_DIR}/.config/hypr/hyprland.lua"
  local managed="${target_home}/.config/hypr/hyprland.lua"
  local stamp backup suffix=0

  [[ -f "$live" && ! -L "$live" ]] || return 0

  [[ -f "$helper" && ! -L "$helper" ]] \
    || die "Screen Share Guard Hyprland migration helper is unavailable or unsafe: ${helper}"
  [[ -f "$managed" && ! -L "$managed" ]] \
    || die "Managed hyprland.lua is unavailable for Screen Share Guard migration: ${managed}"

  stamp="$(date '+%Y%m%d-%H%M%S')"
  backup="${live}.backup.${stamp}"
  while [[ -e "$backup" || -L "$backup" ]]; do
    ((suffix += 1))
    backup="${live}.backup.${stamp}.${suffix}"
  done

  retry_command run_as_target bash "$helper" "$live" "$managed" "$backup" \
    || die "Could not migrate Screen Share Guard controls into personalized hyprland.lua."
}

migrate_retired_hyprlock_stage() {
  local repo_dir="$1"
  local reconciler="${repo_dir}/local/share/awtarchy/awtarchy-package-reconcile.sh"
  local runtime_source="${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh"
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
  local live="${HOME_DIR}/.config/hypr/hyprlock.conf" backup=""

  lockscreen_target_retires_hyprlock "$repo_dir" || return 0
  migrate_live_hyprlock_hyprland "$repo_dir"

  [[ -f "$reconciler" && ! -L "$reconciler" ]] \
    || die "Lockscreen package migration helper is unavailable or unsafe: ${reconciler}"
  [[ -r "$runtime_source" && ! -L "$runtime_source" ]] \
    || die "Lockscreen package migration runtime is unavailable or unsafe: ${runtime_source}"

  if [[ -e "$live" || -L "$live" ]]; then
    backup="$(retired_hyprlock_backup_path)"
    retry_command run_as_target mv -- "$live" "$backup" \
      || die "Could not preserve retired Hyprlock config: ${live}"
    log "Preserved retired Hyprlock config: ${backup}"
  fi

  AWTARCHY_RUNTIME="$runtime_source" \
    AWTARCHY_MANAGED_PACKAGES_FILE="$managed_file" \
    AWTARCHY_LOCKSCREEN_RETIRE_CONFIRMED=1 \
    bash "$reconciler" --migrate-lockscreen-retirement \
      || die "Could not complete the ownership-safe Hyprlock package migration."
}

# ──────────────────────────────────────────────────────────────────────────────
# Built-in raw-key terminal UI
# ──────────────────────────────────────────────────────────────────────────────
configure_mdns_stack() {
  local resolved_dir="/etc/systemd/resolved.conf.d"
  local resolved_file="${resolved_dir}/90-awtarchy-mdns.conf"
  local nsswitch="/etc/nsswitch.conf"
  local marker="# Managed by Awtarchy: Avahi owns mDNS/DNS-SD."
  local tmp="" nss_tmp="" backup="" nss_rc=0 changed=0
  local -a root_cmd=()

  if (( DRY_RUN == 1 )); then
    log "DRY-RUN: configure Avahi as the single mDNS stack and ensure nss-mdns"
    return 0
  fi

  command -v pacman >/dev/null 2>&1 || return 0
  pacman -Qq avahi >/dev/null 2>&1 || return 0
  have python3 || {
    warn "python3 is unavailable; mDNS NSS integration was not changed."
    return 0
  }

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    root_cmd=()
  else
    have sudo || {
      warn "sudo is unavailable; mDNS system integration was not changed."
      return 0
    }
    if ! sudo -v; then
      warn "sudo authentication failed; mDNS system integration was not changed."
      return 0
    fi
    root_cmd=(sudo)
  fi

  if ! pacman -Qq nss-mdns >/dev/null 2>&1; then
    "${root_cmd[@]}" pacman -S --needed --noconfirm nss-mdns || {
      warn "Could not install nss-mdns; Avahi NSS integration was not changed."
      return 0
    }
    changed=1
    "${root_cmd[@]}" install -d -m 0755 /var/lib/awtarchy
    "${root_cmd[@]}" touch /var/lib/awtarchy/managed-packages
    if ! grep -Fxq nss-mdns /var/lib/awtarchy/managed-packages 2>/dev/null; then
      printf '%s\n' nss-mdns | "${root_cmd[@]}" tee -a /var/lib/awtarchy/managed-packages >/dev/null
    fi
    "${root_cmd[@]}" sh -c 'LC_ALL=C sort -u -o /var/lib/awtarchy/managed-packages /var/lib/awtarchy/managed-packages && chmod 0644 /var/lib/awtarchy/managed-packages'
  fi

  if "${root_cmd[@]}" test -L "$resolved_file"; then
    warn "Refusing symbolic-link resolved mDNS drop-in: ${resolved_file}"
  elif "${root_cmd[@]}" test -e "$resolved_file" \
    && ! "${root_cmd[@]}" grep -Fqx "$marker" "$resolved_file";
  then
    warn "Refusing to replace non-Awtarchy resolved mDNS drop-in: ${resolved_file}"
  else
    tmp="$(mktemp)"
    printf '%s\n' "$marker" '[Resolve]' 'MulticastDNS=no' >"$tmp"
    "${root_cmd[@]}" install -d -m 0755 "$resolved_dir"
    if ! "${root_cmd[@]}" cmp -s "$tmp" "$resolved_file" 2>/dev/null; then
      "${root_cmd[@]}" install -m 0644 "$tmp" "$resolved_file"
      changed=1
    fi
    rm -f -- "$tmp"
  fi

  if [[ -L "$nsswitch" ]]; then
    warn "Refusing symbolic-link NSS configuration: ${nsswitch}"
  elif [[ -f "$nsswitch" && -r "$nsswitch" ]]; then
    nss_tmp="$(mktemp)"
    cp -- "$nsswitch" "$nss_tmp"
    python3 - "$nss_tmp" <<'PY' || nss_rc=$?
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)
hosts = [i for i, line in enumerate(lines) if line.lstrip().startswith("hosts:")]
if len(hosts) != 1:
    raise SystemExit(3)

i = hosts[0]
line = lines[i]
newline = "\n" if line.endswith("\n") else ""
raw = line[:-1] if newline else line
prefix, rhs = raw.split(":", 1)
tokens = rhs.split()

if any(token.startswith("mdns") for token in tokens):
    raise SystemExit(0)

try:
    insert_at = tokens.index("resolve")
except ValueError:
    try:
        insert_at = tokens.index("dns")
    except ValueError:
        raise SystemExit(4)

tokens[insert_at:insert_at] = ["mdns_minimal", "[NOTFOUND=return]"]
lines[i] = f"{prefix}: {' '.join(tokens)}{newline}"
path.write_text("".join(lines), encoding="utf-8")
raise SystemExit(10)
PY
    case "$nss_rc" in
      0)
        :
        ;;
      10)
        backup="${nsswitch}.awtarchy-backup.$(date '+%Y%m%d-%H%M%S')"
        "${root_cmd[@]}" cp -a -- "$nsswitch" "$backup"
        "${root_cmd[@]}" install -m 0644 "$nss_tmp" "$nsswitch"
        changed=1
        log "Backed up NSS configuration: ${backup}"
        ;;
      3)
        warn "Expected exactly one hosts: line in ${nsswitch}; leaving it unchanged."
        ;;
      4)
        warn "No resolve/dns anchor found in ${nsswitch}; leaving hosts lookup order unchanged."
        ;;
      *)
        warn "Could not reconcile ${nsswitch}; leaving it unchanged."
        ;;
    esac
    rm -f -- "$nss_tmp"
  else
    warn "NSS configuration is unavailable: ${nsswitch}"
  fi

  if (( changed == 1 )) && have systemctl; then
    "${root_cmd[@]}" systemctl try-restart systemd-resolved.service >/dev/null 2>&1 || true
    "${root_cmd[@]}" systemctl try-restart avahi-daemon.service >/dev/null 2>&1 || true
  fi
}

clear_screen() {
  if [[ -w /dev/tty ]]; then
    if have clear; then clear >/dev/tty; else printf '\033[H\033[2J' >/dev/tty; fi
  else
    if have clear; then clear; else printf '\033[H\033[2J'; fi
  fi
}

read_key() {
  local key rest
  if [[ -r /dev/tty ]]; then
    IFS= read -rsn1 key </dev/tty || return 1
    if [[ "$key" == $'\033' ]]; then
      IFS= read -rsn2 -t 0.02 rest </dev/tty || true
      key+="${rest}"
    fi
  else
    IFS= read -rsn1 key || return 1
    if [[ "$key" == $'\033' ]]; then
      IFS= read -rsn2 -t 0.02 rest || true
      key+="${rest}"
    fi
  fi
  printf '%s' "$key"
}

prompt_line() {
  local prompt="$1" out=""
  printf '%s' "$prompt" >/dev/tty
  IFS= read -r out </dev/tty || true
  printf '%s' "$out"
}

press_any_key() {
  printf '%s' "Press any key to continue..." >/dev/tty
  read_key >/dev/null || true
}

single_select_menu() {
  local title="$1" default_index="$2"
  shift 2
  local -a items=("$@")
  local index="$default_index" key i
  (( index < 0 )) && index=0
  (( index >= ${#items[@]} )) && index=0

  while true; do
    clear_screen
    printf '%s\n\n' "${COLOR_CYAN}${title}${COLOR_RESET}" >/dev/tty
    for i in "${!items[@]}"; do
      if (( i == index )); then
        printf '  > %s\n' "${items[$i]}" >/dev/tty
      else
        printf '    %s\n' "${items[$i]}" >/dev/tty
      fi
    done
    printf '\n%s\n' "${COLOR_DIM}Up/Down = move, Enter = select, q = quit${COLOR_RESET}" >/dev/tty
    key="$(read_key || true)"
    case "$key" in
      $'\033[A')
        if (( index > 0 )); then
          ((index--)) || true
        fi
        ;;
      $'\033[B')
        if (( index + 1 < ${#items[@]} )); then
          ((index++)) || true
        fi
        ;;
      $'\n'|$'\r'|"") printf '%s\n' "$index"; return 0 ;;
      q|Q) printf '%s\n' "-1"; return 1 ;;
    esac
  done
}

yes_no_menu() {
  local title="$1" default_yes="${2:-1}"
  local idx=0 choice
  if [[ "$default_yes" == "1" ]]; then idx=0; else idx=1; fi
  choice="$(single_select_menu "$title" "$idx" "Yes" "No")" || return 1
  [[ "$choice" == "0" ]]
}

summary_toggle_menu() {
  local title="$1"
  local -n labels_ref="$2"
  local -n values_ref="$3"
  local index=0 key i
  while true; do
    clear_screen
    printf '%s\n\n' "${COLOR_CYAN}${title}${COLOR_RESET}"
    for i in "${!labels_ref[@]}"; do
      local mark='[ ]'
      [[ "${values_ref[$i]}" == "1" ]] && mark='[✓]'
      if (( i == index )); then
        printf '  > %s %s\n' "$mark" "${labels_ref[$i]}"
      else
        printf '    %s %s\n' "$mark" "${labels_ref[$i]}"
      fi
    done
    printf '\n%s\n' "${COLOR_DIM}Space = toggle, Enter = continue, b = back, Up/Down = move${COLOR_RESET}"
    key="$(read_key || true)"
    case "$key" in
      $'\033[A')
        if (( index > 0 )); then
          ((index--)) || true
        fi
        ;;
      $'\033[B')
        if (( index + 1 < ${#labels_ref[@]} )); then
          ((index++)) || true
        fi
        ;;
      ' ')
        if [[ "${values_ref[index]}" == "1" ]]; then
          values_ref[index]=0
        else
          values_ref[index]=1
        fi
        ;;
      b|B) return 2 ;;
      $'\n'|$'\r'|"") return 0 ;;
    esac
  done
}

split_pkg_words() {
  local blob="$1"
  local -a words=()
  local IFS=' '

  read -r -a words <<< "$blob"
  printf '%s\n' "${words[@]}"
}

build_arch_picker_arrays() {
  ARCH_LABELS=()
  ARCH_VALUES=()
  ARCH_SELECTED_FLAGS=()
  ARCH_KINDS=()

  local group group_name packages pkg
  for pkg in "${OPTIONAL_ARCH_PACKAGES[@]}"; do
    ARCH_LABELS+=("${pkg}    ${COLOR_DIM}(optional)${COLOR_RESET}")
    ARCH_VALUES+=("${pkg}")
    ARCH_SELECTED_FLAGS+=("0")
    ARCH_KINDS+=("item")
  done

  while IFS= read -r group; do
    [[ -n "$group" ]] || continue
    IFS=':' read -r group_name packages <<< "$group"

    ARCH_LABELS+=("${group_name}")
    ARCH_VALUES+=("")
    ARCH_SELECTED_FLAGS+=("0")
    ARCH_KINDS+=("group")

    while IFS= read -r pkg; do
      [[ -n "$pkg" ]] || continue
      ARCH_LABELS+=("  ${pkg}")
      ARCH_VALUES+=("${pkg}")
      ARCH_SELECTED_FLAGS+=("1")
      ARCH_KINDS+=("item")
    done < <(split_pkg_words "$packages")
  done < <(printf '%s\n' "${PKG_GROUPS[@]}")
}

build_aur_picker_arrays() {
  AUR_LABELS=()
  AUR_VALUES=()
  AUR_SELECTED_FLAGS=()
  AUR_KINDS=()
  local pkg

  for pkg in "${OPTIONAL_AUR_PACKAGES[@]}"; do
    AUR_LABELS+=("${pkg}    ${COLOR_DIM}(optional)${COLOR_RESET}")
    AUR_VALUES+=("${pkg}")
    AUR_SELECTED_FLAGS+=("0")
    AUR_KINDS+=("item")
  done

  for pkg in "${PACKAGES_AUR[@]}"; do
    AUR_LABELS+=("${pkg}")
    AUR_VALUES+=("${pkg}")
    AUR_SELECTED_FLAGS+=("1")
    AUR_KINDS+=("item")
  done
}

build_flatpak_picker_arrays() {
  FLATPAK_LABELS=()
  FLATPAK_VALUES=()
  FLATPAK_SELECTED_FLAGS=()
  FLATPAK_KINDS=()
  local entry selected friendly appid
  for entry in "${FLATPAK_CATALOG[@]}"; do
    IFS='|' read -r selected friendly appid <<< "$entry"
    FLATPAK_LABELS+=("${friendly}    ${COLOR_DIM}${appid}${COLOR_RESET}")
    FLATPAK_VALUES+=("${friendly}|${appid}")
    FLATPAK_SELECTED_FLAGS+=("${selected}")
    FLATPAK_KINDS+=("item")
  done
}

sync_virt_manager_bundle_selection() {
  local trigger="$1" selected_value="$2" values_name="$3" selected_name="$4"
  [[ "$trigger" == virt-manager ]] || return 0

  local -n _values_ref="$values_name"
  local -n _selected_ref="$selected_name"
  local pkg i
  for pkg in "${VIRT_MANAGER_PACKAGES[@]}"; do
    for i in "${!_values_ref[@]}"; do
      if [[ "${_values_ref[i]}" == "$pkg" ]]; then
        _selected_ref[i]="$selected_value"
        break
      fi
    done
  done
}

group_item_bounds() {
  local group_index="$1"
  local -n _kinds_ref="$2"
  local -n _start_ref="$3"
  local -n _end_ref="$4"

  _start_ref=$((group_index + 1))
  _end_ref="${#_kinds_ref[@]}"

  local i
  for (( i = group_index + 1; i < ${#_kinds_ref[@]}; i++ )); do
    if [[ "${_kinds_ref[i]}" == "group" ]]; then
      _end_ref="$i"
      return 0
    fi
  done
}

group_selected_count() {
  local group_index="$1"
  local -n _selected_ref="$2"
  local -n _kinds_ref="$3"
  local start=0 end=0 i total=0 selected=0

  # Pass the caller-visible array name into group_item_bounds.
  # Passing _kinds_ref here makes group_item_bounds create a nameref to its own
  # local nameref name, which triggers Bash circular-name-reference errors.
  group_item_bounds "$group_index" "$3" start end
  for (( i = start; i < end; i++ )); do
    [[ "${_kinds_ref[i]}" == "item" ]] || continue
    ((total++)) || true
    if [[ "${_selected_ref[i]}" == "1" ]]; then
      ((selected++)) || true
    fi
  done

  printf '%s/%s' "$selected" "$total"
}

group_is_fully_selected() {
  local group_index="$1"
  local selected_name="$2"
  local kinds_name="$3"
  # shellcheck disable=SC2178
  local -n _selected_ref="$selected_name"
  local -n _kinds_ref="$kinds_name"
  local start=0 end=0 i total=0 selected=0

  group_item_bounds "$group_index" "$kinds_name" start end
  for (( i = start; i < end; i++ )); do
    [[ "${_kinds_ref[i]}" == "item" ]] || continue
    ((total++)) || true
    if [[ "${_selected_ref[i]}" == "1" ]]; then
      ((selected++)) || true
    fi
  done

  (( total > 0 && selected == total ))
}

group_set_selection() {
  local group_index="$1"
  local selected_value="$2"
  local selected_name="$3"
  local kinds_name="$4"
  # shellcheck disable=SC2178
  local -n _selected_ref="$selected_name"
  local -n _kinds_ref="$kinds_name"
  local start=0 end=0 i

  group_item_bounds "$group_index" "$kinds_name" start end
  for (( i = start; i < end; i++ )); do
    if [[ "${_kinds_ref[i]}" == "item" ]]; then
      _selected_ref[i]="$selected_value"
    fi
  done
}

edit_package_group() {
  local title="$1" group_index="$2"
  local labels_name="$3" values_name="$4" selected_name="$5" kinds_name="$6"
  local -n labels_ref="$labels_name"
  # shellcheck disable=SC2178
  local -n values_ref="$values_name"
  # shellcheck disable=SC2178
  local -n selected_ref="$selected_name"
  local -n kinds_ref="$kinds_name"

  local start=0 end=0 index=0 filter="" key i shown_pos
  group_item_bounds "$group_index" "$kinds_name" start end

  while true; do
    local -a view_indices=()
    view_indices+=("-100")
    view_indices+=("-104")
    view_indices+=("-201")
    view_indices+=("-202")
    view_indices+=("-101")
    view_indices+=("-103")

    for (( i = start; i < end; i++ )); do
      [[ "${kinds_ref[i]}" == "item" ]] || continue
      if [[ -n "$filter" ]]; then
        local raw_label="${labels_ref[i]//$COLOR_DIM/}"
        raw_label="${raw_label//$COLOR_RESET/}"
        [[ "${raw_label,,}" == *"${filter,,}"* || "${values_ref[i],,}" == *"${filter,,}"* ]] || continue
      fi
      view_indices+=("$i")
    done

    (( index < 0 )) && index=0
    (( index >= ${#view_indices[@]} )) && index=$((${#view_indices[@]} - 1))

    local term_lines page_size total page_start end_pos count_text
    term_lines="$(tput lines 2>/dev/null || printf '30')"
    [[ "$term_lines" =~ ^[0-9]+$ ]] || term_lines=30
    page_size=$((term_lines - 9))
    (( page_size < 10 )) && page_size=10
    total="${#view_indices[@]}"
    page_start=$((index - page_size / 2))
    (( page_start < 0 )) && page_start=0
    if (( page_start + page_size > total )); then
      page_start=$((total - page_size))
      (( page_start < 0 )) && page_start=0
    fi
    end_pos=$((page_start + page_size))
    (( end_pos > total )) && end_pos=$total
    count_text="$(group_selected_count "$group_index" "$selected_name" "$kinds_name")"

    clear_screen
    printf '%s\n' "${COLOR_CYAN}${title}: ${labels_ref[group_index]}${COLOR_RESET}"
    printf '%s\n' "Selected: ${count_text}"
    [[ -n "$filter" ]] && printf '%s\n' "Filter: ${filter}"
    printf '%s\n\n' "Showing $((page_start + 1))-${end_pos} of ${total}"

    shown_pos="$page_start"
    while (( shown_pos < end_pos )); do
      i="${view_indices[shown_pos]}"
      local prefix="   "
      (( shown_pos == index )) && prefix="  >"
      case "$i" in
        -100) printf '%s [✓] Done editing category\n' "$prefix" ;;
        -104) printf '%s [<] Back to full list\n' "$prefix" ;;
        -201) printf '%s [✓] Select all in this category\n' "$prefix" ;;
        -202) printf '%s [ ] Clear all in this category\n' "$prefix" ;;
        -101) printf '%s [?] Search/filter category\n' "$prefix" ;;
        -103) printf '%s [x] Clear search/filter\n' "$prefix" ;;
        *)
          local mark='[ ]'
          [[ "${selected_ref[i]}" == "1" ]] && mark='[✓]'
          printf '%s %s %s\n' "$prefix" "$mark" "${labels_ref[i]}"
          ;;
      esac
      ((shown_pos++)) || true
    done

    printf '\n%s\n' "${COLOR_DIM}Space/Enter = activate/toggle, b = back, Up/Down = move${COLOR_RESET}"
    key="$(read_key || true)"
    case "$key" in
      $'\033[A')
        if (( index > 0 )); then
          ((index--)) || true
        fi
        ;;
      $'\033[B')
        if (( index + 1 < ${#view_indices[@]} )); then
          ((index++)) || true
        fi
        ;;
      b|B)
        return 0
        ;;
      ' '|$'\n'|$'\r'|"")
        local selected_index="${view_indices[index]}"
        case "$selected_index" in
          -100|-104)
            return 0
            ;;
          -201)
            for (( i = start; i < end; i++ )); do
              [[ "${kinds_ref[i]}" == "item" ]] && selected_ref[i]=1
            done
            ;;
          -202)
            for (( i = start; i < end; i++ )); do
              [[ "${kinds_ref[i]}" == "item" ]] && selected_ref[i]=0
            done
            ;;
          -101)
            clear_screen
            filter="$(prompt_line "Search/filter category: ")"
            index=0
            ;;
          -103)
            filter=""
            index=0
            ;;
          *)
            if [[ "${selected_ref[selected_index]}" == "1" ]]; then
              selected_ref[selected_index]=0
            else
              selected_ref[selected_index]=1
            fi
            ;;
        esac
        ;;
    esac
  done
}


flatpak_picker_has_app() {
  local appid="$1" values_name="$2" selected_name="$3"
  # shellcheck disable=SC2178
  local -n _values_ref="$values_name"
  # shellcheck disable=SC2178
  local -n _selected_ref="$selected_name"
  local i existing_appid

  for i in "${!_values_ref[@]}"; do
    existing_appid="${_values_ref[i]#*|}"
    if [[ "$existing_appid" == "$appid" ]]; then
      _selected_ref[i]=1
      return 0
    fi
  done

  return 1
}

flatpak_picker_add_app() {
  local name="$1" appid="$2" labels_name="$3" values_name="$4" selected_name="$5" kinds_name="$6"
  # shellcheck disable=SC2178
  local -n _labels_ref="$labels_name"
  # shellcheck disable=SC2178
  local -n _values_ref="$values_name"
  # shellcheck disable=SC2178
  local -n _selected_ref="$selected_name"
  # shellcheck disable=SC2178
  local -n _kinds_ref="$kinds_name"

  [[ -n "$appid" ]] || return 1
  [[ -n "$name" ]] || name="$appid"

  if flatpak_picker_has_app "$appid" "$values_name" "$selected_name"; then
    return 0
  fi

  _labels_ref+=("${name}    ${COLOR_DIM}${appid}${COLOR_RESET}")
  _values_ref+=("${name}|${appid}")
  _selected_ref+=("1")
  _kinds_ref+=("item")
}

api_search_tool_ready() {
  have python3 || have python || have curl
}

api_search_python_ready() {
  have python3 || have python
}

ensure_api_search_tool() {
  local purpose="${1:-search}"

  if api_search_tool_ready; then
    return 0
  fi

  if (( DRY_RUN == 1 )); then
    return 1
  fi

  if [[ "${EUID}" -ne 0 ]]; then
    return 1
  fi

  clear_screen
  printf '%s\n\n' "${COLOR_CYAN}Installing ${purpose} helper dependency...${COLOR_RESET}" >/dev/tty
  printf '%s\n' "Awtarchy needs python or curl to search online package indexes before the main install starts." >/dev/tty
  printf '%s\n\n' "Installing python, curl, and ca-certificates now." >/dev/tty

  pacman -S --needed --noconfirm python curl ca-certificates >/dev/tty
  api_search_tool_ready
}

ensure_python_api_search_tool() {
  local purpose="${1:-search}"

  if api_search_python_ready; then
    return 0
  fi

  if (( DRY_RUN == 1 )); then
    return 1
  fi

  if [[ "${EUID}" -ne 0 ]]; then
    return 1
  fi

  clear_screen
  printf '%s\n\n' "${COLOR_CYAN}Installing ${purpose} helper dependency...${COLOR_RESET}" >/dev/tty
  printf '%s\n' "Awtarchy needs python to query and parse online package indexes reliably." >/dev/tty
  printf '%s\n\n' "Installing python and ca-certificates now." >/dev/tty

  pacman -S --needed --noconfirm python ca-certificates >/dev/tty
  api_search_python_ready
}

ensure_aur_search_tool() {
  ensure_python_api_search_tool "AUR search"
}

ensure_flatpak_search_tool() {
  if have flatpak || api_search_tool_ready; then
    return 0
  fi
  ensure_api_search_tool "Flatpak search"
}

show_search_tool_missing() {
  local purpose="$1"
  clear_screen
  printf '%s\n\n' "${COLOR_YELLOW}${purpose} is unavailable.${COLOR_RESET}" >/dev/tty
  if (( DRY_RUN == 1 )); then
    printf '%s\n' "Dry-run mode does not install helper dependencies." >/dev/tty
    printf '%s\n' "Install python or curl first, or test this path during a live sudo install." >/dev/tty
  elif [[ "${EUID}" -ne 0 ]]; then
    printf '%s\n' "Run the installer with sudo so it can install python/curl for package search." >/dev/tty
  else
    printf '%s\n' "Could not install or find python/curl for package search." >/dev/tty
  fi
  printf '\n' >/dev/tty
  press_any_key
}

arch_repo_package_exists() {
  local pkg="$1"
  [[ -n "$pkg" ]] || return 1
  pacman -Si "$pkg" >/dev/null 2>&1
}

arch_picker_has_pkg() {
  local pkg="$1" values_name="$2" selected_name="$3"
  # shellcheck disable=SC2178
  local -n _values_ref="$values_name"
  # shellcheck disable=SC2178
  local -n _selected_ref="$selected_name"
  local i

  for i in "${!_values_ref[@]}"; do
    if [[ "${_values_ref[i]}" == "$pkg" ]]; then
      _selected_ref[i]=1
      return 0
    fi
  done

  return 1
}

arch_picker_add_pkg() {
  local pkg="$1" labels_name="$2" values_name="$3" selected_name="$4" kinds_name="$5"
  # shellcheck disable=SC2178
  local -n _labels_ref="$labels_name"
  # shellcheck disable=SC2178
  local -n _values_ref="$values_name"
  # shellcheck disable=SC2178
  local -n _selected_ref="$selected_name"
  # shellcheck disable=SC2178
  local -n _kinds_ref="$kinds_name"

  [[ -n "$pkg" ]] || return 1

  if arch_picker_has_pkg "$pkg" "$values_name" "$selected_name"; then
    return 0
  fi

  _labels_ref+=("${pkg}")
  _values_ref+=("${pkg}")
  _selected_ref+=("1")
  _kinds_ref+=("item")
}

arch_search_append_result() {
  local pkg="$1" repo="$2" version="$3" description="$4" labels_name="$5" names_name="$6"
  # shellcheck disable=SC2178
  local -n _result_labels="$labels_name"
  # shellcheck disable=SC2178
  local -n _result_names="$names_name"
  local existing label

  [[ -n "$pkg" ]] || return 1
  for existing in "${_result_names[@]}"; do
    [[ "$existing" == "$pkg" ]] && return 0
  done

  label="$pkg"
  if [[ -n "$repo" || -n "$version" || -n "$description" ]]; then
    label+="    ${COLOR_DIM}"
    [[ -n "$repo" ]] && label+="${repo}"
    [[ -n "$version" ]] && label+=" ${version}"
    [[ -n "$description" ]] && label+=" - ${description}"
    label+="${COLOR_RESET}"
  fi

  _result_labels+=("$label")
  _result_names+=("$pkg")
}

arch_search_results() {
  local query="$1" labels_name="$2" names_name="$3"
  # shellcheck disable=SC2178
  local -n _result_labels="$labels_name"
  # shellcheck disable=SC2178
  local -n _result_names="$names_name"
  local pkg repo version description

  _result_labels=()
  _result_names=()

  [[ -n "$query" ]] || return 1

  # Prefer local pacman metadata on Arch systems.
  if have pacman; then
    while IFS=$'\t' read -r pkg repo version description _; do
      pkg="${pkg//$'\r'/}"
      repo="${repo//$'\r'/}"
      version="${version//$'\r'/}"
      description="${description//$'\r'/}"
      arch_search_append_result "$pkg" "$repo" "$version" "$description" "$labels_name" "$names_name"
    done < <(pacman -Si "$query" 2>/dev/null | awk -F ': *' '
      /^Repository/{repo=$2}
      /^Name/{name=$2}
      /^Version/{version=$2}
      /^Description/{desc=$2}
      END{if(name != "") print name "\t" repo "\t" version "\t" desc}
    ')

    while IFS=$'\t' read -r pkg repo version description _; do
      pkg="${pkg//$'\r'/}"
      repo="${repo//$'\r'/}"
      version="${version//$'\r'/}"
      description="${description//$'\r'/}"
      arch_search_append_result "$pkg" "$repo" "$version" "$description" "$labels_name" "$names_name"
      (( ${#_result_names[@]} >= 25 )) && break
    done < <(pacman -Ss "$query" 2>/dev/null | awk '
      /^[^[:space:]][^\/]+\/[^[:space:]]+/ {
        if (name != "") print name "\t" repo "\t" version "\t" desc
        split($1, parts, "/")
        repo=parts[1]
        name=parts[2]
        version=$2
        desc=""
        next
      }
      /^[[:space:]]/ {
        sub(/^[[:space:]]+/, "")
        desc=$0
        if (name != "") {
          print name "\t" repo "\t" version "\t" desc
          name=""; repo=""; version=""; desc=""
        }
      }
      END{if(name != "") print name "\t" repo "\t" version "\t" desc}
    ')
  fi

  # Fallback to Arch's package search JSON endpoint when pacman metadata is absent or stale.
  if (( ${#_result_names[@]} == 0 )) && api_search_tool_ready; then
    if have python3 || have python; then
      local pybin="python3"
      have python3 || pybin="python"
      while IFS=$'\t' read -r pkg repo version description _; do
        pkg="${pkg//$'\r'/}"
        repo="${repo//$'\r'/}"
        version="${version//$'\r'/}"
        description="${description//$'\r'/}"
        arch_search_append_result "$pkg" "$repo" "$version" "$description" "$labels_name" "$names_name"
      done < <("$pybin" - "$query" <<'PYARCH'
import json
import sys
import urllib.parse
import urllib.request

query = sys.argv[1]
urls = [
    "https://archlinux.org/packages/search/json/?" + urllib.parse.urlencode({"name": query}),
    "https://archlinux.org/packages/search/json/?" + urllib.parse.urlencode({"q": query}),
]
seen = set()
count = 0
for url in urls:
    request = urllib.request.Request(url, headers={"User-Agent": "awtarchy-installer"})
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            data = json.load(response)
    except Exception:
        continue
    rows = data.get("results", []) if isinstance(data, dict) else []
    for row in rows:
        if not isinstance(row, dict):
            continue
        name = row.get("pkgname") or row.get("name") or ""
        if not name or name in seen:
            continue
        seen.add(name)
        repo = row.get("repo") or row.get("repo_name") or ""
        version = row.get("pkgver") or row.get("version") or ""
        rel = row.get("pkgrel") or ""
        if version and rel:
            version = f"{version}-{rel}"
        desc = row.get("pkgdesc") or row.get("description") or ""
        print(f"{name}\t{repo}\t{version}\t{desc}")
        count += 1
        if count >= 25:
            raise SystemExit(0)
PYARCH
)
    elif have curl; then
      while IFS=$'\t' read -r pkg repo version description _; do
        pkg="${pkg//$'\r'/}"
        repo="${repo//$'\r'/}"
        version="${version//$'\r'/}"
        description="${description//$'\r'/}"
        arch_search_append_result "$pkg" "$repo" "$version" "$description" "$labels_name" "$names_name"
      done < <(
        curl -fsSL --max-time 10 --get --data-urlencode "q=${query}" 'https://archlinux.org/packages/search/json/' 2>/dev/null \
        | tr '{' '\n' \
        | sed -nE 's/.*"pkgname"[[:space:]]*:[[:space:]]*"([^"]+)".*"repo"[[:space:]]*:[[:space:]]*"([^"]+)".*"pkgver"[[:space:]]*:[[:space:]]*"([^"]+)".*"pkgdesc"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1\t\2\t\3\t\4/p' \
        | awk -F '\t' '$1 != "" && !seen[$1]++ {print}' \
        | head -25
      )
    fi
  fi

  (( ${#_result_names[@]} > 0 ))
}

arch_search_add_menu() {
  local labels_name="$1" values_name="$2" selected_name="$3" kinds_name="$4"
  local query choice i
  local -a result_labels=()
  local -a result_names=()
  local -a menu_items=()

  while true; do
    clear_screen
    query="$(prompt_line "Search Arch repo package name: ")"
    [[ -z "$query" ]] && return 1

    if ! arch_search_results "$query" result_labels result_names; then
      if ! have pacman && ! ensure_api_search_tool "Arch repo search"; then
        show_search_tool_missing "Arch repo search"
        continue
      fi
      arch_search_results "$query" result_labels result_names || true
    fi

    if (( ${#result_names[@]} == 0 )); then
      clear_screen
      printf '%s\n\n' "${COLOR_YELLOW}No Arch repo search results found.${COLOR_RESET}" >/dev/tty
      printf '%s\n' "Try a different package name. Arch repo packages must exist in enabled pacman repositories or Arch package search." >/dev/tty
      printf '\n' >/dev/tty
      press_any_key
      continue
    fi

    menu_items=()
    for i in "${!result_labels[@]}"; do
      menu_items+=("${result_labels[i]}")
    done
    menu_items+=("Search again")
    menu_items+=("Back")

    choice="$(single_select_menu "Arch repo search: ${query}" 0 "${menu_items[@]}")" || continue
    if (( choice < ${#result_names[@]} )); then
      arch_picker_add_pkg "${result_names[choice]}" "$labels_name" "$values_name" "$selected_name" "$kinds_name"
      return 0
    fi

    if (( choice == ${#result_names[@]} )); then
      continue
    fi
    return 1
  done
}

flatpak_search_results() {
  local query="$1" labels_name="$2" names_name="$3" ids_name="$4"
  # shellcheck disable=SC2178
  local -n _result_labels="$labels_name"
  # shellcheck disable=SC2178
  local -n _result_names="$names_name"
  # shellcheck disable=SC2178
  local -n _result_ids="$ids_name"
  local appid name description line_count=0

  _result_labels=()
  _result_names=()
  _result_ids=()

  [[ -n "$query" ]] || return 1

  # Prefer local Flatpak metadata when available.
  if have flatpak; then
    while IFS=$'\t' read -r appid name description _; do
      appid="${appid//$'\r'/}"
      name="${name//$'\r'/}"
      description="${description//$'\r'/}"

      [[ -n "$appid" ]] || continue
      [[ "$appid" == "Application ID" || "$appid" == "Application" ]] && continue
      [[ "$appid" == *.* ]] || continue
      [[ -n "$name" ]] || name="$appid"

      if [[ -n "$description" ]]; then
        _result_labels+=("${name}    ${COLOR_DIM}${appid} - ${description}${COLOR_RESET}")
      else
        _result_labels+=("${name}    ${COLOR_DIM}${appid}${COLOR_RESET}")
      fi
      _result_names+=("$name")
      _result_ids+=("$appid")

      ((line_count++)) || true
      (( line_count >= 25 )) && break
    done < <(flatpak search --columns=application,name,description "$query" 2>/dev/null || true)
  fi

  # Fresh installs may not have flatpak yet. Use Flathub's API directly.
  if (( ${#_result_ids[@]} == 0 )) && { have python3 || have python; }; then
    local pybin="python3"
    have python3 || pybin="python"
    while IFS=$'\t' read -r appid name description _; do
      appid="${appid//$'\r'/}"
      name="${name//$'\r'/}"
      description="${description//$'\r'/}"

      [[ -n "$appid" ]] || continue
      [[ "$appid" == *.* ]] || continue
      [[ -n "$name" ]] || name="$appid"

      if [[ -n "$description" ]]; then
        _result_labels+=("${name}    ${COLOR_DIM}${appid} - ${description}${COLOR_RESET}")
      else
        _result_labels+=("${name}    ${COLOR_DIM}${appid}${COLOR_RESET}")
      fi
      _result_names+=("$name")
      _result_ids+=("$appid")
    done < <("$pybin" - "$query" <<'PYFLATHUB'
import json
import sys
import urllib.request

query = sys.argv[1]
payload = json.dumps({"query": query, "filters": []}).encode("utf-8")
request = urllib.request.Request(
    "https://flathub.org/api/v2/search",
    data=payload,
    headers={
        "Content-Type": "application/json",
        "User-Agent": "awtarchy-installer",
    },
    method="POST",
)

try:
    with urllib.request.urlopen(request, timeout=8) as response:
        data = json.load(response)
except Exception:
    sys.exit(0)

if isinstance(data, list):
    rows = data
elif isinstance(data, dict):
    rows = data.get("hits") or data.get("results") or data.get("apps") or data.get("data") or []
else:
    rows = []

count = 0
for row in rows:
    if not isinstance(row, dict):
        continue
    appid = row.get("flatpakAppId") or row.get("id") or row.get("app_id") or row.get("appId") or row.get("application")
    name = row.get("name") or row.get("title") or appid
    description = row.get("summary") or row.get("description") or row.get("developerName") or ""
    if not appid or "." not in appid:
        continue
    print(f"{appid}\t{name}\t{description}")
    count += 1
    if count >= 25:
        break
PYFLATHUB
)
  fi

  if (( ${#_result_ids[@]} == 0 )) && have curl; then
    local escaped_query
    escaped_query="${query//\\/\\\\}"
    escaped_query="${escaped_query//\"/\\\"}"
    while IFS=$'\t' read -r appid name description _; do
      appid="${appid//$'\r'/}"
      name="${name//$'\r'/}"
      description="${description//$'\r'/}"

      [[ -n "$appid" ]] || continue
      [[ "$appid" == *.* ]] || continue
      [[ -n "$name" ]] || name="$appid"

      if [[ -n "$description" ]]; then
        _result_labels+=("${name}    ${COLOR_DIM}${appid} - ${description}${COLOR_RESET}")
      else
        _result_labels+=("${name}    ${COLOR_DIM}${appid}${COLOR_RESET}")
      fi
      _result_names+=("$name")
      _result_ids+=("$appid")
    done < <(
      curl -fsSL --max-time 10 \
        -X POST 'https://flathub.org/api/v2/search' \
        -H 'Content-Type: application/json' \
        -H 'User-Agent: awtarchy-installer' \
        --data-raw "{\"query\":\"${escaped_query}\",\"filters\":[]}" 2>/dev/null \
      | tr '{' '\n' \
      | sed -nE '
          s/.*"(flatpakAppId|id|app_id|appId|application)"[[:space:]]*:[[:space:]]*"([^"]+)".*"(name|title)"[[:space:]]*:[[:space:]]*"([^"]*)".*/\2\t\4\t/p
          s/.*"(name|title)"[[:space:]]*:[[:space:]]*"([^"]*)".*"(flatpakAppId|id|app_id|appId|application)"[[:space:]]*:[[:space:]]*"([^"]+)".*/\4\t\2\t/p
        ' \
      | awk -F '\t' '$1 ~ /\./ && !seen[$1]++ {print}' \
      | head -25
    )
  fi

  (( ${#_result_ids[@]} > 0 ))
}

flatpak_app_lookup_name() {
  local appid="$1" out_name_ref="$2"
  # shellcheck disable=SC2178
  local -n _out_name_ref="$out_name_ref"
  local -a result_labels=()
  local -a result_names=()
  local -a result_ids=()
  local i

  _out_name_ref=""
  [[ -n "$appid" && "$appid" == *.* ]] || return 1

  if ! ensure_flatpak_search_tool; then
    return 2
  fi

  flatpak_search_results "$appid" result_labels result_names result_ids || return 1
  for i in "${!result_ids[@]}"; do
    if [[ "${result_ids[i]}" == "$appid" ]]; then
      _out_name_ref="${result_names[i]}"
      [[ -n "$_out_name_ref" ]] || _out_name_ref="$appid"
      return 0
    fi
  done

  return 1
}

flatpak_manual_add_app() {
  local labels_name="$1" values_name="$2" selected_name="$3" kinds_name="$4"
  local appid name lookup_name rc

  clear_screen
  appid="$(prompt_line "Enter full Flathub app ID, example com.github.tchx84.Flatseal: ")"
  [[ -z "$appid" ]] && return 1

  lookup_name=""
  if flatpak_app_lookup_name "$appid" lookup_name; then
    name="$lookup_name"
  else
    rc=$?
    if (( rc == 2 )); then
      show_search_tool_missing "Flatpak app validation"
    else
      clear_screen
      printf '%s\n\n' "${COLOR_YELLOW}Flathub app ID not found: ${appid}${COLOR_RESET}" >/dev/tty
      printf '%s\n' "Manual Flatpak entries must be confirmed against Flathub before being added." >/dev/tty
      printf '%s\n' "Use Search Flathub by app name if you are not sure of the exact app ID." >/dev/tty
      printf '\n' >/dev/tty
      press_any_key
    fi
    return 1
  fi

  flatpak_picker_add_app "$name" "$appid" "$labels_name" "$values_name" "$selected_name" "$kinds_name"
}

flatpak_search_add_menu() {
  local labels_name="$1" values_name="$2" selected_name="$3" kinds_name="$4"
  local query choice i
  local -a result_labels=()
  local -a result_names=()
  local -a result_ids=()
  local -a menu_items=()

  while true; do
    clear_screen
    query="$(prompt_line "Search Flathub app name or app ID: ")"
    [[ -z "$query" ]] && return 1

    if ! ensure_flatpak_search_tool; then
      show_search_tool_missing "Flatpak search"
      continue
    fi

    if ! flatpak_search_results "$query" result_labels result_names result_ids; then
      clear_screen
      printf '%s\n\n' "${COLOR_YELLOW}No Flatpak search results found.${COLOR_RESET}" >/dev/tty
      printf '%s\n' "Try a different app name or app ID. Flatpak apps must be selected from confirmed Flathub results." >/dev/tty
      printf '\n' >/dev/tty
      press_any_key
      continue
    fi

    menu_items=()
    for i in "${!result_labels[@]}"; do
      menu_items+=("${result_labels[i]}")
    done
    menu_items+=("Search again")
    menu_items+=("Back")

    choice="$(single_select_menu "Flathub search: ${query}" 0 "${menu_items[@]}")" || continue
    if (( choice < ${#result_ids[@]} )); then
      flatpak_picker_add_app "${result_names[choice]}" "${result_ids[choice]}" "$labels_name" "$values_name" "$selected_name" "$kinds_name"
      return 0
    fi

    if (( choice == ${#result_ids[@]} )); then
      continue
    fi
    return 1
  done
}

aur_picker_has_pkg() {
  local pkg="$1" values_name="$2" selected_name="$3"
  # shellcheck disable=SC2178
  local -n _values_ref="$values_name"
  # shellcheck disable=SC2178
  local -n _selected_ref="$selected_name"
  local i

  for i in "${!_values_ref[@]}"; do
    if [[ "${_values_ref[i]}" == "$pkg" ]]; then
      _selected_ref[i]=1
      return 0
    fi
  done

  return 1
}

aur_picker_add_pkg() {
  local pkg="$1" labels_name="$2" values_name="$3" selected_name="$4" kinds_name="$5"
  # shellcheck disable=SC2178
  local -n _labels_ref="$labels_name"
  # shellcheck disable=SC2178
  local -n _values_ref="$values_name"
  # shellcheck disable=SC2178
  local -n _selected_ref="$selected_name"
  # shellcheck disable=SC2178
  local -n _kinds_ref="$kinds_name"

  [[ -n "$pkg" ]] || return 1

  if aur_picker_has_pkg "$pkg" "$values_name" "$selected_name"; then
    return 0
  fi

  _labels_ref+=("$pkg")
  _values_ref+=("$pkg")
  _selected_ref+=("1")
  _kinds_ref+=("item")
}

aur_search_append_result() {
  local pkg="$1" description="$2" votes="$3" popularity="$4" labels_name="$5" names_name="$6"
  # shellcheck disable=SC2178
  local -n _result_labels="$labels_name"
  # shellcheck disable=SC2178
  local -n _result_names="$names_name"
  local existing

  [[ -n "$pkg" ]] || return 1
  for existing in "${_result_names[@]}"; do
    [[ "$existing" == "$pkg" ]] && return 0
  done

  if [[ -n "$description" ]]; then
    _result_labels+=("${pkg}    ${COLOR_DIM}${description} | votes: ${votes:-0} | pop: ${popularity:-0}${COLOR_RESET}")
  else
    _result_labels+=("${pkg}    ${COLOR_DIM}votes: ${votes:-0} | pop: ${popularity:-0}${COLOR_RESET}")
  fi
  _result_names+=("$pkg")
}

aur_search_results() {
  local query="$1" labels_name="$2" names_name="$3"
  # shellcheck disable=SC2178
  local -n _result_labels="$labels_name"
  # shellcheck disable=SC2178
  local -n _result_names="$names_name"
  local pkg description votes popularity

  _result_labels=()
  _result_names=()

  [[ -n "$query" ]] || return 1

  # Query the AUR RPC directly. Exact package info is checked first so exact
  # packages still show up even when the broader search endpoint misses them.
  if have python3 || have python; then
    local pybin="python3"
    have python3 || pybin="python"
    while IFS=$'\t' read -r pkg description votes popularity _; do
      pkg="${pkg//$'\r'/}"
      description="${description//$'\r'/}"
      votes="${votes//$'\r'/}"
      popularity="${popularity//$'\r'/}"
      aur_search_append_result "$pkg" "$description" "$votes" "$popularity" "$labels_name" "$names_name"
    done < <("$pybin" - "$query" <<'PYAUR'
import json
import sys
import urllib.parse
import urllib.request

query = sys.argv[1]
seen = set()

def fetch_url(url):
    request = urllib.request.Request(url, headers={"User-Agent": "awtarchy-installer"})
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            data = json.load(response)
    except Exception:
        return []
    return data.get("results", []) if isinstance(data, dict) else []

base = "https://aur.archlinux.org/rpc/v5"
rows = []
# Exact lookup first.
rows.extend(fetch_url(base + "/info?" + urllib.parse.urlencode({"arg[]": [query]}, doseq=True)))
# Then normal name/description search for close matches.
rows.extend(fetch_url(base + "/search/" + urllib.parse.quote(query, safe="") + "?by=name-desc"))

count = 0
for row in rows:
    if not isinstance(row, dict):
        continue
    name = row.get("Name") or ""
    if not name or name in seen:
        continue
    seen.add(name)
    desc = row.get("Description") or ""
    votes = row.get("NumVotes") or 0
    pop = row.get("Popularity") or 0
    print(f"{name}\t{desc}\t{votes}\t{pop}")
    count += 1
    if count >= 25:
        break
PYAUR
)
  fi

  (( ${#_result_names[@]} > 0 ))
}

aur_package_exists() {
  local pkg="$1"
  [[ -n "$pkg" ]] || return 1

  if ! ensure_aur_search_tool; then
    return 2
  fi

  if have python3 || have python; then
    local pybin="python3"
    have python3 || pybin="python"
    "$pybin" - "$pkg" <<'PYAURINFO'
import json
import sys
import urllib.parse
import urllib.request

pkg = sys.argv[1]
url = "https://aur.archlinux.org/rpc/v5/info?" + urllib.parse.urlencode({"arg[]": [pkg]}, doseq=True)
request = urllib.request.Request(url, headers={"User-Agent": "awtarchy-installer"})

try:
    with urllib.request.urlopen(request, timeout=8) as response:
        data = json.load(response)
except Exception:
    sys.exit(1)

rows = data.get("results", []) if isinstance(data, dict) else []
for row in rows:
    if isinstance(row, dict) and row.get("Name") == pkg:
        sys.exit(0)
sys.exit(1)
PYAURINFO
    return $?
  fi

  return 2
}

aur_manual_add_pkg() {
  local labels_name="$1" values_name="$2" selected_name="$3" kinds_name="$4"
  local pkg rc

  clear_screen
  pkg="$(prompt_line "Enter AUR package name: ")"
  [[ -z "$pkg" ]] && return 1

  if aur_package_exists "$pkg"; then
    aur_picker_add_pkg "$pkg" "$labels_name" "$values_name" "$selected_name" "$kinds_name"
    return 0
  fi

  rc=$?
  if (( rc == 2 )); then
    show_search_tool_missing "AUR package validation"
  else
    clear_screen
    printf '%s\n\n' "${COLOR_YELLOW}AUR package not found: ${pkg}${COLOR_RESET}" >/dev/tty
    printf '%s\n' "Manual AUR entries must be confirmed against the AUR RPC before being added." >/dev/tty
    printf '%s\n' "Use Search AUR by name/description if you are not sure of the exact package name." >/dev/tty
    printf '\n' >/dev/tty
    press_any_key
  fi

  return 1
}

aur_search_add_menu() {
  local labels_name="$1" values_name="$2" selected_name="$3" kinds_name="$4"
  local query choice i
  local -a result_labels=()
  local -a result_names=()
  local -a menu_items=()

  while true; do
    clear_screen
    query="$(prompt_line "Search AUR package name: ")"
    [[ -z "$query" ]] && return 1

    if ! ensure_aur_search_tool; then
      show_search_tool_missing "AUR search"
      continue
    fi

    if ! aur_search_results "$query" result_labels result_names; then
      clear_screen
      printf '%s\n\n' "${COLOR_YELLOW}No AUR search results found.${COLOR_RESET}" >/dev/tty
      printf '%s\n' "Try a different package name. AUR packages must be selected from confirmed AUR RPC results." >/dev/tty
      printf '\n' >/dev/tty
      press_any_key
      continue
    fi

    menu_items=()
    for i in "${!result_labels[@]}"; do
      menu_items+=("${result_labels[i]}")
    done
    menu_items+=("Search again")
    menu_items+=("Back")

    choice="$(single_select_menu "AUR search: ${query}" 0 "${menu_items[@]}")" || continue
    if (( choice < ${#result_names[@]} )); then
      aur_picker_add_pkg "${result_names[choice]}" "$labels_name" "$values_name" "$selected_name" "$kinds_name"
      return 0
    fi

    if (( choice == ${#result_names[@]} )); then
      continue
    fi
    return 1
  done
}


add_custom_picker_item() {
  local type="$1" labels_name="$2" values_name="$3" selected_name="$4" kinds_name="$5"
  # shellcheck disable=SC2178
  local -n _labels_ref="$labels_name"
  # shellcheck disable=SC2178
  local -n _values_ref="$values_name"
  # shellcheck disable=SC2178
  local -n _selected_ref="$selected_name"
  # shellcheck disable=SC2178
  local -n _kinds_ref="$kinds_name"
  local custom

  if [[ "$type" == "Flatpak app ID" ]]; then
    flatpak_search_add_menu "$labels_name" "$values_name" "$selected_name" "$kinds_name"
    return $?
  fi

  if [[ "$type" == "AUR package" ]]; then
    aur_search_add_menu "$labels_name" "$values_name" "$selected_name" "$kinds_name"
    return $?
  fi

  if [[ "$type" == "Arch package" ]]; then
    arch_search_add_menu "$labels_name" "$values_name" "$selected_name" "$kinds_name"
    return $?
  fi

  clear_screen
  custom="$(prompt_line "Enter ${type}: ")"
  [[ -z "$custom" ]] && return 1
  _labels_ref+=("${custom}")
  _values_ref+=("${custom}")
  _selected_ref+=("1")
  _kinds_ref+=("item")
}


package_picker() {
  local title="$1" type="$2"
  local labels_name="$3" values_name="$4" selected_name="$5" kinds_name="$6"
  local -n labels_ref="$labels_name"
  # shellcheck disable=SC2178
  local -n values_ref="$values_name"
  # shellcheck disable=SC2178
  local -n selected_ref="$selected_name"
  local -n kinds_ref="$kinds_name"
  local index=0 filter="" key i shown_pos

  while true; do
    local -a view_indices=()
    view_indices+=("-100")
    view_indices+=("-104")
    view_indices+=("-201")
    view_indices+=("-202")
    view_indices+=("-101")
    view_indices+=("-102")
    view_indices+=("-103")

    for i in "${!labels_ref[@]}"; do
      # Keep the Arch package overview fast: show category rows only.
      # Individual default packages are edited inside a category screen.
      if [[ "$type" == "Arch package" && "${kinds_ref[$i]}" == "item" && "${labels_ref[$i]}" == "  "* ]]; then
        continue
      fi
      if [[ -n "$filter" ]]; then
        local raw_label="${labels_ref[$i]//$COLOR_DIM/}"
        raw_label="${raw_label//$COLOR_RESET/}"
        [[ "${raw_label,,}" == *"${filter,,}"* || "${values_ref[$i],,}" == *"${filter,,}"* ]] || continue
      fi
      view_indices+=("$i")
    done

    (( index < 0 )) && index=0
    (( index >= ${#view_indices[@]} )) && index=$((${#view_indices[@]} - 1))

    local term_lines page_size total start end_pos
    term_lines="$(tput lines 2>/dev/null || printf '30')"
    [[ "$term_lines" =~ ^[0-9]+$ ]] || term_lines=30
    page_size=$((term_lines - 8))
    (( page_size < 10 )) && page_size=10
    total="${#view_indices[@]}"
    start=$((index - page_size / 2))
    (( start < 0 )) && start=0
    if (( start + page_size > total )); then
      start=$((total - page_size))
      (( start < 0 )) && start=0
    fi
    end_pos=$((start + page_size))
    (( end_pos > total )) && end_pos=$total

    clear_screen
    printf '%s\n' "${COLOR_CYAN}${title}${COLOR_RESET}"
    [[ -n "$filter" ]] && printf '%s\n' "Filter: ${filter}"
    printf '%s\n\n' "Showing $((start + 1))-${end_pos} of ${total}"

    shown_pos="$start"
    while (( shown_pos < end_pos )); do
      i="${view_indices[$shown_pos]}"
      local prefix="   "
      (( shown_pos == index )) && prefix="  >"
      case "$i" in
        -100) printf '%s [✓] Done with this list\n' "$prefix" ;;
        -104) printf '%s [<] Back\n' "$prefix" ;;
        -201) printf '%s [✓] Select all in this list\n' "$prefix" ;;
        -202) printf '%s [ ] Clear all in this list\n' "$prefix" ;;
        -101) printf '%s [?] Search/filter list\n' "$prefix" ;;
        -102) if [[ "$type" == "Flatpak app ID" ]]; then
          printf '%s [+] Search/add Flatpak app\n' "$prefix"
        elif [[ "$type" == "AUR package" ]]; then
          printf '%s [+] Search/add AUR package\n' "$prefix"
        elif [[ "$type" == "Arch package" ]]; then
          printf '%s [+] Add verified Arch package\n' "$prefix"
        else
          printf '%s [+] Add custom %s\n' "$prefix" "$type"
        fi
        ;;
        -103) printf '%s [x] Clear search/filter\n' "$prefix" ;;
        *)
          if [[ "${kinds_ref[$i]}" == "group" ]]; then
            if [[ "$type" == "Arch package" ]]; then
              local count_text
              count_text="$(group_selected_count "$i" "$selected_name" "$kinds_name")"
              printf '%s %s%s%s %s[%s selected]%s %s(e = edit)%s\n' "$prefix" "$COLOR_MAGENTA" "${labels_ref[$i]}" "$COLOR_RESET" "$COLOR_DIM" "$count_text" "$COLOR_RESET" "$COLOR_DIM" "$COLOR_RESET"
            else
              printf '%s %s%s%s\n' "$prefix" "$COLOR_MAGENTA" "${labels_ref[$i]}" "$COLOR_RESET"
            fi
          else
            local mark='[ ]'
            [[ "${selected_ref[$i]}" == "1" ]] && mark='[✓]'
            printf '%s %s %s\n' "$prefix" "$mark" "${labels_ref[$i]}"
          fi
          ;;
      esac
      ((shown_pos++)) || true
    done

    if [[ "$type" == "Arch package" ]]; then
      printf '\n%s\n' "${COLOR_DIM}Enter/e = edit category, Space = select/clear category, b = back, Up/Down = move${COLOR_RESET}"
    elif [[ "$type" == "Flatpak app ID" ]]; then
      printf '\n%s\n' "${COLOR_DIM}Space/Enter = activate/toggle/search, b = back, Up/Down = move${COLOR_RESET}"
    else
      printf '\n%s\n' "${COLOR_DIM}Space/Enter = activate/toggle, b = back, Up/Down = move${COLOR_RESET}"
    fi
    key="$(read_key || true)"
    case "$key" in
      $'\033[A')
        if (( index > 0 )); then
          ((index--)) || true
        fi
        ;;
      $'\033[B')
        if (( index + 1 < ${#view_indices[@]} )); then
          ((index++)) || true
        fi
        ;;
      e|E)
        local selected_index="${view_indices[$index]}"
        if [[ "$selected_index" != -* && "${kinds_ref[$selected_index]}" == "group" ]]; then
          edit_package_group "$title" "$selected_index" "$labels_name" "$values_name" "$selected_name" "$kinds_name"
        fi
        ;;
      ' ')
        local selected_index="${view_indices[$index]}"
        case "$selected_index" in
          -100)
            return 0
            ;;
          -104)
            return 2
            ;;
          -201)
            for i in "${!kinds_ref[@]}"; do
              [[ "${kinds_ref[i]}" == "item" ]] && selected_ref[i]=1
            done
            ;;
          -202)
            for i in "${!kinds_ref[@]}"; do
              [[ "${kinds_ref[i]}" == "item" ]] && selected_ref[i]=0
            done
            ;;
          -101)
            clear_screen
            filter="$(prompt_line "Search/filter ${type}: ")"
            index=0
            ;;
          -102)
            if add_custom_picker_item "$type" "$labels_name" "$values_name" "$selected_name" "$kinds_name"; then
              filter=""
              index=$((${#labels_ref[@]} + 4))
            fi
            ;;
          -103)
            filter=""
            index=0
            ;;
          *)
            if [[ "${kinds_ref[$selected_index]}" == "group" ]]; then
              if group_is_fully_selected "$selected_index" "$selected_name" "$kinds_name"; then
                group_set_selection "$selected_index" 0 "$selected_name" "$kinds_name"
              else
                group_set_selection "$selected_index" 1 "$selected_name" "$kinds_name"
              fi
            elif [[ "${kinds_ref[$selected_index]}" == "item" ]]; then
              if [[ "${selected_ref[selected_index]}" == "1" ]]; then
                selected_ref[selected_index]=0
              else
                selected_ref[selected_index]=1
              fi
              sync_virt_manager_bundle_selection                 "${values_ref[selected_index]}" "${selected_ref[selected_index]}"                 "$values_name" "$selected_name"
            fi
            ;;
        esac
        ;;
      $'\n'|$'\r'|"")
        local selected_index="${view_indices[$index]}"
        case "$selected_index" in
          -100)
            return 0
            ;;
          -104)
            return 2
            ;;
          -201)
            for i in "${!kinds_ref[@]}"; do
              [[ "${kinds_ref[i]}" == "item" ]] && selected_ref[i]=1
            done
            ;;
          -202)
            for i in "${!kinds_ref[@]}"; do
              [[ "${kinds_ref[i]}" == "item" ]] && selected_ref[i]=0
            done
            ;;
          -101)
            clear_screen
            filter="$(prompt_line "Search/filter ${type}: ")"
            index=0
            ;;
          -102)
            if add_custom_picker_item "$type" "$labels_name" "$values_name" "$selected_name" "$kinds_name"; then
              filter=""
              index=$((${#labels_ref[@]} + 4))
            fi
            ;;
          -103)
            filter=""
            index=0
            ;;
          *)
            if [[ "${kinds_ref[$selected_index]}" == "group" ]]; then
              edit_package_group "$title" "$selected_index" "$labels_name" "$values_name" "$selected_name" "$kinds_name"
            elif [[ "${kinds_ref[$selected_index]}" == "item" ]]; then
              if [[ "${selected_ref[selected_index]}" == "1" ]]; then
                selected_ref[selected_index]=0
              else
                selected_ref[selected_index]=1
              fi
              sync_virt_manager_bundle_selection                 "${values_ref[selected_index]}" "${selected_ref[selected_index]}"                 "$values_name" "$selected_name"
            fi
            ;;
        esac
        ;;
      b|B) return 2 ;;
    esac
  done
}

collect_selected_items() {
  # shellcheck disable=SC2178
  local -n values_ref="$1"
  # shellcheck disable=SC2178
  local -n selected_ref="$2"
  # shellcheck disable=SC2178
  local -n kinds_ref="$3"
  local -n out_ref="$4"
  out_ref=()
  local i
  for i in "${!values_ref[@]}"; do
    [[ "${kinds_ref[$i]}" == "item" ]] || continue
    [[ "${selected_ref[$i]}" == "1" ]] || continue
    out_ref+=("${values_ref[$i]}")
  done
}

print_dry_run_list() {
  local title="$1"
  shift || true

  printf '\n%s\n' "${COLOR_CYAN}${title}${COLOR_RESET}"
  if (( $# == 0 )); then
    printf '  - none\n'
    return 0
  fi

  local item
  for item in "$@"; do
    printf '  - %s\n' "$item"
  done
}

print_install_dry_run_plan() {
  print_install_review
  printf '\n%s\n' "${COLOR_GREEN}Dry-run complete. No changes were made.${COLOR_RESET}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Up-front install questionnaire
# ──────────────────────────────────────────────────────────────────────────────
print_install_review() {
  local mode_label="LIVE INSTALL"
  local system_type="desktop"
  local gpu_enabled="no"
  local ly_enabled="no"
  local pam_enabled="no"
  local reboot_label="yes"

  (( DRY_RUN == 1 )) && mode_label="DRY-RUN"
  [[ "$IS_LAPTOP" == true ]] && system_type="laptop"
  [[ "$INSTALL_GPU" == 1 ]] && gpu_enabled="yes"
  [[ "$INSTALL_LY" == 1 ]] && ly_enabled="yes"
  [[ "$ENABLE_KEYRING_PAM" == 1 ]] && pam_enabled="yes"
  (( NO_REBOOT == 1 || DRY_RUN == 1 )) && reboot_label="no"

  clear_screen
  printf '%s\n\n' "${COLOR_CYAN}Awtarchy ${mode_label} review${COLOR_RESET}"
  printf 'Target user: %s\n' "$TARGET_USER"
  printf 'Home dir: %s\n' "$HOME_DIR"
  printf 'Repo dir: %s\n' "$REPO_DIR"
  printf 'System type: %s\n' "$system_type"
  printf 'Virtual machine/container detected: %s\n' "$IS_VM"
  printf 'Arch packages: %s\n' "${#ARCH_SELECTED[@]}"
  printf 'AUR packages: %s\n' "${#AUR_SELECTED[@]}"
  printf 'Flatpak apps: %s\n' "${#FLATPAK_SELECTED_IDS[@]}"
  printf 'GPU dependencies: %s\n' "$gpu_enabled"
  printf 'Ly tty2: %s\n' "$ly_enabled"
  printf 'PAM keyring: %s\n' "$pam_enabled"
  printf 'Reboot at end: %s\n' "$reboot_label"

  printf '\n%s\n' "${COLOR_CYAN}Planned stages${COLOR_RESET}"
  printf '  - Check disk space and install bootstrap packages\n'
  printf '  - Clone/update ~/awtarchy if missing\n'
  if (( INSTALL_ARCH == 1 )); then printf '  - Install selected Arch repo packages\n'; else printf '  - Skip Arch repo packages\n'; fi
  if (( INSTALL_AUR == 1 )); then printf '  - Install selected AUR packages\n'; else printf '  - Skip AUR packages\n'; fi
  if (( INSTALL_FLATPAK == 1 )); then printf '  - Install selected Flatpak apps\n'; else printf '  - Skip Flatpak apps\n'; fi
  printf '  - Install/update Alacritty themes\n'
  if [[ "$INSTALL_GPU" == 1 && "$IS_VM" == false ]]; then printf '  - Run GPU dependency automation\n'; else printf '  - Skip GPU dependency automation\n'; fi
  printf '  - Install/update Micro themes\n'
  if (( ENABLE_KEYRING_PAM == 1 )); then printf '  - Enable GNOME Keyring PAM integration\n'; else printf '  - Skip GNOME Keyring PAM integration\n'; fi
  if (( INSTALL_LY == 1 )); then printf '  - Enable Ly on tty2 for next boot only\n'; else printf '  - Skip Ly\n'; fi
  printf '  - Copy awtarchy-managed config files into %s/.config\n' "$HOME_DIR"
  printf '  - Apply Awtarchy desktop defaults\n'
  printf '  - Repair ownership and permissions\n'

  if (( INSTALL_ARCH == 1 )); then print_dry_run_list "Arch repo packages (${#ARCH_SELECTED[@]})" "${ARCH_SELECTED[@]}"; fi
  if (( INSTALL_AUR == 1 )); then print_dry_run_list "AUR packages (${#AUR_SELECTED[@]})" "${AUR_SELECTED[@]}"; fi
  if (( INSTALL_FLATPAK == 1 )); then print_dry_run_list "Flatpak apps (${#FLATPAK_SELECTED_IDS[@]})" "${FLATPAK_SELECTED_IDS[@]}"; fi
}

confirm_install_review() {
  local title action choice
  if (( DRY_RUN == 1 )); then
    action="Print dry-run plan"
  else
    action="Start install now"
  fi

  while true; do
    print_install_review
    title="Review complete. Choose what to do next."
    choice="$(single_select_menu "$title" 0 "$action" "Back to choices" "Cancel")" || return 2
    case "$choice" in
      0) return 0 ;;
      1) return 1 ;;
      *) return 2 ;;
    esac
  done
}

run_install_questionnaire() {
  require_root
  detect_target_user_install

  if user_config_has_no_files; then
    INSTALL_LY=1
    ENABLE_KEYRING_PAM=1
    OVERWRITE_BASHRC=1
    OVERWRITE_BASH_PROFILE=1
  fi

  if systemd-detect-virt --quiet; then IS_VM=true; else IS_VM=false; fi

  local step=0 rc choice
  local -a labels=()
  local -a values=()
  local -a shell_labels=()
  local -a shell_values=()

  while true; do
    case "$step" in
      0)
        local intro_title
        intro_title="Awtarchy install setup

Nothing installs yet. This first part only collects choices.

Before any changes are made, you will choose:
  - system type
  - install sections
  - Arch repo packages
  - AUR packages
  - Flatpak apps
  - shell-file overwrite behavior

After that, Awtarchy shows a summary. In dry-run mode it prints the plan and exits.
In normal install mode it will overwrite awtarchy-managed config files under:
  ${HOME_DIR}"

        choice="$(single_select_menu "$intro_title" 0 "Start setup" "Back to main menu")" || return 2
        case "$choice" in
          0) step=1 ;;
          *) return 2 ;;
        esac
        ;;

      1)
        if [[ "$IS_VM" == true ]]; then
          IS_LAPTOP=false
          step=2
          continue
        fi

        choice="$(single_select_menu "System type" 1 "Laptop" "Desktop" "Back")" || { step=0; continue; }
        case "$choice" in
          0) IS_LAPTOP=true; step=2 ;;
          1) IS_LAPTOP=false; step=2 ;;
          *) step=0 ;;
        esac
        ;;

      2)
        labels=(
          "Arch repo packages"
          "AUR packages"
          "Flatpak apps"
          "GPU dependencies"
          "Ly TTY login manager"
          "GNOME Keyring PAM integration"
        )
        values=("$INSTALL_ARCH" "$INSTALL_AUR" "$INSTALL_FLATPAK" "$INSTALL_GPU" "$INSTALL_LY" "$ENABLE_KEYRING_PAM")
        if [[ "$IS_VM" == true ]]; then
          values[3]=0
          # shellcheck disable=SC2034
          labels[3]="GPU dependencies ${COLOR_DIM}(disabled in VM)${COLOR_RESET}"
        fi

        if summary_toggle_menu "Install sections" labels values; then
          INSTALL_ARCH="${values[0]}"
          INSTALL_AUR="${values[1]}"
          INSTALL_FLATPAK="${values[2]}"
          INSTALL_GPU="${values[3]}"
          INSTALL_LY="${values[4]}"
          ENABLE_KEYRING_PAM="${values[5]}"
          step=3
        else
          rc=$?
          if (( rc == 2 )); then
            if [[ "$IS_VM" == true ]]; then step=0; else step=1; fi
          else
            return "$rc"
          fi
        fi
        ;;

      3)
        if [[ -f "${HOME_DIR}/.bashrc" || -f "${HOME_DIR}/.bash_profile" ]]; then
          shell_labels=()
          shell_values=()
          if [[ -f "${HOME_DIR}/.bashrc" ]]; then shell_labels+=("Overwrite existing ~/.bashrc"); shell_values+=("$OVERWRITE_BASHRC"); fi
          if [[ -f "${HOME_DIR}/.bash_profile" ]]; then shell_labels+=("Overwrite existing ~/.bash_profile"); shell_values+=("$OVERWRITE_BASH_PROFILE"); fi

          if summary_toggle_menu "Existing shell files" shell_labels shell_values; then
            local n=0
            if [[ -f "${HOME_DIR}/.bashrc" ]]; then OVERWRITE_BASHRC="${shell_values[$n]}"; ((n++)) || true; else OVERWRITE_BASHRC=1; fi
            if [[ -f "${HOME_DIR}/.bash_profile" ]]; then OVERWRITE_BASH_PROFILE="${shell_values[$n]}"; else OVERWRITE_BASH_PROFILE=1; fi
            step=4
          else
            rc=$?
            if (( rc == 2 )); then step=2; else return "$rc"; fi
          fi
        else
          OVERWRITE_BASHRC=1
          OVERWRITE_BASH_PROFILE=1
          step=4
        fi
        ;;

      4)
        if (( INSTALL_ARCH == 1 )); then
          if ! declare -p ARCH_LABELS ARCH_VALUES ARCH_SELECTED_FLAGS ARCH_KINDS >/dev/null 2>&1; then
            build_arch_picker_arrays
          fi

          if package_picker "Arch repo packages" "Arch package" ARCH_LABELS ARCH_VALUES ARCH_SELECTED_FLAGS ARCH_KINDS; then
            collect_selected_items ARCH_VALUES ARCH_SELECTED_FLAGS ARCH_KINDS ARCH_SELECTED
            step=5
          else
            rc=$?
            if (( rc == 2 )); then step=3; else return "$rc"; fi
          fi
        else
          ARCH_SELECTED=()
          step=5
        fi
        ;;

      5)
        if (( INSTALL_AUR == 1 )); then
          if ! declare -p AUR_LABELS AUR_VALUES AUR_SELECTED_FLAGS AUR_KINDS >/dev/null 2>&1; then
            build_aur_picker_arrays
          fi

          if package_picker "AUR packages" "AUR package" AUR_LABELS AUR_VALUES AUR_SELECTED_FLAGS AUR_KINDS; then
            collect_selected_items AUR_VALUES AUR_SELECTED_FLAGS AUR_KINDS AUR_SELECTED
            step=6
          else
            rc=$?
            if (( rc == 2 )); then step=4; else return "$rc"; fi
          fi
        else
          AUR_SELECTED=()
          step=6
        fi
        ;;

      6)
        if (( INSTALL_FLATPAK == 1 )); then
          if ! declare -p FLATPAK_LABELS FLATPAK_VALUES FLATPAK_SELECTED_FLAGS FLATPAK_KINDS >/dev/null 2>&1; then
            build_flatpak_picker_arrays
          fi

          if package_picker "Flatpak apps" "Flatpak app ID" FLATPAK_LABELS FLATPAK_VALUES FLATPAK_SELECTED_FLAGS FLATPAK_KINDS; then
            local -a flatpak_pairs=()
            collect_selected_items FLATPAK_VALUES FLATPAK_SELECTED_FLAGS FLATPAK_KINDS flatpak_pairs
            FLATPAK_SELECTED_NAMES=()
            FLATPAK_SELECTED_IDS=()
            local pair name appid
            for pair in "${flatpak_pairs[@]}"; do
              IFS='|' read -r name appid <<< "$pair"
              FLATPAK_SELECTED_NAMES+=("$name")
              FLATPAK_SELECTED_IDS+=("$appid")
            done
            step=7
          else
            rc=$?
            if (( rc == 2 )); then step=5; else return "$rc"; fi
          fi
        else
          FLATPAK_SELECTED_NAMES=()
          FLATPAK_SELECTED_IDS=()
          step=7
        fi
        ;;

      7)
        if confirm_install_review; then
          return 0
        else
          rc=$?
          case "$rc" in
            1)
              if (( INSTALL_FLATPAK == 1 )); then
                step=6
              elif (( INSTALL_AUR == 1 )); then
                step=5
              elif (( INSTALL_ARCH == 1 )); then
                step=4
              elif [[ -f "${HOME_DIR}/.bashrc" || -f "${HOME_DIR}/.bash_profile" ]]; then
                step=3
              else
                step=2
              fi
              ;;
            2) return 2 ;;
            *) return "$rc" ;;
          esac
        fi
        ;;

      *)
        return 2
        ;;
    esac
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# Install stages
# ──────────────────────────────────────────────────────────────────────────────
prepare_base_install() {
  local required_space_mb=1024 available_space_mb
  available_space_mb="$(df --output=avail / | tail -1)"
  available_space_mb=$((available_space_mb / 1024))
  (( available_space_mb >= required_space_mb )) || die "Not enough disk space. 1GB required."

  log "Updating package list and installing bootstrap packages..."
  if ! retry_command pacman -Syu --noconfirm; then
    warn "System update failed. Trying reflector mirror refresh."
    pacman -S --needed --noconfirm reflector || true
    retry_command reflector --verbose --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
    retry_command pacman -Syu --noconfirm || exit 1
  fi

  retry_command pacman -S --needed --noconfirm git ipcalc dos2unix reflector || exit 1
  pacman_install_one playerctl || die "Failed to install required media-control dependency: playerctl"
  pacman_install_one hyprland-qt-support || die "Failed to install required Hyprland Qt style provider: hyprland-qt-support"

  if [[ ! -d "$REPO_DIR" ]]; then
    log "Cloning awtarchy repository to ${REPO_DIR}..."
    retry_command git clone https://github.com/dillacorn/awtarchy "$REPO_DIR" || exit 1
  fi
  retry_command chown -R "${TARGET_USER}:${TARGET_USER}" "$REPO_DIR"

  log "Converting repository files to Unix line endings..."
  find "$REPO_DIR" -type f -exec dos2unix {} + 2>/dev/null || true
}

reconcile_power_profile_backend() {
  local repo_dir="$1"
  local reconciler="${repo_dir}/local/share/awtarchy/awtarchy-power-profile.sh"

  [[ -f "$reconciler" && ! -L "$reconciler" ]] \
    || die "Release is missing the power-profile reconciler: ${reconciler}"
  /usr/bin/bash -n "$reconciler" \
    || die "Release power-profile reconciler failed Bash syntax validation."

  AWTARCHY_MANAGED_PACKAGES_FILE="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}" \
    /usr/bin/bash "$reconciler"
}

install_arch_repo_apps_stage() {
  (( INSTALL_ARCH == 1 )) || { warn "Skipping Arch repo application install."; return 0; }

  if ! grep -q "^\[multilib\]" /etc/pacman.conf || ! grep -q "^Include = /etc/pacman.d/mirrorlist" /etc/pacman.conf; then
    die "Multilib repository is not enabled. Enable [multilib] in /etc/pacman.conf, then rerun."
  fi

  if pacman -Qi jack2 >/dev/null 2>&1; then
    warn "Removing conflicting jack2 package before pipewire-jack..."
    pacman -Rdd --noconfirm jack2 || die "Failed to remove jack2. Remove manually and retry."
  fi
  pacman_install_one pipewire-jack || true

  if (( ${#ARCH_SELECTED[@]} == 0 )); then
    warn "No Arch repo packages selected. Skipping package loop."
  else
    log "Updating system before Arch repo package install..."
    pacman -Syu --noconfirm || die "System update failed. Resolve and rerun."

    local group group_name packages pkg p
    for group in "${PKG_GROUPS[@]}"; do
      IFS=':' read -r group_name packages <<< "$group"
      local -a group_selected=()
      while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        array_contains_exact "$pkg" "${ARCH_SELECTED[@]}" && group_selected+=("$pkg")
      done < <(split_pkg_words "$packages")
      (( ${#group_selected[@]} )) || continue
      printf '\n%s\n' "${COLOR_CYAN}Installing ${group_name}...${COLOR_RESET}"
      for pkg in "${group_selected[@]}"; do
        pacman_install_one "$pkg" || warn "Continuing despite failure: $pkg"
      done
    done

    local pkg
    for pkg in "${ARCH_SELECTED[@]}"; do
      local found=0
      for group in "${PKG_GROUPS[@]}"; do
        IFS=':' read -r _ packages <<< "$group"
        while IFS= read -r p; do
          [[ -n "$p" ]] || continue
          [[ "$p" == "$pkg" ]] && found=1
        done < <(split_pkg_words "$packages")
      done
      (( found == 1 )) && continue
      pacman_install_one "$pkg" || warn "Continuing despite failure: $pkg"
    done
  fi

  log "Configuring system services..."
  configure_mdns_stack
  systemctl enable --now avahi-daemon || true
  if systemctl is-active --quiet unbound; then systemctl disable --now unbound || true; fi
  systemctl enable --now systemd-resolved || true
  systemctl stop dnsmasq.service || true
  systemctl disable dnsmasq.service || true
  systemctl enable --now NetworkManager || true

  if [[ "$IS_VM" == false ]]; then
    if grep -qi Intel /proc/cpuinfo && [[ "$IS_LAPTOP" == true ]]; then
      log "Setting up Intel laptop power management..."
      if pacman_install_one thermald; then
        systemctl enable --now thermald || true
      fi
    fi

    log "Configuring virtualization..."
    systemctl enable --now libvirtd || true
    for _ in {1..10}; do systemctl is-active --quiet libvirtd && break; sleep 1; done
    virsh net-destroy default || true
    virsh net-start default || true
    virsh net-autostart default || true
    if have ufw; then
      ufw allow in on virbr0 || true
      ufw allow out on virbr0 || true
      ufw reload || true
    fi
  fi

  if pacman -Qi earlyoom >/dev/null 2>&1; then systemctl enable --now earlyoom || true; fi
  if pacman -Qi bluez >/dev/null 2>&1; then systemctl enable --now bluetooth.service || true; fi
}

ensure_aur_sudo_access() {
  command -v sudo >/dev/null 2>&1 \
    || die "sudo is required for AUR package transactions."
  log "Confirming the target user's normal sudo authorization for AUR package installation..."
  if ! run_as_target sudo -v; then
    die "AUR installation requires the target user's normal sudo authorization."
  fi
}

ensure_aur_install_requirements() {
  log "Installing AUR package build requirements..."
  pacman -S --needed --noconfirm base-devel git gnupg
}


ensure_yay() {
  local tmp pkg

  if [[ -x /usr/bin/yay ]] && run_as_target /usr/bin/yay --version >/dev/null 2>&1; then
    return 0
  fi

  warn "yay not found. Bootstrapping the standard AUR helper..."
  tmp="$(run_as_target mktemp -d)" || die "Could not create a temporary yay build directory."

  if ! run_as_target git clone --depth 1 https://aur.archlinux.org/yay.git "${tmp}/yay"; then
    rm -rf -- "$tmp"
    die "Failed to download yay from the AUR."
  fi

  if ! run_as_target bash --noprofile --norc -c \
      'cd -- "$1" && makepkg -s --noconfirm --needed' awtarchy-yay "${tmp}/yay"; then
    rm -rf -- "$tmp"
    die "Failed to build yay."
  fi

  pkg="$(find "${tmp}/yay" -maxdepth 1 -type f -name 'yay-*.pkg.tar*' ! -name '*-debug*' -print -quit)"
  if [[ -z "$pkg" ]]; then
    rm -rf -- "$tmp"
    die "Built yay package archive was not found."
  fi

  if ! pacman -U --noconfirm --needed "$pkg"; then
    rm -rf -- "$tmp"
    die "Failed to install yay."
  fi
  rm -rf -- "$tmp"

  [[ -x /usr/bin/yay ]] && run_as_target /usr/bin/yay --version >/dev/null 2>&1 \
    || die "yay bootstrap completed without a usable /usr/bin/yay."
}


ensure_aur_scanner() {
  if [[ -x /usr/bin/aur-scan ]] \
      && run_as_target /usr/bin/aur-scan --version >/dev/null 2>&1; then
    return 0
  fi

  ensure_aur_install_requirements
  ensure_aur_sudo_access
  ensure_yay

  log "Installing stable aur-scanner through yay for the initial bootstrap..."
  if ! run_as_target /usr/bin/yay -S --noconfirm --pgpfetch aur-scanner; then
    die "Failed to bootstrap stable aur-scanner."
  fi

  [[ -x /usr/bin/aur-scan ]] \
    && run_as_target /usr/bin/aur-scan --version >/dev/null 2>&1 \
    || die "aur-scanner installed without a usable /usr/bin/aur-scan."
}

install_aur_with_scanner() {
  (( $# > 0 )) || return 0

  if (( DRY_RUN == 1 )); then
    log "DRY-RUN: would run aur-scan install for: $*"
    return 0
  fi

  ensure_aur_scanner
  run_as_target /usr/bin/aur-scan install "$@" --noconfirm
}

obs_pipewire_audio_capture_user_plugin_installed() {
  [[ -f "${HOME_DIR}/.config/obs-studio/plugins/linux-pipewire-audio/bin/64bit/linux-pipewire-audio.so" ]]
}

aur_selected_package_installed() {
  local pkg="$1" alt=""

  case "$pkg" in
    alacritty|alacritty-graphics)
      for alt in alacritty alacritty-graphics; do
        pacman -Q "$alt" >/dev/null 2>&1 && return 0
      done
      return 1
      ;;
    qimgv|qimgv-git)
      for alt in qimgv qimgv-git; do
        pacman -Q "$alt" >/dev/null 2>&1 && return 0
      done
      return 1
      ;;
    hyprmoncfg|hyprmoncfg-bin|hyprmoncfg-git)
      for alt in hyprmoncfg hyprmoncfg-bin hyprmoncfg-git; do
        pacman -Q "$alt" >/dev/null 2>&1 && return 0
      done
      return 1
      ;;
    obs-pipewire-audio-capture|obs-pipewire-audio-capture-bin)
      for alt in         obs-pipewire-audio-capture         obs-pipewire-audio-capture-bin
      do
        pacman -Q "$alt" >/dev/null 2>&1 && return 0
      done

      obs_pipewire_audio_capture_user_plugin_installed
      ;;
    *)
      pacman -Q "$pkg" >/dev/null 2>&1
      ;;
  esac
}

obs_pipewire_audio_capture_release_url() {
  local url=""

  url="$(
    curl -fsSL --max-time 12 \
      -H "Accept: application/vnd.github+json" \
      -H "User-Agent: awtarchy-installer" \
      "https://api.github.com/repos/dimtpap/obs-pipewire-audio-capture/releases/latest" \
      | jq -r '
          .assets[]
          | select(.name | test("^linux-pipewire-audio-.*\\.tar\\.gz$"))
          | select((.name | test("flatpak|obs-27")) | not)
          | .browser_download_url
        ' \
      | head -n 1
  )" || true

  if [[ -n "$url" && "$url" != "null" ]]; then
    printf '%s\n' "$url"
    return 0
  fi

  return 1
}

install_obs_pipewire_audio_capture_user_plugin() {
  local plugin_dir="${HOME_DIR}/.config/obs-studio/plugins"
  local plugin_root="${plugin_dir}/linux-pipewire-audio"
  local tmp_dir=""
  local archive=""
  local release_url=""

  if obs_pipewire_audio_capture_user_plugin_installed; then
    printf '%s\n' "${COLOR_YELLOW}obs-pipewire-audio-capture already installed in OBS user plugins. Skipping fallback...${COLOR_RESET}"
    return 0
  fi

  log "Installing OBS PipeWire audio capture plugin with upstream per-user fallback..."

  pacman -S --needed --noconfirm \
    obs-studio wireplumber pipewire pipewire-pulse curl ca-certificates jq

  if ! release_url="$(obs_pipewire_audio_capture_release_url)"; then
    release_url="https://github.com/dimtpap/obs-pipewire-audio-capture/releases/download/1.2.1/linux-pipewire-audio-1.2.1.tar.gz"
    warn "Could not query latest OBS PipeWire audio capture release. Falling back to 1.2.1 archive."
  fi

  tmp_dir="$(run_as_target mktemp -d /tmp/awtarchy-obs-pipewire-audio.XXXXXX)"
  archive="${tmp_dir}/linux-pipewire-audio.tar.gz"

  run_as_target curl -fL --retry 3 --retry-delay 2 -o "$archive" "$release_url"

  if tar -tzf "$archive" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
    run_as_target rm -rf -- "$tmp_dir"
    die "OBS PipeWire audio capture archive contains unsafe paths."
  fi

  if ! tar -tzf "$archive" | grep -q '^linux-pipewire-audio/'; then
    run_as_target rm -rf -- "$tmp_dir"
    die "OBS PipeWire audio capture archive has unexpected layout."
  fi

  run_as_target rm -rf -- "$plugin_root"
  run_as_target install -d -m 0755 "$plugin_dir"

  run_as_target tar -xzf "$archive" -C "$plugin_dir"
  run_as_target chmod -R u+rwX,go+rX "$plugin_root"

  run_as_target rm -rf -- "$tmp_dir"

  if ! obs_pipewire_audio_capture_user_plugin_installed; then
    die "OBS PipeWire audio capture fallback install did not produce the expected plugin file."
  fi

  ok "OBS PipeWire audio capture plugin installed to ${plugin_root}"
}

install_obs_pipewire_audio_capture_package() {
  local pkg="obs-pipewire-audio-capture"

  if pacman -Q "$pkg" >/dev/null 2>&1; then
    printf '%s\n' "${COLOR_YELLOW}${pkg} already installed through pacman. Skipping...${COLOR_RESET}"
    return 0
  fi

  if obs_pipewire_audio_capture_user_plugin_installed; then
    printf '%s\n' "${COLOR_YELLOW}${pkg} already installed in OBS user plugins. Skipping...${COLOR_RESET}"
    return 0
  fi

  if install_aur_with_scanner "$pkg"; then
    return 0
  fi

  warn "${pkg} failed through aur-scanner. Falling back to upstream per-user OBS plugin install."
  install_obs_pipewire_audio_capture_user_plugin
}

install_aur_repo_apps_stage() {
  (( INSTALL_AUR == 1 )) || { warn "Skipping AUR application install."; return 0; }

  ensure_aur_install_requirements
  ensure_aur_sudo_access
  ensure_yay
  ensure_aur_scanner

  if (( ${#AUR_SELECTED[@]} == 0 )); then
    warn "No AUR packages selected. Skipping package loop."
  else
    log "Installing selected AUR packages through upstream aur-scanner..."
    local pkg
    for pkg in "${AUR_SELECTED[@]}"; do
      if aur_selected_package_installed "$pkg"; then
        printf '%s\n' "${COLOR_YELLOW}${pkg} or an equivalent installation is already present. Skipping...${COLOR_RESET}"
      else
        printf '%s\n' "${COLOR_CYAN}Verifying and installing ${pkg}...${COLOR_RESET}"
        if [[ "$pkg" == "obs-pipewire-audio-capture" ]]; then
          if ! install_obs_pipewire_audio_capture_package; then
            warn "AUR package failed: ${pkg}. Continuing with remaining selections."
            continue
          fi
        else
          if ! install_aur_with_scanner "$pkg"; then
            warn "AUR package failed: ${pkg}. Continuing with remaining selections."
            continue
          fi
        fi
        printf '%s\n' "${COLOR_GREEN}${pkg} installed successfully.${COLOR_RESET}"
      fi
    done
  fi

  if pacman -Q moonlight-qt-bin >/dev/null 2>&1; then
    log "Moonlight AUR package detected. Configuring UFW rules for Moonlight..."
    if have ufw; then
      ufw allow 48010/tcp || true
      ufw allow 48000/udp || true
      ufw allow 48010/udp || true
    else
      warn "UFW is not installed. Skipping Moonlight firewall configuration."
    fi
  fi
}

flatpak_effective_scope_install() {
  local root_fs_type
  root_fs_type="$(df -T / | awk 'NR==2 {print $2}')"
  if [[ "$root_fs_type" == "btrfs" ]]; then printf '%s\n' system; else printf '%s\n' user; fi
}

run_flatpak_scope() {
  local scope="$1"
  shift
  if [[ "$scope" == "user" ]]; then
    runuser -u "$TARGET_USER" -- flatpak --user "$@"
  else
    flatpak "$@"
  fi
}

install_flatpak_apps_stage() {
  (( INSTALL_FLATPAK == 1 )) || { warn "Skipping Flatpak application install."; return 0; }
  if ! have flatpak; then
    log "Flatpak is not installed. Installing flatpak..."
    pacman -S --needed --noconfirm flatpak
  fi

  local scope remote_name remote_url
  scope="$(flatpak_effective_scope_install)"
  remote_name="flathub"
  remote_url="https://flathub.org/repo/flathub.flatpakrepo"

  if ! run_flatpak_scope "$scope" remotes --columns=name | grep -Fxq "$remote_name"; then
    run_flatpak_scope "$scope" remote-add --if-not-exists "$remote_name" "$remote_url"
  fi

  if [[ "$scope" == "user" ]]; then
    local alias_line rc_path shell_rc
    alias_line='alias flatpak="flatpak --user"'
    for shell_rc in .bashrc .zshrc; do
      rc_path="${HOME_DIR}/${shell_rc}"
      if [[ -f "$rc_path" ]] && ! grep -Fxq "$alias_line" "$rc_path"; then
        # shellcheck disable=SC2016 # Variables intentionally expand in the target-user shell.
        run_as_target bash -c '
          {
            printf "\n# Automatically apply --user flag for Flatpak on non-Btrfs or user-scope systems\n"
            printf "%s\n" "$2"
          } >>"$1"
        ' awtarchy-flatpak-alias "$rc_path" "$alias_line"
      fi
    done
  fi

  log "Updating installed Flatpak apps in ${scope} scope..."
  run_flatpak_scope "$scope" update -y || true

  local app name i
  for i in "${!FLATPAK_SELECTED_IDS[@]}"; do
    app="${FLATPAK_SELECTED_IDS[$i]}"
    name="${FLATPAK_SELECTED_NAMES[$i]}"
    if run_flatpak_scope "$scope" list --app --columns=application | grep -Fxq "$app"; then
      printf '%s\n' "${COLOR_YELLOW}${name} (${app}) already installed. Skipping...${COLOR_RESET}"
      continue
    fi
    local retries=3 count=0
    until run_flatpak_scope "$scope" list --app --columns=application | grep -Fxq "$app"; do
      if (( count >= retries )); then
        warn "Failed to install ${name} (${app}) after ${retries} attempts. Skipping."
        break
      fi
      log "Installing ${name} (${app}) attempt $((count + 1))/${retries}..."
      if run_flatpak_scope "$scope" install -y "$remote_name" "$app"; then
        break
      fi
      ((count++)) || true
      sleep 2
    done
  done

  if run_flatpak_scope "$scope" list --app --columns=application | grep -Fxq dev.vencord.Vesktop; then
    log "Applying Flatpak override for Vesktop to disable X11 socket..."
    run_flatpak_scope "$scope" override --nosocket=x11 dev.vencord.Vesktop || true
  fi

  if have ufw; then
    log "Configuring UFW rules for NDI..."
    ufw allow 5353/udp || true
    ufw allow 5959:5969/tcp || true
    ufw allow 5959:5969/udp || true
    ufw allow 6960:6970/tcp || true
    ufw allow 6960:6970/udp || true
    ufw allow 7960:7970/tcp || true
    ufw allow 7960:7970/udp || true
    ufw allow 5960/tcp || true

    if run_flatpak_scope "$scope" list --app --columns=application | grep -Fxq com.moonlight_stream.Moonlight; then
      log "Moonlight Flatpak detected. Configuring UFW rules for Moonlight..."
      ufw allow 48010/tcp || true
      ufw allow 48000/udp || true
      ufw allow 48010/udp || true
    fi
  else
    warn "ufw not installed. Skipping NDI/Moonlight firewall configuration."
  fi
}

install_alacritty_themes_stage() {
  local target_dir="${HOME_DIR}/.config/alacritty"
  run_as_target install -d -m 0755 "$target_dir"

  if [[ -d "$target_dir/themes" ]]; then
    log "Alacritty themes directory exists. Checking for updates..."
    run_as_target bash -lc "cd '$target_dir/themes' && git fetch origin && default_branch=\$(git remote show origin | awk '/HEAD branch/ {print \$NF}') && remote_commit=\$(git rev-parse origin/\$default_branch) && local_commit=\$(git rev-parse HEAD) && if [[ \$local_commit != \$remote_commit ]]; then git reset --hard origin/\$default_branch; fi"
  else
    log "Cloning Alacritty themes..."
    run_as_target git clone https://github.com/alacritty/alacritty-theme "$target_dir/themes"
  fi
}

install_micro_themes_stage() {
  [[ -n "${TARGET_USER:-}" ]] || die "TARGET_USER unset."
  have git || die "git is required."

  local repo_url1="https://github.com/catppuccin/micro"
  local repo_url2="https://github.com/zyedidia/micro"
  local target_colorscheme="geany"
  local flatpak_config_root="${HOME_DIR}/.var/app/io.github.zyedidia.micro/config"
  local config_root

  if run_as_target flatpak info --user io.github.zyedidia.micro >/dev/null 2>&1 || [[ -d "$flatpak_config_root" ]]; then
    config_root="$flatpak_config_root"
  else
    config_root="${HOME_DIR}/.config"
  fi

  local micro_dir="${config_root}/micro"
  local color_dir="${micro_dir}/colorschemes"
  local settings_json="${micro_dir}/settings.json"
  local tmp1 tmp2 have_jq=0
  tmp1="$(run_as_target mktemp -d)"
  tmp2="$(run_as_target mktemp -d)"
  trap 'rm -rf "${tmp1:-}" "${tmp2:-}" 2>/dev/null || true; cleanup_install_temp' EXIT
  have jq && have_jq=1

  log "Cloning Micro theme sources..."
  run_as_target git clone --depth=1 "$repo_url1" "$tmp1" >/dev/null
  run_as_target git clone --depth=1 "$repo_url2" "$tmp2" >/dev/null

  run_as_target install -d -m 0755 "$color_dir"
  compgen -G "${tmp1}/themes/*.micro" >/dev/null && run_as_target cp -f "${tmp1}/themes/"*.micro "$color_dir/"
  compgen -G "${tmp2}/runtime/colorschemes/*.micro" >/dev/null && run_as_target cp -f "${tmp2}/runtime/colorschemes/"*.micro "$color_dir/"

  run_as_target install -d -m 0755 "$micro_dir"
  printf '{\n  "colorscheme": "%s"\n}\n' "$target_colorscheme" \
    | run_as_target tee "${settings_json}.tmp" >/dev/null
  (( have_jq == 1 )) && jq -e . "${settings_json}.tmp" >/dev/null
  run_as_target mv -f "${settings_json}.tmp" "$settings_json"

  [[ -f "$settings_json" ]] || die "Failed to create ${settings_json}"
  if [[ ! -f "${color_dir}/${target_colorscheme}.micro" ]]; then
    warn "${target_colorscheme}.micro not found in ${color_dir}"
  fi
}

cleanup_legacy_keyring_pam_stage() {
  local repo_dir="${1:-${REPO_DIR:-}}"
  local transformer="${repo_dir}/local/share/awtarchy/keyring-pam-cleanup.py"
  local pam_dir="${AWTARCHY_PAM_DIR:-/etc/pam.d}"
  local login_file="${pam_dir}/login"
  local ly_file="${pam_dir}/ly"
  local backup_file="${login_file}.awtarchy-backup"
  local cleaned="" rc=0 mode="" owner="" group=""

  if [[ -n "${AWTARCHY_PAM_DIR:-}" && "$pam_dir" != /tmp/* ]]; then
    die "AWTARCHY_PAM_DIR test override must stay under /tmp."
  fi
  [[ -f "$login_file" && ! -L "$login_file" ]] || return 0
  [[ -f "$ly_file" && ! -L "$ly_file" ]] || return 0
  grep -Fq 'pam_gnome_keyring.so' "$ly_file" || return 0
  [[ -f "$transformer" && ! -L "$transformer" ]] || {
    warn "GNOME Keyring PAM cleanup helper is missing; leaving PAM unchanged."
    return 0
  }
  have python3 || {
    warn "python3 is unavailable; leaving legacy GNOME Keyring PAM state unchanged."
    return 0
  }

  cleaned="$(mktemp)"
  if python3 "$transformer" "$login_file" "$cleaned"; then
    rc=0
  else
    rc=$?
  fi
  if (( rc == 3 )); then
    rm -f -- "$cleaned"
    return 0
  fi
  if (( rc != 0 )); then
    rm -f -- "$cleaned"
    warn "Could not validate legacy GNOME Keyring PAM state; leaving PAM unchanged."
    return 0
  fi

  mode="$(stat -c '%a' -- "$login_file" 2>/dev/null || true)"
  owner="$(stat -c '%u' -- "$login_file" 2>/dev/null || true)"
  group="$(stat -c '%g' -- "$login_file" 2>/dev/null || true)"
  if [[ ! "$mode" =~ ^[0-7]{3,4}$ || ! "$owner" =~ ^[0-9]+$ || ! "$group" =~ ^[0-9]+$ ]]; then
    rm -f -- "$cleaned"
    warn "Could not preserve /etc/pam.d/login metadata; leaving PAM unchanged."
    return 0
  fi

  if [[ -n "${AWTARCHY_PAM_DIR:-}" || "${EUID}" -eq 0 ]]; then
    if [[ -L "$login_file" ]]; then
      rm -f -- "$cleaned"
      warn "Refusing symbolic-link PAM login file: ${login_file}"
      return 0
    fi
    if [[ ! -e "$backup_file" ]]; then
      cp -a -- "$login_file" "$backup_file" || {
        rm -f -- "$cleaned"
        warn "Could not back up ${login_file}; leaving PAM unchanged."
        return 0
      }
    fi
    install -m "$mode" -o "$owner" -g "$group" -- "$cleaned" "$login_file" || {
      rm -f -- "$cleaned"
      warn "Could not remove legacy GNOME Keyring PAM duplication."
      return 0
    }
  else
    have sudo || {
      rm -f -- "$cleaned"
      warn "sudo is unavailable; legacy GNOME Keyring PAM duplication was not removed."
      return 0
    }
    if ! sudo -v; then
      rm -f -- "$cleaned"
      warn "sudo authentication failed; legacy GNOME Keyring PAM duplication was not removed."
      return 0
    fi
    if sudo test -L "$login_file" || sudo test -L "$backup_file"; then
      rm -f -- "$cleaned"
      warn "Refusing symbolic-link GNOME Keyring PAM cleanup path."
      return 0
    fi
    if ! sudo test -e "$backup_file"; then
      if ! sudo cp -a -- "$login_file" "$backup_file"; then
        rm -f -- "$cleaned"
        warn "Could not back up ${login_file}; leaving PAM unchanged."
        return 0
      fi
    fi
    if ! sudo install -m "$mode" -o "$owner" -g "$group" -- "$cleaned" "$login_file"; then
      rm -f -- "$cleaned"
      warn "Could not remove legacy GNOME Keyring PAM duplication."
      return 0
    fi
  fi

  rm -f -- "$cleaned"
  log "Removed duplicate Awtarchy GNOME Keyring hooks from ${login_file}; Ly owns keyring PAM integration."
}

enable_keyring_pam_stage() {
  if (( INSTALL_LY == 1 )); then
    log "Ly provides GNOME Keyring PAM integration; skipping duplicate /etc/pam.d/login hooks."
    return 0
  fi
  (( ENABLE_KEYRING_PAM == 1 )) || { warn "Skipping GNOME Keyring PAM change."; return 0; }
  local tmpfile
  tmpfile="$(mktemp)"
  cat /etc/pam.d/login > "$tmpfile"
  if ! grep -q "pam_gnome_keyring.so" "$tmpfile"; then
    {
      printf '\n# GNOME Keyring Integration\n'
      printf '%s\n' 'auth       optional     pam_gnome_keyring.so'
      printf '%s\n' 'session    optional     pam_gnome_keyring.so auto_start'
    } >> "$tmpfile"
    cp "$tmpfile" /etc/pam.d/login
  fi
  rm -f "$tmpfile"
}

install_ly_stage() {
  (( INSTALL_LY == 1 )) || { warn "Skipping Ly install."; return 0; }
  local tty="tty2"

  log "Installing/enabling Ly on ${tty} for next boot only..."
  if [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    cat > /usr/share/wayland-sessions/hyprland.desktop <<'EOF'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland Wayland compositor
Exec=Hyprland
Type=Application
EOF
  fi

  if ! have ly; then
    pacman -S --needed --noconfirm ly
  fi

  if [[ ! -f /etc/systemd/system/ly@.service && ! -f /usr/lib/systemd/system/ly@.service ]]; then
    cat > /etc/systemd/system/ly@.service <<'EOF'
[Unit]
Description=Ly TUI display manager (%I)
After=systemd-user-sessions.service
After=getty@%i.service

[Service]
Type=idle
ExecStart=/usr/bin/ly
StandardInput=tty
TTYPath=/dev/%I
TTYReset=yes
TTYVHangup=yes

[Install]
Alias=display-manager.service
EOF
  fi

  systemctl daemon-reload
  systemctl disable "getty@${tty}.service" 2>/dev/null || true
  systemctl enable "ly@${tty}.service"
  systemctl set-default graphical.target
}

detect_installed_release_tag() {
  local latest="" release_commit="" head_commit=""

  if have curl && have python3; then
    latest="$(
      curl -fsSL --connect-timeout 5 --max-time 10 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: awtarchy-installer' \
        'https://api.github.com/repos/dillacorn/awtarchy/releases/latest' 2>/dev/null \
      | python3 -c '
import json, sys
try:
    value = json.load(sys.stdin).get("tag_name", "")
except Exception:
    value = ""
print(str(value).strip())
' 2>/dev/null
    )" || true
  fi

  if [[ -n "$latest" ]] && have git \
    && git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    release_commit="$(git -C "$REPO_DIR" rev-parse "${latest}^{commit}" 2>/dev/null || true)"
    head_commit="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$release_commit" && -n "$head_commit" ]] \
      && git -C "$REPO_DIR" merge-base --is-ancestor "$release_commit" "$head_commit" 2>/dev/null; then
      printf '%s\n' "$latest"
      return 0
    fi
  fi

  printf '%s\n' unreleased
}

# ──────────────────────────────────────────────────────────────────────────────
# Awtarchy PolicyKit authentication agent
# ──────────────────────────────────────────────────────────────────────────────
AWTARCHY_POLKIT_RUNTIME_PARENT="/usr/local/libexec/awtarchy"
AWTARCHY_POLKIT_RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"
AWTARCHY_POLKIT_USER_UNIT_DIR="/usr/local/lib/systemd/user"
AWTARCHY_POLKIT_SERVICE_NAME="awtarchy-polkit-agent.service"
AWTARCHY_POLKIT_SERVICE_DEST="/usr/local/lib/systemd/user/awtarchy-polkit-agent.service"
AWTARCHY_GNOME_POLKIT_BIN="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"

awtarchy_polkit_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return
  fi
  have sudo || { warn "sudo is required to install the Awtarchy PolicyKit agent."; return 1; }
  sudo -- "$@"
}

awtarchy_polkit_verify_source_file() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || { warn "Unsafe PolicyKit source file: $path"; return 1; }
  [[ "$(stat -Lc '%F' -- "$path" 2>/dev/null)" == 'regular file' ]] \
    || { warn "PolicyKit source is not a regular file: $path"; return 1; }
}

awtarchy_polkit_verify_root_directory() {
  local path="$1" uid mode type mode_value
  awtarchy_polkit_root /usr/bin/test -d "$path" \
    && awtarchy_polkit_root /usr/bin/test ! -L "$path" \
    || { warn "Unsafe PolicyKit runtime directory: $path"; return 1; }
  IFS=' ' read -r uid mode type < <(awtarchy_polkit_root /usr/bin/stat -Lc '%u %a %F' -- "$path") || return 1
  [[ "$uid" == 0 && "$type" == directory ]] || { warn "PolicyKit runtime directory is not root-owned: $path"; return 1; }
  mode_value=$((8#$mode))
  (( (mode_value & 0022) == 0 )) || { warn "PolicyKit runtime directory is writable by group/other: $path"; return 1; }
}

awtarchy_polkit_verify_root_file() {
  local path="$1" expected_mode="$2" uid mode type
  awtarchy_polkit_root /usr/bin/test -f "$path" \
    && awtarchy_polkit_root /usr/bin/test ! -L "$path" \
    || { warn "Unsafe PolicyKit runtime file: $path"; return 1; }
  IFS=' ' read -r uid mode type < <(awtarchy_polkit_root /usr/bin/stat -Lc '%u %a %F' -- "$path") || return 1
  [[ "$uid" == 0 && "$mode" == "$expected_mode" && "$type" == 'regular file' ]] \
    || { warn "Unexpected owner/mode/type for PolicyKit runtime file: $path"; return 1; }
}

awtarchy_polkit_verify_runtime_tree() {
  local directory="$1" actual expected
  awtarchy_polkit_verify_root_directory "$directory" || return 1
  awtarchy_polkit_verify_root_file "${directory}/agent.py" 644 || return 1
  awtarchy_polkit_verify_root_file "${directory}/alacritty.toml" 644 || return 1
  awtarchy_polkit_verify_root_file "${directory}/launcher" 755 || return 1
  awtarchy_polkit_verify_root_file "${directory}/tui.py" 644 || return 1
  actual="$(awtarchy_polkit_root /usr/bin/find "$directory" -mindepth 1 -maxdepth 1 -printf '%f
' 2>/dev/null | LC_ALL=C sort)" || return 1
  expected=$'agent.py
alacritty.toml
launcher
tui.py'
  [[ "$actual" == "$expected" ]] || { warn "Unexpected files in Awtarchy PolicyKit runtime."; return 1; }
}

awtarchy_polkit_verify_runtime() {
  awtarchy_polkit_verify_runtime_tree "$AWTARCHY_POLKIT_RUNTIME_DIR" || return 1
  awtarchy_polkit_verify_root_file "$AWTARCHY_POLKIT_SERVICE_DEST" 644 || return 1
}

awtarchy_polkit_restore_install_transaction() {
  local previous_runtime="$1" failed_runtime="$2" previous_service="$3"
  if awtarchy_polkit_root /usr/bin/test -e "$AWTARCHY_POLKIT_RUNTIME_DIR"; then
    awtarchy_polkit_root /usr/bin/mv -Tf -- "$AWTARCHY_POLKIT_RUNTIME_DIR" "$failed_runtime" 2>/dev/null || true
  fi
  if [[ -n "$previous_runtime" ]] && awtarchy_polkit_root /usr/bin/test -e "$previous_runtime"; then
    awtarchy_polkit_root /usr/bin/mv -Tf -- "$previous_runtime" "$AWTARCHY_POLKIT_RUNTIME_DIR" 2>/dev/null || true
  fi
  awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$failed_runtime" 2>/dev/null || true
  if [[ -n "$previous_service" ]] && awtarchy_polkit_root /usr/bin/test -e "$previous_service"; then
    awtarchy_polkit_root /usr/bin/mv -Tf -- "$previous_service" "$AWTARCHY_POLKIT_SERVICE_DEST" 2>/dev/null || true
  fi
}

install_awtarchy_polkit_agent_runtime() {
  local repo_dir="$1"
  local source_dir="${repo_dir}/config/hypr/scripts/awtarchy-polkit-agent"
  local agent_source="${source_dir}/agent.py"
  local tui_source="${source_dir}/tui.py"
  local terminal_config_source="${source_dir}/alacritty.toml"
  local launcher_source="${source_dir}/launcher.sh"
  local service_source="${source_dir}/awtarchy-polkit-agent.service"
  local stage="" previous_runtime="" failed_runtime="" service_tmp="" previous_service=""

  awtarchy_polkit_verify_source_file "$agent_source" || return 1
  awtarchy_polkit_verify_source_file "$tui_source" || return 1
  awtarchy_polkit_verify_source_file "$terminal_config_source" || return 1
  awtarchy_polkit_verify_source_file "$launcher_source" || return 1
  awtarchy_polkit_verify_source_file "$service_source" || return 1
  bash -n "$launcher_source" || { warn "PolicyKit launcher failed Bash syntax validation."; return 1; }
  /usr/bin/python3 -c 'import ast,pathlib,sys; [ast.parse(pathlib.Path(p).read_text(encoding="utf-8"), filename=p) for p in sys.argv[1:]]' \
    "$agent_source" "$tui_source" || { warn "PolicyKit Python source failed syntax validation."; return 1; }

  awtarchy_polkit_root /usr/bin/install -d -m 0755 -o root -g root -- "$AWTARCHY_POLKIT_RUNTIME_PARENT" || return 1
  awtarchy_polkit_root /usr/bin/install -d -m 0755 -o root -g root -- "$AWTARCHY_POLKIT_USER_UNIT_DIR" || return 1
  awtarchy_polkit_verify_root_directory "$AWTARCHY_POLKIT_RUNTIME_PARENT" || return 1
  awtarchy_polkit_verify_root_directory "$AWTARCHY_POLKIT_USER_UNIT_DIR" || return 1

  stage="$(awtarchy_polkit_root /usr/bin/mktemp -d "${AWTARCHY_POLKIT_RUNTIME_PARENT}/.polkit-agent.stage.XXXXXX")" || return 1
  if ! awtarchy_polkit_root /usr/bin/install -m 0644 -o root -g root -- "$agent_source" "${stage}/agent.py" \
    || ! awtarchy_polkit_root /usr/bin/install -m 0644 -o root -g root -- "$tui_source" "${stage}/tui.py" \
    || ! awtarchy_polkit_root /usr/bin/install -m 0644 -o root -g root -- "$terminal_config_source" "${stage}/alacritty.toml" \
    || ! awtarchy_polkit_root /usr/bin/install -m 0755 -o root -g root -- "$launcher_source" "${stage}/launcher" \
    || ! awtarchy_polkit_root /usr/bin/chmod 0755 -- "$stage";
  then
    awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$stage" 2>/dev/null || true
    return 1
  fi
  awtarchy_polkit_verify_runtime_tree "$stage" || {
    awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$stage" 2>/dev/null || true
    return 1
  }

  if awtarchy_polkit_root /usr/bin/test -L "$AWTARCHY_POLKIT_RUNTIME_DIR"; then
    awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$stage" 2>/dev/null || true
    warn "Refusing symbolic-link Awtarchy PolicyKit runtime destination."
    return 1
  fi
  if awtarchy_polkit_root /usr/bin/test -e "$AWTARCHY_POLKIT_RUNTIME_DIR"; then
    [[ "$(awtarchy_polkit_root /usr/bin/stat -Lc '%F' -- "$AWTARCHY_POLKIT_RUNTIME_DIR")" == directory ]] || {
      awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$stage" 2>/dev/null || true
      return 1
    }
    previous_runtime="${AWTARCHY_POLKIT_RUNTIME_PARENT}/.polkit-agent.previous.$$"
    awtarchy_polkit_root /usr/bin/test ! -e "$previous_runtime" || return 1
    awtarchy_polkit_root /usr/bin/mv -Tf -- "$AWTARCHY_POLKIT_RUNTIME_DIR" "$previous_runtime" || return 1
  fi

  failed_runtime="${AWTARCHY_POLKIT_RUNTIME_PARENT}/.polkit-agent.failed.$$"
  if ! awtarchy_polkit_root /usr/bin/mv -Tf -- "$stage" "$AWTARCHY_POLKIT_RUNTIME_DIR"; then
    [[ -z "$previous_runtime" ]] || awtarchy_polkit_root /usr/bin/mv -Tf -- "$previous_runtime" "$AWTARCHY_POLKIT_RUNTIME_DIR" 2>/dev/null || true
    return 1
  fi

  if awtarchy_polkit_root /usr/bin/test -L "$AWTARCHY_POLKIT_SERVICE_DEST"; then
    awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" ""
    warn "Refusing symbolic-link Awtarchy PolicyKit service destination."
    return 1
  fi
  if awtarchy_polkit_root /usr/bin/test -e "$AWTARCHY_POLKIT_SERVICE_DEST"; then
    [[ "$(awtarchy_polkit_root /usr/bin/stat -Lc '%F' -- "$AWTARCHY_POLKIT_SERVICE_DEST")" == 'regular file' ]] \
      || { awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" ""; return 1; }
    previous_service="${AWTARCHY_POLKIT_USER_UNIT_DIR}/.awtarchy-polkit-agent.service.previous.$$"
    awtarchy_polkit_root /usr/bin/test ! -e "$previous_service" || return 1
    awtarchy_polkit_root /usr/bin/mv -Tf -- "$AWTARCHY_POLKIT_SERVICE_DEST" "$previous_service" || return 1
  fi

  service_tmp="$(awtarchy_polkit_root /usr/bin/mktemp "${AWTARCHY_POLKIT_USER_UNIT_DIR}/.awtarchy-polkit-agent.service.XXXXXX")" || {
    awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" "$previous_service"
    return 1
  }
  if ! awtarchy_polkit_root /usr/bin/install -m 0644 -o root -g root -- "$service_source" "$service_tmp" \
    || ! awtarchy_polkit_root /usr/bin/mv -Tf -- "$service_tmp" "$AWTARCHY_POLKIT_SERVICE_DEST";
  then
    awtarchy_polkit_root /usr/bin/rm -f -- "$service_tmp" 2>/dev/null || true
    awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" "$previous_service"
    return 1
  fi

  if ! awtarchy_polkit_verify_runtime; then
    awtarchy_polkit_restore_install_transaction "$previous_runtime" "$failed_runtime" "$previous_service"
    warn "Awtarchy PolicyKit runtime verification failed."
    return 1
  fi

  [[ -z "$previous_runtime" ]] || awtarchy_polkit_root /usr/bin/rm -rf --one-file-system -- "$previous_runtime" || return 1
  [[ -z "$previous_service" ]] || awtarchy_polkit_root /usr/bin/rm -f -- "$previous_service" || return 1
  log "Installed root-owned Awtarchy terminal PolicyKit authentication runtime."
}

migrate_awtarchy_polkit_autostart() {
  local rel=".config/hypr/hyprland.lua"
  local file="${HOME_DIR}/${rel}" tmp="" count_old count_new item already_changed=0
  local old='    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")'
  local new='    hl.exec_cmd("/usr/bin/systemctl --user restart awtarchy-polkit-agent.service")'

  [[ -f "$file" && ! -L "$file" ]] || { warn "Hyprland config is unavailable for PolicyKit migration: $file"; return 2; }
  count_old="$(grep -Fxc -- "$old" "$file" || true)"
  count_new="$(grep -Fxc -- "$new" "$file" || true)"

  if (( count_new == 1 && count_old == 0 )); then
    return 0
  fi
  if (( count_old != 1 || count_new != 0 )); then
    warn "Hyprland has custom PolicyKit startup; leaving that custom startup untouched."
    return 2
  fi

  tmp="$(mktemp)"
  awk -v old="$old" -v new="$new" '{ if ($0 == old) print new; else print }' "$file" >"$tmp"

  for item in "${CHANGED[@]:-}"; do
    [[ "$item" == "$rel" ]] && already_changed=1
  done
  if (( already_changed == 0 )); then
    snapshot_for_rollback "$rel" "$file"
    ROLLBACK_PATHS+=("$rel")
    make_persistent_backup "$file"
    CHANGED+=("$rel")
  fi
  if ! validate_candidate "$tmp" "$rel" || ! atomic_copy "$tmp" "$file"; then
    rm -f -- "$tmp"
    return 1
  fi
  rm -f -- "$tmp"
  log "Migrated Hyprland from polkit-gnome to the Awtarchy PolicyKit service."
}

awtarchy_polkit_target_uid() {
  id -u "$TARGET_USER" 2>/dev/null
}

awtarchy_polkit_user_command() {
  local target_uid runtime_dir
  target_uid="$(awtarchy_polkit_target_uid)" || return 1
  runtime_dir="/run/user/${target_uid}"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    runuser -u "$TARGET_USER" -- /usr/bin/env \
      HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
      XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
      "$@"
  else
    /usr/bin/env HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
      XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
      "$@"
  fi
}

awtarchy_polkit_recover_session_environment() {
  local target_uid runtime_dir line key value
  target_uid="$(awtarchy_polkit_target_uid)" || return 1
  runtime_dir="/run/user/${target_uid}"
  if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "$runtime_dir" ]]; then
    export XDG_RUNTIME_DIR="$runtime_dir"
  fi
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "${runtime_dir}/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus"
  fi

  if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -n "${XDG_SESSION_ID:-}" ]]; then
    return 0
  fi

  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ -n "$value" ]] || continue

    case "$key" in
      WAYLAND_DISPLAY)
        [[ -n "${WAYLAND_DISPLAY:-}" ]] || export WAYLAND_DISPLAY="$value"
        ;;
      HYPRLAND_INSTANCE_SIGNATURE)
        [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || export HYPRLAND_INSTANCE_SIGNATURE="$value"
        ;;
      XDG_SESSION_ID)
        [[ -n "${XDG_SESSION_ID:-}" ]] || export XDG_SESSION_ID="$value"
        ;;
      XDG_CURRENT_DESKTOP)
        [[ -n "${XDG_CURRENT_DESKTOP:-}" ]] || export XDG_CURRENT_DESKTOP="$value"
        ;;
      XDG_SESSION_DESKTOP)
        [[ -n "${XDG_SESSION_DESKTOP:-}" ]] || export XDG_SESSION_DESKTOP="$value"
        ;;
      XDG_SESSION_TYPE)
        [[ -n "${XDG_SESSION_TYPE:-}" ]] || export XDG_SESSION_TYPE="$value"
        ;;
    esac
  done < <(awtarchy_polkit_user_command /usr/bin/systemctl --user show-environment 2>/dev/null || true)

  [[ -n "${WAYLAND_DISPLAY:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -n "${XDG_SESSION_ID:-}" ]]
}

awtarchy_polkit_get_gnome_pids() {
  local target_uid pid resolved
  target_uid="$(awtarchy_polkit_target_uid)" || return 1
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
    resolved="$(readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || continue
    [[ "$resolved" == "$AWTARCHY_GNOME_POLKIT_BIN" ]] || continue
    printf '%s\n' "$pid"
  done < <(pgrep -u "$target_uid" -f -- "$AWTARCHY_GNOME_POLKIT_BIN" 2>/dev/null || true)
}

awtarchy_polkit_stop_gnome() {
  local pid attempt active=""
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -TERM -- "$pid" 2>/dev/null || awtarchy_polkit_root /usr/bin/kill -TERM -- "$pid" 2>/dev/null || true
  done < <(awtarchy_polkit_get_gnome_pids)
  for attempt in {1..40}; do
    active="$(awtarchy_polkit_get_gnome_pids)"
    [[ -z "$active" ]] && return 0
    sleep 0.05
  done
  warn "Could not stop the exact polkit-gnome agent process."
  return 1
}

restore_legacy_polkit_gnome() {
  local target_uid runtime_dir attempt active=""
  [[ -x "$AWTARCHY_GNOME_POLKIT_BIN" && -f "$AWTARCHY_GNOME_POLKIT_BIN" && ! -L "$AWTARCHY_GNOME_POLKIT_BIN" ]] || return 1
  active="$(awtarchy_polkit_get_gnome_pids)"
  [[ -n "$active" ]] && return 0
  target_uid="$(awtarchy_polkit_target_uid)" || return 1
  runtime_dir="/run/user/${target_uid}"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    runuser -u "$TARGET_USER" -- /usr/bin/env HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
      XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
      WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-}" \
      /usr/bin/nohup "$AWTARCHY_GNOME_POLKIT_BIN" </dev/null >/dev/null 2>&1 &
  else
    /usr/bin/nohup "$AWTARCHY_GNOME_POLKIT_BIN" </dev/null >/dev/null 2>&1 &
  fi
  for attempt in {1..60}; do
    active="$(awtarchy_polkit_get_gnome_pids)"
    [[ -n "$active" ]] && return 0
    sleep 0.05
  done
  return 1
}

awtarchy_polkit_process_tree_has_agent() {
  local root_pid="$1" expected_python parent children_raw child child_exe
  local -a queue=() children=() argv=()
  expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)" || return 1
  queue=("$root_pid")

  while (( ${#queue[@]} > 0 )); do
    parent="${queue[0]}"
    queue=("${queue[@]:1}")
    children_raw=""
    if [[ -r "/proc/${parent}/task/${parent}/children" ]]; then
      IFS= read -r children_raw <"/proc/${parent}/task/${parent}/children" || true
    fi
    children=()
    IFS=' ' read -r -a children <<<"$children_raw"
    for child in "${children[@]}"; do
      [[ "$child" =~ ^[1-9][0-9]*$ ]] || continue
      queue+=("$child")
      child_exe="$(/usr/bin/readlink -f -- "/proc/${child}/exe" 2>/dev/null)" || continue
      [[ "$child_exe" == "$expected_python" ]] || continue
      argv=()
      mapfile -d '' -t argv <"/proc/${child}/cmdline" 2>/dev/null || continue
      if [[ "${argv[0]:-}" == /usr/bin/python3 \
        && "${argv[1]:-}" == -I \
        && "${argv[2]:-}" == "${AWTARCHY_POLKIT_RUNTIME_DIR}/agent.py" ]];
      then
        return 0
      fi
    done
  done
  return 1
}

awtarchy_polkit_verify_service_process() {
  local pid resolved expected_python
  local -a argv=()
  pid="$(awtarchy_polkit_user_command /usr/bin/systemctl --user show -p MainPID --value "$AWTARCHY_POLKIT_SERVICE_NAME" 2>/dev/null)" || return 1
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)" || return 1
  resolved="$(/usr/bin/readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || return 1
  [[ "$resolved" == "$expected_python" ]] || return 1
  mapfile -d '' -t argv <"/proc/${pid}/cmdline" 2>/dev/null || return 1
  [[ "${argv[0]:-}" == /usr/bin/python3 \
    && "${argv[1]:-}" == -I \
    && "${argv[2]:-}" == "${AWTARCHY_POLKIT_RUNTIME_DIR}/agent.py" ]]
}

activate_awtarchy_polkit_agent() {
  local target_uid runtime_dir attempt restarts activation_rc=0
  target_uid="$(awtarchy_polkit_target_uid)" || return 1
  runtime_dir="/run/user/${target_uid}"

  awtarchy_polkit_recover_session_environment || return 2
  [[ -S "${runtime_dir}/bus" && -n "${WAYLAND_DISPLAY:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -n "${XDG_SESSION_ID:-}" ]] || return 2
  awtarchy_polkit_verify_runtime || return 1

  awtarchy_polkit_user_command /usr/bin/env \
    WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" \
    XDG_SESSION_ID="$XDG_SESSION_ID" \
    XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}" \
    XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}" \
    /usr/bin/systemctl --user import-environment \
    WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_ID XDG_CURRENT_DESKTOP XDG_SESSION_TYPE >/dev/null || return 1

  awtarchy_polkit_user_command /usr/bin/systemctl --user daemon-reload || return 1
  awtarchy_polkit_user_command /usr/bin/systemctl --user disable "$AWTARCHY_POLKIT_SERVICE_NAME" >/dev/null 2>&1 || true
  awtarchy_polkit_user_command /usr/bin/systemctl --user stop "$AWTARCHY_POLKIT_SERVICE_NAME" >/dev/null 2>&1 || true
  awtarchy_polkit_user_command /usr/bin/systemctl --user reset-failed "$AWTARCHY_POLKIT_SERVICE_NAME" >/dev/null 2>&1 || true
  awtarchy_polkit_stop_gnome || return 1

  if ! awtarchy_polkit_user_command /usr/bin/systemctl --user start "$AWTARCHY_POLKIT_SERVICE_NAME"; then
    restore_legacy_polkit_gnome || true
    return 1
  fi

  for attempt in {1..25}; do
    if ! awtarchy_polkit_user_command /usr/bin/systemctl --user is-active --quiet "$AWTARCHY_POLKIT_SERVICE_NAME"; then
      activation_rc=1
      break
    fi
    sleep 0.20
  done
  restarts="$(awtarchy_polkit_user_command /usr/bin/systemctl --user show -p NRestarts --value "$AWTARCHY_POLKIT_SERVICE_NAME" 2>/dev/null || printf 'unknown')"
  if (( activation_rc != 0 )) || [[ ! "$restarts" =~ ^[0-9]+$ || "$restarts" -ne 0 ]] || ! awtarchy_polkit_verify_service_process; then
    awtarchy_polkit_user_command /usr/bin/systemctl --user stop "$AWTARCHY_POLKIT_SERVICE_NAME" >/dev/null 2>&1 || true
    restore_legacy_polkit_gnome || true
    warn "Awtarchy PolicyKit agent failed live activation; polkit-gnome was restored."
    return 1
  fi
  log "Awtarchy PolicyKit authentication agent is active."
}

remove_legacy_polkit_gnome_package() {
  local manifest tmp
  [[ -z "${TESTING_BRANCH:-}" ]] || { log "Git testing keeps polkit-gnome installed as an inactive emergency fallback."; return 0; }
  managed_package_recorded polkit-gnome || { log "polkit-gnome is not recorded as Awtarchy-owned; leaving the package installed but inactive."; return 0; }
  pacman -Qq polkit-gnome >/dev/null 2>&1 || return 0
  run_update_root /usr/bin/pacman -Rns --noconfirm polkit-gnome || { warn "Could not remove retired Awtarchy-owned polkit-gnome; leaving it installed but inactive."; return 0; }
  manifest="$(managed_packages_file)"
  [[ -r "$manifest" ]] || return 0
  tmp="$(mktemp)"
  grep -Fxv polkit-gnome "$manifest" >"$tmp" || true
  if ! cat -- "$tmp" | atomic_update_root_file_from_stdin 0644 0 0 "$manifest"; then
    rm -f -- "$tmp"
    warn "Removed polkit-gnome but could not update the Awtarchy package ownership manifest."
    return 0
  fi
  rm -f -- "$tmp"
  log "Removed retired Awtarchy-owned polkit-gnome package."
}

install_awtarchy_command_stage() {
  local install_dir="${HOME_DIR}/.local/share/awtarchy"
  local bin_dir="${HOME_DIR}/.local/bin"
  local state_dir="${HOME_DIR}/.local/state/awtarchy"
  local command_version_file="${state_dir}/command-version"
  local config_version_file="${state_dir}/config-version"
  local runtime_src="${REPO_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
  local launcher_src="${REPO_DIR}/local/bin/awtarchy"
  local tag="" revision="" version_tmp=""

  [[ -f "$runtime_src" ]] || die "Missing Awtarchy runtime: ${runtime_src}"
  [[ -f "$launcher_src" ]] || die "Missing Awtarchy command: ${launcher_src}"
  bash -n "$runtime_src" || die "Awtarchy runtime failed Bash syntax validation."
  bash -n "$launcher_src" || die "Awtarchy command failed Bash syntax validation."

  create_directory "$install_dir"
  create_directory "$bin_dir"
  create_directory "$state_dir"

  retry_command run_as_target install -m 0755 "$runtime_src" "${install_dir}/awtarchy-runtime.sh"
  retry_command run_as_target install -m 0755 "$launcher_src" "${bin_dir}/awtarchy"

  tag="$(detect_installed_release_tag)"
  if have git && git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    revision="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)"
  fi

  version_tmp="$(run_as_target mktemp --tmpdir="$state_dir" '.version.tmp.XXXXXX')"
  {
    printf 'tag=%s\n' "$tag"
    [[ -n "$revision" ]] && printf 'revision=%s\n' "$revision"
    printf 'installed_at=%s\n' "$(date -Iseconds)"
  } | run_as_target tee "$version_tmp" >/dev/null
  retry_command run_as_target install -m 0644 "$version_tmp" "$command_version_file"
  retry_command run_as_target install -m 0644 "$version_tmp" "$config_version_file"
  run_as_target rm -f -- "$version_tmp"

  if [[ "${AWTARCHY_SKIP_SELF_UPDATE:-0}" != "1" ]]; then
    log "Verifying the installed Awtarchy command against the current main updater..."
    if ! run_as_target env -u XDG_DATA_HOME -u XDG_STATE_HOME \
      HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
      "${bin_dir}/awtarchy" self-update
    then
      die "Could not verify the installed Awtarchy command against the current main updater."
    fi
  else
    log "Keeping the unreleased Quickshell conversion runtime installed for testing."
  fi

  ok "Installed Awtarchy command: ${bin_dir}/awtarchy"
}

copy_awtarchy_configs_stage() {
  log "Copying Awtarchy configuration files..."
  create_directory "${HOME_DIR}/.config"

  local config_file
  for config_file in bashrc bash_profile; do
    local src="${REPO_DIR}/${config_file}"
    local dest="${HOME_DIR}/.${config_file}"
    [[ -f "$src" ]] || { warn "Missing ${src}. Skipping."; continue; }
    if [[ -f "$dest" ]]; then
      if [[ "$config_file" == "bashrc" && "$OVERWRITE_BASHRC" != "1" ]]; then warn "Keeping existing ${dest}"; continue; fi
      if [[ "$config_file" == "bash_profile" && "$OVERWRITE_BASH_PROFILE" != "1" ]]; then warn "Keeping existing ${dest}"; continue; fi
    fi
    retry_command run_as_target cp -- "$src" "$dest"
    if findmnt -n -o FSTYPE / | grep -qi btrfs; then
      run_as_target sed -i '/alias flatpak=.flatpak --user./ s/^/#/' "$dest" || true
    fi
    retry_command run_as_target chmod 0644 "$dest"
  done

  local -a config_dirs=(hypr quickshell alacritty gtk-3.0 Kvantum SpeedCrunch fastfetch pcmanfm-qt yazi xdg-desktop-portal qt5ct qt6ct lsfg-vk wiremix cava micro ddcutil)
  local dir
  for dir in "${config_dirs[@]}"; do
    if [[ -d "${REPO_DIR}/config/${dir}" ]]; then
      retry_command run_as_target cp -r -- "${REPO_DIR}/config/${dir}" "${HOME_DIR}/.config/" || exit 1
    else
      warn "Missing config/${dir}; skipping."
    fi
  done

  create_directory "${HOME_DIR}/.local/share/nwg-look"
  create_directory "${HOME_DIR}/.local/share/SpeedCrunch"
  create_directory "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes"

  [[ -f "${REPO_DIR}/Xresources" ]] && retry_command run_as_target cp -- "${REPO_DIR}/Xresources" "${HOME_DIR}/.Xresources"
  [[ -f "${REPO_DIR}/config/mimeapps.list" ]] && retry_command run_as_target cp -- "${REPO_DIR}/config/mimeapps.list" "${HOME_DIR}/.config/"
  [[ -f "${REPO_DIR}/config/gamemode.ini" ]] && retry_command run_as_target cp -- "${REPO_DIR}/config/gamemode.ini" "${HOME_DIR}/.config/"
  [[ -f "${REPO_DIR}/local/share/nwg-look/gsettings" ]] && retry_command run_as_target cp -- "${REPO_DIR}/local/share/nwg-look/gsettings" "${HOME_DIR}/.local/share/nwg-look/"

  run_as_target chmod 0644 \
    "${HOME_DIR}/.Xresources" \
    "${HOME_DIR}/.config/mimeapps.list" \
    "${HOME_DIR}/.config/gamemode.ini" \
    "${HOME_DIR}/.local/share/nwg-look/gsettings" 2>/dev/null || true

  if compgen -G "${REPO_DIR}/local/share/SpeedCrunch/color-schemes/*.json" >/dev/null; then
    retry_command run_as_target cp "${REPO_DIR}/local/share/SpeedCrunch/color-schemes/"*.json "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes/"
    run_as_target chmod 0644 "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes/"*.json || true
  fi

  create_directory "${HOME_DIR}/.local/share/applications"
  if [[ -d "${REPO_DIR}/local/share/applications" ]]; then
    retry_command run_as_target cp -r "${REPO_DIR}/local/share/applications/." "${HOME_DIR}/.local/share/applications"
    run_as_target find "${HOME_DIR}/.local/share/applications" -type d -exec chmod 0755 {} +
    run_as_target find "${HOME_DIR}/.local/share/applications" -type f -exec chmod 0644 {} +
  fi

  local cursor_theme
  for cursor_theme in Bibata-Modern-Ice Bibata-Modern-Classic; do
    create_directory "${HOME_DIR}/.local/share/icons/${cursor_theme}"
    if [[ -d "/usr/share/icons/${cursor_theme}" ]]; then
      retry_command run_as_target cp -r "/usr/share/icons/${cursor_theme}/." "${HOME_DIR}/.local/share/icons/${cursor_theme}/"
      run_as_target find "${HOME_DIR}/.local/share/icons/${cursor_theme}" -type d -exec chmod 0755 {} +
      run_as_target find "${HOME_DIR}/.local/share/icons/${cursor_theme}" -type f -exec chmod 0644 {} +
    fi
  done

  install -d -m 755 /usr/share/icons/default
  cat > /usr/share/icons/default/index.theme <<'EOF'
[Icon Theme]
Inherits=Bibata-Modern-Ice
EOF
  chmod 644 /usr/share/icons/default/index.theme

  if have flatpak; then
    run_as_target flatpak override --user --env=GTK_CURSOR_THEME=Bibata-Modern-Ice || true
  fi

  create_directory "${HOME_DIR}/Pictures/wallpapers"
  create_directory "${HOME_DIR}/Pictures/Screenshots"
  local -a wallpapers=(awtarchy_geology.png awtarchy_space.png)
  local wallpaper
  for wallpaper in "${wallpapers[@]}"; do
    [[ -f "${REPO_DIR}/${wallpaper}" ]] || { warn "Missing ${wallpaper}; skipping."; continue; }
    retry_command run_as_target cp -- "${REPO_DIR}/${wallpaper}" "${HOME_DIR}/Pictures/wallpapers/"
    run_as_target chmod 0644 "${HOME_DIR}/Pictures/wallpapers/${wallpaper}"
  done

  for dir in "${config_dirs[@]}"; do
    [[ -d "${HOME_DIR}/.config/${dir}" ]] || continue
    run_as_target find "${HOME_DIR}/.config/${dir}" -type d -exec chmod 0755 {} + 2>/dev/null || true
    run_as_target find "${HOME_DIR}/.config/${dir}" -type f -exec chmod 0644 {} + 2>/dev/null || true
  done
  if [[ -d "${HOME_DIR}/.config/hypr/scripts" ]]; then
    run_as_target find "${HOME_DIR}/.config/hypr/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
  fi
  if [[ -d "${HOME_DIR}/.config/hypr/themes" ]]; then
    run_as_target find "${HOME_DIR}/.config/hypr/themes" -type f -exec chmod +x {} + 2>/dev/null || true
  fi
}


remove_legacy_shell_packages_stage() {
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
  local marker="${HOME_DIR}/.local/state/awtarchy/quickshell-connectivity-migration-complete"
  local pkg tmp installed_names remaining_names cleanup_ok=1
  local -a obsolete=(waybar waybar-git fuzzel wlogout mako wofi network-manager-applet blueman)
  local -a installed=()

  if ! installed_names="$(pacman -Qq 2>/dev/null)"; then
    warn "Could not query exact installed package names; retired shell package cleanup will retry later."
    return 0
  fi
  for pkg in "${obsolete[@]}"; do
    grep -Fxq -- "$pkg" <<<"$installed_names" && installed+=("$pkg")
  done

  for pkg in "${installed[@]}"; do
    log "Removing retired Awtarchy shell package: ${pkg}"
    if pacman -Rns --noconfirm "$pkg"; then
      if [[ -f "$managed_file" ]]; then
        tmp="$(mktemp)"
        grep -Fxv "$pkg" "$managed_file" >"$tmp" || true
        cat "$tmp" >"$managed_file"
        rm -f "$tmp"
      fi
    else
      cleanup_ok=0
      warn "Could not remove retired package ${pkg}; continuing conversion."
    fi
  done

  if (( cleanup_ok == 1 )); then
    if ! remaining_names="$(pacman -Qq 2>/dev/null)"; then
      cleanup_ok=0
    fi
    for pkg in "${obsolete[@]}"; do
      grep -Fxq -- "$pkg" <<<"$remaining_names" && cleanup_ok=0
    done
  fi

  if (( cleanup_ok == 1 )); then
    run_as_target install -d -m 0755 "$(dirname "$marker")"
    run_as_target touch "$marker"
    run_as_target chmod 0644 "$marker"
  fi
}


remove_legacy_shell_path_stage() {
  local dest="$1" candidate

  for candidate in "$dest" "${dest}.backup" "${dest}.backup."*; do
    [[ -e "$candidate" || -L "$candidate" ]] || continue
    run_as_target rm -rf -- "$candidate"
  done
}

remove_legacy_shell_files_stage() {
  local scripts_dir="${HOME_DIR}/.config/hypr/scripts"
  local applications_dir="${HOME_DIR}/.local/share/applications"
  local obsolete

  for obsolete in \
    "${HOME_DIR}/.config/waybar" \
    "${HOME_DIR}/.config/fuzzel" \
    "${HOME_DIR}/.config/mako" \
    "${HOME_DIR}/.config/wlogout" \
    "${HOME_DIR}/.config/wofi" \
    "${HOME_DIR}/.cache/waybar" \
    "${HOME_DIR}/.cache/fuzzel" \
    "${HOME_DIR}/.cache/wofi"
  do
    remove_legacy_shell_path_stage "$obsolete"
  done

  for obsolete in "${HOME_DIR}/.cache/wofi-"*; do
    [[ -e "$obsolete" || -L "$obsolete" ]] || continue
    remove_legacy_shell_path_stage "$obsolete"
  done

  for obsolete in \
    cliphist-fuzzel.sh \
    cliphist-wofi.sh \
    fuzzel_toggle.sh \
    mako_dismiss.sh \
    waybar.sh \
    waybar_flip.sh \
    waybar_ready_sound.sh \
    waybar_restore_resume.sh \
    waybar_rotate.sh \
    waybar_toggle.sh \
    waybar_toggle_idle.sh \
    wlogout_toggle.sh
  do
    remove_legacy_shell_path_stage "${scripts_dir}/${obsolete}"
  done

  for obsolete in \
    hypr_quicksettings.desktop \
    waybar_flip.desktop \
    waybar_rotate.desktop \
    waybar_toggle.desktop
  do
    remove_legacy_shell_path_stage "${applications_dir}/${obsolete}"
  done
}

run_install() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-reboot) NO_REBOOT=1; shift ;;
      --dry-run|--test) DRY_RUN=1; NO_REBOOT=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) die "Unknown install option: $1" ;;
    esac
  done

  local rc
  set +e
  run_install_questionnaire
  rc=$?
  set -e
  if (( rc != 0 )); then
    if (( rc == 2 )); then
      if (( TOP_MENU_ACTIVE == 0 )); then
        top_menu
      fi
      return 2
    fi
    return "$rc"
  fi
  if (( DRY_RUN == 1 )); then
    print_install_dry_run_plan
    return 0
  fi
  prepare_base_install
  install_arch_repo_apps_stage
  migrate_cheese_to_snapshot_stage \
    "${REPO_DIR}/local/share/awtarchy/awtarchy-package-reconcile.sh" \
    "${BASH_SOURCE[0]}"
  if [[ "$IS_LAPTOP" == true && "$IS_VM" == false ]]; then
    reconcile_power_profile_backend "$REPO_DIR"
  fi
  install_aur_repo_apps_stage
  install_flatpak_apps_stage
  install_alacritty_themes_stage
  if [[ "$INSTALL_GPU" == 1 && "$IS_VM" == false ]]; then
    install_gpu_dependencies_main
  else
    warn "Skipping GPU driver automation."
  fi
  install_micro_themes_stage
  enable_keyring_pam_stage
  install_ly_stage
  if (( INSTALL_LY == 1 )); then
    cleanup_legacy_keyring_pam_stage "$REPO_DIR"
  fi
  copy_awtarchy_configs_stage
  install_awtarchy_polkit_agent_runtime "$REPO_DIR" || die "Could not install the Awtarchy PolicyKit authentication runtime."
  remove_legacy_shell_files_stage
  install_awtarchy_command_stage
  remove_legacy_shell_packages_stage
  migrate_retired_hyprlock_stage "$REPO_DIR"

  ok "Setup complete. Rebooting now."
  if (( NO_REBOOT == 1 )) || [[ "${AWTARCHY_NO_REBOOT:-0}" == "1" ]]; then
    warn "Reboot skipped because --no-reboot or AWTARCHY_NO_REBOOT=1 was set."
  else
    sleep 1
    reboot
  fi
}

run_backup_cleaner_entry() {
  if [[ "${EUID}" -eq 0 ]]; then
    local target=""
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      target="${SUDO_USER}"
    else
      target="$(awk -F: '$3>=1000 && $1!="nobody"{print $1; exit}' /etc/passwd || true)"
    fi
    [[ -n "$target" ]] || die "Could not determine normal user for backup cleaner."
    exec runuser -u "$target" -- bash "${BASH_SOURCE[0]}" __backup-cleaner "$@"
  fi
  update_backup_cleaner_main "$@"
}

top_menu() {
  local choice rc
  TOP_MENU_ACTIVE=1

  while true; do
    choice="$(single_select_menu "Awtarchy" 0 \
      "Install Awtarchy" \
      "Dry-run Awtarchy install plan" \
      "Update configs (preserve Hyprland customizations)" \
      "Reset configs (clean-slate managed files)" \
      "Clean Awtarchy backup files" \
      "Exit")" || exit 0

    case "$choice" in
      0)
        if run_install; then
          :
        else
          rc=$?
          (( rc == 2 )) || return "$rc"
        fi
        ;;
      1)
        if run_install --dry-run; then
          :
        else
          rc=$?
          (( rc == 2 )) || return "$rc"
        fi
        ;;
      2)
        update_reset_backup_main --mode preserve
        ;;
      3)
        update_reset_backup_main --mode clean
        ;;
      4)
        run_backup_cleaner_entry
        ;;
      *)
        exit 0
        ;;
    esac
  done
}

install_gpu_dependencies_main() {
set -euo pipefail
IFS=$'\n\t'

# install_GPU_dependencies.sh
# - Safe when called from a root-run install.sh (sudo)
# - Detects AMD/Intel/NVIDIA and installs correct Vulkan stack
# - NVIDIA:
#   - Uses nvidia-open* from official repos for modern GPUs (Turing+/RTX/GTX16 and newer)
#   - Uses AUR legacy branches when NVIDIA legacy page indicates (470/390/340)
#   - Uses 580xx (AUR) for Pascal/Maxwell/Volta class GPUs (per Arch 590 transition notice)
# - Removes conflicting NVIDIA packages before switching
# - Ensures modeset:
#     * modprobe:  options nvidia_drm modeset=1
#     * bootloader cmdline: nvidia-drm.modeset=1 (adds if missing)
# - Rebuilds initramfs (mkinitcpio/dracut)
# - Patches Hyprland config NVIDIA env lines (best-effort; no cursor no_hardware_cursors edits)
# - Dry-run/testing:
#     * --dry-run/--test prints a plan + every command that would run, without changing the system
#     * --nvidia/--amd/--intel forces a GPU path (useful for testing without hardware detection)

ts(){ date +%F_%H%M%S; }
log(){ printf '%s\n' "$*"; }
warn(){ printf 'WARN: %s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

DO_UPGRADE=0
INSTALL_LIB32=1
INSTALL_OPENCL=0
PATCH_BOOTLOADERS=0
WRITE_MODPROBE_MODESET=1
WRITE_BLACKLIST_NOUVEAU=1
PATCH_MKINITCPIO_MODULES=0

DRY_RUN=0
FORCE_GPU=""
NVIDIA_TOUCHED=0

KPARAM_A="nvidia-drm.modeset=1"
KPARAM_B="nvidia_drm.modeset=1" # accepted if user already has it, but we add hyphen form

usage(){
  cat >&2 <<'EOF'
Usage: install_GPU_dependencies.sh [options]
  --upgrade                  pacman -Syu (default: off)
  --no-lib32                 skip lib32 packages
  --opencl                   attempt OpenCL packages
  --dry-run, --test          print plan + actions; do not install/remove/write/rebuild
  --nvidia                   force NVIDIA path (skips lspci detection + legacy branch lookup)
  --amd                      force AMD path (skips lspci detection)
  --intel                    force Intel path (skips lspci detection)
  --no-bootloader-patch      do not patch systemd-boot/grub/limine cmdline
  --no-modprobe-modeset      do not write /etc/modprobe.d/nvidia-drm.conf
  --no-blacklist-nouveau     do not write /etc/modprobe.d/blacklist-nouveau.conf
  --no-mkinitcpio-modules    do not edit mkinitcpio MODULES for early NVIDIA modules
EOF
}

while (($#)); do
  case "$1" in
    -h|--help) usage; return 0 ;;
    --upgrade) DO_UPGRADE=1; shift ;;
    --no-lib32) INSTALL_LIB32=0; shift ;;
    --opencl) INSTALL_OPENCL=1; shift ;;
    --dry-run|--test) DRY_RUN=1; shift ;;
    --nvidia) FORCE_GPU="nvidia"; shift ;;
    --amd) FORCE_GPU="amd"; shift ;;
    --intel) FORCE_GPU="intel"; shift ;;
    --no-bootloader-patch) PATCH_BOOTLOADERS=0; shift ;;
    --no-modprobe-modeset) WRITE_MODPROBE_MODESET=0; shift ;;
    --no-blacklist-nouveau) WRITE_BLACKLIST_NOUVEAU=0; shift ;;
    --no-mkinitcpio-modules) PATCH_MKINITCPIO_MODULES=0; shift ;;
    *) warn "Ignoring unknown arg: $1"; shift ;;
  esac
done

print_cmd(){
  printf 'DRY-RUN: '
  printf '%q ' "$@"
  printf '\n'
}

# ---------- privilege + user context ----------
EUID_NOW="${EUID:-$(id -u)}"
RUN_USER=""
USER_HOME=""

pick_run_user_from_getent(){
  # first real user (uid>=1000) that isn't nologin/false
  getent passwd | awk -F: '
    $3>=1000 && $1!="nobody" && $7!~/(nologin|false)$/ {print $1; exit}
  '
}

if [[ "$EUID_NOW" -eq 0 ]]; then
  RUN_USER="${SUDO_USER:-}"
  if [[ -z "$RUN_USER" || "$RUN_USER" == "root" ]]; then
    RUN_USER="$(pick_run_user_from_getent || true)"
  fi
else
  RUN_USER="${USER:-}"
fi

[[ -n "$RUN_USER" ]] || die "Unable to determine RUN_USER (non-root user) for AUR builds."

USER_HOME="$(getent passwd "$RUN_USER" | awk -F: '{print $6}')"
[[ -n "$USER_HOME" ]] || die "Unable to determine HOME for user: $RUN_USER"

as_root(){
  if (( DRY_RUN )); then
    print_cmd "$@"
    return 0
  fi
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    have sudo || die "sudo not found"
    sudo -v
    sudo "$@"
  fi
}

as_user(){
  if (( DRY_RUN )); then
    printf 'DRY-RUN: (as_user %s) ' "${RUN_USER:-?}"
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    have sudo || die "sudo not found (needed to run as $RUN_USER)"
    sudo -u "$RUN_USER" -H env HOME="$USER_HOME" USER="$RUN_USER" LOGNAME="$RUN_USER" "$@"
  else
    "$@"
  fi
}

backup_root_file(){
  local f
  f="$1"
  [[ -f "$f" ]] || return 0
  as_root cp -a "$f" "${f}.bak.$(ts)"
}

multilib_enabled(){
  [[ -f /etc/pacman.conf ]] || return 1
  awk '
    $0 ~ /^[[:space:]]*#/{next}
    $0 ~ /^\[multilib\]/{found=1}
    found && $0 ~ /^Include[[:space:]]*=/{ok=1}
    END{exit (ok?0:1)}
  ' /etc/pacman.conf
}

pacman_install(){
  local -a newly_managed=()
  local package=""
  for package in "$@"; do
    pacman -Qq "$package" >/dev/null 2>&1 || newly_managed+=("$package")
  done

  as_root pacman -S --needed --noconfirm "$@"

  if (( ${#newly_managed[@]} )); then
    as_root install -d -m 0755 /var/lib/awtarchy
    as_root touch /var/lib/awtarchy/managed-packages
    for package in "${newly_managed[@]}"; do
      pacman -Qq "$package" >/dev/null 2>&1 || continue
      if ! grep -Fxq "$package" /var/lib/awtarchy/managed-packages 2>/dev/null; then
        printf '%s\n' "$package" | as_root tee -a /var/lib/awtarchy/managed-packages >/dev/null
      fi
    done
    as_root sh -c 'LC_ALL=C sort -u -o /var/lib/awtarchy/managed-packages /var/lib/awtarchy/managed-packages && chmod 0644 /var/lib/awtarchy/managed-packages'
  fi
}

pacman_remove(){
  as_root pacman -Rns --noconfirm "$@"
}

ensure_tools(){
  pacman_install git base-devel curl pciutils
}

detect_gpu_lines(){
  if [[ -n "${FORCE_GPU:-}" ]]; then
    return 0
  fi
  if ! have lspci; then
    if (( DRY_RUN )); then
      warn "lspci not found; in dry-run, use --nvidia/--amd/--intel for deterministic testing."
      return 0
    fi
    pacman_install pciutils
  fi
  lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller|2D controller' || true
}

extract_pci_ids_for_vendor(){
  local lines vid
  lines="$1"
  vid="$2"
  grep -Eio "\[$vid:[0-9a-fA-F]{4}\]" <<<"$lines" \
    | tr -d '[]' \
    | awk -F: '{print toupper($2)}' \
    | sort -u
}

# ---------- AUR helper bootstrap ----------
bootstrap_yay(){
  if (( DRY_RUN )); then
    log "DRY-RUN: would bootstrap yay (AUR helper) if needed"
    return 0
  fi

  have yay && return 0
  have paru && return 0

  ensure_tools

  local tmp
  tmp="$(mktemp -d)"
  as_root chown -R "$RUN_USER:$RUN_USER" "$tmp"

  as_user bash -lc "cd '$tmp' && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -s --noconfirm --needed"

  local pkg
  pkg="$(find "$tmp/yay" -maxdepth 1 -type f -name '*.pkg.tar*' ! -name '*-debug*' | head -n1 || true)"
  [[ -n "$pkg" ]] || die "Failed to build yay from AUR."

  as_root pacman -U --noconfirm --needed "$pkg"
  have yay || die "yay bootstrap failed."
  rm -rf "$tmp"
}

aur_install(){
  if (( DRY_RUN )); then
    log "DRY-RUN: would AUR install: $*"
    return 0
  fi

  local -a newly_managed=()
  local package=""
  for package in "$@"; do
    pacman -Qq "$package" >/dev/null 2>&1 || newly_managed+=("$package")
  done

  install_aur_with_scanner "$@"

  if (( ${#newly_managed[@]} )); then
    as_root install -d -m 0755 /var/lib/awtarchy
    as_root touch /var/lib/awtarchy/managed-packages
    for package in "${newly_managed[@]}"; do
      pacman -Qq "$package" >/dev/null 2>&1 || continue
      if ! grep -Fxq "$package" /var/lib/awtarchy/managed-packages 2>/dev/null; then
        printf '%s\n' "$package" | as_root tee -a /var/lib/awtarchy/managed-packages >/dev/null
      fi
    done
    as_root sh -c 'LC_ALL=C sort -u -o /var/lib/awtarchy/managed-packages /var/lib/awtarchy/managed-packages && chmod 0644 /var/lib/awtarchy/managed-packages'
  fi
}
# ---------- kernel detection (Arch + Cachy variants) ----------
detect_kernel_pkgs(){
  # Prefer real installed kernel pkgbases from /usr/lib/modules (works for Cachy variants, custom kernels).
  local -a bases=()
  if [[ -d /usr/lib/modules ]]; then
    local f b
    shopt -s nullglob
    for f in /usr/lib/modules/*/pkgbase; do
      [[ -f "$f" ]] || continue
      b="$(<"$f")"
      [[ -n "$b" ]] && bases+=("$b")
    done
    shopt -u nullglob
  fi
  if ((${#bases[@]})); then
    printf '%s\n' "${bases[@]}" | sort -u
    return 0
  fi
  # Fallback: best-effort via installed package names
  pacman -Qq 2>/dev/null | grep -E '^linux($|-lts$|-zen$|-hardened$|-cachyos($|-.*$))' | sort -u || true
}

headers_for_kernel(){
  local k
  k="$1"
  case "$k" in
    linux) echo linux-headers ;;
    linux-lts) echo linux-lts-headers ;;
    linux-zen) echo linux-zen-headers ;;
    linux-hardened) echo linux-hardened-headers ;;
    linux-cachyos) echo linux-cachyos-headers ;;
    *) echo "${k}-headers" ;;
  esac
}

install_headers_for_installed_kernels(){
  local want_dkms="${1:-1}"
  (( want_dkms )) && pacman_install dkms

  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs)

  if ((${#kernels[@]}==0)); then
    pacman_install linux-headers || true
    return 0
  fi

  local k hp
  for k in "${kernels[@]}"; do
    hp="$(headers_for_kernel "$k")"
    if pacman -Si "$hp" >/dev/null 2>&1; then
      pacman_install "$hp"
    else
      warn "Headers pkg not found: $hp (kernel: $k)"
    fi
  done
}

try_install_linux_firmware_nvidia(){
  # Only installs if the package exists in enabled repos (safe on vanilla Arch).
  if pacman -Si linux-firmware-nvidia >/dev/null 2>&1; then
    pacman_install linux-firmware-nvidia || true
  fi
}

kernel_pkgbases_counts(){
  # prints: "<cachy_count> <other_count>"
  local cc=0 oc=0 k
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    if [[ "$k" == linux-cachyos* ]]; then
      ((cc++))
    else
      ((oc++))
    fi
  done < <(detect_kernel_pkgs)
  printf '%s %s\n' "$cc" "$oc"
}


nvidia_should_defer_boot_integration(){
  local cc oc
  read -r cc oc < <(kernel_pkgbases_counts)
  (( cc == 0 && oc > 0 ))
}

cachyos_prebuilt_nvidia_open_pkgs(){
  # If Cachy repos are enabled and per-kernel packages exist for every installed Cachy kernel,
  # return the list. Otherwise return non-zero to trigger DKMS fallback.
  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs | awk '/^linux-cachyos/ {print}')
  ((${#kernels[@]})) || return 1

  local -a pkgs=()
  local k p
  for k in "${kernels[@]}"; do
    p="${k}-nvidia-open"
    pacman -Si "$p" >/dev/null 2>&1 || return 1
    pkgs+=("$p")
  done
  printf '%s\n' "${pkgs[@]}"
}

# ---------- NVIDIA conflict removal ----------
nvidia_conflict_regex(){
  # Used for both listing and removal.
  printf '%s' '^(nvidia|nvidia-lts|nvidia-dkms|nvidia-open|nvidia-open-lts|nvidia-open-dkms|nvidia-lts-open|nvidia-utils|lib32-nvidia-utils|nvidia-settings|egl-wayland|opencl-nvidia|lib32-opencl-nvidia|libva-nvidia-driver|linux-cachyos[^[:space:]]*-nvidia-open|linux-cachyos[^[:space:]]*-nvidia|nvidia-[0-9]{3}xx.*|lib32-nvidia-[0-9]{3}xx.*|opencl-nvidia-[0-9]{3}xx.*|lib32-opencl-nvidia-[0-9]{3}xx.*)$'
}

list_installed_nvidia_packages(){
  local re
  re="$(nvidia_conflict_regex)"
  pacman -Qq 2>/dev/null | grep -E "$re" | sort -u || true
}

remove_all_nvidia_packages(){
  local -a pkgs=()
  mapfile -t pkgs < <(list_installed_nvidia_packages)
  ((${#pkgs[@]})) || return 0
  pacman_remove "${pkgs[@]}"
}

# ---------- modeset configuration ----------
write_blacklist_nouveau(){
  (( WRITE_BLACKLIST_NOUVEAU )) || return 0
  local f
  f="/etc/modprobe.d/blacklist-nouveau.conf"
  backup_root_file "$f"
  as_root install -d -m 0755 /etc/modprobe.d
  as_root bash -lc "cat > '$f' <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF"
}

write_modprobe_modeset(){
  (( WRITE_MODPROBE_MODESET )) || return 0
  local f
  f="/etc/modprobe.d/nvidia-drm.conf"
  backup_root_file "$f"
  as_root install -d -m 0755 /etc/modprobe.d
  as_root bash -lc "printf '%s\n' 'options nvidia_drm modeset=1' > '$f'"
}

patch_systemd_boot_entries(){
  local dir
  dir="/boot/loader/entries"
  [[ -d "$dir" ]] || return 0

  local e tmp
  shopt -s nullglob
  for e in "$dir"/*.conf; do
    backup_root_file "$e"
    tmp="$(mktemp)"
    awk -v kpA="$KPARAM_A" -v kpB="$KPARAM_B" '
      /^[[:space:]]*options[[:space:]]+/ {
        if (index($0,kpA) || index($0,kpB)) { print; next }
        print $0 " " kpA
        next
      }
      { print }
    ' "$e" >"$tmp"
    as_root install -m 0644 "$tmp" "$e"
    rm -f "$tmp"
  done
  shopt -u nullglob
}

patch_grub_default(){
  local f
  f="/etc/default/grub"
  [[ -f "$f" ]] || return 0

  backup_root_file "$f"

  local tmp line
  tmp="$(mktemp)"
  while IFS= read -r line; do
    if [[ "$line" == GRUB_CMDLINE_LINUX_DEFAULT=* ]]; then
      local v q
      v="${line#*=}"
      q=""
      if [[ "${v:0:1}" == "\"" && "${v: -1}" == "\"" ]]; then
        q="\""
        v="${v:1:${#v}-2}"
      elif [[ "${v:0:1}" == "'" && "${v: -1}" == "'" ]]; then
        q="'"
        v="${v:1:${#v}-2}"
      fi

      if [[ "$v" == *"$KPARAM_A"* || "$v" == *"$KPARAM_B"* ]]; then
        printf '%s\n' "$line" >>"$tmp"
      else
        v="${v% }"
        v="$v $KPARAM_A"
        printf 'GRUB_CMDLINE_LINUX_DEFAULT=%s%s%s\n' "$q" "$v" "$q" >>"$tmp"
      fi
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$f"

  as_root install -m 0644 "$tmp" "$f"
  rm -f "$tmp"

  if have grub-mkconfig; then
    if [[ -f /boot/grub/grub.cfg ]]; then
      as_root grub-mkconfig -o /boot/grub/grub.cfg || true
    elif [[ -f /boot/grub2/grub.cfg ]]; then
      as_root grub-mkconfig -o /boot/grub2/grub.cfg || true
    fi
  fi
}

patch_limine(){
  local f=""
  local -a candidates=(
    "/boot/limine/limine.conf"
    "/boot/limine.conf"
    "/boot/EFI/limine/limine.conf"
    "/boot/limine/limine.cfg"
    "/boot/limine.cfg"
  )

  local c
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] || continue
    f="$c"
    break
  done
  [[ -n "$f" ]] || return 0

  backup_root_file "$f"

  local tmp line
  tmp="$(mktemp)"
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*cmdline:[[:space:]]* ]]; then
      if [[ "$line" == *"$KPARAM_A"* || "$line" == *"$KPARAM_B"* ]]; then
        printf '%s\n' "$line" >>"$tmp"
      else
        printf '%s %s\n' "$line" "$KPARAM_A" >>"$tmp"
      fi
    elif [[ "$line" =~ ^[[:space:]]*(CMDLINE|KERNEL_CMDLINE)[[:space:]]*= ]]; then
      if [[ "$line" == *"$KPARAM_A"* || "$line" == *"$KPARAM_B"* ]]; then
        printf '%s\n' "$line" >>"$tmp"
      else
        printf '%s %s\n' "$line" "$KPARAM_A" >>"$tmp"
      fi
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$f"

  as_root install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

patch_bootloaders(){
  (( PATCH_BOOTLOADERS )) || return 0
  patch_systemd_boot_entries
  patch_grub_default
  patch_limine
}

patch_mkinitcpio_modules(){
  (( PATCH_MKINITCPIO_MODULES )) || return 0
  local f
  f="/etc/mkinitcpio.conf"
  [[ -f "$f" ]] || return 0

  backup_root_file "$f"

  local tmp line
  tmp="$(mktemp)"
  while IFS= read -r line; do
    if [[ "$line" == MODULES=\(*\) ]]; then
      local inside oldifs
      inside="${line#MODULES=(}"
      inside="${inside%)}"

      local -a mods=()
      oldifs="$IFS"
      IFS=' '
      read -r -a mods <<<"$inside"
      IFS="$oldifs"

      local -a need=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
      local n
      for n in "${need[@]}"; do
        if ! printf '%s\n' "${mods[@]}" | grep -qx "$n"; then
          mods+=("$n")
        fi
      done

      local joined
      IFS=' '
      joined="${mods[*]}"
      IFS="$oldifs"

      printf 'MODULES=(%s)\n' "$joined" >>"$tmp"
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$f"

  as_root install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

rebuild_initramfs(){
  if (( DRY_RUN )); then
    log "DRY-RUN: would rebuild initramfs (mkinitcpio/dracut)"
    return 0
  fi
  if have mkinitcpio; then
    as_root mkinitcpio -P
    return 0
  fi
  if have dracut; then
    as_root dracut --regenerate-all --force
    return 0
  fi
  warn "No mkinitcpio/dracut found; skipping initramfs rebuild."
}

# Uncomment/enable a specific Hyprland env line if present commented, otherwise append it.
ensure_hypr_env_active(){
  local conf key val tmp
  conf="$1"
  key="$2"
  val="$3"

  if grep -qE "^[[:space:]]*env[[:space:]]*=[[:space:]]*${key}[[:space:]]*,[[:space:]]*${val}([[:space:]]*#.*)?[[:space:]]*$" "$conf"; then
    return 0
  fi

  if grep -qE "^[[:space:]]*#[[:space:]]*env[[:space:]]*=[[:space:]]*${key}[[:space:]]*,[[:space:]]*${val}([[:space:]]*#.*)?[[:space:]]*$" "$conf"; then
    tmp="$(mktemp)"
    awk -v key="$key" -v val="$val" '
      BEGIN { done=0 }
      {
        if (!done && $0 ~ "^[[:space:]]*#[[:space:]]*env[[:space:]]*=[[:space:]]*" key "[[:space:]]*,[[:space:]]*" val "([[:space:]]*#.*)?[[:space:]]*$") {
          sub(/^[[:space:]]*#[[:space:]]*/, "", $0)
          done=1
        }
        print
      }
    ' "$conf" >"$tmp"
    cat "$tmp" >"$conf"
    rm -f "$tmp"
    return 0
  fi

  printf '%s\n' "env = ${key},${val}" >>"$conf"
}

patch_hyprland_env_nvidia(){
  local conf
  conf="${USER_HOME}/.config/hypr/hyprland.conf"
  [[ -f "$conf" ]] || return 0

  if (( DRY_RUN )); then
    log "DRY-RUN: would patch Hyprland NVIDIA env lines in: $conf"
    return 0
  fi

  cp -a "$conf" "${conf}.bak.$(ts)"
  ensure_hypr_env_active "$conf" "__GLX_VENDOR_LIBRARY_NAME" "nvidia"
  ensure_hypr_env_active "$conf" "LIBVA_DRIVER_NAME" "nvidia"
  ensure_hypr_env_active "$conf" "GBM_BACKEND" "nvidia-drm"
}

# ---------- base GPU stacks ----------
install_common_base(){
  pacman_install mesa libglvnd vulkan-icd-loader
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pacman_install lib32-mesa lib32-libglvnd lib32-vulkan-icd-loader
  fi
}

install_amd(){
  pacman_install vulkan-radeon
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pacman_install lib32-vulkan-radeon
  fi
}

install_intel(){
  pacman_install vulkan-intel
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pacman_install lib32-vulkan-intel
  fi
}

# ---------- NVIDIA branch detection ----------
fetch_nvidia_legacy_html(){
  local out
  out="$1"
  curl -fsSL "https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/" -o "$out"
}

legacy_branch_for_devid(){
  # returns: 470|390|340|"" based on nvidia legacy page sections
  local devid html
  devid="$1"
  html="$2"

  local needle
  needle="0x${devid}"

  awk -v IGNORECASE=1 -v needle="$needle" '
    /470\.[0-9]+/ {b="470"}
    /390\.[0-9]+/ {b="390"}
    /340\.[0-9]+/ {b="340"}
    index($0, needle) { if (b!="") {print b; exit} }
  ' "$html"
}

nvidia_model_lines(){
  local lines
  lines="$1"
  grep -Ei 'NVIDIA' <<<"$lines" || true
}

is_modern_nvidia(){
  local s
  s="$1"
  grep -qiE '(RTX|Quadro RTX|TITAN RTX|GTX[[:space:]]*16|RTX[[:space:]]*[0-9]{3,4}|A[0-9]{2,4}|H[0-9]{2,4}|L[0-9]{2,4})' <<<"$s"
}

is_preturing_nvidia(){
  local s
  s="$1"
  grep -qiE '(GTX[[:space:]]*(10|9|8|7)|Quadro[[:space:]]*(P|M|K)|Tesla[[:space:]]*(P|V|M|K)|NVS|ION)' <<<"$s"
}

select_open_pkg(){
  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs)
  ((${#kernels[@]})) || die "Unable to detect installed kernels."

  local cc oc
  read -r cc oc < <(kernel_pkgbases_counts)

  # Mixed Cachy + non-Cachy kernels: avoid module-provider conflicts; prefer DKMS.
  if (( cc>0 && oc>0 )); then
    pacman -Si nvidia-open-dkms >/dev/null 2>&1 || die "Mixed Cachy/non-Cachy kernels detected but nvidia-open-dkms not available."
    printf '%s\n' "nvidia-open-dkms"
    return 0
  fi

  # Multiple kernels installed: prefer DKMS so one module provider covers all.
  if ((${#kernels[@]} != 1)); then
    pacman -Si nvidia-open-dkms >/dev/null 2>&1 || die "Multiple kernels installed but nvidia-open-dkms not available."
    printf '%s\n' "nvidia-open-dkms"
    return 0
  fi

  # No Cachy kernel installed yet: prefer DKMS so adding Cachy later does not
  # leave early NVIDIA module expectations tied to a single non-Cachy kernel.
  if (( cc == 0 )); then
    if pacman -Si nvidia-open-dkms >/dev/null 2>&1; then
      printf '%s\n' "nvidia-open-dkms"
      return 0
    fi
  fi

  case "${kernels[0]}" in
    linux)
      if pacman -Si nvidia-open >/dev/null 2>&1; then printf '%s\n' "nvidia-open"; return 0; fi
      ;;
    linux-lts)
      if pacman -Si nvidia-open-lts >/dev/null 2>&1; then printf '%s\n' "nvidia-open-lts"; return 0; fi
      if pacman -Si nvidia-lts-open >/dev/null 2>&1; then printf '%s\n' "nvidia-lts-open"; return 0; fi
      ;;
    *)
      if pacman -Si nvidia-open-dkms >/dev/null 2>&1; then printf '%s\n' "nvidia-open-dkms"; return 0; fi
      ;;
  esac

  if pacman -Si nvidia-open-dkms >/dev/null 2>&1; then printf '%s\n' "nvidia-open-dkms"; return 0; fi
  if pacman -Si nvidia-open >/dev/null 2>&1; then printf '%s\n' "nvidia-open"; return 0; fi
  die "No nvidia-open packages found in enabled repos."
}

nvidia_open_install_plan(){
  # Prints a human plan to stdout:
  #   STRATEGY=<...>
  #   INSTALL=<pkg...>
  #   NEED_HEADERS=<0|1>
  local cc oc
  read -r cc oc < <(kernel_pkgbases_counts)

  if (( cc>0 && oc==0 )); then
    local -a prebuilt=()
    if mapfile -t prebuilt < <(cachyos_prebuilt_nvidia_open_pkgs 2>/dev/null); then
      if ((${#prebuilt[@]})); then
        printf 'STRATEGY=cachy-prebuilt\n'
        printf 'NEED_HEADERS=0\n'
        printf 'INSTALL=%s\n' "${prebuilt[*]}"
        return 0
      fi
    fi
    printf 'STRATEGY=cachy-dkms-fallback\n'
  fi

  local modpkg
  modpkg="$(select_open_pkg)"
  printf 'STRATEGY=arch-open\n'
  printf 'NEED_HEADERS=%s\n' "$([[ "$modpkg" == *-dkms ]] && echo 1 || echo 0)"
  printf 'INSTALL=%s\n' "$modpkg"
}

install_nvidia_open_stack(){
  local plan strategy need_headers install_line
  plan="$(nvidia_open_install_plan)"
  strategy="$(awk -F= '$1=="STRATEGY"{print $2}' <<<"$plan")"
  need_headers="$(awk -F= '$1=="NEED_HEADERS"{print $2}' <<<"$plan")"
  install_line="$(awk -F= '$1=="INSTALL"{print $2}' <<<"$plan")"

  log "NVIDIA open strategy: $strategy"

  if [[ "$strategy" == "cachy-prebuilt" ]]; then
    local -a prebuilt=()
    # shellcheck disable=SC2206
    prebuilt=($install_line)
    pacman_install "${prebuilt[@]}" nvidia-utils nvidia-settings egl-wayland
    try_install_linux_firmware_nvidia
  else
    local modpkg
    modpkg="$install_line"
    install_headers_for_installed_kernels "$need_headers"
    pacman_install "$modpkg" nvidia-utils nvidia-settings egl-wayland
    try_install_linux_firmware_nvidia
  fi

  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pacman_install lib32-nvidia-utils
  fi
  if (( INSTALL_OPENCL )); then
    pacman_install opencl-nvidia || true
    if (( INSTALL_LIB32 )) && multilib_enabled; then
      pacman_install lib32-opencl-nvidia || true
    fi
  fi
}

install_nvidia_580xx_stack(){
  install_headers_for_installed_kernels 1
  ensure_tools
  ensure_aur_scanner

  aur_install nvidia-580xx-dkms nvidia-580xx-utils nvidia-580xx-settings
  pacman_install egl-wayland
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    aur_install lib32-nvidia-580xx-utils
  fi
  if (( INSTALL_OPENCL )); then
    aur_install opencl-nvidia-580xx || true
    if (( INSTALL_LIB32 )) && multilib_enabled; then
      aur_install lib32-opencl-nvidia-580xx || true
    fi
  fi
}

install_nvidia_legacy_branch(){
  local branch
  branch="$1"
  install_headers_for_installed_kernels 1
  ensure_tools
  ensure_aur_scanner

  case "$branch" in
    470)
      aur_install nvidia-470xx-dkms nvidia-470xx-utils nvidia-470xx-settings
      ;;
    390)
      aur_install nvidia-390xx-dkms nvidia-390xx-utils nvidia-390xx-settings
      ;;
    340)
      aur_install nvidia-340xx nvidia-340xx-utils || die "340xx is frequently broken on modern Arch; install failed."
      ;;
    *)
      die "Unknown legacy branch: $branch"
      ;;
  esac

  pacman_install egl-wayland
}

verify_nvidia_module_for_running_kernel(){
  local kver pb
  kver="$(uname -r)"
  pb=""
  [[ -f "/usr/lib/modules/${kver}/pkgbase" ]] && pb="$(<"/usr/lib/modules/${kver}/pkgbase")"

  if have modinfo; then
    if ! modinfo -k "$kver" nvidia >/dev/null 2>&1; then
      if [[ -n "$pb" ]]; then
        warn "nvidia kernel module not found for running kernel: $kver (pkgbase: $pb)"
      else
        warn "nvidia kernel module not found for running kernel: $kver"
      fi
      return 1
    fi
  fi
  return 0
}

configure_nvidia_boot_integration(){
  if nvidia_should_defer_boot_integration; then
    warn "No Cachy kernel detected yet. Deferring NVIDIA bootloader/mkinitcpio/initramfs changes so a later-installed Cachy kernel can generate its initramfs cleanly."
    return 0
  fi

  patch_bootloaders
  patch_mkinitcpio_modules
  rebuild_initramfs
}

configure_nvidia(){
  write_blacklist_nouveau
  write_modprobe_modeset
  configure_nvidia_boot_integration
  patch_hyprland_env_nvidia

  if (( DRY_RUN )); then
    log "DRY-RUN: would verify nvidia-smi + running-kernel module presence"
    return 0
  fi

  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi not present after install (nvidia-utils or legacy utils missing)."
  verify_nvidia_module_for_running_kernel || true
}

nvidia_plan_report(){
  log "---- DRY-RUN PLAN (NVIDIA) ----"
  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs)
  if ((${#kernels[@]})); then
    log "Installed kernel pkgbases: ${kernels[*]}"
  else
    log "Installed kernel pkgbases: (none detected)"
  fi

  local cc oc
  read -r cc oc < <(kernel_pkgbases_counts)
  log "Kernel mix: cachy=${cc} other=${oc}"

  local -a installed=()
  mapfile -t installed < <(list_installed_nvidia_packages)
  if ((${#installed[@]})); then
    log "Installed NVIDIA-related packages that would be removed:"
    printf '  %s\n' "${installed[@]}"
  else
    log "Installed NVIDIA-related packages that would be removed: (none)"
  fi

  local plan strategy need_headers install_line
  plan="$(nvidia_open_install_plan)"
  strategy="$(awk -F= '$1=="STRATEGY"{print $2}' <<<"$plan")"
  need_headers="$(awk -F= '$1=="NEED_HEADERS"{print $2}' <<<"$plan")"
  install_line="$(awk -F= '$1=="INSTALL"{print $2}' <<<"$plan")"

  log "Selected NVIDIA module strategy: $strategy"
  if [[ "$strategy" == "cachy-prebuilt" ]]; then
    log "Would install prebuilt per-kernel module packages: $install_line"
  else
    log "Would install module package: $install_line"
    log "Would install kernel headers + dkms: $need_headers"
  fi

  log "Would install userspace: nvidia-utils nvidia-settings egl-wayland"
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    log "Would install 32-bit userspace: lib32-nvidia-utils"
  fi
  if (( INSTALL_OPENCL )); then
    log "Would install OpenCL: opencl-nvidia (and lib32-opencl-nvidia if multilib enabled)"
  fi

  if pacman -Si linux-firmware-nvidia >/dev/null 2>&1; then
    log "Would install firmware: linux-firmware-nvidia"
  fi

  log "Would write nouveau blacklist: $WRITE_BLACKLIST_NOUVEAU"
  log "Would write nvidia_drm modeset modprobe: $WRITE_MODPROBE_MODESET"
  if nvidia_should_defer_boot_integration; then
    log "Would defer bootloader/mkinitcpio/initramfs changes until a Cachy kernel is installed"
  else
    log "Would patch bootloader cmdline: $PATCH_BOOTLOADERS (adds: $KPARAM_A)"
    log "Would patch mkinitcpio MODULES: $PATCH_MKINITCPIO_MODULES (adds early nvidia modules)"
    log "Would rebuild initramfs: yes (mkinitcpio/dracut if present)"
  fi
  log "Would patch Hyprland NVIDIA env lines: yes (if hyprland.conf exists)"
  log "---- END PLAN ----"
}

# NVIDIA auto path (with legacy lookup)
install_nvidia_auto(){
  local gpu_lines
  gpu_lines="$1"

  local -a ids=()
  mapfile -t ids < <(extract_pci_ids_for_vendor "$gpu_lines" "10de")
  ((${#ids[@]})) || return 0

  local models
  models="$(nvidia_model_lines "$gpu_lines")"

  log "NVIDIA detected: ${ids[*]}"
  [[ -n "$models" ]] && log "$models"

  if (( DRY_RUN )); then
    # Dry-run should not curl/download the legacy page; print the decision tree + open strategy plan.
    local class="unknown"
    if is_modern_nvidia "$models"; then
      class="modern (Turing+/RTX/GTX16+)"
    elif is_preturing_nvidia "$models"; then
      class="older (Pascal/Maxwell/Volta-style naming)"
    fi

    log "DRY-RUN: NVIDIA classification (from model string): $class"
    log "DRY-RUN: would check NVIDIA legacy GPU list for PCI IDs to select 470/390/340 if applicable"
    log "DRY-RUN: if not legacy-branch, then:"
    log "  - modern -> install nvidia-open* (Arch/Cachy strategy below)"
    log "  - older  -> install nvidia-580xx-dkms stack from AUR"
    nvidia_plan_report
    return 0
  fi

  remove_all_nvidia_packages

  local tmp branch=""
  tmp="$(mktemp)"
  if fetch_nvidia_legacy_html "$tmp"; then
    local id b
    for id in "${ids[@]}"; do
      b="$(legacy_branch_for_devid "$id" "$tmp" || true)"
      if [[ -n "$b" ]]; then
        if [[ -z "$branch" ]]; then
          branch="$b"
        elif [[ "$branch" != "$b" ]]; then
          rm -f "$tmp"
          die "Multiple NVIDIA GPUs require different legacy branches ($branch vs $b). Refusing to guess."
        fi
      fi
    done
  fi
  rm -f "$tmp"

  if [[ -n "$branch" ]]; then
    log "NVIDIA legacy branch selected: $branch"
    install_nvidia_legacy_branch "$branch"
    configure_nvidia
    return 0
  fi

  if is_modern_nvidia "$models"; then
    log "NVIDIA modern path: nvidia-open*"
    install_nvidia_open_stack
    configure_nvidia
    return 0
  fi

  if is_preturing_nvidia "$models"; then
    log "NVIDIA older path: 580xx (AUR)"
    install_nvidia_580xx_stack
    configure_nvidia
    return 0
  fi

  log "NVIDIA unknown model naming: trying nvidia-open* first"
  install_nvidia_open_stack
  configure_nvidia
}

# ---------- base plan output ----------
dry_run_banner(){
  log "DRY-RUN: enabled. No changes will be made."
  log "Options: upgrade=$DO_UPGRADE lib32=$INSTALL_LIB32 opencl=$INSTALL_OPENCL bootloader_patch=$PATCH_BOOTLOADERS modprobe_modeset=$WRITE_MODPROBE_MODESET blacklist_nouveau=$WRITE_BLACKLIST_NOUVEAU mkinitcpio_modules=$PATCH_MKINITCPIO_MODULES"
  if [[ -n "${FORCE_GPU:-}" ]]; then
    log "Forced GPU path: $FORCE_GPU"
  fi
}

gpu_dependencies_original_main(){
  if have systemd-detect-virt && systemd-detect-virt -q; then
    log "VM detected; skipping GPU driver automation."
    return 0
  fi

  have pacman || return 0

  if (( DRY_RUN )); then
    dry_run_banner
  fi

  if (( DO_UPGRADE )); then
    as_root pacman -Syu --noconfirm
  else
    as_root pacman -Sy --noconfirm
  fi

  install_common_base

  if [[ -n "${FORCE_GPU:-}" ]]; then
    case "$FORCE_GPU" in
      nvidia)
        NVIDIA_TOUCHED=1
        if (( DRY_RUN )); then
          nvidia_plan_report
        fi
        remove_all_nvidia_packages
        install_nvidia_open_stack
        configure_nvidia
        ;;
      amd)
        install_amd
        ;;
      intel)
        install_intel
        ;;
      *)
        die "Unknown --gpu override: $FORCE_GPU"
        ;;
    esac

    if (( NVIDIA_TOUCHED )); then
      log "GPU install complete. Reboot recommended after NVIDIA changes."
    else
      log "GPU install complete."
    fi
    return 0
  fi

  local lines
  lines="$(detect_gpu_lines)"
  [[ -n "$lines" ]] || return 0

  log "GPU(s):"
  log "$lines"

  local amd_ids intel_ids nvidia_ids
  amd_ids="$(extract_pci_ids_for_vendor "$lines" "1002" || true)"
  intel_ids="$(extract_pci_ids_for_vendor "$lines" "8086" || true)"
  nvidia_ids="$(extract_pci_ids_for_vendor "$lines" "10de" || true)"

  [[ -n "$amd_ids" ]] && install_amd
  [[ -n "$intel_ids" ]] && install_intel
  if [[ -n "$nvidia_ids" ]]; then
    NVIDIA_TOUCHED=1
    install_nvidia_auto "$lines"
  fi

  if (( NVIDIA_TOUCHED )); then
    log "GPU install complete. Reboot recommended after NVIDIA changes."
  else
    log "GPU install complete."
  fi
}

gpu_dependencies_original_main "$@"
}

update_reset_backup_main() {
set -Eeuo pipefail
umask 022

REPO_OWNER="dillacorn"
REPO_NAME="awtarchy"
LOG_PREFIX="[awtarchy-update]"

log()  { printf '%s %s\n' "$LOG_PREFIX" "$*"; }
warn() { printf '%s WARN: %s\n' "$LOG_PREFIX" "$*" >&2; }
die()  { printf '%s ERROR: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
ts() { date -Iseconds; }
stamp() { date +%Y%m%d-%H%M%S; }

TARGET_USER=""
HOME_DIR=""
STATE_DIR=""
BASELINE_HOME=""
MANIFEST_FILE=""
HARDWARE_FILE=""
ACTIVE_THEME_FILE=""
GIT_TESTING_FILE=""
AUDIT_LOG=""
UPDATE_MODE=""
CONFLICT_POLICY="keep-local"
MERGE_CONFLICT_RESOLUTION=""
REVIEW_ONLY=0
ASSUME_YES=0
TAG_OVERRIDE=""
TESTING_BRANCH=""
TESTING_COMMIT=""
RESOLVED_RELEASE_COMMIT=""
BACKUPS=()
CHANGED=()
PRESERVED=()
MERGED=()
REMOVED=()
FAILED=()
ROLLBACK_PATHS=()
MOUSE_ENABLED=0
GPU_DETECTION_RELIABLE=0
TMPD=""
TARGET_STAGE_HOME=""
QUICKSHELL_UPDATE_RESTORE_ON_EXIT=0
QUICKSHELL_UPDATE_RECOVERY_MARKER=""

restore_quickshell_update_shell_on_exit() {
  local marker="${QUICKSHELL_UPDATE_RECOVERY_MARKER:-}" marker_pending=0
  if [[ -n "$marker" && -f "$marker" && ! -L "$marker" ]]; then
    marker_pending=1
  fi
  (( QUICKSHELL_UPDATE_RESTORE_ON_EXIT == 1 || marker_pending == 1 )) || return 0
  QUICKSHELL_UPDATE_RESTORE_ON_EXIT=0

  [[ -n "${HOME_DIR:-}" ]] || {
    warn "Could not restore Quickshell after interrupted update: target home is unavailable."
    return 1
  }

  local manager="${HOME_DIR}/.config/hypr/scripts/quickshell.sh"
  local status=""
  [[ -f "$manager" && ! -L "$manager" ]] || {
    warn "Could not restore Quickshell after interrupted update: manager is unavailable."
    return 1
  }

  status="$(run_target bash "$manager" status 9>&- 2>/dev/null || true)"
  if [[ "$status" == "running" ]]; then
    (( marker_pending == 0 )) || rm -f -- "$marker"
    return 0
  fi

  log "Update interrupted; restoring Quickshell..."
  if ! AWTARCHY_REPORT_SUPPRESS_QUICKSHELL=1 run_target bash "$manager" start 9>&-; then
    warn "Could not restore Quickshell after interrupted update."
    return 1
  fi

  status="$(run_target bash "$manager" status 9>&- 2>/dev/null || true)"
  if [[ "$status" == "running" ]]; then
    [[ -z "$marker" ]] || rm -f -- "$marker"
    log "Quickshell restored."
    return 0
  fi

  warn "Could not verify Quickshell after interrupted-update recovery."
  return 1
}

recover_interrupted_quickshell_update() {
  local marker="${QUICKSHELL_UPDATE_RECOVERY_MARKER:-}"
  [[ -n "$marker" ]] || return 0
  if [[ -L "$marker" ]]; then
    warn "Refusing unsafe Quickshell interrupted-update recovery marker: ${marker}"
    return 1
  fi
  [[ -f "$marker" ]] || return 0

  log "Recovering Quickshell from a previously interrupted update..."
  QUICKSHELL_UPDATE_RESTORE_ON_EXIT=1
  restore_quickshell_update_shell_on_exit
}

cleanup_update() {
  local exit_rc=$?
  if (( MOUSE_ENABLED == 1 )); then
    printf '\033[?1000l\033[?1006l' >/dev/tty 2>/dev/null || true
  fi
  [[ -n "${TMPD:-}" ]] && rm -rf -- "$TMPD" 2>/dev/null || true
  restore_quickshell_update_shell_on_exit || true
  return "$exit_rc"
}
trap cleanup_update EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

run_target() {
  if [[ "${EUID}" -eq 0 ]]; then
    local -a user_env=(env "HOME=${HOME_DIR}" "USER=${TARGET_USER}" "LOGNAME=${TARGET_USER}")
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$TARGET_USER" -- "${user_env[@]}" "$@"
    elif command -v sudo >/dev/null 2>&1; then
      sudo -u "$TARGET_USER" -H -- "${user_env[@]}" "$@"
    else
      die "Running as root but neither runuser nor sudo is available to run commands as ${TARGET_USER}"
    fi
  else
    "$@"
  fi
}

reapply_cursor_theme_after_update() {
  local helper="${HOME_DIR}/.config/hypr/scripts/quickshell_cursor_theme.sh"
  [[ -f "$helper" && ! -L "$helper" ]] || return 0

  log "Applying saved Bibata cursor theme to the current session..."
  if ! run_target env \
    "HOME=${HOME_DIR}" \
    "USER=${TARGET_USER}" \
    "XDG_CONFIG_HOME=${HOME_DIR}/.config" \
    "XDG_CACHE_HOME=${HOME_DIR}/.cache" \
    "XDG_DATA_HOME=${HOME_DIR}/.local/share" \
    bash "$helper" reapply; then
    warn "Bibata cursor settings were saved, but the current Hyprland session could not be switched live."
  fi
}

restart_hypridle_after_update() {
  local helper="${HOME_DIR}/.config/hypr/scripts/hypridle_restart.sh"
  local target_uid=""

  [[ -f "$helper" ]] || return 0

  # A direct desktop update has the Hyprland signature. When an update was
  # launched through sudo and that variable was filtered, an existing
  # per-user Hypridle process is enough evidence that it should be refreshed.
  if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    command -v pgrep >/dev/null 2>&1 || return 0
    target_uid="$(id -u "$TARGET_USER" 2>/dev/null || true)"
    [[ "$target_uid" =~ ^[0-9]+$ ]] || return 0
    run_target pgrep -u "$target_uid" -x hypridle >/dev/null 2>&1 || return 0
  fi

  log "Restarting Hypridle to load updated idle callbacks..."
  if ! run_target env \
    "HOME=${HOME_DIR}" \
    "USER=${TARGET_USER}" \
    "LOGNAME=${TARGET_USER}" \
    "HYPRIDLE_CONFIG=${HOME_DIR}/.config/hypr/hypridle.conf" \
    "HYPRIDLE_RESTORE_SCRIPT=${HOME_DIR}/.config/hypr/scripts/quickshell_bar_restore.sh" \
    bash "$helper" 9>&-
  then
    warn "Hypridle could not be restarted automatically. Run ${helper} after the update."
  fi
}

init_target_user() {
  if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
  elif [[ "${EUID}" -eq 0 ]]; then
    TARGET_USER="$(awk -F: '$3 >= 1000 && $1 != "nobody" { print $1; exit }' /etc/passwd)"
  else
    TARGET_USER="${USER:-$(id -un)}"
  fi
  [[ -n "$TARGET_USER" ]] || die "Could not determine the target desktop user. Run with sudo from that user account."

  HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
  [[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || die "Could not resolve HOME for user: ${TARGET_USER}"

  STATE_DIR="${HOME_DIR}/.local/state/awtarchy"
  QUICKSHELL_UPDATE_RECOVERY_MARKER="${STATE_DIR}/quickshell-update-stopped"
  BASELINE_HOME="${STATE_DIR}/baseline/home"
  MANIFEST_FILE="${STATE_DIR}/baseline/manifest.paths"
  HARDWARE_FILE="${STATE_DIR}/hardware-state"
  ACTIVE_THEME_FILE="${STATE_DIR}/active-theme"
  GIT_TESTING_FILE="${STATE_DIR}/git-testing"
  mkdir -p -- "${STATE_DIR}/logs"
  AUDIT_LOG="${STATE_DIR}/logs/update-$(stamp).log"
  if [[ "${EUID}" -eq 0 ]]; then
    chown -R "${TARGET_USER}:${TARGET_USER}" "$STATE_DIR" 2>/dev/null || true
  fi
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --tag)
        TAG_OVERRIDE="${2:-}"
        [[ -n "$TAG_OVERRIDE" ]] || die "--tag requires a release tag"
        shift 2
        ;;
      --testing-commit)
        TESTING_COMMIT="${2:-}"
        [[ "$TESTING_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]] \
          || die "--testing-commit requires a full 40-character commit SHA"
        TESTING_COMMIT="${TESTING_COMMIT,,}"
        shift 2
        ;;
      --testing-branch)
        TESTING_BRANCH="${2:-}"
        [[ -n "$TESTING_BRANCH" ]] || die "--testing-branch requires a remote branch name"
        [[ $TESTING_BRANCH != *$'\n'* \
          && $TESTING_BRANCH != *$'\r'* \
          && $TESTING_BRANCH != *$'\t'* ]] \
          || die "--testing-branch contains unsupported control characters"
        shift 2
        ;;
      --mode)
        UPDATE_MODE="${2:-}"
        [[ "$UPDATE_MODE" == "preserve" || "$UPDATE_MODE" == "clean" ]] || die "--mode must be preserve or clean"
        shift 2
        ;;
      --conflict-policy)
        CONFLICT_POLICY="${2:-}"
        case "$CONFLICT_POLICY" in
          prompt|keep-local|use-release|abort) ;;
          *) die "--conflict-policy must be prompt, keep-local, use-release, or abort" ;;
        esac
        shift 2
        ;;
      --review-only)
        REVIEW_ONLY=1
        shift
        ;;
      --yes|-y)
        ASSUME_YES=1
        shift
        ;;
      --help|-h)
        cat <<'EOF'
Usage:
  awtarchy.sh update-reset-backup [options]

Options:
  --tag <tag>              Update from an exact GitHub release tag
  --testing-branch <name>  Selected Awtarchy remote branch for Git testing
  --testing-commit <sha>   Exact commit verified against --testing-branch
  --mode preserve|clean    Select update mode without the menu
  --conflict-policy <mode> Resolve merge conflicts with prompt, keep-local,
                           use-release, or abort (default: prompt)
  --review-only            Download, classify, and review without changing files
  --yes                    Accept conservative hardware cleanup prompts
EOF
        return 2
        ;;
      *)
        die "Unknown update option: $1"
        ;;
    esac
  done

  [[ -z "$TAG_OVERRIDE" || -z "$TESTING_COMMIT" ]] \
    || die "--tag and --testing-commit cannot be used together"
  if [[ -n "$TESTING_BRANCH" || -n "$TESTING_COMMIT" ]]; then
    [[ -n "$TESTING_BRANCH" && -n "$TESTING_COMMIT" ]] \
      || die "--testing-branch and --testing-commit must be used together"
  fi
}

curl_headers() {
  CURL_ARGS=(
    -fL
    --show-error
    --retry 3
    --retry-delay 1
    -H "User-Agent: awtarchy-update"
  )
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_ARGS+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
}

fetch_latest_release_tag() {
  local api="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
  local json
  json="$(curl "${CURL_ARGS[@]}" \
    --silent \
    --connect-timeout 10 \
    --max-time 30 \
    -H "Accept: application/vnd.github+json" "$api")" \
    || die "Failed to query GitHub latest release API"
  python3 - "$json" <<'PY'
import json, sys
j = json.loads(sys.argv[1])
tag = (j.get("tag_name") or "").strip()
if not tag:
    raise SystemExit(2)
print(tag)
PY
}

urlencode_path_segment() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe="-._~"))
PY
}

resolve_remote_testing_branch_head() {
  local branch="$1" branch_enc="" branch_json=""

  branch_enc="$(urlencode_path_segment "$branch")" || return 1
  branch_json="$(curl "${CURL_ARGS[@]}" --silent --connect-timeout 10 --max-time 20 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/branches/${branch_enc}")" \
    || return 1
  python3 - "$branch_json" "$branch" <<'PY'
import json
import re
import sys

try:
    payload = json.loads(sys.argv[1])
except (IndexError, json.JSONDecodeError):
    raise SystemExit(1)

expected = sys.argv[2]
name = str(payload.get("name") or "")
revision = str((payload.get("commit") or {}).get("sha") or "").lower()
if name != expected or not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise SystemExit(1)
print(revision)
PY
}

testing_commit_belongs_to_branch() {
  local commit="$1" branch_head="$2" compare_json=""

  [[ $commit == "$branch_head" ]] && return 0
  compare_json="$(curl "${CURL_ARGS[@]}" --silent --connect-timeout 10 --max-time 20 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/compare/${commit}...${branch_head}")" \
    || return 1
  python3 - "$compare_json" "$commit" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except (IndexError, json.JSONDecodeError):
    raise SystemExit(1)

requested = sys.argv[2].lower()
status = str(payload.get("status") or "")
merge_base = str((payload.get("merge_base_commit") or {}).get("sha") or "").lower()
if status not in {"ahead", "identical"} or merge_base != requested:
    raise SystemExit(1)
PY
}

parse_github_git_object() {
  python3 - "$1" <<'PY'
import json
import re
import sys

try:
    payload = json.loads(sys.argv[1])
    obj = payload["object"]
    kind = str(obj["type"]).strip()
    revision = str(obj["sha"]).strip().lower()
except (IndexError, KeyError, TypeError, json.JSONDecodeError):
    raise SystemExit(1)
if kind not in {"commit", "tag"} or not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise SystemExit(1)
print(kind)
print(revision)
PY
}

resolve_release_tag_commit() {
  local tag="$1" tag_enc="" release_json="" object_json=""
  local kind="" revision="" depth=0
  local -a object_fields=()
  local -A seen=()

  tag_enc="$(urlencode_path_segment "$tag")" || return 1
  release_json="$(curl "${CURL_ARGS[@]}" --silent --connect-timeout 10 --max-time 20 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${tag_enc}")" \
    || return 1
  python3 - "$release_json" "$tag" <<'PY' || return 1
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except (IndexError, json.JSONDecodeError):
    raise SystemExit(1)
if (
    str(payload.get("tag_name") or "") != sys.argv[2]
    or payload.get("draft") is not False
    or not str(payload.get("published_at") or "").strip()
):
    raise SystemExit(1)
PY

  object_json="$(curl "${CURL_ARGS[@]}" --silent --connect-timeout 10 --max-time 20 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/git/ref/tags/${tag_enc}")" \
    || return 1
  mapfile -t object_fields < <(parse_github_git_object "$object_json")
  (( ${#object_fields[@]} == 2 )) || return 1
  kind="${object_fields[0]}"
  revision="${object_fields[1]}"

  while (( depth < 8 )); do
    case "$kind" in
      commit)
        printf '%s\n' "$revision"
        return 0
        ;;
      tag)
        [[ -z ${seen[$revision]:-} ]] || return 1
        seen[$revision]=1
        object_json="$(curl "${CURL_ARGS[@]}" --silent --connect-timeout 10 --max-time 20 \
          -H 'Accept: application/vnd.github+json' \
          "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/git/tags/${revision}")" \
          || return 1
        object_fields=()
        mapfile -t object_fields < <(parse_github_git_object "$object_json")
        (( ${#object_fields[@]} == 2 )) || return 1
        kind="${object_fields[0]}"
        revision="${object_fields[1]}"
        ;;
      *) return 1 ;;
    esac
    (( depth += 1 ))
  done
  return 1
}

download_release_tarball() {
  local tag="$1" out="$2" max_time="${3:-300}" commit
  commit="$(resolve_release_tag_commit "$tag")" || return 1
  RESOLVED_RELEASE_COMMIT="$commit"
  download_testing_commit_tarball "$commit" "$out" "$max_time"
}

download_testing_commit_tarball() {
  local commit="$1" out="$2" max_time="${3:-300}"
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || return 2

  curl "${CURL_ARGS[@]}" \
    --progress-bar \
    --connect-timeout 10 \
    --max-time "$max_time" \
    --retry 1 \
    --speed-limit 1024 \
    --speed-time 30 \
    -o "$out" \
    "https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/${commit}.tar.gz"
}
validate_source_archive() {
  local archive="$1" expected_top="${2:-}"
  python3 - "$archive" "$expected_top" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

MAX_MEMBERS = 100000
MAX_UNPACKED_BYTES = 2 * 1024 * 1024 * 1024

try:
    with tarfile.open(sys.argv[1], "r:gz") as archive:
        members = archive.getmembers()
except (OSError, tarfile.TarError):
    raise SystemExit(1)

if not members or len(members) > MAX_MEMBERS:
    raise SystemExit(1)
expected = sys.argv[2]
top = ""
seen = set()
unpacked = 0
for member in members:
    name = member.name.rstrip("/")
    if not name or any(c in name for c in "\n\r\t\0\\"):
        raise SystemExit("unsafe archive path")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in name.split("/")):
        raise SystemExit("unsafe archive path")
    if not (member.isfile() or member.isdir()):
        raise SystemExit("unsupported archive entry")
    normalized = path.as_posix()
    if normalized in seen:
        raise SystemExit("duplicate archive entry")
    seen.add(normalized)
    unpacked += member.size
    if unpacked > MAX_UNPACKED_BYTES:
        raise SystemExit("archive exceeds unpacked size limit")
    if not top:
        top = path.parts[0]
    elif path.parts[0] != top:
        raise SystemExit("archive has multiple top-level paths")
if expected and top != expected:
    raise SystemExit("archive root does not match immutable revision")
print(top)
PY
}

tar_topdir() {
  validate_source_archive "$@"
}

has_controlling_tty() {
  [[ -r /dev/tty && -w /dev/tty ]] || return 1
  { true </dev/tty >/dev/tty; } 2>/dev/null
}

is_interactive() {
  [[ -t 0 && -t 1 ]] && has_controlling_tty
}

ask_yes_no() {
  local prompt="$1" ans=""
  (( ASSUME_YES == 1 )) && return 0
  is_interactive || return 1
  while true; do
    printf '%s [y/N] ' "$prompt" >/dev/tty
    IFS= read -r ans </dev/tty || return 1
    case "$ans" in
      y|Y|yes|YES) return 0 ;;
      ""|n|N|no|NO) return 1 ;;
    esac
  done
}

acquire_lock() {
  need_cmd flock
  local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u "$TARGET_USER")}"
  mkdir -p -- "$runtime" 2>/dev/null || true
  exec 9>"${runtime}/awtarchy-update.lock"
  flock -n 9 || die "Another Awtarchy update is already running."
}

copy_target() {
  local src="$1" dest="$2"
  [[ -e "$src" || -L "$src" ]] || return 0
  mkdir -p -- "$(dirname "$dest")"
  cp -a --no-preserve=ownership -- "$src" "$dest"
}

normalize_managed_executables() {
  local root="$1" rel dir
  for rel in \
    .config/hypr/scripts \
    .config/hypr/themes \
    .config/waybar/scripts
  do
    dir="${root}/${rel}"
    [[ -d "$dir" ]] || continue
    find "$dir" -type f -exec chmod 0755 {} +
  done
}

build_target_home() {
  local repo_dir="$1" target_home="$2" d
  mkdir -p -- "$target_home"

  copy_target "${repo_dir}/bashrc" "${target_home}/.bashrc"
  copy_target "${repo_dir}/bash_profile" "${target_home}/.bash_profile"
  copy_target "${repo_dir}/Xresources" "${target_home}/.Xresources"
  copy_target "${repo_dir}/config/mimeapps.list" "${target_home}/.config/mimeapps.list"
  copy_target "${repo_dir}/config/gamemode.ini" "${target_home}/.config/gamemode.ini"

  # Every directory under config/ is Awtarchy-managed. Discover them from
  # the exact release instead of maintaining a list that can omit new paths.
  while IFS= read -r -d '' config_dir; do
    d="${config_dir##*/}"
    mkdir -p -- "${target_home}/.config/${d}"
    cp -a --no-preserve=ownership -- "${config_dir}/." "${target_home}/.config/${d}/"
  done < <(find "${repo_dir}/config" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

  copy_target "${repo_dir}/local/share/nwg-look/gsettings" \
    "${target_home}/.local/share/nwg-look/gsettings"

  if [[ -d "${repo_dir}/local/share/SpeedCrunch/color-schemes" ]]; then
    mkdir -p -- "${target_home}/.local/share/SpeedCrunch/color-schemes"
    cp -a --no-preserve=ownership -- \
      "${repo_dir}/local/share/SpeedCrunch/color-schemes/." \
      "${target_home}/.local/share/SpeedCrunch/color-schemes/"
  fi

  if [[ -d "${repo_dir}/local/share/applications" ]]; then
    mkdir -p -- "${target_home}/.local/share/applications"
    cp -a --no-preserve=ownership -- \
      "${repo_dir}/local/share/applications/." \
      "${target_home}/.local/share/applications/"
  fi

  copy_target "${repo_dir}/awtarchy_geology.png" \
    "${target_home}/Pictures/wallpapers/awtarchy_geology.png"

  # GitHub release archives can expose managed scripts without executable bits.
  # Normalize staging so comparison, installation, and saved baselines all use
  # the executable modes expected by Awtarchy.
  normalize_managed_executables "$target_home"
}

valid_theme_name() {
  local name="$1"
  [[ -n "$name" && "$name" != */* && "$name" != "." && "$name" != ".." && "$name" != *$'\n'* ]]
}

infer_active_theme() {
  local repo_dir="$1" theme="" speed="${HOME_DIR}/.config/SpeedCrunch/SpeedCrunch.ini"
  if [[ -r "$ACTIVE_THEME_FILE" ]]; then
    IFS= read -r theme <"$ACTIVE_THEME_FILE" || true
    if valid_theme_name "$theme" && [[ -f "${repo_dir}/config/hypr/themes/${theme}" ]]; then
      printf '%s\n' "$theme"
      return 0
    fi
  fi

  if [[ -r "$speed" ]]; then
    theme="$(sed -n 's/^Display\\ColorSchemeName=//p' "$speed" | head -n1 | tr -d '\r')"
    if valid_theme_name "$theme" && [[ -f "${repo_dir}/config/hypr/themes/${theme}" ]]; then
      printf '%s\n' "$theme"
      return 0
    fi
  fi

  return 1
}


render_theme_target() {
  local theme_file="$1" target_home="$2" theme="$3"
  python3 - "$theme_file" "$target_home" "$theme" <<'PY'
from pathlib import Path
import json
import re
import sys

theme_path = Path(sys.argv[1])
home = Path(sys.argv[2])
theme_name = sys.argv[3]

if theme_path.stat().st_size > 131072:
    raise SystemExit("theme data exceeds the safety limit")

allowed = {
    "NEW_ACTIVE_BORDER", "NEW_INACTIVE_BORDER",
    "QS_BACKGROUND", "QS_HOVER", "QS_FOCUS", "QS_ACTIVE",
    "QS_URGENT", "QS_CHARGING", "QS_CRITICAL", "QS_FOREGROUND",
    "QS_DARK", "QS_MUTED", "MICRO_COLORSCHEME", "ALACRITTY_THEME",
    "SPEEDCRUNCH_COLORSCHEME",
    # Read-only compatibility keys from pre-Quickshell Awtarchy themes.
    "W_BG", "W_COLOR", "W_CUSTOM_HOVER_BG", "W_FOCUS_BG",
    "W_ACTIVE_BG", "W_URGENT_BG", "W_BATT_CHARGING_BG",
    "W_BATT_CRITICAL_BG", "W_ACTIVE_COLOR", "W_MUTED",
}
values = {}
text = theme_path.read_text(encoding="utf-8", errors="replace")
for raw in text.splitlines():
    if len(raw) > 4096:
        raise SystemExit("theme data contains an oversized line")
    match = re.match(r"^([A-Z_][A-Z0-9_]*)=(.*)$", raw.strip())
    if not match or match.group(1) not in allowed:
        continue
    key, value = match.groups()
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    values.setdefault(key, value)

def first(*keys, default):
    for key in keys:
        value = values.get(key, "").strip()
        if value:
            return value
    return default

def color(*keys, default, border=False):
    value = first(*keys, default=default)
    pattern = r"[0-9A-Fa-f]{8}" if border else r"#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?"
    if not re.fullmatch(pattern, value):
        raise SystemExit(f"invalid theme color for {keys[0]}")
    return value

def safe_name(value, label, suffix=None):
    if not value or len(value) > 128 or any(c in value for c in "/\\\n\r\t\0"):
        raise SystemExit(f"invalid {label}")
    if suffix and not value.endswith(suffix):
        raise SystemExit(f"invalid {label}")
    return value

active_border = color("NEW_ACTIVE_BORDER", default="a0a0a0ff", border=True)
inactive_border = color("NEW_INACTIVE_BORDER", default="4b4b4bff", border=True)
palette = {
    "background": color("QS_BACKGROUND", "W_BG", default="#353535"),
    "hover": color("QS_HOVER", "W_CUSTOM_HOVER_BG", default="#404040"),
    "focus": color("QS_FOCUS", "W_FOCUS_BG", default="#4a4a4a"),
    "active": color("QS_ACTIVE", "W_ACTIVE_BG", default="#2b2b2b"),
    "urgent": color("QS_URGENT", "W_URGENT_BG", default="#ff5555"),
    "charging": color("QS_CHARGING", "W_BATT_CHARGING_BG", default="#6a9955"),
    "critical": color("QS_CRITICAL", "W_BATT_CRITICAL_BG", default="#ff5555"),
    "foreground": color("QS_FOREGROUND", "W_COLOR", default="#d0d0d0"),
    "dark": color("QS_DARK", "W_ACTIVE_COLOR", default="#1a1a1a"),
    "muted": color("QS_MUTED", "W_MUTED", default="#404040"),
    "lockAccent": f"#{active_border[:6]}",
}

micro = values.get("MICRO_COLORSCHEME", "").strip()
if not micro:
    match = re.search(r'"colorscheme"\s*:\s*"([^"]+)"', text)
    micro = match.group(1).strip() if match else "geany"
micro = safe_name(micro, "Micro colorscheme")

alacritty = values.get("ALACRITTY_THEME", "").strip()
if not alacritty:
    match = re.search(r'themes/themes/([^"\'|]+\.toml)', text)
    alacritty = match.group(1).strip() if match else "wombat.toml"
alacritty = safe_name(alacritty, "Alacritty theme", ".toml")

speedcrunch = values.get("SPEEDCRUNCH_COLORSCHEME", "").strip()
if not speedcrunch:
    match = re.search(r'Display\\ColorSchemeName=([^|\'"\n]+)', text)
    speedcrunch = match.group(1).strip() if match else theme_name
speedcrunch = safe_name(speedcrunch, "SpeedCrunch colorscheme")

hypr_lua = home / ".config/hypr/hyprland.lua"
hypr_conf = home / ".config/hypr/hyprland.conf"
if hypr_lua.is_file():
    content = hypr_lua.read_text(encoding="utf-8")
    for key, value in {
        "active_border": f"rgba({active_border})",
        "inactive_border": f"rgba({inactive_border})",
    }.items():
        pattern = re.compile(
            r'(^[ \t]*(?!--)[^\n]*?\b' + re.escape(key)
            + r'\s*=\s*)"[^"\\]*(?:\\.[^"\\]*)*"',
            re.MULTILINE,
        )
        content, count = pattern.subn(lambda m, v=value: m.group(1) + json.dumps(v), content)
        if count == 0:
            raise SystemExit(f"did not find Hyprland Lua key: {key}")
    hypr_lua.write_text(content, encoding="utf-8")
elif hypr_conf.is_file():
    content = hypr_conf.read_text(encoding="utf-8")
    content = re.sub(r"(?m)^ *col\.active_border *= *.*$", f"col.active_border = rgba({active_border})", content)
    content = re.sub(r"(?m)^ *col\.inactive_border *= *.*$", f"col.inactive_border = rgba({inactive_border})", content)
    hypr_conf.write_text(content, encoding="utf-8")

micro_settings = home / ".config/micro/settings.json"
if micro_settings.is_file():
    content = micro_settings.read_text(encoding="utf-8")
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        data = json.loads(re.sub(r",(\s*[}\]])", r"\1", content))
    data["colorscheme"] = micro
    micro_settings.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")

alacritty_conf = home / ".config/alacritty/alacritty.toml"
if alacritty_conf.is_file():
    content = alacritty_conf.read_text(encoding="utf-8")
    content, count = re.subn(
        r'~/.config/alacritty/themes/themes/[^"\n]+\.toml',
        f"~/.config/alacritty/themes/themes/{alacritty}",
        content,
    )
    if count:
        alacritty_conf.write_text(content, encoding="utf-8")

speed_ini = home / ".config/SpeedCrunch/SpeedCrunch.ini"
if speed_ini.is_file():
    content = speed_ini.read_text(encoding="utf-8")
    content, count = re.subn(
        r"(?m)^Display\\ColorSchemeName=.*$",
        lambda _match: f"Display\\ColorSchemeName={speedcrunch}",
        content,
    )
    if count:
        speed_ini.write_text(content, encoding="utf-8")

theme_json = home / ".config/quickshell/awtarchy/theme.json"
theme_json.parent.mkdir(parents=True, exist_ok=True)
theme_json.write_text(json.dumps(palette, indent=2) + "\n", encoding="utf-8")
PY
}

apply_theme_to_target() {
  local repo_dir="$1" target_home="$2" theme="$3"
  [[ -n "$theme" ]] || return 0
  local theme_script="${repo_dir}/config/hypr/themes/${theme}"
  [[ -f "$theme_script" ]] || {
    warn "Selected theme no longer exists in this release: ${theme}"
    return 1
  }

  local support_manifest="${TMPD}/theme-support.paths"
  : >"$support_manifest"

  # Theme scripts may touch application-owned files that are not stored in the
  # repository. Seed throwaway staging copies so target generation can run,
  # then remove them before the managed-file manifest is built.
  local micro_rel=".config/micro/settings.json"
  local micro_target="${target_home}/${micro_rel}"
  if [[ ! -e "$micro_target" && ! -L "$micro_target" ]]; then
    mkdir -p -- "$(dirname "$micro_target")"
    if [[ -f "${HOME_DIR}/${micro_rel}" ]]; then
      cp -a --no-preserve=ownership -- "${HOME_DIR}/${micro_rel}" "$micro_target"
    else
      cat >"$micro_target" <<'EOF'
{
    "colorscheme": "default",
    "autosave": 0
}
EOF
    fi
    printf '%s\n' "$micro_rel" >>"$support_manifest"
  fi

  log "Generating release target with theme: ${theme}"
  local rc=0 support_rel=""
  render_theme_target "$theme_script" "$target_home" "$theme" >/dev/null || rc=$?

  while IFS= read -r support_rel; do
    [[ -n "$support_rel" ]] || continue
    rm -f -- "${target_home}/${support_rel}"
    rmdir --ignore-fail-on-non-empty "$(dirname "${target_home}/${support_rel}")" 2>/dev/null || true
  done <"$support_manifest"

  return "$rc"
}

capture_fuzzel_anchor() {
  local file="${HOME_DIR}/.config/fuzzel/fuzzel.ini"
  [[ -f "$file" ]] || return 1
  python3 - "$file" <<'PY'
import re, sys
path = sys.argv[1]
in_main = False
for raw in open(path, encoding="utf-8", errors="replace"):
    line = raw.rstrip("\n")
    if re.match(r"^\s*\[main\]\s*$", line):
        in_main = True
        continue
    if re.match(r"^\s*\[", line):
        in_main = False
    if in_main and not re.match(r"^\s*[#;]", line):
        m = re.match(r"^\s*anchor\s*=\s*(.*?)\s*$", line)
        if m:
            print(m.group(1))
            raise SystemExit(0)
raise SystemExit(1)
PY
}

restore_fuzzel_anchor() {
  local value="$1" file="${HOME_DIR}/.config/fuzzel/fuzzel.ini"
  [[ -n "$value" && -f "$file" ]] || return 0
  python3 - "$file" "$value" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
value = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()
out = []
in_main = False
main_seen = False
written = False
for line in lines:
    if re.match(r"^\s*\[main\]\s*$", line):
        if in_main and not written:
            out.append(f"anchor={value}")
            written = True
        in_main = True
        main_seen = True
        out.append(line)
        continue
    if re.match(r"^\s*\[", line):
        if in_main and not written:
            out.append(f"anchor={value}")
            written = True
        in_main = False
    if in_main and not re.match(r"^\s*[#;]", line) and re.match(r"^\s*anchor\s*=", line):
        if not written:
            out.append(f"anchor={value}")
            written = True
        continue
    out.append(line)
if in_main and not written:
    out.append(f"anchor={value}")
    written = True
if not main_seen:
    out.extend(["", "[main]", f"anchor={value}"])
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

detect_hardware() {
  CPU_VENDOR="unknown"
  GPU_VENDORS=""
  GPU_DETECTION_RELIABLE=0
  IS_LAPTOP_NOW=0

  if grep -qi 'GenuineIntel' /proc/cpuinfo 2>/dev/null; then
    CPU_VENDOR="intel"
  elif grep -qi 'AuthenticAMD' /proc/cpuinfo 2>/dev/null; then
    CPU_VENDOR="amd"
  fi

  if command -v lspci >/dev/null 2>&1; then
    local lines
    lines="$(lspci -nn 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller|2D controller' || true)"
    if [[ -n "$lines" ]]; then
      local -a vendors=()
      grep -qi '\[1002:' <<<"$lines" && vendors+=(amd)
      grep -qi '\[8086:' <<<"$lines" && vendors+=(intel)
      grep -qi '\[10de:' <<<"$lines" && vendors+=(nvidia)
      if (( ${#vendors[@]} )); then
        GPU_DETECTION_RELIABLE=1
        GPU_VENDORS="$(IFS=,; printf '%s' "${vendors[*]}")"
      fi
    fi
  fi

  if [[ -d /sys/class/power_supply ]] && find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' -print -quit 2>/dev/null | grep -q .; then
    IS_LAPTOP_NOW=1
  fi
}

state_value() {
  local key="$1" file="$2"
  [[ -r "$file" ]] || return 1
  sed -n "s/^${key}=//p" "$file" | head -n1
}

vendor_present() {
  local vendor="$1" list=",${2},"
  [[ "$list" == *",${vendor},"* ]]
}

managed_packages_file() {
  printf '%s\n' '/var/lib/awtarchy/managed-packages'
}

run_update_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return
  fi

  have sudo || {
    warn "sudo is required for hardware system reconciliation."
    return 1
  }
  sudo -- "$@"
}

atomic_update_root_file_from_stdin() {
  local mode="$1" uid="$2" gid="$3" dest="$4"
  local dir tmp=""

  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || return 1
  [[ "$dest" == /* && "$dest" != *$'\n'* && "$dest" != *$'\r'* ]] || return 1

  dir="${dest%/*}"
  run_update_root /usr/bin/test -d "$dir" || return 1
  if ! run_update_root /usr/bin/test ! -L "$dir"; then
    warn "Refusing root write through symbolic-link directory: ${dir}"
    return 1
  fi
  if run_update_root /usr/bin/test -L "$dest"; then
    warn "Refusing root write to symbolic-link destination: ${dest}"
    return 1
  fi

  tmp="$(run_update_root /usr/bin/mktemp "${dir}/.awtarchy-write.XXXXXX")" || return 1
  if ! run_update_root /usr/bin/tee "$tmp" >/dev/null; then
    run_update_root /usr/bin/rm -f -- "$tmp" || true
    return 1
  fi
  if ! run_update_root /usr/bin/chmod "$mode" "$tmp" \
    || ! run_update_root /usr/bin/chown "${uid}:${gid}" "$tmp" \
    || ! run_update_root /usr/bin/mv -Tf -- "$tmp" "$dest";
  then
    run_update_root /usr/bin/rm -f -- "$tmp" || true
    return 1
  fi
}

managed_package_recorded() {
  local package="$1" manifest
  manifest="$(managed_packages_file)"
  [[ -r "$manifest" ]] && grep -Fxq "$package" "$manifest"
}

remove_managed_packages_matching() {
  local label="$1" regex="$2"
  local manifest tmp pkg
  local -a pkgs=()

  manifest="$(managed_packages_file)"
  [[ -r "$manifest" ]] || {
    warn "No Awtarchy package ownership manifest exists; refusing automatic ${label} package removal."
    return 0
  }

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    [[ "$pkg" =~ $regex ]] || continue
    pacman -Qq "$pkg" >/dev/null 2>&1 && pkgs+=("$pkg")
  done <"$manifest"

  (( ${#pkgs[@]} )) || return 0
  printf '%s\n' "${label} packages installed by Awtarchy:" >&2
  printf '  %s\n' "${pkgs[@]}" >&2
  ask_yes_no "Remove these obsolete ${label} packages?" || return 0

  run_update_root /usr/bin/pacman -Rns --noconfirm "${pkgs[@]}"

  tmp="$(mktemp)"
  grep -Fvx -f <(printf '%s\n' "${pkgs[@]}") "$manifest" >"$tmp" || true
  if ! cat -- "$tmp" | atomic_update_root_file_from_stdin 0644 0 0 "$manifest"; then
    rm -f -- "$tmp"
    return 1
  fi
  rm -f -- "$tmp"
}

record_managed_packages() {
  local manifest package tmp
  manifest="$(managed_packages_file)"
  tmp="$(mktemp)"

  if [[ -r "$manifest" ]]; then
    cat -- "$manifest" >"$tmp"
  else
    : >"$tmp"
  fi

  for package in "$@"; do
    [[ -n "$package" ]] || continue
    pacman -Qq "$package" >/dev/null 2>&1 || continue
    grep -Fxq "$package" "$tmp" || printf '%s\n' "$package" >>"$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"

  if ! run_update_root /usr/bin/install -d -m 0755 "$(dirname "$manifest")" \
    || ! cat -- "$tmp" | atomic_update_root_file_from_stdin 0644 0 0 "$manifest";
  then
    rm -f -- "$tmp"
    return 1
  fi
  rm -f -- "$tmp"
}

install_managed_pacman_packages() {
  local label="$1"
  shift
  local -a requested=("$@") missing=()
  local package

  command -v pacman >/dev/null 2>&1 || return 0

  for package in "${requested[@]}"; do
    pacman -Qq "$package" >/dev/null 2>&1 || missing+=("$package")
  done
  (( ${#missing[@]} )) || return 0

  printf '%s\n' "Required ${label} packages are missing:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  ask_yes_no "Install the missing ${label} packages?" || return 0
  run_update_root /usr/bin/pacman -S --needed --noconfirm "${missing[@]}"
  record_managed_packages "${missing[@]}"
}

target_uses_direct_aur_scanner() {
  local target_home="$1"
  local target_bashrc="${target_home}/.bashrc"

  [[ -f "$target_bashrc" && ! -L "$target_bashrc" ]] || return 1
  grep -Fq 'github.com/dillacorn/awtarchy' "$target_bashrc" || return 1
  grep -Fq 'aur-scan' "$target_bashrc" || return 1
  if grep -Eq '^(aurguard|aurverify|aurinstall)[[:space:]]*\(\)' "$target_bashrc"; then
    return 1
  fi
}

ensure_update_aur_scanner() {
  if [[ -x /usr/bin/aur-scan ]] && /usr/bin/aur-scan --version >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -x /usr/bin/yay ]] || ! /usr/bin/yay --version >/dev/null 2>&1; then
    warn "The direct aur-scanner shell is ready to migrate, but /usr/bin/aur-scan is missing and a usable /usr/bin/yay is unavailable for bootstrap."
    return 1
  fi

  log "Installing stable aur-scanner before replacing the AurGuard-era shell..."
  if ! /usr/bin/yay -S --noconfirm --pgpfetch aur-scanner; then
    warn "Failed to bootstrap stable aur-scanner; the managed shell has not been migrated."
    return 1
  fi

  if [[ ! -x /usr/bin/aur-scan ]] || ! /usr/bin/aur-scan --version >/dev/null 2>&1; then
    warn "aur-scanner bootstrap completed without a usable /usr/bin/aur-scan."
    return 1
  fi
}

multilib_enabled_update() {
  [[ -f /etc/pacman.conf ]] || return 1
  awk '
    /^[[:space:]]*#/ { next }
    /^\[multilib\]/ { found=1; next }
    found && /^[[:space:]]*Include[[:space:]]*=/ { ok=1 }
    END { exit(ok ? 0 : 1) }
  ' /etc/pacman.conf
}

nvidia_stack_installed() {
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Qq 2>/dev/null | grep -E '^(nvidia|nvidia-open|nvidia-[0-9]{3}xx|linux-cachyos.*-nvidia)(-|$)|^nvidia-utils$' >/dev/null
}

ensure_current_hardware_packages() {
  command -v pacman >/dev/null 2>&1 || return 0

  local -a common=(mesa libglvnd vulkan-icd-loader)
  local -a amd=(vulkan-radeon) intel=(vulkan-intel)
  if multilib_enabled_update; then
    common+=(lib32-mesa lib32-libglvnd lib32-vulkan-icd-loader)
    amd+=(lib32-vulkan-radeon)
    intel+=(lib32-vulkan-intel)
  fi
  install_managed_pacman_packages "common graphics" "${common[@]}"
  if vendor_present amd "$GPU_VENDORS"; then
    install_managed_pacman_packages "AMD Vulkan" "${amd[@]}"
  fi
  if vendor_present intel "$GPU_VENDORS"; then
    install_managed_pacman_packages "Intel Vulkan" "${intel[@]}"
  fi

  if vendor_present nvidia "$GPU_VENDORS" && ! nvidia_stack_installed; then
    warn "NVIDIA hardware is detected but no NVIDIA driver stack is installed."
    if ask_yes_no "Run Awtarchy GPU dependency automation for the detected GPU hardware?"; then
      if ! ( install_gpu_dependencies_main ); then
        warn "GPU dependency automation failed. Existing configuration was not removed."
      fi
    fi
  fi

  local tlp_was_missing=0 thermald_was_missing=0
  if (( IS_LAPTOP_NOW == 1 )); then
    pacman -Qq tlp >/dev/null 2>&1 || tlp_was_missing=1
    install_managed_pacman_packages "laptop power-management" tlp
    if (( tlp_was_missing == 1 )) && pacman -Qq tlp >/dev/null 2>&1; then
      run_update_root /usr/bin/systemctl enable --now tlp.service || true
    fi

    if [[ "$CPU_VENDOR" == "intel" ]]; then
      pacman -Qq thermald >/dev/null 2>&1 || thermald_was_missing=1
      install_managed_pacman_packages "Intel laptop thermald" thermald
      if (( thermald_was_missing == 1 )) && pacman -Qq thermald >/dev/null 2>&1; then
        run_update_root /usr/bin/systemctl enable --now thermald.service || true
      fi
    fi
  fi
}

comment_nvidia_lua_env() {
  local rel=".config/hypr/hyprland.lua"
  local file="${HOME_DIR}/${rel}" tmp
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  python3 - "$file" "$tmp" <<'PY'
from pathlib import Path
import re, sys
source = Path(sys.argv[1])
out = Path(sys.argv[2])
keys = {
    "GBM_BACKEND", "__GLX_VENDOR_LIBRARY_NAME", "LIBVA_DRIVER_NAME",
    "NVD_BACKEND", "__GL_GSYNC_ALLOWED", "__GL_VRR_ALLOWED"
}
lines = []
for line in source.read_text(encoding="utf-8").splitlines():
    match = re.match(r'^(\s*)(?!--)hl\.env\("([^"]+)"', line)
    if match and match.group(2) in keys:
        line = match.group(1) + "-- " + line[len(match.group(1)):]
    lines.append(line)
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

  if cmp -s -- "$file" "$tmp"; then
    rm -f -- "$tmp"
    return 0
  fi

  local already_changed=0 item
  for item in "${CHANGED[@]}"; do
    [[ "$item" == "$rel" ]] && already_changed=1
  done
  if (( already_changed == 0 )); then
    snapshot_for_rollback "$rel" "$file"
    ROLLBACK_PATHS+=("$rel")
    make_persistent_backup "$file"
    CHANGED+=("$rel")
  fi
  if ! validate_candidate "$tmp" "$rel" || ! atomic_copy "$tmp" "$file"; then
    rm -f -- "$tmp"
    rollback_changes
    return 1
  fi
  rm -f -- "$tmp"
}

remove_exact_nvidia_files() {
  local file normalized
  for file in /etc/modprobe.d/nvidia-drm.conf /etc/modprobe.d/blacklist-nouveau.conf; do
    [[ -e "$file" ]] || continue
    if [[ -L "$file" ]]; then
      warn "Leaving symbolic-link NVIDIA system file untouched: $file"
      continue
    fi
    normalized="$(run_update_root /usr/bin/cat -- "$file" 2>/dev/null | sed '/^[[:space:]]*$/d' | sed 's/[[:space:]]*$//')" || continue
    case "$file:$normalized" in
      "/etc/modprobe.d/nvidia-drm.conf:options nvidia_drm modeset=1")
        run_update_root /usr/bin/rm -f -- "$file"
        ;;
      "/etc/modprobe.d/blacklist-nouveau.conf:"$'blacklist nouveau\noptions nouveau modeset=0')
        run_update_root /usr/bin/rm -f -- "$file"
        ;;
      *)
        warn "Leaving modified NVIDIA system file untouched: $file"
        ;;
    esac
  done
}

remove_nvidia_boot_entries() {
  local changed=0 file tmp mode uid gid backup source_tmp
  local -a files=()

  if run_update_root /usr/bin/test -d /boot/loader/entries; then
    while IFS= read -r -d '' file; do
      files+=("$file")
    done < <(run_update_root /usr/bin/find /boot/loader/entries -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null || true)
  fi

  for file in /etc/default/grub /boot/limine/limine.conf /boot/limine.conf /boot/EFI/limine/limine.conf /boot/limine/limine.cfg /boot/limine.cfg; do
    run_update_root /usr/bin/test -f "$file" && files+=("$file")
  done

  for file in "${files[@]}"; do
    run_update_root /usr/bin/test ! -L "$file" || {
      warn "Leaving symbolic-link bootloader file untouched: $file"
      continue
    }
    run_update_root /usr/bin/grep -Eq 'nvidia[-_]drm\.modeset=1' "$file" || continue

    tmp="$(mktemp)"
    run_update_root /usr/bin/cat -- "$file" \
      | sed -E 's/(^|[[:space:]])nvidia[-_]drm\.modeset=1([[:space:]]|$)/ /g; s/[[:space:]]+/ /g; s/ =/=/g; s/[[:space:]]+$//' \
      >"$tmp"
    mode="$(run_update_root /usr/bin/stat -c '%a' -- "$file")"
    uid="$(run_update_root /usr/bin/stat -c '%u' -- "$file")"
    gid="$(run_update_root /usr/bin/stat -c '%g' -- "$file")"
    backup="${file}.backup.$(stamp)"
    run_update_root /usr/bin/cp -a -- "$file" "$backup"
    if ! cat -- "$tmp" | atomic_update_root_file_from_stdin "$mode" "$uid" "$gid" "$file"; then
      rm -f -- "$tmp"
      return 1
    fi
    rm -f -- "$tmp"
    changed=1
  done

  if run_update_root /usr/bin/test -f /etc/mkinitcpio.conf \
    && run_update_root /usr/bin/test ! -L /etc/mkinitcpio.conf \
    && run_update_root /usr/bin/grep -Eq 'MODULES=.*nvidia' /etc/mkinitcpio.conf;
  then
    source_tmp="$(mktemp)"
    tmp="$(mktemp)"
    run_update_root /usr/bin/cat -- /etc/mkinitcpio.conf >"$source_tmp"
    python3 - "$source_tmp" "$tmp" <<'PY'
from pathlib import Path
import re, sys
source = Path(sys.argv[1])
out_path = Path(sys.argv[2])
remove = {"nvidia", "nvidia_modeset", "nvidia_uvm", "nvidia_drm"}
out = []
for line in source.read_text().splitlines():
    m = re.match(r'^(\s*MODULES=\()(.*)(\)\s*)$', line)
    if m:
        words = [w for w in m.group(2).split() if w not in remove]
        line = m.group(1) + " ".join(words) + m.group(3)
    out.append(line)
out_path.write_text("\n".join(out) + "\n")
PY
    mode="$(run_update_root /usr/bin/stat -c '%a' -- /etc/mkinitcpio.conf)"
    uid="$(run_update_root /usr/bin/stat -c '%u' -- /etc/mkinitcpio.conf)"
    gid="$(run_update_root /usr/bin/stat -c '%g' -- /etc/mkinitcpio.conf)"
    backup="/etc/mkinitcpio.conf.backup.$(stamp)"
    run_update_root /usr/bin/cp -a -- /etc/mkinitcpio.conf "$backup"
    if ! cat -- "$tmp" | atomic_update_root_file_from_stdin "$mode" "$uid" "$gid" /etc/mkinitcpio.conf; then
      rm -f -- "$source_tmp" "$tmp"
      return 1
    fi
    rm -f -- "$source_tmp" "$tmp"
    changed=1
  fi

  if (( changed == 1 )); then
    if command -v grub-mkconfig >/dev/null 2>&1 && run_update_root /usr/bin/test -f /boot/grub/grub.cfg; then
      run_update_root /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg || true
    fi
    if command -v mkinitcpio >/dev/null 2>&1; then
      run_update_root /usr/bin/mkinitcpio -P
    elif command -v dracut >/dev/null 2>&1; then
      run_update_root /usr/bin/dracut --regenerate-all --force
    fi
  fi
}

hardware_reconcile() {
  detect_hardware
  local prev_cpu="" prev_gpu="" prev_laptop="" gpu_cleanup_allowed=1
  prev_cpu="$(state_value cpu_vendor "$HARDWARE_FILE" || true)"
  prev_gpu="$(state_value gpu_vendors "$HARDWARE_FILE" || true)"
  prev_laptop="$(state_value is_laptop "$HARDWARE_FILE" || true)"

  {
    printf 'Hardware detected:\n'
    printf '  CPU vendor: %s\n' "$CPU_VENDOR"
    printf '  GPU vendors: %s\n' "${GPU_VENDORS:-unknown}"
    printf '  Laptop: %s\n' "$IS_LAPTOP_NOW"
    if [[ -n "$prev_cpu" ]]; then
      printf 'Previous Awtarchy state: CPU=%s GPU=%s laptop=%s\n' "$prev_cpu" "$prev_gpu" "$prev_laptop"
    fi
  } | tee -a "$AUDIT_LOG"

  if (( GPU_DETECTION_RELIABLE == 0 )); then
    gpu_cleanup_allowed=0
    warn "GPU detection was inconclusive; no vendor cleanup will be attempted."
  fi

  if (( gpu_cleanup_allowed == 1 )); then
    if vendor_present nvidia "$prev_gpu" && ! vendor_present nvidia "$GPU_VENDORS"; then
      warn "NVIDIA hardware was previously recorded but is no longer detected."
      if ask_yes_no "Disable obsolete NVIDIA Hyprland settings and clean Awtarchy-owned NVIDIA system state?"; then
        comment_nvidia_lua_env
        remove_managed_packages_matching "NVIDIA" '^(nvidia|lib32-nvidia|opencl-nvidia|lib32-opencl-nvidia|libva-nvidia-driver|egl-wayland|linux-cachyos.*-nvidia)'
        remove_exact_nvidia_files
        remove_nvidia_boot_entries
      fi
    fi

    if vendor_present amd "$prev_gpu" && ! vendor_present amd "$GPU_VENDORS"; then
      remove_managed_packages_matching "AMD Vulkan" '^(vulkan-radeon|lib32-vulkan-radeon)$'
    fi

    if vendor_present intel "$prev_gpu" && ! vendor_present intel "$GPU_VENDORS"; then
      remove_managed_packages_matching "Intel Vulkan" '^(vulkan-intel|lib32-vulkan-intel)$'
    fi
  fi

  if [[ "$prev_cpu" == "intel" && "$CPU_VENDOR" != "intel" && "$CPU_VENDOR" != "unknown" ]]; then
    if managed_package_recorded thermald; then
      if systemctl is-enabled thermald.service >/dev/null 2>&1; then
        run_update_root /usr/bin/systemctl disable --now thermald.service || true
      fi
      remove_managed_packages_matching "Intel CPU thermald" '^thermald$'
    else
      warn "thermald is not recorded as Awtarchy-owned; leaving it untouched."
    fi
  fi

  if [[ "$prev_laptop" == "1" && "$IS_LAPTOP_NOW" == "0" ]]; then
    if managed_package_recorded tlp; then
      if systemctl is-enabled tlp.service >/dev/null 2>&1; then
        run_update_root /usr/bin/systemctl disable --now tlp.service || true
      fi
    fi
    remove_managed_packages_matching "laptop power-management" '^(tlp|tlpui)$'
  fi

  if (( gpu_cleanup_allowed == 0 )); then
    local saved_gpu="$GPU_VENDORS"
    GPU_VENDORS=""
    ensure_current_hardware_packages
    GPU_VENDORS="$saved_gpu"
  else
    ensure_current_hardware_packages
  fi

  configure_mdns_stack
}


print_hardware_preview() {
  detect_hardware
  local prev_cpu="" prev_gpu="" prev_laptop=""
  prev_cpu="$(state_value cpu_vendor "$HARDWARE_FILE" || true)"
  prev_gpu="$(state_value gpu_vendors "$HARDWARE_FILE" || true)"
  prev_laptop="$(state_value is_laptop "$HARDWARE_FILE" || true)"

  printf '\nHardware review:\n'
  printf '  Current CPU vendor: %s\n' "$CPU_VENDOR"
  printf '  Current GPU vendors: %s\n' "${GPU_VENDORS:-unknown}"
  printf '  Current form factor: %s\n' "$([[ "$IS_LAPTOP_NOW" == 1 ]] && printf laptop || printf desktop)"
  if [[ -n "$prev_cpu" || -n "$prev_gpu" || -n "$prev_laptop" ]]; then
    printf '  Previous state: CPU=%s GPU=%s laptop=%s\n' "${prev_cpu:-unknown}" "${prev_gpu:-unknown}" "${prev_laptop:-unknown}"
  else
    printf '  Previous state: not recorded yet\n'
  fi

  if (( GPU_DETECTION_RELIABLE == 0 )); then
    printf '  GPU cleanup: disabled because detection is inconclusive\n'
  else
    vendor_present nvidia "$prev_gpu" && ! vendor_present nvidia "$GPU_VENDORS" \
      && printf '  Proposed transition: remove Awtarchy-owned NVIDIA state after confirmation\n'
    vendor_present amd "$prev_gpu" && ! vendor_present amd "$GPU_VENDORS" \
      && printf '  Proposed transition: remove Awtarchy-owned AMD Vulkan packages after confirmation\n'
    vendor_present intel "$prev_gpu" && ! vendor_present intel "$GPU_VENDORS" \
      && printf '  Proposed transition: remove Awtarchy-owned Intel Vulkan packages after confirmation\n'
  fi
  if [[ "$prev_cpu" == intel && "$CPU_VENDOR" != intel && "$CPU_VENDOR" != unknown ]]; then
    printf '  Proposed transition: disable/remove Awtarchy-owned thermald after confirmation\n'
  fi
  if [[ "$prev_laptop" == 1 && "$IS_LAPTOP_NOW" == 0 ]]; then
    printf '  Proposed transition: disable/remove Awtarchy-owned laptop power tools after confirmation\n'
  fi
  printf '\n'
}

write_hardware_state() {
  local saved_cpu="$CPU_VENDOR" saved_gpu="$GPU_VENDORS"
  if [[ "$saved_cpu" == "unknown" && -r "$HARDWARE_FILE" ]]; then
    saved_cpu="$(state_value cpu_vendor "$HARDWARE_FILE" || printf 'unknown')"
  fi
  if (( GPU_DETECTION_RELIABLE == 0 )) && [[ -r "$HARDWARE_FILE" ]]; then
    saved_gpu="$(state_value gpu_vendors "$HARDWARE_FILE" || true)"
  fi

  mkdir -p -- "$(dirname "$HARDWARE_FILE")"
  {
    printf 'cpu_vendor=%s\n' "$saved_cpu"
    printf 'gpu_vendors=%s\n' "$saved_gpu"
    printf 'is_laptop=%s\n' "$IS_LAPTOP_NOW"
    printf 'updated_at=%s\n' "$(ts)"
  } >"$HARDWARE_FILE"
}

bootstrap_previous_baseline() {
  local active_theme="$1"
  local version_file="" old_tag="" old_updated_at=""
  local old_tgz old_top old_repo old_home old_manifest
  local source_repo="" local_ref="" history_ref="" archive_ready=0 recovered_locally=0

  if [[ -d "$BASELINE_HOME" && -r "$MANIFEST_FILE" ]]; then
    if quickshell_hyprland_has_legacy_refs "${HOME_DIR}/.config/hypr/hyprland.lua" \
      && ! quickshell_hyprland_has_legacy_refs "${BASELINE_HOME}/.config/hypr/hyprland.lua";
    then
      log "Live Hyprland still references the retired Awtarchy shell; reconstructing the previous stable baseline before migration."
    else
      return 0
    fi
  fi

  for version_file in \
    "${STATE_DIR}/config-version" \
    "${STATE_DIR}/baseline/metadata" \
    "${STATE_DIR}/command-version" \
    "${HOME_DIR}/.cache/awtarchy/version"
  do
    old_tag="$(sed -n 's/^tag=//p' "$version_file" 2>/dev/null | head -n1 || true)"
    [[ -n "$old_tag" ]] || continue
    case "$old_tag" in
      unknown|unreleased)
        old_tag=""
        continue
        ;;
    esac
    if [[ $old_tag =~ ^.+@[0-9a-fA-F]{40}$ ]]; then
      old_tag=""
      continue
    fi
    old_updated_at="$(
      sed -n -E 's/^(updated_at|installed_at|migrated_at|generated_at)=//p' \
        "$version_file" 2>/dev/null | head -n1 || true
    )"
    break
  done

  [[ -n "$old_tag" ]] || {
    warn "No previous release tag is available; legacy differences will be preserved conservatively."
    return 0
  }

  log "Reconstructing previous generated baseline from release: ${old_tag}"
  old_tgz="${TMPD}/previous-awtarchy.tgz"

  if download_release_tarball "$old_tag" "$old_tgz" 30; then
    archive_ready=1
  else
    warn "The previous release tag ${old_tag} is no longer available from GitHub."

    source_repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    if command -v git >/dev/null 2>&1 && git -C "$source_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local_ref="$(
        git -C "$source_repo" rev-parse --verify "refs/tags/${old_tag}^{commit}" 2>/dev/null \
          || true
      )"

      if [[ -z "$local_ref" && -n "$old_updated_at" ]]; then
        for history_ref in refs/remotes/origin/main refs/heads/main HEAD; do
          git -C "$source_repo" rev-parse --verify "${history_ref}^{commit}" >/dev/null 2>&1 \
            || continue
          local_ref="$(
            git -C "$source_repo" rev-list -1 --before="$old_updated_at" "$history_ref" 2>/dev/null \
              || true
          )"
          [[ -n "$local_ref" ]] && break
        done
      fi

      if [[ -n "$local_ref" ]]; then
        local prefix="awtarchy-previous-${local_ref:0:12}"
        if git -C "$source_repo" archive \
          --format=tar.gz \
          --prefix="${prefix}/" \
          --output="$old_tgz" \
          "$local_ref"
        then
          archive_ready=1
          recovered_locally=1
          log "Recovered a previous-release candidate from local Git history: ${local_ref:0:12}"
        fi
      fi
    fi
  fi

  if (( archive_ready == 0 )); then
    warn "Could not reconstruct previous release ${old_tag}; using conservative legacy handling."
    return 0
  fi

  if ! old_top="$(tar_topdir "$old_tgz")"; then
    warn "Previous release archive ${old_tag} was unreadable; using conservative legacy handling."
    return 0
  fi

  mkdir -p -- "${TMPD}/previous-release"
  tar -xzf "$old_tgz" -C "${TMPD}/previous-release"
  old_repo="${TMPD}/previous-release/${old_top}"
  old_home="${TMPD}/previous-target-home"
  build_target_home "$old_repo" "$old_home"

  if [[ -n "$active_theme" && -f "${old_repo}/config/hypr/themes/${active_theme}" ]]; then
    if ! apply_theme_to_target "$old_repo" "$old_home" "$active_theme"; then
      warn "Could not generate the previous themed baseline; using conservative legacy handling."
      return 0
    fi
  fi

  if (( recovered_locally == 1 )); then
    local score exact comparable percent
    score="$(
      python3 - "$HOME_DIR" "$old_home" <<'PY'
from pathlib import Path
import os
import sys

live = Path(sys.argv[1])
candidate = Path(sys.argv[2])

exact = 0
comparable = 0

for candidate_path in candidate.rglob("*"):
    if not (candidate_path.is_file() or candidate_path.is_symlink()):
        continue

    rel = candidate_path.relative_to(candidate)
    live_path = live / rel

    if not (live_path.exists() or live_path.is_symlink()):
        continue

    comparable += 1

    if candidate_path.is_symlink() or live_path.is_symlink():
        if (
            candidate_path.is_symlink()
            and live_path.is_symlink()
            and os.readlink(candidate_path) == os.readlink(live_path)
        ):
            exact += 1
        continue

    try:
        if candidate_path.read_bytes() == live_path.read_bytes():
            exact += 1
    except OSError:
        pass

percent = int((exact * 100) / comparable) if comparable else 0
print(exact, comparable, percent)
PY
    )"
    IFS=" " read -r exact comparable percent <<<"$score"

    log "Recovered baseline confidence: ${exact}/${comparable} comparable files match exactly (${percent}%)."

    if (( comparable < 10 || exact < 5 || percent < 35 )); then
      warn "The recovered local-history candidate does not match enough installed files to trust."
      warn "Using conservative legacy handling instead of risking an incorrect three-way baseline."
      return 0
    fi
  fi

  old_manifest="${TMPD}/previous-manifest.paths"
  find "$old_home" \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort >"$old_manifest"
  BASELINE_HOME="$old_home"
  MANIFEST_FILE="$old_manifest"
}

home_rel_to_repo_path() {
  local rel="$1"
  case "$rel" in
    .config/*)
      printf 'config/%s\n' "${rel#.config/}"
      ;;
    .local/share/*)
      printf 'local/share/%s\n' "${rel#.local/share/}"
      ;;
    .bashrc)
      printf 'bashrc\n'
      ;;
    .bash_profile)
      printf 'bash_profile\n'
      ;;
    .Xresources)
      printf 'Xresources\n'
      ;;
    Pictures/wallpapers/awtarchy_geology.png)
      printf 'awtarchy_geology.png\n'
      ;;
    *)
      return 1
      ;;
  esac
}

augment_baseline_from_local_git_history() {
  local target_home="$1"
  local source_repo augmented_root augmented_home augmented_manifest
  local rel repo_path local_file recovered_file commit tree_mode
  local recovered=0

  source_repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  command -v git >/dev/null 2>&1 || return 0
  git -C "$source_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  augmented_root="${TMPD}/augmented-baseline"
  augmented_home="${augmented_root}/home"
  augmented_manifest="${augmented_root}/manifest.paths"
  rm -rf -- "$augmented_root"
  mkdir -p -- "$augmented_home"

  if [[ -d "$BASELINE_HOME" ]]; then
    cp -a --no-preserve=ownership -- "$BASELINE_HOME/." "$augmented_home/"
  fi
  if [[ -r "$MANIFEST_FILE" ]]; then
    cp -- "$MANIFEST_FILE" "$augmented_manifest"
  else
    : >"$augmented_manifest"
  fi

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    [[ -e "${augmented_home}/${rel}" || -L "${augmented_home}/${rel}" ]] && continue

    local_file="${HOME_DIR}/${rel}"
    [[ -f "$local_file" && ! -L "$local_file" ]] || continue

    repo_path="$(home_rel_to_repo_path "$rel" || true)"
    [[ -n "$repo_path" ]] || continue

    recovered_file="${augmented_root}/candidate"
    while IFS= read -r commit; do
      [[ -n "$commit" ]] || continue
      if ! git -C "$source_repo" show "${commit}:${repo_path}" >"$recovered_file" 2>/dev/null; then
        continue
      fi
      cmp -s -- "$local_file" "$recovered_file" || continue

      mkdir -p -- "$(dirname -- "${augmented_home}/${rel}")"
      cp -- "$recovered_file" "${augmented_home}/${rel}"

      tree_mode="$(
        git -C "$source_repo" ls-tree "$commit" -- "$repo_path" 2>/dev/null \
          | awk 'NR == 1 { print $1 }'
      )"
      case "$rel" in
        .config/hypr/scripts/*|.config/hypr/themes/*|.config/waybar/scripts/*)
          chmod 0755 "${augmented_home}/${rel}"
          ;;
        *)
          if [[ "$tree_mode" == "100755" ]]; then
            chmod 0755 "${augmented_home}/${rel}"
          else
            chmod 0644 "${augmented_home}/${rel}"
          fi
          ;;
      esac

      printf '%s\n' "$rel" >>"$augmented_manifest"
      ((recovered++)) || true
      break
    done < <(
      git -C "$source_repo" log --all --format='%H' -- "$repo_path" 2>/dev/null
    )
  done < <(
    find "$target_home" \( -type f -o -type l \) -printf '%P\n' \
      | LC_ALL=C sort
  )

  if (( recovered == 0 )); then
    rm -rf -- "$augmented_root"
    return 0
  fi

  LC_ALL=C sort -u -o "$augmented_manifest" "$augmented_manifest"
  normalize_managed_executables "$augmented_home"
  BASELINE_HOME="$augmented_home"
  MANIFEST_FILE="$augmented_manifest"
  log "Recovered ${recovered} missing baseline file(s) by matching installed content to local Git history."
}

validate_managed_relative_path() {
  local rel="$1"
  [[ -n $rel && $rel != /* \
    && $rel != *$'\n'* && $rel != *$'\r'* && $rel != *$'\t'* \
    && $rel != *$'\\'* \
    && "/$rel/" != *'/../'* && "/$rel/" != *'/./'* && "/$rel/" != *'//'* ]] \
    || return 1

  case "$rel" in
    .bashrc|.bash_profile|.Xresources|.config/mimeapps.list|.config/gamemode.ini)
      return 0
      ;;
    .config/hypr/*|.config/quickshell/*|.config/alacritty/*|.config/gtk-3.0/*|\
    .config/Kvantum/*|.config/SpeedCrunch/*|.config/fastfetch/*|\
    .config/pcmanfm-qt/*|.config/yazi/*|.config/xdg-desktop-portal/*|\
    .config/qt5ct/*|.config/qt6ct/*|.config/lsfg-vk/*|.config/wiremix/*|\
    .config/cava/*|.config/micro/*|.config/ddcutil/*|\
    .config/waybar/*|.config/fuzzel/*|.config/mako/*|.config/wlogout/*|.config/wofi/*|\
    .local/share/nwg-look/*|.local/share/SpeedCrunch/*|.local/share/applications/*|\
    Pictures/wallpapers/awtarchy_geology.png)
      return 0
      ;;
  esac
  return 1
}

validate_plan_row() {
  local class="$1" rel="$2" local_file="$3" target_file="$4" baseline_file="$5"
  case "$class" in
    NEW|OUTDATED|USER|LEGACY|BOTH|REMOVED|ORPHANED) ;;
    *) return 1 ;;
  esac
  validate_managed_relative_path "$rel" || return 1
  [[ $local_file == "${HOME_DIR}/${rel}" \
    && $target_file == "${TARGET_STAGE_HOME}/${rel}" \
    && $baseline_file == "${BASELINE_HOME}/${rel}" ]]
}

build_plan() {
  local target_home="$1" plan_file="$2"
  python3 - "$HOME_DIR" "$target_home" "$BASELINE_HOME" "$MANIFEST_FILE" "$plan_file" <<'PY'
from pathlib import Path, PurePosixPath
import json, os, re, stat, sys
home, target, baseline, manifest, out = map(Path, sys.argv[1:])

CONFIG_ROOTS = {
    "hypr", "quickshell", "alacritty", "gtk-3.0", "Kvantum",
    "SpeedCrunch", "fastfetch", "pcmanfm-qt", "yazi",
    "xdg-desktop-portal", "qt5ct", "qt6ct", "lsfg-vk", "wiremix",
    "cava", "micro", "ddcutil", "waybar", "fuzzel", "mako",
    "wlogout", "wofi",
}

def valid_rel(raw):
    if not raw or raw.startswith("/") or "\\" in raw or any(c in raw for c in "\n\r\t\0"):
        return False
    path = PurePosixPath(raw)
    if any(part in {"", ".", ".."} for part in raw.split("/")):
        return False
    parts = path.parts
    if raw in {".bashrc", ".bash_profile", ".Xresources", ".config/mimeapps.list", ".config/gamemode.ini"}:
        return True
    if len(parts) >= 3 and parts[0] == ".config" and parts[1] in CONFIG_ROOTS:
        return True
    if len(parts) >= 4 and parts[:3] in {
        (".local", "share", "nwg-look"),
        (".local", "share", "SpeedCrunch"),
        (".local", "share", "applications"),
    }:
        return True
    return raw == "Pictures/wallpapers/awtarchy_geology.png"

def paths(root):
    if not root.exists():
        return set()
    found = set()
    for p in root.rglob("*"):
        if p.is_file() or p.is_symlink():
            rel = p.relative_to(root).as_posix()
            if not valid_rel(rel):
                raise SystemExit(f"unsafe managed target path: {rel}")
            found.add(rel)
    return found

def semantic_file_bytes(rel, path):
    data = path.read_bytes()

    if rel == ".config/micro/bindings.json":
        try:
            parsed = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return data
        return json.dumps(
            parsed,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")

    ini_like = {
        ".config/SpeedCrunch/SpeedCrunch.ini",
        ".config/pcmanfm-qt/default/settings.conf",
        ".config/qt5ct/qt5ct.conf",
        ".config/qt6ct/qt6ct.conf",
    }
    if rel not in ini_like:
        return data

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data

    section = ""
    normalized = []
    speedcrunch_noise = {
        "Layout\\ManualWindowGeometry",
        "Layout\\State",
        "Layout\\WindowGeometry",
        "Layout\\WindowOnFullScreen",
    }
    pcman_noise = {
        "Desktop": {
            "LastSlide",
            "ScreenNames",
            "WallpaperDialogSize",
            "WallpaperDialogSplitterPos",
        },
        "FolderView": {"CustomColumnWidths"},
        "Search": {"ContentPatterns", "NamePatterns"},
        "Window": {
            "LastWindowHeight",
            "LastWindowMaximized",
            "LastWindowWidth",
            "SplitViewTabsNum",
            "SplitterPos",
            "TabPaths",
        },
    }

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
            normalized.append(raw_line)
            continue

        key = stripped.split("=", 1)[0] if "=" in stripped else ""

        if rel == ".config/SpeedCrunch/SpeedCrunch.ini" and section == "SpeedCrunch" and key in speedcrunch_noise:
            continue

        if rel == ".config/pcmanfm-qt/default/settings.conf":
            if key in pcman_noise.get(section, set()):
                continue
            if (
                section == "Desktop"
                and key == "NoItemTooltip"
                and stripped.split("=", 1)[1].strip().lower() == "false"
            ):
                continue
            if section == "Desktop" and key == "Font":
                raw_line = re.sub(r',,0,0"$', '"', raw_line)

        if (
            rel in {".config/qt5ct/qt5ct.conf", ".config/qt6ct/qt6ct.conf"}
            and section == "SettingsWindow"
            and key == "geometry"
        ):
            continue

        normalized.append(raw_line)

    return ("\n".join(normalized) + "\n").encode("utf-8")


def identity(rel, path):
    if not path.exists() and not path.is_symlink():
        return None
    if path.is_symlink():
        return ("link", os.readlink(path))
    mode = stat.S_IMODE(path.stat().st_mode)
    return ("file", mode, semantic_file_bytes(rel, path))

new_paths = paths(target)
old_paths = set()
legacy_nonmanaged_baseline_paths = {
    ".local/state/awtarchy/active-theme",
}
if manifest.is_file():
    for line in manifest.read_text().splitlines():
        rel = line.strip()
        if not rel:
            continue
        if rel in legacy_nonmanaged_baseline_paths:
            continue
        if not valid_rel(rel):
            raise SystemExit(f"unsafe managed baseline path: {rel}")
        old_paths.add(rel)
all_paths = sorted(new_paths | old_paths)
rows = []
for rel in all_paths:
    local = home / rel
    new = target / rel
    old = baseline / rel
    li, ni, oi = identity(rel, local), identity(rel, new), identity(rel, old)
    if ni is not None and li == ni:
        continue
    if ni is None:
        cls = "REMOVED" if oi is not None and li == oi else "ORPHANED"
    elif li is None:
        cls = "NEW"
    elif oi is None:
        cls = "LEGACY"
    elif li == oi:
        cls = "OUTDATED"
    elif ni == oi:
        cls = "USER"
    else:
        cls = "BOTH"
    rows.append((cls, rel, str(local), str(new), str(old)))
with out.open("w", encoding="utf-8") as f:
    for row in rows:
        f.write("\t".join(row) + "\n")
PY
}

read_update_key() {
  local key="" rest="" c=""
  IFS= read -rsn1 key </dev/tty || return 1
  if [[ "$key" == $'\033' ]]; then
    rest=""
    while IFS= read -rsn1 -t 0.02 c </dev/tty; do
      rest+="$c"
      [[ "$c" == "M" || "$c" == "m" || ${#rest} -ge 32 ]] && break
    done
    key+="$rest"
  fi
  printf '%s' "$key"
}

enable_mouse() {
  printf '\033[?1000h\033[?1006h' >/dev/tty
  MOUSE_ENABLED=1
}

disable_mouse() {
  printf '\033[?1000l\033[?1006l' >/dev/tty 2>/dev/null || true
  MOUSE_ENABLED=0
}

file_summary() {
  local label="$1" file="$2"
  if [[ -f "$file" ]]; then
    printf '%s SHA-256: %s\n' "$label" "$(sha256sum "$file" | awk '{print $1}')"
    printf '%s lines: %s\n' "$label" "$(wc -l <"$file")"
  elif [[ -L "$file" ]]; then
    printf '%s symlink: %s\n' "$label" "$(readlink "$file")"
  else
    printf '%s: missing\n' "$label"
  fi
}

show_diff() {
  local class="$1" rel="$2" local_file="$3" target_file="$4" baseline_file="$5"
  disable_mouse
  local tmp="${TMPD}/diff.$RANDOM" left="$local_file" right="$target_file"
  [[ -e "$left" || -L "$left" ]] || left=/dev/null
  [[ -e "$right" || -L "$right" ]] || right=/dev/null
  {
    printf 'Classification: %s\n' "$class"
    printf 'Managed path: %s\n' "$rel"
    file_summary Local "$local_file"
    file_summary Release "$target_file"
    printf '\nLines beginning with - are local. Lines beginning with + are the release target.\n\n'
    if command -v git >/dev/null 2>&1; then
      git --no-pager diff --no-index --color=always -- "$left" "$right" || true
    else
      diff -u -- "$left" "$right" || true
    fi
  } >"$tmp"

  if command -v less >/dev/null 2>&1; then
    less -R "$tmp" </dev/tty >/dev/tty
  else
    cat "$tmp" >/dev/tty
    printf '\nPress any key to return...' >/dev/tty
    read_update_key >/dev/null || true
  fi
  rm -f -- "$tmp"
  enable_mouse
}

review_plan() {
  local plan_file="$1"
  local -a classes=() rels=() locals=() targets=() baselines=()
  local class rel local_file target_file baseline_file
  while IFS=$'\t' read -r class rel local_file target_file baseline_file; do
    [[ -n "$class" ]] || continue
    validate_plan_row "$class" "$rel" "$local_file" "$target_file" "$baseline_file" \
      || die "Refusing unsafe managed-file review row: ${rel:-<empty>}"
    classes+=("$class")
    rels+=("$rel")
    locals+=("$local_file")
    targets+=("$target_file")
    baselines+=("$baseline_file")
  done <"$plan_file"

  if (( ${#classes[@]} == 0 )); then
    log "All managed files exactly match the generated release target."
    return 0
  fi

  if ! is_interactive; then
    warn "Non-interactive shell: printing mismatch list without the browser."
    local i
    for i in "${!classes[@]}"; do
      printf '%4d  %-12s  %s\n' "$((i + 1))" "[${classes[i]}]" "${rels[i]}"
    done
    return 0
  fi

  local index=0 page_start=0 page_size=12 key="" i mouse_y mouse_index
  enable_mouse
  while true; do
    local lines
    lines="$(tput lines 2>/dev/null || printf '24')"
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=24
    page_size=$((lines - 9))
    (( page_size < 5 )) && page_size=5
    page_start=$((index / page_size * page_size))

    printf '\033[H\033[2J' >/dev/tty
    printf 'Awtarchy managed-file differences: %d\n\n' "${#classes[@]}" >/dev/tty
    printf 'Click/Enter or press 1-9 to view a diff. Entries are informational, not update toggles.\n' >/dev/tty
    printf 'Page Up/Page Down changes pages. q closes review and continues the requested operation.\n\n' >/dev/tty

    for (( i = 0; i < page_size && page_start + i < ${#classes[@]}; i++ )); do
      local absolute=$((page_start + i)) marker=' '
      (( absolute == index )) && marker='>'
      printf '%s %2d. %-12s %s\n' "$marker" "$((i + 1))" "[${classes[absolute]}]" "${rels[absolute]}" >/dev/tty
    done

    key="$(read_update_key || true)"
    case "$key" in
      $'\033[A') (( index > 0 )) && ((index--)) || true ;;
      $'\033[B') (( index + 1 < ${#classes[@]} )) && ((index++)) || true ;;
      $'\033[5~') index=$((index - page_size)); (( index < 0 )) && index=0 ;;
      $'\033[6~') index=$((index + page_size)); (( index >= ${#classes[@]} )) && index=$((${#classes[@]} - 1)) ;;
      $'\n'|$'\r'|"")
        show_diff "${classes[index]}" "${rels[index]}" "${locals[index]}" "${targets[index]}" "${baselines[index]}"
        ;;
      q|Q)
        disable_mouse
        return 0
        ;;
      [1-9])
        i=$((10#$key - 1))
        if (( i < page_size && page_start + i < ${#classes[@]} )); then
          index=$((page_start + i))
          show_diff "${classes[index]}" "${rels[index]}" "${locals[index]}" "${targets[index]}" "${baselines[index]}"
        fi
        ;;
      $'\033[<'*M|$'\033[<'*m)
        if [[ "$key" =~ ^$'\033'\[\<([0-9]+)\;([0-9]+)\;([0-9]+)(M|m)$ ]]; then
          mouse_y="${BASH_REMATCH[3]}"
          mouse_index=$((mouse_y - 6))
          if (( mouse_index >= 0 && mouse_index < page_size && page_start + mouse_index < ${#classes[@]} )); then
            index=$((page_start + mouse_index))
            show_diff "${classes[index]}" "${rels[index]}" "${locals[index]}" "${targets[index]}" "${baselines[index]}"
          fi
        fi
        ;;
    esac
  done
}

select_update_mode() {
  [[ -n "$UPDATE_MODE" ]] && return 0
  if ! is_interactive; then
    UPDATE_MODE="preserve"
    warn "Non-interactive shell: defaulting to preserve mode."
    return 0
  fi

  local choice=""
  while true; do
    printf '\nUpdate mode:\n' >/dev/tty
    printf '  1. Update managed files and preserve hyprland.lua customizations (recommended)\n' >/dev/tty
    printf '  2. Clean-slate managed files\n' >/dev/tty
    printf '  3. Cancel\n' >/dev/tty
    printf 'Choose [1]: ' >/dev/tty
    IFS= read -r choice </dev/tty || die "Update canceled."
    case "$choice" in
      ""|1) UPDATE_MODE="preserve"; return 0 ;;
      2) UPDATE_MODE="clean"; return 0 ;;
      3) die "Update canceled." ;;
    esac
  done
}

make_persistent_backup() {
  local dest="$1"
  [[ -e "$dest" || -L "$dest" ]] || return 0
  local backup="${dest}.backup"
  [[ -e "$backup" || -L "$backup" ]] && backup="${dest}.backup.$(stamp)"
  cp -a -- "$dest" "$backup"
  BACKUPS+=("$backup")
}

snapshot_for_rollback() {
  local rel="$1" dest="$2"
  local root="${TMPD}/rollback/home/${rel}"
  mkdir -p -- "$(dirname "$root")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    cp -a -- "$dest" "$root"
  else
    : >"${root}.awtarchy-absent"
  fi
}

rollback_changes() {
  warn "Rolling back changed user files."
  local rel dest saved
  for rel in "${ROLLBACK_PATHS[@]}"; do
    dest="${HOME_DIR}/${rel}"
    saved="${TMPD}/rollback/home/${rel}"
    rm -rf -- "$dest" 2>/dev/null || true
    if [[ -e "$saved" || -L "$saved" ]]; then
      mkdir -p -- "$(dirname "$dest")"
      cp -a -- "$saved" "$dest"
    fi
  done
}

atomic_copy() {
  local src="$1" dest="$2" tmp
  [[ -e "$src" || -L "$src" ]] || return 1
  mkdir -p -- "$(dirname "$dest")"
  tmp="$(mktemp --tmpdir="$(dirname "$dest")" '.awtarchy.tmp.XXXXXX')"
  rm -f -- "$tmp"
  cp -a --no-preserve=ownership -- "$src" "$tmp"
  [[ "${EUID}" -eq 0 ]] && chown -h "${TARGET_USER}:${TARGET_USER}" "$tmp" 2>/dev/null || true
  mv -Tf -- "$tmp" "$dest"
}

validate_candidate() {
  local file="$1" rel="$2"
  [[ -f "$file" ]] || return 0
  case "$rel" in
    *.sh|.bashrc|.bash_profile) bash -n "$file" ;;
    *.lua)
      command -v lua >/dev/null 2>&1 || return 0
      AWTARCHY_LUA_VALIDATE_FILE="$file" lua -e 'local path = assert(os.getenv("AWTARCHY_LUA_VALIDATE_FILE")); assert(loadfile(path))'
      ;;
    *.json)
      python3 -m json.tool "$file" >/dev/null
      ;;
    *.toml)
      python3 - "$file" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
      ;;
    *.desktop)
      # Awtarchy intentionally uses shell-based Exec= launchers that work in the
      # target desktop environment but are rejected by desktop-file-validate.
      # Validate the required desktop-entry structure without making those
      # intentional shell commands fatal to an update.
      grep -Fqx '[Desktop Entry]' "$file" \
        && grep -Eq '^Type=(Application|Link|Directory)$' "$file" \
        && grep -Eq '^Name=.+$' "$file"
      ;;
  esac
}

attempt_merge() {
  local local_file="$1" baseline_file="$2" target_file="$3" rel="$4" out="$5"
  command -v git >/dev/null 2>&1 || return 1
  [[ -f "$local_file" && -f "$baseline_file" && -f "$target_file" ]] || return 1
  set +e
  git merge-file -p -- "$local_file" "$baseline_file" "$target_file" >"$out"
  local rc=$?
  set -e
  (( rc == 0 )) || return 1
  validate_candidate "$out" "$rel"
}

install_live_file() {
  local rel="$1" target_file="$2" local_file="$3" persistent_backup="${4:-0}"
  if ! validate_candidate "$target_file" "$rel"; then
    FAILED+=("$rel")
    return 1
  fi
  snapshot_for_rollback "$rel" "$local_file"
  ROLLBACK_PATHS+=("$rel")
  (( persistent_backup == 1 )) && make_persistent_backup "$local_file"
  if [[ -d "$local_file" && ! -L "$local_file" ]]; then
    rm -rf -- "$local_file"
  fi
  if ! atomic_copy "$target_file" "$local_file"; then
    FAILED+=("$rel")
    rollback_changes
    return 1
  fi
  CHANGED+=("$rel")
}

remove_live_file() {
  local rel="$1" local_file="$2" persistent_backup="${3:-0}"
  snapshot_for_rollback "$rel" "$local_file"
  ROLLBACK_PATHS+=("$rel")
  (( persistent_backup == 1 )) && make_persistent_backup "$local_file"
  if ! rm -rf -- "$local_file"; then
    FAILED+=("$rel")
    rollback_changes
    return 1
  fi
  CHANGED+=("$rel")
  REMOVED+=("$rel")
}

apply_plan() {
  local plan_file="$1"
  local class rel local_file target_file baseline_file merge_tmp
  while IFS=$'\t' read -r class rel local_file target_file baseline_file; do
    [[ -n "$class" ]] || continue
    validate_plan_row "$class" "$rel" "$local_file" "$target_file" "$baseline_file" \
      || { FAILED+=("${rel:-unsafe-plan-row}"); rollback_changes; return 1; }
    case "$class" in
      NEW|OUTDATED)
        install_live_file "$rel" "$target_file" "$local_file" 0 || return 1
        ;;
      USER)
        if [[ "$UPDATE_MODE" == "preserve" && "$rel" == ".config/hypr/hyprland.lua" ]]; then
          PRESERVED+=("$rel")
        else
          install_live_file "$rel" "$target_file" "$local_file" 1 || return 1
        fi
        ;;
      LEGACY)
        if [[ "$UPDATE_MODE" == "preserve" && "$rel" == ".config/hypr/hyprland.lua" ]]; then
          PRESERVED+=("$rel")
          warn "Legacy Hyprland difference retained because no trusted old baseline exists: $rel"
        else
          install_live_file "$rel" "$target_file" "$local_file" 1 || return 1
        fi
        ;;
      BOTH)
        if [[ "$UPDATE_MODE" == "preserve" && "$rel" == ".config/hypr/hyprland.lua" ]]; then
          merge_tmp="${TMPD}/merge/${rel}"
          mkdir -p -- "$(dirname "$merge_tmp")"
          if attempt_merge "$local_file" "$baseline_file" "$target_file" "$rel" "$merge_tmp"; then
            install_live_file "$rel" "$merge_tmp" "$local_file" 1 || return 1
            MERGED+=("$rel")
          else
            case "$CONFLICT_POLICY" in
              use-release)
                install_live_file "$rel" "$target_file" "$local_file" 1 || return 1
                warn "Explicit conflict policy installed the release Hyprland file and kept the local file as a backup: $rel"
                ;;
              abort)
                FAILED+=("$rel")
                warn "Explicit conflict policy aborted on Hyprland merge conflict: $rel"
                rollback_changes
                return 1
                ;;
              prompt|keep-local)
                PRESERVED+=("$rel")
                warn "Hyprland merge conflict; kept the local file and skipped overlapping release changes: $rel"
                ;;
              *)
                FAILED+=("$rel")
                warn "Unsupported merge conflict policy: $CONFLICT_POLICY"
                rollback_changes
                return 1
                ;;
            esac
          fi
        else
          install_live_file "$rel" "$target_file" "$local_file" 1 || return 1
        fi
        ;;
      REMOVED)
        remove_live_file "$rel" "$local_file" 0 || return 1
        ;;
      ORPHANED)
        if [[ "$UPDATE_MODE" == "preserve" ]]; then
          warn "A locally modified managed file was removed upstream; removing it from the live tree and keeping a backup: $rel"
        fi
        remove_live_file "$rel" "$local_file" 1 || return 1
        ;;
    esac
  done <"$plan_file"
}

fix_managed_perms() {
  local target_home="$1" rel dest mode
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    dest="${HOME_DIR}/${rel}"
    [[ -e "$dest" || -L "$dest" ]] || continue
    if [[ ! -L "$target_home/$rel" ]]; then
      mode="$(stat -c '%a' "$target_home/$rel" 2>/dev/null || true)"
      [[ -n "$mode" ]] && chmod "$mode" "$dest" 2>/dev/null || true
    fi
    if [[ "${EUID}" -eq 0 ]]; then
      chown -h "${TARGET_USER}:${TARGET_USER}" "$dest" 2>/dev/null || true
      chown "${TARGET_USER}:${TARGET_USER}" "$(dirname "$dest")" 2>/dev/null || true
    fi
  done < <(find "$target_home" \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort)
}

validate_live() {
  local rel file
  for rel in "${CHANGED[@]}"; do
    file="${HOME_DIR}/${rel}"
    [[ -e "$file" || -L "$file" ]] || continue
    validate_candidate "$file" "$rel" || return 1
  done

  if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    local errors
    errors="$(hyprctl configerrors 2>&1 || true)"
    if [[ -n "${errors//[[:space:]]/}" ]] && ! grep -Eqi 'no (config )?errors' <<<"$errors"; then
      warn "Hyprland reported configuration errors:"
      printf '%s\n' "$errors" >&2
      return 1
    fi
  fi
}

commit_baseline() {
  local target_home="$1" tag="$2" active_theme="$3" new_baseline="${STATE_DIR}/baseline.new"
  rm -rf -- "$new_baseline"
  mkdir -p -- "$new_baseline/home"
  cp -a --no-preserve=ownership -- "$target_home/." "$new_baseline/home/"
  find "$target_home" \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort >"$new_baseline/manifest.paths"
  {
    printf 'tag=%s\n' "$tag"
    printf 'theme=%s\n' "$active_theme"
    printf 'generated_at=%s\n' "$(ts)"
  } >"$new_baseline/metadata"
  rm -rf -- "${STATE_DIR}/baseline"
  mv -- "$new_baseline" "${STATE_DIR}/baseline"
  BASELINE_HOME="${STATE_DIR}/baseline/home"
  MANIFEST_FILE="${STATE_DIR}/baseline/manifest.paths"
}

refresh_cursor_assets() {
  [[ "${AWTARCHY_TEST_SKIP_CURSOR_REFRESH:-0}" == "1" ]] && return 0

  mkdir -p -- "${HOME_DIR}/.local/share/icons/Bibata-Modern-Ice"
  if [[ -d /usr/share/icons/Bibata-Modern-Ice ]]; then
    cp -a --no-preserve=ownership /usr/share/icons/Bibata-Modern-Ice/. \
      "${HOME_DIR}/.local/share/icons/Bibata-Modern-Ice/" 2>/dev/null || true
    [[ "${EUID}" -eq 0 ]] && chown -R "${TARGET_USER}:${TARGET_USER}" \
      "${HOME_DIR}/.local/share/icons/Bibata-Modern-Ice" 2>/dev/null || true
  fi

  if [[ "${EUID}" -eq 0 ]]; then
    install -d -m 0755 /usr/share/icons/default
    printf '%s\n' '[Icon Theme]' 'Inherits=Bibata-Modern-Ice' >/usr/share/icons/default/index.theme
    chmod 0644 /usr/share/icons/default/index.theme
  fi

  if command -v flatpak >/dev/null 2>&1; then
    run_target flatpak override --user --env=GTK_CURSOR_THEME=Bibata-Modern-Ice >/dev/null 2>&1 || true
  fi
}

write_version_stamp() {
  local tag="$1" dest="${HOME_DIR}/.local/state/awtarchy/config-version"
  mkdir -p -- "$(dirname "$dest")"
  {
    printf 'tag=%s\n' "$tag"
    printf 'updated_at=%s\n' "$(ts)"
  } >"$dest"
  [[ "${EUID}" -eq 0 ]] && chown "${TARGET_USER}:${TARGET_USER}" "$dest" 2>/dev/null || true
}

stable_release_before_git_test() {
  local value="" file=""
  value="$(state_value stable_release "$GIT_TESTING_FILE" 2>/dev/null || true)"
  if [[ -n $value ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  for file in \
    "${STATE_DIR}/config-version" \
    "${STATE_DIR}/baseline/metadata"
  do
    value="$(state_value tag "$file" 2>/dev/null || true)"
    [[ -n $value ]] || continue
    case "$value" in
      unknown|unreleased) continue ;;
    esac
    if [[ $value =~ ^.+@[0-9a-fA-F]{40}$ ]]; then
      continue
    fi
    printf '%s\n' "$value"
    return 0
  done
  printf '%s\n' unknown
}

write_git_testing_state() {
  local branch="$1" revision="$2" stable_release="$3" dir="" tmp=""
  dir="$(dirname "$GIT_TESTING_FILE")"
  mkdir -p -- "$dir"
  tmp="$(mktemp --tmpdir="$dir" '.git-testing.tmp.XXXXXX')"
  {
    printf 'branch=%s\n' "$branch"
    printf 'revision=%s\n' "$revision"
    printf 'stable_release=%s\n' "$stable_release"
    printf 'tested_at=%s\n' "$(ts)"
  } >"$tmp"
  chmod 0644 "$tmp"
  if [[ "${EUID}" -eq 0 ]]; then
    chown "${TARGET_USER}:${TARGET_USER}" "$tmp" 2>/dev/null || true
  fi
  mv -Tf -- "$tmp" "$GIT_TESTING_FILE"
}

clear_git_testing_state() {
  rm -f -- "$GIT_TESTING_FILE"
}

write_audit() {
  local tag="$1" theme="$2"
  {
    printf 'Awtarchy update completed\n'
    printf 'target_user=%s\n' "$TARGET_USER"
    printf 'release=%s\n' "$tag"
    printf 'mode=%s\n' "$UPDATE_MODE"
    printf 'theme=%s\n' "$theme"
    printf 'changed=%s\n' "${#CHANGED[@]}"
    printf 'preserved=%s\n' "${#PRESERVED[@]}"
    printf 'merged=%s\n' "${#MERGED[@]}"
    printf 'removed=%s\n' "${#REMOVED[@]}"
    printf 'backups=%s\n' "${#BACKUPS[@]}"
    printf '\nChanged files:\n'; printf '  %s\n' "${CHANGED[@]:-}"
    printf '\nPreserved files:\n'; printf '  %s\n' "${PRESERVED[@]:-}"
    printf '\nMerged files:\n'; printf '  %s\n' "${MERGED[@]:-}"
    printf '\nRemoved files:\n'; printf '  %s\n' "${REMOVED[@]:-}"
    printf '\nFailed files:\n'; printf '  %s\n' "${FAILED[@]:-}"
    printf '\nBackups:\n'; printf '  %s\n' "${BACKUPS[@]:-}"
  } >>"$AUDIT_LOG"
}


QUICKSHELL_UPDATE_LEGACY_SNAPSHOT=""

QUICKSHELL_HYPRLAND_USER_PATCH=""

quickshell_hyprland_has_legacy_refs() {
  local file="$1"
  [[ -r "$file" ]] || return 1
  grep -Eq \
    'waybar\.sh start|waybar_ready_sound\.sh|fuzzel_toggle\.sh|wlogout_toggle\.sh|mako_dismiss\.sh|cliphist-(fuzzel|wofi)\.sh|waybar_(toggle|flip|rotate)\.sh|hypr_quicksettings\.sh --ui' \
    "$file"
}

stage_quickshell_hyprland_user_patch() {
  local target_home="$1" rel=".config/hypr/hyprland.lua"
  local live="${HOME_DIR}/${rel}" baseline="${BASELINE_HOME}/${rel}"
  local target="${target_home}/${rel}" patch="${TMPD}/quickshell-hyprland-user.patch" rc=0

  quickshell_hyprland_has_legacy_refs "$live" || return 0
  quickshell_hyprland_has_legacy_refs "$baseline" || return 0
  [[ -f "$target" ]] || return 0
  command -v git >/dev/null 2>&1 \
    || die "git is required to record personal Hyprland modifications during migration."

  set +e
  git --no-pager diff --no-index --no-prefix -- "$baseline" "$live" >"$patch" 2>/dev/null
  rc=$?
  set -e
  (( rc <= 1 )) || die "Could not record personal Hyprland modifications before migration."

  if [[ -s "$patch" ]]; then
    QUICKSHELL_HYPRLAND_USER_PATCH="$patch"
    log "Recorded personal Hyprland modifications against the previous Awtarchy baseline."
  else
    rm -f -- "$patch"
  fi
}

persist_quickshell_hyprland_user_patch() {
  [[ -n "$QUICKSHELL_HYPRLAND_USER_PATCH" && -s "$QUICKSHELL_HYPRLAND_USER_PATCH" ]] || return 0
  local dir="${STATE_DIR}/migrations"
  local dest="${dir}/quickshell-hyprland-user.patch"
  mkdir -p -- "$dir"
  install -m 0600 "$QUICKSHELL_HYPRLAND_USER_PATCH" "$dest"
  if [[ "${EUID}" -eq 0 ]]; then
    chown "${TARGET_USER}:${TARGET_USER}" "$dest" 2>/dev/null || true
  fi
  log "Saved the pre-migration Hyprland user delta: ${dest}"
}

run_quickshell_update_pacman() {
  if [[ "${EUID}" -eq 0 ]]; then
    pacman "$@"
    return
  fi

  command -v sudo >/dev/null 2>&1 \
    || die "sudo is required to install the Quickshell migration packages"
  sudo -v || die "sudo authentication failed; no managed configs were changed"
  sudo pacman "$@"
}

record_quickshell_update_packages() {
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
  local tmp pkg
  local -a packages=("$@")
  (( ${#packages[@]} )) || return 0

  tmp="$(mktemp)"
  [[ -r "$managed_file" ]] && cat "$managed_file" >"$tmp" || : >"$tmp"
  for pkg in "${packages[@]}"; do
    printf '%s\n' "$pkg" >>"$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"

  if [[ "${EUID}" -eq 0 ]]; then
    install -d -m 0755 "$(dirname "$managed_file")"
    install -m 0644 "$tmp" "$managed_file"
  else
    sudo install -d -m 0755 "$(dirname "$managed_file")"
    sudo install -m 0644 "$tmp" "$managed_file"
  fi
  rm -f -- "$tmp"
}

repair_v342_mouse_submap_target() {
  local target_home="$1" tag="$2"
  local file="${target_home}/.config/hypr/hyprland.lua"

  [[ "$tag" == "v3.4.2" ]] || return 0
  [[ -f "$file" && ! -L "$file" ]] \
    || die "v3.4.2 post-release Hyprland target is unavailable."

  python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = '''hl.define_submap("mouse", function()
    -- Submap references in "mouse" (Toggle off)  [empty file on exit]
    local mouse_off = _submap_off_cmd("mouse")

    -- Resize (MOUSE-left/right / hold)
    for _, bind in ipairs(resize_keys) do
        hl.bind(bind[1], hl.dsp.window.resize({ x = bind[2], y = bind[3], relative = true }), { repeating = true })
    end

    hl.bind("mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind("mouse:273", hl.dsp.window.resize(), { mouse = true })
    hl.bind("mouse:274", hl.dsp.window.float({ action = "toggle" }), {})
    hl.bind("Escape", hl.dsp.exec_cmd(mouse_off), {})
    hl.bind("Return", hl.dsp.exec_cmd(mouse_off), {})

    -- Submap binds in "mouse"  (Toggle off/on)
    hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(mouse_off), {})
    hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd(noalt_on), {})
    hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd(vm_on), {})
end)'''

new = '''hl.define_submap("mouse", function()
    -- Submap references in "mouse" (Toggle off)  [empty file on exit]
    local mouse_off = _submap_off_cmd("mouse")

    -- Pointer-only window controls. Keep normal keyboard input available to
    -- focused applications while mouse mode is active.
    hl.bind("mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind("mouse:273", hl.dsp.window.resize(), { mouse = true })
    hl.bind("mouse:274", hl.dsp.window.float({ action = "toggle" }), {})

    -- Submap binds in "mouse"  (Toggle off/on)
    hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(mouse_off), {})
    hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd(noalt_on), {})
    hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd(vm_on), {})
end)'''

if new in text:
    raise SystemExit(0)
if text.count(old) != 1:
    raise SystemExit("v3.4.2 mouse-submap repair anchor mismatch")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
  log "Applied v3.4.2 mouse-submap post-release repair to generated target."
}

repair_v342_workspace_focus_target() {
  local target_home="$1" tag="$2"
  local bar_file="${target_home}/.config/quickshell/awtarchy/Bar.qml"
  local shell_file="${target_home}/.config/quickshell/awtarchy/shell.qml"

  [[ "$tag" == "v3.4.2" ]] || return 0
  [[ -f "$bar_file" && ! -L "$bar_file" ]] \
    || die "v3.4.2 post-release Bar target is unavailable."
  [[ -f "$shell_file" && ! -L "$shell_file" ]] \
    || die "v3.4.2 post-release shell target is unavailable."

  python3 - "$bar_file" "$shell_file" <<'PY_WORKSPACE_FOCUS'
from pathlib import Path
import sys

bar_path = Path(sys.argv[1])
shell_path = Path(sys.argv[2])

bar_text = bar_path.read_text(encoding="utf-8")
old = 'normalBackground: modelData.urgent ? Theme.urgent : (modelData.active ? Theme.subtleActive : "transparent")'
new = 'normalBackground: modelData.urgent ? Theme.urgent : (modelData.focused ? Theme.subtleActive : "transparent")'
old_count = bar_text.count(old)
new_count = bar_text.count(new)

if old_count == 0 and new_count == 2:
    pass
elif old_count == 2:
    bar_path.write_text(bar_text.replace(old, new), encoding="utf-8")
else:
    raise SystemExit(f"v3.4.2 workspace-focus Bar repair anchor mismatch: old={old_count}, new={new_count}")

shell_text = shell_path.read_text(encoding="utf-8")
move_block = '''            if (event.name === "moveworkspace" || event.name === "moveworkspacev2") {
                Hyprland.refreshMonitors();
                return;
            }

'''
config_anchor = '''            if (event.name === "configreloaded") {
                runtimeRules.exec([root.runtimeRulesScript]);
                NumlockSessionTweak.enforce();
                return;
            }
'''
if move_block not in shell_text:
    if shell_text.count(config_anchor) != 1:
        raise SystemExit("v3.4.2 workspace-focus shell repair anchor mismatch")
    shell_path.write_text(shell_text.replace(config_anchor, move_block + config_anchor, 1), encoding="utf-8")
PY_WORKSPACE_FOCUS
  log "Applied v3.4.2 workspace-focus post-release repair to generated target."
}
repair_v343_transient_task_icons_target() {
  local target_home="$1" tag="$2"
  local bar_file="${target_home}/.config/quickshell/awtarchy/Bar.qml"

  [[ "$tag" == "v3.4.3" ]] || return 0
  [[ -f "$bar_file" && ! -L "$bar_file" ]] \
    || die "v3.4.3 post-release Bar target is unavailable."

  python3 - "$bar_file" <<'PY_TRANSIENT_TASK_ICONS'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
guard = '''        const taskTitle = String(toplevel.title || "").trim();
        if (taskTitle.length === 0)
            return false;
'''
if guard in text:
    raise SystemExit(0)

anchor = '''        if (!toplevel || !toplevel.monitor || toplevel.monitor.name !== monitorName)
            return false;
        if (isAwtarchyFlyout(toplevel))
            return false;
'''
replacement = '''        if (!toplevel || !toplevel.monitor || toplevel.monitor.name !== monitorName)
            return false;
        const taskTitle = String(toplevel.title || "").trim();
        if (taskTitle.length === 0)
            return false;
        if (isAwtarchyFlyout(toplevel))
            return false;
'''
if text.count(anchor) != 1:
    raise SystemExit("v3.4.3 transient-task repair anchor mismatch")
path.write_text(text.replace(anchor, replacement, 1), encoding="utf-8")
PY_TRANSIENT_TASK_ICONS
  log "Applied v3.4.3 transient-task-icon post-release repair to generated target."
}

repair_v347_idle_inhibitor_feedback_target() {
  local target_home="$1" tag="$2"
  local state_file="${target_home}/.config/quickshell/awtarchy/SystemState.qml"

  [[ "$tag" == "v3.4.7" ]] || return 0
  [[ -f "$state_file" && ! -L "$state_file" ]] \
    || die "v3.4.7 post-release SystemState target is unavailable."

  python3 - "$state_file" <<'PY_V347_IDLE_INHIBITOR'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

def block(*lines):
    return "\n".join(lines) + "\n"

replacements = [
    (
        block(
            "    property bool idleInhibited: false",
            "    property bool idleBroken: false",
            "    property var coreUsage: ({})",
        ),
        block(
            "    property bool idleInhibited: false",
            "    property bool idleBroken: false",
            "    property bool idleReconcilePending: false",
            "    property var coreUsage: ({})",
        ),
    ),
    (
        block(
            "    Process {",
            "        id: idleStatusProcess",
            "        command: [\"sh\", \"-c\", \"if [ -x '\" + root.idleScript + \"' ]; then '\" + root.idleScript + \"'; fi\"]",
            "        stdout: StdioCollector {",
            "            onStreamFinished: {",
            "                try {",
            "                    const status = JSON.parse(text.trim());",
            "                    const classes = status.class || [];",
            "                    root.idleInhibited = classes.indexOf(\"activated\") >= 0;",
            "                    root.idleBroken = classes.indexOf(\"error\") >= 0;",
            "                } catch (error) {",
            "                    root.idleInhibited = false;",
            "                    root.idleBroken = false;",
            "                }",
            "            }",
            "        }",
            "    }",
        ),
        block(
            "    Process {",
            "        id: idleStatusProcess",
            "        command: [\"sh\", \"-c\", \"if [ -x '\" + root.idleScript + \"' ]; then '\" + root.idleScript + \"'; fi\"]",
            "        stdout: StdioCollector {",
            "            onStreamFinished: {",
            "                if (idleReconcilePending)",
            "                    return;",
            "                try {",
            "                    const status = JSON.parse(text.trim());",
            "                    const classes = status.class || [];",
            "                    root.idleInhibited = classes.indexOf(\"activated\") >= 0;",
            "                    root.idleBroken = classes.indexOf(\"error\") >= 0;",
            "                } catch (error) {",
            "                    root.idleInhibited = false;",
            "                    root.idleBroken = false;",
            "                }",
            "            }",
            "        }",
            "        onExited: {",
            "            if (root.idleReconcilePending && !idleToggleProcess.running)",
            "                root.refreshIdleAfterToggle();",
            "        }",
            "    }",
            "",
            "    Process {",
            "        id: idleToggleProcess",
            "        onExited: root.refreshIdleAfterToggle()",
            "    }",
        ),
    ),
    (
        block(
            "            if (!metricsProcess.running)",
            "                metricsProcess.running = true;",
            "            if (!idleStatusProcess.running)",
            "                idleStatusProcess.running = true;",
        ),
        block(
            "            if (!metricsProcess.running)",
            "                metricsProcess.running = true;",
            "            if (!idleStatusProcess.running && !idleToggleProcess.running && !root.idleReconcilePending)",
            "                idleStatusProcess.running = true;",
        ),
    ),
    (
        block(
            "    function toggleIdle() {",
            "        Quickshell.execDetached([idleScript, \"toggle\"]);",
            "        refreshIdleTimer.restart();",
            "    }",
            "",
            "    Timer {",
            "        id: refreshIdleTimer",
            "        interval: 350",
            "        repeat: false",
            "        onTriggered: {",
            "            if (!idleStatusProcess.running)",
            "                idleStatusProcess.running = true;",
            "        }",
            "    }",
        ),
        block(
            "    function refreshIdleAfterToggle() {",
            "        if (!root.idleReconcilePending || idleToggleProcess.running || idleStatusProcess.running)",
            "            return;",
            "        root.idleReconcilePending = false;",
            "        idleStatusProcess.running = true;",
            "    }",
            "",
            "    function toggleIdle() {",
            "        if (idleToggleProcess.running)",
            "            return;",
            "        root.idleInhibited = !root.idleInhibited;",
            "        root.idleReconcilePending = true;",
            "        idleToggleProcess.exec([idleScript, \"toggle\"]);",
            "    }",
        ),
    ),
]

for index, (old, new) in enumerate(replacements, start=1):
    if text.count(old) != 1:
        raise SystemExit(f"v3.4.7 idle inhibitor target repair anchor mismatch: block {index}")
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
PY_V347_IDLE_INHIBITOR
  log "Applied v3.4.7 idle-inhibitor post-release repair to generated target."
}

repair_v350_aur_helper_policy_target() {
  local target_home="$1" tag="$2"
  local bashrc_file="${target_home}/.bashrc"

  [[ "$tag" == "v3.5.0" ]] || return 0
  [[ -f "$bashrc_file" && ! -L "$bashrc_file" ]] \
    || die "v3.5.0 post-release bashrc target is unavailable."

  python3 - "$bashrc_file" <<'PY_V350_AUR_HELPER'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"v3.5.0 AUR helper target repair anchor mismatch: {label} count={count}")
    text = text.replace(old, new, 1)


def replace_line_once(old: str, new: str, label: str) -> None:
    global text
    lines = text.splitlines(keepends=True)
    matches = []
    for index, line in enumerate(lines):
        body = line[:-1] if line.endswith("\n") else line
        if body == old:
            matches.append(index)
    if len(matches) != 1:
        raise SystemExit(f"v3.5.0 AUR helper target repair line mismatch: {label} count={len(matches)}")
    index = matches[0]
    newline = "\n" if lines[index].endswith("\n") else ""
    lines[index] = new + newline
    text = "".join(lines)


replace_once(
    "# Upstream aur-scanner owns AUR scanning and installation. Keep yay/paru useful\n"
    "# for read-only inspection while preventing accidental package transactions.\n"
    "_awtarchy_aur_helper_is_read_only() {\n",
    "# Upstream aur-scanner owns AUR scanning and installation. Keep yay/paru useful\n"
    "# for read-only inspection and explicit package removal while blocking installs,\n"
    "# upgrades, cleanup operations, and other unsupported package transactions.\n"
    "_awtarchy_aur_helper_is_allowed() {\n",
    "policy header",
)
replace_line_once(
    "    -Ss|-Si|-Sl|-Sg)",
    "    -Ss|-Si|-Sl|-Sg|-Sp|-R*|--remove|--remove=*)",
    "first-argument allowlist",
)
replace_line_once(
    "      -Ss|-Si|-Sl|-Sg)",
    "      -Ss|-Si|-Sl|-Sg|-Sp|-R*|--remove|--remove=*)",
    "per-argument allowlist",
)
replace_line_once(
    "      -S*|-R*|-U*|-D*|-F*|-G*|-Y*|\\",
    "      -S*|-U*|-D*|-F*|-G*|-Y*|\\",
    "short-option mutation block",
)
replace_line_once(
    "      --sync|--sync=*|--remove|--remove=*|--upgrade|--upgrade=*|\\",
    "      --sync|--sync=*|--upgrade|--upgrade=*|\\",
    "long-option mutation block",
)
replace_once(
    'if _awtarchy_aur_helper_is_read_only "$@"; then',
    'if _awtarchy_aur_helper_is_allowed "$@"; then',
    "helper predicate call",
)
replace_once(
    'printf \'Awtarchy blocks package-changing %s transactions.\\n\' "$helper" >&2',
    'printf \'Awtarchy blocks this %s transaction.\\n\' "$helper" >&2',
    "blocked-transaction message",
)

path.write_text(text, encoding="utf-8")
PY_V350_AUR_HELPER
  log "Applied v3.5.0 AUR helper post-release repair to generated target."
}

repair_v353_update_notifier_target() {
  local target_home="$1" tag="$2"
  local notifier_file="${target_home}/.config/hypr/scripts/quickshell_update_notifications.sh"

  [[ "$tag" == "v3.5.3" ]] || return 0
  [[ -f "$notifier_file" && ! -L "$notifier_file" ]] \
    || die "v3.5.3 post-release update notifier target is unavailable."

  python3 - "$notifier_file" <<'PY_V353_UPDATE_NOTIFIER'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = '        "$DEFAULT_TERMINAL" \\\n'
new = '        /usr/bin/setsid -f --wait "$DEFAULT_TERMINAL" \\\n'
count = text.count(old)
if count != 2:
    raise SystemExit(f"expected 2 legacy notifier terminal launches, found {count}")
text = text.replace(old, new)
path.write_text(text, encoding="utf-8")
PY_V353_UPDATE_NOTIFIER
  log "Applied v3.5.3 update-notifier post-release repair to generated target."
}

repair_v354_sony_battery_disable_repo() {
  local repo_dir="$1" tag="$2"
  local helper="${repo_dir}/local/libexec/awtarchy/power-profile-helper"

  [[ "$tag" == "v3.5.4" ]] || return 0
  [[ -f "$helper" && ! -L "$helper" ]]     || die "v3.5.4 post-release battery helper source is unavailable."

  python3 - "$helper" <<'PY_V354_SONY_BATTERY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """    huawei)
      /usr/bin/grep -Eq 'charge_control_thresholds[^=]*=[[:space:]]*[0-9]+[[:space:]]+100([^0-9]|$)' <<<"$report"
      ;;
    *)
"""
new = """    huawei)
      /usr/bin/grep -Eq 'charge_control_thresholds[^=]*=[[:space:]]*[0-9]+[[:space:]]+100([^0-9]|$)' <<<"$report"
      ;;
    sony)
      /usr/bin/grep -Eq 'battery_care_limiter[^=]*=[[:space:]]*0([^0-9]|$)' <<<"$report"
      ;;
    *)
"""
if new in text:
    raise SystemExit(0)
if text.count(old) != 1:
    raise SystemExit("v3.5.4 Sony battery helper repair could not find the expected release source")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY_V354_SONY_BATTERY
  /usr/bin/bash -n "$helper"     || die "v3.5.4 post-release Sony battery helper failed Bash syntax validation."
  log "Applied v3.5.4 Sony battery-disable post-release repair to release helper source."
}


repair_v355_clipboard_thumbnail_repo() {
  local repo_dir="$1" tag="$2"
  local backend="${repo_dir}/config/hypr/scripts/quickshell_clipboard.sh"
  local history="${repo_dir}/local/share/awtarchy/quickshell-managed-history.sha256"
  local expected_hash="ab73a9056ecd3cd692112cf218464c9abe1de5792b0fdaad1f6401b063a0d967"
  local actual_hash=""

  [[ "$tag" == "v3.5.5" ]] || return 0
  [[ -f "$backend" && ! -L "$backend" ]] \
    || die "v3.5.5 clipboard source is unavailable for the stable repair."
  [[ -f "$history" && ! -L "$history" ]] \
    || die "v3.5.5 managed-history source is unavailable for the stable repair."

  actual_hash="$(sha256sum "$backend" | awk '{print $1}')"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    python3 - "$backend" "$history" <<'PY_V355_CLIPBOARD'
from pathlib import Path
import sys

backend = Path(sys.argv[1])
history = Path(sys.argv[2])
text = backend.read_text(encoding="utf-8")
old_timeout = 'DECODE_TIMEOUT="${DECODE_TIMEOUT:-0.70s}"\nLIST_PRODUCER_PID=""'
new_timeout = 'DECODE_TIMEOUT="${DECODE_TIMEOUT:-0.70s}"\nTHUMB_TIMEOUT="${THUMB_TIMEOUT:-2s}"\nLIST_PRODUCER_PID=""'
old_magick = '        && magick "$tmp" -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}>" "png:$png" >/dev/null 2>&1; then'
new_magick = (
    '        && timeout --kill-after=1s "$THUMB_TIMEOUT" magick \\\n'
    '            -limit memory 256MiB -limit map 256MiB -limit disk 512MiB \\\n'
    '            "${tmp}[0]" -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}>" "png:$png" >/dev/null 2>&1; then'
)
if text.count(old_timeout) != 1 or text.count(old_magick) != 1:
    raise SystemExit("v3.5.5 clipboard repair could not find the expected release source")
backend.write_text(text.replace(old_timeout, new_timeout, 1).replace(old_magick, new_magick, 1), encoding="utf-8")

lines = [
    "8891de8271fa22f3932e7f9ee355c47f0807ab27f1151c77abf54bf10603fd02\t.config/hypr/scripts/quickshell_clipboard.sh",
    "ab73a9056ecd3cd692112cf218464c9abe1de5792b0fdaad1f6401b063a0d967\t.config/hypr/scripts/quickshell_clipboard.sh",
]
htext = history.read_text(encoding="utf-8")
if htext and not htext.endswith("\n"):
    htext += "\n"
existing = set(htext.splitlines())
for line in lines:
    if line not in existing:
        htext += line + "\n"
history.write_text(htext, encoding="utf-8")
PY_V355_CLIPBOARD
  fi

  actual_hash="$(sha256sum "$backend" | awk '{print $1}')"
  [[ "$actual_hash" == "$expected_hash" ]] \
    || die "v3.5.5 clipboard repair produced unexpected source hash ${actual_hash}."
  /usr/bin/bash -n "$backend" \
    || die "v3.5.5 clipboard repair failed Bash syntax validation."
  log "Applied v3.5.5 clipboard thumbnail resource hardening to release source."
}

prepare_quickshell_update_target() {
  local target_home="$1" rel

  # Retired shell paths must never enter the generated target or saved baseline,
  # including when migrating from an older or manually repackaged archive.
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    rm -rf -- "${target_home:?}/${rel}"
  done < <(quickshell_update_legacy_paths)
}

normalize_quickshell_update_plan() {
  local repo_dir="$1" plan_file="$2" manifest result
  local managed_count legacy_count

  manifest="${AWTARCHY_QUICKSHELL_MANAGED_HISTORY:-${repo_dir}/local/share/awtarchy/quickshell-managed-history.sha256}"
  [[ -r "$manifest" ]] \
    || die "Quickshell managed-file history is missing: ${manifest}"

  result="$(python3 - "$plan_file" "$manifest" <<'PY_UPDATE_PLAN'
from pathlib import Path
import hashlib
import re
import sys

plan_path, manifest_path = map(Path, sys.argv[1:])

known = {}
for raw in manifest_path.read_text(encoding="utf-8").splitlines():
    if not raw or raw.startswith("#"):
        continue
    try:
        digest, rel = raw.split("\t", 1)
    except ValueError:
        raise SystemExit(f"invalid managed-history row: {raw!r}")
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise SystemExit(f"invalid managed-history checksum: {digest!r}")
    known.setdefault(rel, set()).add(digest)

rows = []
managed_count = 0
legacy_count = 0
for raw in plan_path.read_text(encoding="utf-8").splitlines():
    if not raw:
        continue
    fields = raw.split("\t")
    if len(fields) != 5:
        raise SystemExit(f"invalid update-plan row: {raw!r}")
    cls, rel, local_file, target_file, baseline_file = fields
    local_path = Path(local_file)

    if cls in {"USER", "LEGACY", "BOTH"} and rel in known:
        if local_path.is_file() and not local_path.is_symlink():
            digest = hashlib.sha256(local_path.read_bytes()).hexdigest()
            if digest in known[rel]:
                cls = "OUTDATED"
                managed_count += 1

    rows.append((cls, rel, local_file, target_file, baseline_file))

plan_path.write_text(
    "".join("\t".join(row) + "\n" for row in rows),
    encoding="utf-8",
)
print(managed_count, legacy_count)
PY_UPDATE_PLAN
)" || die "Could not normalize the Quickshell managed-file update plan"

  IFS=' ' read -r managed_count legacy_count <<<"$result"
  if (( managed_count > 0 )); then
    log "Recognized ${managed_count} previously shipped Awtarchy file(s) as managed updates."
  fi
  if (( legacy_count > 0 )); then
    log "Marked ${legacy_count} retired shell file(s) for removal without backups."
  fi
}

scxctl_update_helper_is_current() {
  local source="$1"
  local destination="/usr/local/libexec/awtarchy/scxctl-helper"
  local owner="" mode=""

  [[ -f "$source" && ! -L "$source" ]] || return 1
  [[ -f "$destination" && ! -L "$destination" && -x "$destination" ]] || return 1
  owner="$(/usr/bin/stat -c %u -- "$destination" 2>/dev/null)" || return 1
  mode="$(/usr/bin/stat -c %a -- "$destination" 2>/dev/null)" || return 1
  [[ "$owner" == 0 && "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$mode & 8#022) == 0 )) || return 1
  /usr/bin/cmp -s -- "$source" "$destination"
}

repair_scxctl_update_helper() {
  local repo_dir="$1"
  local source="${repo_dir}/local/libexec/awtarchy/scxctl-helper"
  local destination="/usr/local/libexec/awtarchy/scxctl-helper"
  local destination_dir="${destination%/*}"
  local temporary="" source_hash="" installed_hash="" first_line=""

  [[ -f "$source" && ! -L "$source" ]] \
    || die "Release is missing the trusted sched-ext helper: ${source}"
  first_line="$(/usr/bin/head -n1 -- "$source" 2>/dev/null || true)"
  [[ "$first_line" == '#!/usr/bin/bash' ]] \
    || die "Release sched-ext helper does not use the fixed /usr/bin/bash interpreter."
  /usr/bin/bash -n "$source" \
    || die "Release sched-ext helper failed Bash syntax validation."

  scxctl_update_helper_is_current "$source" && return 0

  have sudo || die "sudo is required to install the trusted sched-ext helper."
  source_hash="$(/usr/bin/sha256sum "$source" | /usr/bin/awk '{print $1}')"
  [[ "$source_hash" =~ ^[0-9a-f]{64}$ ]] \
    || die "Could not hash the release sched-ext helper."

  log "Installing trusted sched-ext helper..."
  sudo -v || die "sudo authentication failed; no managed configs were changed."
  if sudo /usr/bin/test -L "$destination_dir"; then
    die "Refusing symbolic-link sched-ext helper directory: ${destination_dir}"
  fi
  sudo /usr/bin/install -d -m 0755 -o root -g root "$destination_dir" \
    || die "Could not create the sched-ext helper directory."
  sudo /usr/bin/test ! -L "$destination_dir" \
    || die "Refusing symbolic-link sched-ext helper directory: ${destination_dir}"

  temporary="$(sudo /usr/bin/mktemp "${destination_dir}/.scxctl-helper.XXXXXX")" \
    || die "Could not create a temporary sched-ext helper."
  if ! sudo /usr/bin/install -m 0755 -o root -g root "$source" "$temporary"; then
    sudo /usr/bin/rm -f -- "$temporary" || true
    die "Could not stage the sched-ext helper."
  fi

  installed_hash="$(sudo /usr/bin/sha256sum "$temporary" | /usr/bin/awk '{print $1}')" \
    || {
      sudo /usr/bin/rm -f -- "$temporary" || true
      die "Could not verify the staged sched-ext helper."
    }
  if [[ "$installed_hash" != "$source_hash" ]]; then
    sudo /usr/bin/rm -f -- "$temporary" || true
    die "Staged sched-ext helper did not match the release source."
  fi

  first_line="$(sudo /usr/bin/head -n1 -- "$temporary" 2>/dev/null || true)"
  if [[ "$first_line" != '#!/usr/bin/bash' ]]; then
    sudo /usr/bin/rm -f -- "$temporary" || true
    die "Staged sched-ext helper has an unsafe interpreter."
  fi
  if ! sudo /usr/bin/bash -n "$temporary"; then
    sudo /usr/bin/rm -f -- "$temporary" || true
    die "Staged sched-ext helper failed Bash syntax validation."
  fi

  sudo /usr/bin/mv -Tf -- "$temporary" "$destination" \
    || {
      sudo /usr/bin/rm -f -- "$temporary" || true
      die "Could not activate the sched-ext helper."
    }
  scxctl_update_helper_is_current "$source" \
    || die "Trusted sched-ext helper verification failed after installation."
  log "Trusted sched-ext helper installed."
}

ensure_quickshell_update_prerequisites() {
  command -v pacman >/dev/null 2>&1 \
    || die "pacman is required for the Quickshell migration"

  local pkg
  local -a required=(quickshell upower playerctl hyprland-qt-support polkit python-gobject) missing=()
  for pkg in "${required[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  (( ${#missing[@]} )) || return 0

  log "Installing required Quickshell migration packages: ${missing[*]}"
  run_quickshell_update_pacman -S --needed --noconfirm "${missing[@]}" \
    || die "Could not install the Quickshell migration packages; no managed configs were changed"

  for pkg in "${missing[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 \
      || die "Required package is still missing after installation: ${pkg}"
  done
  record_quickshell_update_packages "${missing[@]}"
}

quickshell_update_legacy_paths() {
  printf '%s\n' \
    .config/waybar \
    .config/fuzzel \
    .config/mako \
    .config/wlogout \
    .config/wofi \
    .cache/waybar \
    .cache/fuzzel \
    .cache/wofi \
    .config/hypr/scripts/cliphist-fuzzel.sh \
    .config/hypr/scripts/cliphist-wofi.sh \
    .config/hypr/scripts/fuzzel_toggle.sh \
    .config/hypr/scripts/mako_dismiss.sh \
    .config/hypr/scripts/quickshell_flyout_state_collect.py \
    .config/hypr/scripts/waybar.sh \
    .config/hypr/scripts/waybar_flip.sh \
    .config/hypr/scripts/waybar_ready_sound.sh \
    .config/hypr/scripts/waybar_restore_resume.sh \
    .config/hypr/scripts/waybar_rotate.sh \
    .config/hypr/scripts/waybar_toggle.sh \
    .config/hypr/scripts/waybar_toggle_idle.sh \
    .config/hypr/scripts/wlogout_toggle.sh \
    .local/share/applications/hypr_quicksettings.desktop \
    .local/share/applications/waybar_flip.desktop \
    .local/share/applications/waybar_rotate.desktop \
    .local/share/applications/waybar_toggle.desktop
}

quickshell_update_existing_legacy_paths() {
  local rel dest candidate

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    dest="${HOME_DIR}/${rel}"
    for candidate in "$dest" "${dest}.backup" "${dest}.backup."*; do
      [[ -e "$candidate" || -L "$candidate" ]] || continue
      printf '%s\n' "${candidate#"${HOME_DIR}/"}"
    done
  done < <(quickshell_update_legacy_paths)

  for candidate in "${HOME_DIR}/.cache/wofi-"*; do
    [[ -e "$candidate" || -L "$candidate" ]] || continue
    printf '%s\n' "${candidate#"${HOME_DIR}/"}"
  done
}

snapshot_quickshell_update_legacy_paths() {
  local rel dest
  QUICKSHELL_UPDATE_LEGACY_SNAPSHOT="${TMPD}/quickshell-existing-legacy.paths"
  quickshell_update_existing_legacy_paths \
    | LC_ALL=C sort -u >"$QUICKSHELL_UPDATE_LEGACY_SNAPSHOT"

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    dest="${HOME_DIR}/${rel}"
    snapshot_for_rollback "$rel" "$dest"
    ROLLBACK_PATHS+=("$rel")
  done <"$QUICKSHELL_UPDATE_LEGACY_SNAPSHOT"
}

prune_removed_quickshell_paths_from_preserved() {
  local item root remove
  local -a retained=()

  for item in "${PRESERVED[@]}"; do
    remove=0
    while IFS= read -r root; do
      [[ -n "$root" ]] || continue
      if [[ "$item" == "$root" || "$item" == "$root/"* ]]; then
        remove=1
        break
      fi
    done < <(quickshell_update_legacy_paths)
    (( remove == 1 )) || retained+=("$item")
  done

  PRESERVED=("${retained[@]}")
}

remove_quickshell_update_legacy_files() {
  local rel dest removal_file
  removal_file="${TMPD}/quickshell-remove-legacy.paths"
  {
    [[ -r "$QUICKSHELL_UPDATE_LEGACY_SNAPSHOT" ]] \
      && cat "$QUICKSHELL_UPDATE_LEGACY_SNAPSHOT"
    quickshell_update_existing_legacy_paths
  } | LC_ALL=C sort -u >"$removal_file"

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    dest="${HOME_DIR}/${rel}"
    [[ -e "$dest" || -L "$dest" ]] || continue
    if ! rm -rf -- "$dest"; then
      FAILED+=("$rel")
      return 1
    fi
    CHANGED+=("$rel")
    REMOVED+=("$rel")
  done <"$removal_file"

  prune_removed_quickshell_paths_from_preserved
}

reload_quickshell_update_hyprland() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
  run_target hyprctl reload >/dev/null 2>&1
}

quickshell_update_proc_root() {
  if [[ ${AWTARCHY_TEST_MODE:-0} == 1 && -n ${AWTARCHY_TEST_PROC_ROOT:-} ]]; then
    printf '%s\n' "$AWTARCHY_TEST_PROC_ROOT"
  else
    printf '%s\n' /proc
  fi
}

quickshell_update_process_state_start_time() {
  local pid="$1" proc_root="" stat_line="" stat_tail=""
  local -a stat_fields=()

  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  proc_root="$(quickshell_update_proc_root)"
  IFS= read -r stat_line 2>/dev/null <"${proc_root}/${pid}/stat" || return 1
  [[ "$stat_line" == *') '* ]] || return 1
  stat_tail="${stat_line##*) }"
  IFS=' ' read -r -a stat_fields <<<"$stat_tail"
  (( ${#stat_fields[@]} >= 20 )) || return 1
  [[ "${stat_fields[0]}" =~ ^[A-Za-z]$ ]] || return 1
  [[ "${stat_fields[19]}" =~ ^[0-9]+$ ]] || return 1
  printf '%s %s\n' "${stat_fields[0]}" "${stat_fields[19]}"
}

quickshell_update_process_identity_is_running() {
  local pid="$1" expected_start_time="$2" state="" start_time=""

  IFS=' ' read -r state start_time < <(quickshell_update_process_state_start_time "$pid") || return 1
  case "$state" in
    Z|X|x) return 1 ;;
  esac
  [[ "$start_time" == "$expected_start_time" ]]
}

quickshell_update_pid_is_quickshell() {
  local pid="$1" proc_root="" executable=""

  proc_root="$(quickshell_update_proc_root)"
  executable="$(readlink "${proc_root}/${pid}/exe" 2>/dev/null)" || return 1
  executable="${executable% (deleted)}"
  [[ "${executable##*/}" == quickshell ]]
}

quickshell_update_signal_identity() {
  local pid="$1" expected_start_time="$2" rc=0

  run_target python3 - "$pid" "$expected_start_time" 9>&- <<'PY' || rc=$?
import os
import signal
import sys

GONE_OR_REUSED = 3
UNSAFE = 4

try:
    pid = int(sys.argv[1])
    expected_start_time = sys.argv[2]
except (IndexError, ValueError):
    raise SystemExit(UNSAFE)

if pid <= 0 or not expected_start_time.isdecimal():
    raise SystemExit(UNSAFE)

try:
    pidfd = os.pidfd_open(pid, 0)
except ProcessLookupError:
    raise SystemExit(GONE_OR_REUSED)
except (AttributeError, OSError):
    raise SystemExit(UNSAFE)

try:
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8", errors="surrogateescape") as handle:
            stat_line = handle.read()
    except FileNotFoundError:
        raise SystemExit(GONE_OR_REUSED)
    except OSError:
        raise SystemExit(UNSAFE)

    marker = stat_line.rfind(") ")
    if marker < 0:
        raise SystemExit(UNSAFE)
    fields = stat_line[marker + 2:].split()
    if len(fields) < 20 or len(fields[0]) != 1 or not fields[19].isdecimal():
        raise SystemExit(UNSAFE)
    if fields[0] in {"Z", "X", "x"} or fields[19] != expected_start_time:
        raise SystemExit(GONE_OR_REUSED)

    try:
        executable = os.readlink(f"/proc/{pid}/exe")
    except FileNotFoundError:
        raise SystemExit(GONE_OR_REUSED)
    except OSError:
        raise SystemExit(UNSAFE)
    if executable.endswith(" (deleted)"):
        executable = executable[:-10]
    if os.path.basename(executable) != "quickshell":
        raise SystemExit(UNSAFE)

    try:
        signal.pidfd_send_signal(pidfd, signal.SIGTERM)
    except ProcessLookupError:
        raise SystemExit(GONE_OR_REUSED)
    except (AttributeError, OSError):
        raise SystemExit(UNSAFE)
finally:
    os.close(pidfd)
PY
  return "$rc"
}

quickshell_update_target_has_process() {
  local target_uid=""
  command -v pgrep >/dev/null 2>&1 || return 2
  target_uid="$(id -u "$TARGET_USER" 2>/dev/null || true)"
  [[ "$target_uid" =~ ^[0-9]+$ ]] || return 2
  run_target pgrep -u "$target_uid" -x quickshell >/dev/null 2>&1
}

quickshell_update_instance_pids() {
  local config_name="${QUICKSHELL_CONFIG_NAME:-awtarchy}" instances="" list_rc=0 process_rc=0

  instances="$(run_target qs -c "$config_name" list --json 9>&- 2>/dev/null)" || list_rc=$?
  if (( list_rc != 0 )) || ! jq -e 'type == "array"' <<<"$instances" >/dev/null 2>&1; then
    quickshell_update_target_has_process || process_rc=$?
    case "$process_rc" in
      1) return 0 ;;
      *) return 1 ;;
    esac
  fi
  jq -r '.[] | .pid | select(type == "number" and . > 0)' <<<"$instances"
}

stop_quickshell_update_instances() {
  local pid="" state="" start_time="" identity="" pid_output="" proc_root="" signal_rc=0
  local identity_error=0 signal_error=0 alive=0
  local -a pids=() identities=() alive_pids=()

  pid_output="$(quickshell_update_instance_pids)" || {
    warn "Updater recovery could not enumerate the running Quickshell instance."
    return 1
  }
  [[ -n "$pid_output" ]] && mapfile -t pids <<<"$pid_output"
  (( ${#pids[@]} > 0 )) || return 0
  proc_root="$(quickshell_update_proc_root)"

  for pid in "${pids[@]}"; do
    if ! IFS=' ' read -r state start_time < <(quickshell_update_process_state_start_time "$pid"); then
      if [[ -d "${proc_root}/${pid}" ]]; then
        warn "Updater recovery could not verify process identity for PID ${pid}; refusing to signal it."
        identity_error=1
      fi
      continue
    fi
    case "$state" in
      Z|X|x) continue ;;
    esac
    if ! quickshell_update_pid_is_quickshell "$pid"; then
      if quickshell_update_process_identity_is_running "$pid" "$start_time"; then
        warn "Updater recovery refused to signal PID ${pid} because it does not identify as Quickshell."
        identity_error=1
      fi
      continue
    fi
    identities+=("${pid}:${start_time}")
  done

  (( identity_error == 0 )) || return 1
  (( ${#identities[@]} > 0 )) || return 0

  QUICKSHELL_UPDATE_RESTORE_ON_EXIT=1
  if [[ -n "${QUICKSHELL_UPDATE_RECOVERY_MARKER:-}" ]]; then
    if [[ -L "$QUICKSHELL_UPDATE_RECOVERY_MARKER" ]]; then
      warn "Refusing unsafe Quickshell interrupted-update recovery marker: ${QUICKSHELL_UPDATE_RECOVERY_MARKER}"
      return 1
    fi
    mkdir -p -- "$(dirname -- "$QUICKSHELL_UPDATE_RECOVERY_MARKER")" || return 1
    : >"$QUICKSHELL_UPDATE_RECOVERY_MARKER" || return 1
  fi

  for identity in "${identities[@]}"; do
    IFS=: read -r pid start_time <<<"$identity"
    signal_rc=0
    quickshell_update_signal_identity "$pid" "$start_time" || signal_rc=$?
    case "$signal_rc" in
      0|3) ;;
      *)
        warn "Updater recovery could not safely signal Quickshell PID ${pid}."
        signal_error=1
        ;;
    esac
  done

  (( signal_error == 0 )) || return 1

  for _ in {1..100}; do
    alive=0
    for identity in "${identities[@]}"; do
      IFS=: read -r pid start_time <<<"$identity"
      if quickshell_update_process_identity_is_running "$pid" "$start_time"; then
        alive=1
        break
      fi
    done
    (( alive == 0 )) && return 0
    sleep 0.05
  done

  for identity in "${identities[@]}"; do
    IFS=: read -r pid start_time <<<"$identity"
    quickshell_update_process_identity_is_running "$pid" "$start_time" \
      && alive_pids+=("$pid")
  done
  if (( ${#alive_pids[@]} == 0 )); then
    return 0
  fi
  warn "Updater recovery could not stop Quickshell PID(s): ${alive_pids[*]}"
  return 1
}

report_quickshell_update_failure() {
  local source_label="$1" target_home="$2"
  local report_script="${target_home}/.config/hypr/scripts/awtarchy_report_failure.sh"

  if [[ ! -f "$report_script" || -L "$report_script" ]]; then
    report_script="${HOME_DIR}/.config/hypr/scripts/awtarchy_report_failure.sh"
  fi
  [[ -f "$report_script" && ! -L "$report_script" ]] || return 0

  AWTARCHY_REPORT_CONFIG_VERSION_OVERRIDE="$source_label" \
    run_target bash "$report_script" \
      capture quickshell restart_after_update quickshell_not_ready 9>&- \
    || true
}

stop_quickshell_update_shell() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
  stop_quickshell_update_instances
}

start_quickshell_update_shell() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0

  local manager="${HOME_DIR}/.config/hypr/scripts/quickshell.sh"
  local status=""
  [[ -f "$manager" ]] || return 1
  # Descriptor 9 owns the updater lock. Keep it in this runtime, but do not
  # let the long-lived Quickshell process or its children inherit it.
  if ! AWTARCHY_REPORT_SUPPRESS_QUICKSHELL=1 run_target bash "$manager" restart 9>&-; then
    # The updater runtime refreshes from main before managed configs refresh
    # from the latest release. Keep this recovery here so an older release
    # manager can still recover a package-replaced "quickshell (deleted)"
    # process during the same ordinary `awtarchy update` invocation.
    warn "Quickshell manager restart failed; retrying with updater-managed process shutdown."
    stop_quickshell_update_instances || return 1
    AWTARCHY_REPORT_SUPPRESS_QUICKSHELL=1 run_target bash "$manager" start 9>&- || return 1
  fi
  status="$(run_target bash "$manager" status 9>&- 2>/dev/null || true)"
  if [[ "$status" == "running" ]]; then
    QUICKSHELL_UPDATE_RESTORE_ON_EXIT=0
    if [[ -n "${QUICKSHELL_UPDATE_RECOVERY_MARKER:-}" && ! -L "$QUICKSHELL_UPDATE_RECOVERY_MARKER" ]]; then
      rm -f -- "$QUICKSHELL_UPDATE_RECOVERY_MARKER"
    fi
    return 0
  fi
  return 1
}

rollback_quickshell_update() {
  local manager="${HOME_DIR}/.config/hypr/scripts/quickshell.sh"
  if [[ -f "$manager" ]]; then
    run_target bash "$manager" stop 9>&- >/dev/null 2>&1 || true
  fi
  rollback_changes
  reload_quickshell_update_hyprland || true
  if [[ -f "$manager" ]] \
    && ! AWTARCHY_REPORT_SUPPRESS_QUICKSHELL=1 run_target bash "$manager" start 9>&-;
  then
    warn "User files were restored, but the restored Quickshell could not be restarted automatically."
  fi
}

remove_quickshell_update_legacy_packages() {
  local marker="${STATE_DIR}/quickshell-connectivity-migration-complete"
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
  local pkg process tmp installed_names installed_list
  local -a obsolete_packages=(waybar waybar-git fuzzel wlogout mako wofi network-manager-applet blueman)
  local -a obsolete_processes=(waybar fuzzel wlogout mako wofi nm-applet blueman-applet blueman-manager)
  local -a installed=()

  if ! installed_names="$(pacman -Qq 2>/dev/null)"; then
    warn "Could not query exact installed package names; retired shell package cleanup will retry later."
    return 0
  fi
  for pkg in "${obsolete_packages[@]}"; do
    grep -Fxq -- "$pkg" <<<"$installed_names" && installed+=("$pkg")
  done

  for process in "${obsolete_processes[@]}"; do
    run_target pkill -x "$process" >/dev/null 2>&1 || true
  done

  if (( ${#installed[@]} )); then
    installed_list="$(IFS=' '; printf '%s' "${installed[*]}")"
    log "Removing retired Awtarchy shell packages: ${installed_list}"
    if ! run_quickshell_update_pacman -Rns --noconfirm "${installed[@]}"; then
      warn "Could not remove all retired shell packages; the migration will retry later."
      return 0
    fi
  fi

  if [[ -f "$managed_file" ]]; then
    tmp="$(mktemp)"
    grep -Ev '^(waybar|waybar-git|fuzzel|wlogout|mako|wofi|network-manager-applet|blueman)$' "$managed_file" >"$tmp" || true
    if [[ "${EUID}" -eq 0 ]]; then
      install -m 0644 "$tmp" "$managed_file" \
        || warn "Retired packages were removed but the Awtarchy package ledger could not be updated."
    elif command -v sudo >/dev/null 2>&1 \
      && sudo -v \
      && sudo install -m 0644 "$tmp" "$managed_file";
    then
      :
    else
      warn "Retired packages were removed but the Awtarchy package ledger could not be updated."
    fi
    rm -f -- "$tmp"
  fi

  : >"$marker"
  [[ "${EUID}" -eq 0 ]] && chown "${TARGET_USER}:${TARGET_USER}" "$marker" 2>/dev/null || true
}

drop_update_privileges() {
  [[ ${EUID} -eq 0 ]] || return 0

  local target="${SUDO_USER:-${AWTARCHY_TEST_TARGET_USER:-}}" target_home=""
  if [[ ${AWTARCHY_TEST_TARGET_USER:-} == root \
    && ${AWTARCHY_TEST_TARGET_HOME:-} == /tmp/* \
    && -n ${AWTARCHY_TEST_ARCHIVE:-} ]]; then
    return 0
  fi
  [[ -n $target && $target != root ]] \
    || die "Do not run Awtarchy config maintenance as root. Run awtarchy as your normal user."
  target_home="$(getent passwd "$target" 2>/dev/null | cut -d: -f6 || true)"
  [[ -n $target_home && -d $target_home ]] \
    || die "Could not resolve the invoking user's home before dropping root privileges."
  command -v runuser >/dev/null 2>&1 \
    || die "runuser is required to drop root privileges for config maintenance."

  exec runuser -u "$target" -- env \
    HOME="$target_home" USER="$target" LOGNAME="$target" \
    bash "${BASH_SOURCE[0]}" update-reset-backup "$@"
}

main() {
  drop_update_privileges "$@"
  parse_args "$@" || return 0
  need_cmd curl
  need_cmd tar
  need_cmd find
  need_cmd cmp
  need_cmd mktemp
  need_cmd getent
  need_cmd python3
  need_cmd sha256sum

  init_target_user
  awtarchy_polkit_recover_session_environment || true
  acquire_lock
  recover_interrupted_quickshell_update \
    || die "Could not recover Quickshell from the previous interrupted update."
  curl_headers

  TMPD="$(mktemp -d)"
  local tag="$TAG_OVERRIDE" source_label="" source_revision="" stable_predecessor=""
  local testing_branch_head=""
  if [[ -n "$TESTING_COMMIT" ]]; then
    testing_branch_head="$(resolve_remote_testing_branch_head "$TESTING_BRANCH")" \
      || die "Could not resolve remote Awtarchy branch: ${TESTING_BRANCH}"
    testing_commit_belongs_to_branch "$TESTING_COMMIT" "$testing_branch_head" \
      || die "Commit ${TESTING_COMMIT} does not belong to selected branch ${TESTING_BRANCH}."
    source_revision="$TESTING_COMMIT"
    source_label="${TESTING_BRANCH}@${TESTING_COMMIT}"
    stable_predecessor="$(stable_release_before_git_test)"
  else
    [[ -n "$tag" ]] || tag="$(fetch_latest_release_tag)"
    source_label="$tag"
  fi
  log "Target user: ${TARGET_USER}"
  if [[ -n "$source_revision" ]]; then
    log "Git testing branch: ${TESTING_BRANCH}"
    log "Resolved branch head: ${testing_branch_head}"
    log "Git testing commit: ${source_revision}"
    log "Stable predecessor: ${stable_predecessor}"
  else
    log "Release tag: ${tag}"
  fi

  local tgz="${TMPD}/awtarchy.tgz" top archive_revision expected_top repo_dir target_home plan_file active_theme=""
  log "Downloading source archive for ${source_label} (stalled transfers abort after 30 seconds)..."
  if [[ -n "$source_revision" ]]; then
    download_testing_commit_tarball "$source_revision" "$tgz" \
      || die "Failed to download testing commit ${source_revision}"
    archive_revision="$source_revision"
  else
    download_release_tarball "$tag" "$tgz" \
      || die "Failed to download release tarball for ${tag}"
    archive_revision="$RESOLVED_RELEASE_COMMIT"
  fi
  expected_top="${REPO_NAME}-${archive_revision}"
  top="$(validate_source_archive "$tgz" "$expected_top")" \
    || die "Source archive does not match immutable revision ${archive_revision}"
  tar -xzf "$tgz" -C "$TMPD"
  repo_dir="${TMPD}/${top}"
  [[ -d "$repo_dir" ]] || die "Extracted repo directory is missing"

  repair_v354_sony_battery_disable_repo "$repo_dir" "$tag"
  repair_v355_clipboard_thumbnail_repo "$repo_dir" "$tag"

  target_home="${TMPD}/target-home"
  TARGET_STAGE_HOME="$target_home"
  build_target_home "$repo_dir" "$target_home"

  active_theme="$(infer_active_theme "$repo_dir" || true)"
  if [[ -n "$active_theme" ]]; then
    apply_theme_to_target "$repo_dir" "$target_home" "$active_theme"       || die "Theme generation failed for ${active_theme}; no live files were changed."
  else
    warn "No trusted active-theme state was found. The release defaults will be used."
  fi

  prepare_quickshell_update_target "$target_home"
  repair_v342_mouse_submap_target "$target_home" "$tag"
  repair_v342_workspace_focus_target "$target_home" "$tag"
  repair_v343_transient_task_icons_target "$target_home" "$tag"
  repair_v347_idle_inhibitor_feedback_target "$target_home" "$tag"
  repair_v350_aur_helper_policy_target "$target_home" "$tag"
  repair_v353_update_notifier_target "$target_home" "$tag"

  bootstrap_previous_baseline "$active_theme"
  augment_baseline_from_local_git_history "$target_home"
  print_hardware_preview

  plan_file="${TMPD}/plan.tsv"
  build_plan "$target_home" "$plan_file"
  normalize_quickshell_update_plan "$repo_dir" "$plan_file"
  stage_quickshell_hyprland_user_patch "$target_home"
  review_plan "$plan_file"

  if (( REVIEW_ONLY == 1 )); then
    log "Review-only mode complete. No files were changed."
    return 0
  fi

  select_update_mode
  if [[ "$UPDATE_MODE" == "preserve" ]]; then
    log "Selected update mode: preserve hyprland.lua; update other managed files"
  else
    log "Selected update mode: clean"
  fi

  if target_uses_direct_aur_scanner "$target_home"; then
    ensure_update_aur_scanner       || die "aur-scanner is required before replacing the AurGuard-era managed shell. No managed files were changed."
  fi

  if [[ ${AWTARCHY_TEST_SKIP_SCXCTL_HELPER_REPAIR:-0} != 1 ]]; then
    repair_scxctl_update_helper "$repo_dir"
    if (( IS_LAPTOP_NOW == 1 )); then
      reconcile_power_profile_backend "$repo_dir"
    fi
  fi
  if (( REVIEW_ONLY == 0 )); then
    cleanup_legacy_keyring_pam_stage "$repo_dir"
  fi
  ensure_quickshell_update_prerequisites
  migrate_cheese_to_snapshot_stage \
    "${repo_dir}/local/share/awtarchy/awtarchy-package-reconcile.sh" \
    "${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh"
  snapshot_quickshell_update_legacy_paths

  stop_quickshell_update_shell \
    || die "Could not stop Quickshell safely before updating managed files."
  apply_plan "$plan_file" || die "Update failed and user files were rolled back."

  if ! install_awtarchy_polkit_agent_runtime "$repo_dir"; then
    rollback_quickshell_update
    die "Could not install the root-owned Awtarchy PolicyKit authentication runtime."
  fi

  local polkit_migration_rc=0 polkit_activation_rc=0 polkit_remove_legacy_ready=0
  migrate_awtarchy_polkit_autostart || polkit_migration_rc=$?
  case "$polkit_migration_rc" in
    0)
      activate_awtarchy_polkit_agent || polkit_activation_rc=$?
      case "$polkit_activation_rc" in
        0)
          polkit_remove_legacy_ready=1
          ;;
        2)
          warn "No live Hyprland user session is available; the Awtarchy PolicyKit agent will start on the next Hyprland session."
          warn "Leaving polkit-gnome installed as a fallback until live activation is confirmed."
          ;;
        *)
          rollback_changes
          die "Awtarchy PolicyKit activation failed; polkit-gnome was restored and managed user files were rolled back."
          ;;
      esac
      ;;
    2)
      warn "Custom PolicyKit startup was detected; the Awtarchy runtime was installed but that custom startup was not replaced."
      ;;
    *)
      rollback_changes
      die "Could not migrate Hyprland PolicyKit startup; managed user files were rolled back."
      ;;
  esac

  hardware_reconcile
  fix_managed_perms "$target_home"
  normalize_managed_executables "$HOME_DIR"
  refresh_cursor_assets

  if ! reload_quickshell_update_hyprland; then
    rollback_quickshell_update
    die "Hyprland reload failed. User files were rolled back."
  fi

  if ! validate_live; then
    rollback_quickshell_update
    die "Live validation failed. User files were rolled back."
  fi

  if ! start_quickshell_update_shell; then
    rollback_quickshell_update
    report_quickshell_update_failure "$source_label" "$target_home"
    die "Quickshell did not start successfully. User files were rolled back."
  fi

  if ! remove_quickshell_update_legacy_files; then
    rollback_quickshell_update
    die "Legacy shell cleanup failed. User files were rolled back."
  fi

  persist_quickshell_hyprland_user_patch
  remove_quickshell_update_legacy_packages
  migrate_retired_hyprlock_stage "$repo_dir"
  migrate_screenshare_guard_hyprland_stage "$repo_dir" "$target_home"

  if (( polkit_remove_legacy_ready == 1 )); then
    remove_legacy_polkit_gnome_package
  fi

  commit_baseline "$target_home" "$source_label" "$active_theme"
  write_hardware_state
  [[ -n "$active_theme" ]] && printf '%s\n' "$active_theme" >"$ACTIVE_THEME_FILE"
  if [[ -n "$source_revision" ]]; then
    write_version_stamp "$source_label"
    write_git_testing_state "$TESTING_BRANCH" "$source_revision" "$stable_predecessor"
  else
    clear_git_testing_state
    write_version_stamp "$source_label"
  fi
  write_audit "$source_label" "$active_theme"
  [[ "${EUID}" -eq 0 ]] && chown -R "${TARGET_USER}:${TARGET_USER}" "$STATE_DIR" 2>/dev/null || true

  # A preserved hyprland.lua may have intentionally won a three-way merge
  # conflict. Apply only the one-time, conflict-safe Hyprmoncfg integration;
  # never replace the user's file or take an already-owned shortcut.
  if [[ "$UPDATE_MODE" == "preserve" ]]; then
    hyprmoncfg_migrator="${HOME_DIR}/.config/hypr/scripts/hyprmoncfg_config_migrate.py"
    if [[ -f "$hyprmoncfg_migrator" ]]; then
      if command -v python3 >/dev/null 2>&1; then
        run_target env \
          "HOME=${HOME_DIR}" \
          "HYPRLAND_CONFIG=${HOME_DIR}/.config/hypr/hyprland.lua" \
          python3 "$hyprmoncfg_migrator" \
          || warn "Hyprmoncfg integration could not be added to the preserved hyprland.lua; local configuration was left intact."
      else
        warn "python3 is unavailable; skipped preserved Hyprmoncfg config migration."
      fi
    fi
  fi

  command -v hyprctl >/dev/null 2>&1 && run_target hyprctl reload >/dev/null 2>&1 || true
  reapply_cursor_theme_after_update
  restart_hypridle_after_update
  if (( ${#BACKUPS[@]} )); then
    warn "Backups created:"
    printf '  %s\n' "${BACKUPS[@]}"
  else
    log "No persistent backups were required."
  fi

  log "Changed: ${#CHANGED[@]}, preserved: ${#PRESERVED[@]}, merged: ${#MERGED[@]}, removed: ${#REMOVED[@]}"
  log "Audit log: ${AUDIT_LOG}"
  log "Done."
}

main "$@"
}

update_backup_cleaner_main() {
set -Eeuo pipefail
umask 022

SCRIPT_NAME="update-backup-cleaner.sh"
LOG_PREFIX="[${SCRIPT_NAME}]"

log()  { printf '%s %s\n'  "$LOG_PREFIX" "$*"; }
warn() { printf '%s WARN: %s\n' "$LOG_PREFIX" "$*" >&2; }
die()  { printf '%s ERROR: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

usage() {
  cat <<'EOF'
Usage:
  awtarchy clean-backups [options]

IMPORTANT:
  - Do NOT run with sudo. This scans backups under your home directory.

Default (interactive TTY):
  - Scans common awtarchy-managed paths under $HOME for:
      *.backup
      *.backup.YYYYMMDD-HHMMSS
  - Shows a paged list (default 20 items/page)
  - Press a number to toggle KEEP immediately (no Enter)
  - Press [D] to delete everything NOT marked KEEP

Options:
  --dry-run              Print full list and exit (no menu, no deletes)
  --yes                  Delete ALL matches without prompts (ignores KEEP UI)
  --older-than <days>    Only match files with mtime strictly greater than <days> (integer)
  --archive <tar.gz>     Create a tar.gz archive (relative to $HOME if not absolute)
  --help                 Show help

Paging config:
  - Default page size: 20
  - Change via:
      AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_DEFAULT=40 awtarchy clean-backups
    or press [G] in the menu (saved in ~/.config/awtarchy/backup_clean_page_size)

Examples:
  awtarchy clean-backups
  awtarchy clean-backups --dry-run
EOF
}

# Refuse sudo/root: this script is designed to run as the user who owns the backups.
if [[ "${EUID}" -eq 0 ]]; then
  die "Do not run this with sudo. Run as your normal user.
Example:
  awtarchy clean-backups"
fi

# --- args ---
DRY_RUN=0
YES=0
OLDER_THAN=""
ARCHIVE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes) YES=1; shift ;;
    --older-than)
      OLDER_THAN="${2:-}"
      [[ "$OLDER_THAN" =~ ^[0-9]+$ ]] || die "--older-than expects an integer days value"
      shift 2
      ;;
    --archive)
      ARCHIVE="${2:-}"
      [[ -n "$ARCHIVE" ]] || die "Missing value for --archive"
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown arg: $1 (use --help)" ;;
  esac
done

need_cmd find
need_cmd stat
need_cmd rm
need_cmd sort
need_cmd mktemp
need_cmd head
need_cmd tr
if [[ -n "$ARCHIVE" ]]; then
  need_cmd tar
fi

HOME_DIR="${HOME:-}"
[[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || die "\$HOME is not set to a valid directory"

# If archive is not absolute, treat it as under $HOME.
if [[ -n "$ARCHIVE" && "$ARCHIVE" != /* ]]; then
  ARCHIVE="${HOME_DIR}/${ARCHIVE}"
fi

# Match:
#   dest.backup
#   dest.backup.YYYYMMDD-HHMMSS
regex_stamp='.*\.backup\.[0-9]{8}-[0-9]{6}$'

# Default roots (all under $HOME):
ROOTS=(
  "${HOME_DIR}"
  "${HOME_DIR}/.config"
  "${HOME_DIR}/.local/share"
  "${HOME_DIR}/Pictures"
)

mtime_args=()
if [[ -n "$OLDER_THAN" ]]; then
  mtime_args+=(-mtime "+${OLDER_THAN}")
fi

collect_backups() {
  local r
  local -a roots=()
  for r in "${ROOTS[@]}"; do
    [[ -e "$r" ]] || continue
    roots+=("$r")
  done
  (( ${#roots[@]} > 0 )) || return 0

  # Top-level in $HOME (dotfile backups like ~/.bashrc.backup)
  find "$HOME_DIR" -maxdepth 1 -type f "${mtime_args[@]}" \
    \( -name '*.backup' -o -regextype posix-extended -regex "$regex_stamp" \) \
    -print 2>/dev/null || true

  # Managed subtrees
  for r in "${roots[@]}"; do
    [[ "$r" == "$HOME_DIR" ]] && continue
    find "$r" -type f "${mtime_args[@]}" \
      \( -name '*.backup' -o -regextype posix-extended -regex "$regex_stamp" \) \
      -print 2>/dev/null || true
  done
}

dedupe_and_sort() {
  declare -A seen=()
  local line
  local -a out=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ -z "${seen[$line]:-}" ]]; then
      seen["$line"]=1
      out+=("$line")
    fi
  done
  (( ${#out[@]} == 0 )) && return 0
  printf '%s\n' "${out[@]}" | LC_ALL=C sort
}

bytes_total_for_list() {
  local -a arr=("$@")
  local f sz
  local total=0
  for f in "${arr[@]}"; do
    sz="$(stat -c '%s' -- "$f" 2>/dev/null || printf '0')"
    [[ "$sz" =~ ^[0-9]+$ ]] && total=$((total + sz))
  done
  printf '%s\n' "$total"
}

print_full_list() {
  local -a arr=("$@")
  local bytes
  bytes="$(bytes_total_for_list "${arr[@]}")"
  log "Matches: ${#arr[@]}"
  log "Total size: ${bytes} bytes"
  log "Files:"
  local i
  for i in "${!arr[@]}"; do
    printf '  [%d] %s\n' "$((i+1))" "${arr[$i]}"
  done
}

make_archive_for_delete_list() {
  local archive_path="$1"
  shift
  local -a del_list=("$@")

  [[ -n "$archive_path" ]] || return 0
  (( ${#del_list[@]} > 0 )) || return 0

  local rel_tmp
  rel_tmp="$(mktemp)"
  : >"$rel_tmp"

  local f rel
  for f in "${del_list[@]}"; do
    case "$f" in
      "$HOME_DIR"/*)
        rel="${f#"$HOME_DIR"/}"
        printf '%s\0' "$rel" >>"$rel_tmp"
        ;;
      *)
        warn "Skipping (not under \$HOME, will not archive): $f"
        ;;
    esac
  done

  mkdir -p -- "$(dirname -- "$archive_path")"
  log "Creating archive: $archive_path"
  tar -C "$HOME_DIR" --null -T "$rel_tmp" -czf "$archive_path"
  rm -f -- "$rel_tmp" 2>/dev/null || true
}

delete_files_verified() {
  local -a del_list=("$@")
  local removed=0 failed=0 skipped=0 f existed=0
  for f in "${del_list[@]}"; do
    existed=0
    [[ -e "$f" ]] && existed=1
    rm -f -- "$f" 2>/dev/null || true

    if (( existed == 0 )); then
      ((skipped++)) || true
      continue
    fi

    if [[ ! -e "$f" ]]; then
      ((removed++)) || true
    else
      ((failed++)) || true
      warn "Failed to delete (still exists): $f"
    fi
  done

  log "Removed: ${removed}"
  (( skipped > 0 )) && log "Skipped (already gone): ${skipped}"
  if (( failed > 0 )); then
    warn "Failed: ${failed}"
    return 2
  fi
  return 0
}

clear_screen() {
  if command -v clear >/dev/null 2>&1; then
    clear
  else
    printf '\033[H\033[2J'
  fi
}

# --- gather files ---
mapfile -t ALL_FILES < <(collect_backups | dedupe_and_sort)

if (( ${#ALL_FILES[@]} == 0 )); then
  log "No .backup files found in awtarchy-managed paths."
  exit 0
fi

if [[ ! -t 0 ]] && (( DRY_RUN == 0 && YES == 0 )); then
  warn "Non-interactive stdin. Showing list only. Use --yes to delete."
  print_full_list "${ALL_FILES[@]}"
  exit 0
fi

if (( DRY_RUN == 1 )); then
  print_full_list "${ALL_FILES[@]}"
  exit 0
fi

if (( YES == 1 )); then
  [[ -n "$ARCHIVE" ]] && make_archive_for_delete_list "$ARCHIVE" "${ALL_FILES[@]}"
  delete_files_verified "${ALL_FILES[@]}"
  exit $?
fi

# --- interactive paged UI ---
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME_DIR/.config}/awtarchy"
PAGE_SIZE_DEFAULT="${AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_DEFAULT:-20}"
PAGE_SIZE_MAX="${AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_MAX:-200}"
PAGE_SIZE_FILE="${AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_FILE:-$CONFIG_DIR/backup_clean_page_size}"

get_page_size() {
  local def="$PAGE_SIZE_DEFAULT"
  local max="$PAGE_SIZE_MAX"
  local v=""
  if [[ -r "$PAGE_SIZE_FILE" ]]; then
    v="$(head -n1 "$PAGE_SIZE_FILE" 2>/dev/null | tr -d '\r' || true)"
  fi
  if [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 5 && v <= max )); then
    printf '%s\n' "$v"
    return 0
  fi
  if [[ "$def" =~ ^[0-9]+$ ]] && (( def >= 5 && def <= max )); then
    printf '%s\n' "$def"
  else
    printf '%s\n' "20"
  fi
}

save_page_size() {
  local n="${1:-}"
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  (( n >= 5 && n <= PAGE_SIZE_MAX )) || return 1
  mkdir -p "$CONFIG_DIR"
  printf '%s\n' "$n" >"$PAGE_SIZE_FILE"
}

declare -A KEEP=()
FILTER=""
page_size="$(get_page_size)"
page=0

build_view() {
  local f q
  if [[ -z "$FILTER" ]]; then
    printf '%s\n' "${ALL_FILES[@]}"
    return 0
  fi
  q="${FILTER,,}"
  for f in "${ALL_FILES[@]}"; do
    [[ "${f,,}" == *"$q"* ]] && printf '%s\n' "$f"
  done
}

prompt_set_page_size() {
  local cur="$1"
  local input
  while :; do
    printf '%s Page size [%s] (5-%s, q=cancel): ' "$LOG_PREFIX" "$cur" "$PAGE_SIZE_MAX"
    read -r input || exit 1
    [[ "${input,,}" == "q" ]] && return 0
    [[ -z "$input" ]] && return 0
    if ! save_page_size "$input"; then
      printf '%s Invalid page size.\n' "$LOG_PREFIX"
      continue
    fi
    page_size="$input"
    printf '%s Saved page size: %s\n' "$LOG_PREFIX" "$page_size"
    return 0
  done
}

prompt_find() {
  local input
  printf '%s Find (substring, empty clears): ' "$LOG_PREFIX"
  read -r input || exit 1
  FILTER="$input"
  page=0
}

toggle_keep_by_local_index() {
  local local_sel="$1"
  local start="$2"
  shift 2
  local -a view=("$@")
  local idx=$(( start + local_sel - 1 ))
  (( idx < 0 || idx >= ${#view[@]} )) && return 1
  local f="${view[$idx]}"
  if [[ -n "${KEEP[$f]:-}" ]]; then
    unset 'KEEP[$f]'
  else
    KEEP["$f"]=1
  fi
}

confirm_delete() {
  local del_count="$1"
  local keep_count="$2"
  local ans
  printf '%s Delete %s files (keeping %s)? [y/N]: ' "$LOG_PREFIX" "$del_count" "$keep_count"
  read -r ans || exit 1
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

PENDING_KEY=""

read_key() {
  local ch=""
  if [[ -n "$PENDING_KEY" ]]; then
    ch="$PENDING_KEY"
    PENDING_KEY=""
    printf '%s' "$ch"
    return 0
  fi
  IFS= read -rsn1 ch || exit 1
  printf '%s' "$ch"
}

read_number_no_enter() {
  local sel="$1"
  local max="$2"
  local next=""
  local prefix

  prefix="$sel"
  if (( prefix * 10 > max )); then
    printf '%s' "$sel"
    return 0
  fi

  if IFS= read -rsn1 -t 0.12 next; then
    if [[ "$next" =~ ^[0-9]$ ]]; then
      sel+="$next"
      prefix="$sel"
      if (( prefix * 10 <= max )); then
        next=""
        if IFS= read -rsn1 -t 0.12 next; then
          if [[ "$next" =~ ^[0-9]$ ]]; then
            sel+="$next"
          else
            PENDING_KEY="$next"
          fi
        fi
      fi
    else
      PENDING_KEY="$next"
    fi
  fi

  printf '%s' "$sel"
}

quit_clean() {
  clear_screen
  exit 0
}

while :; do
  mapfile -t VIEW_FILES < <(build_view)

  total="${#VIEW_FILES[@]}"
  pages=$(( (total + page_size - 1) / page_size ))
  (( pages < 1 )) && pages=1
  (( page < 0 )) && page=0
  if (( page >= pages )); then
    page=$(( pages - 1 ))
  fi

  start=$(( page * page_size ))
  end=$(( start + page_size ))
  (( end > total )) && end=$total
  on_page=$(( end - start ))

  clear_screen
  printf '%s Backup files\n' "$LOG_PREFIX"

  if (( total == 0 )); then
    echo "No matches."
    echo
  else
    printf 'Page %d/%d, %d-%d of %d, size %d\n\n' \
      "$((page + 1))" "$pages" "$((start + 1))" "$end" "$total" "$page_size"

    i="$start"
    local_i=1
    while (( i < end )); do
      f="${VIEW_FILES[$i]}"
      if [[ -n "${KEEP[$f]:-}" ]]; then
        mark="[KEEP]"
      else
        mark="[    ]"
      fi
      printf '  [%d] %s %s\n' "$local_i" "$mark" "$f"
      ((i++)) || true
      ((local_i++)) || true
    done
    echo
  fi

  echo "  [N]Next [P]Prev [G]Page [F]Find"
  echo "  [D]Delete [Q]Quit"
  echo

  if (( on_page > 0 )); then
    printf 'Select 1-%d or key: ' "$on_page"
  else
    printf 'Key: '
  fi

  ch="$(read_key)"

  case "$ch" in
    $'\r'|$'\n') ;;
    [qQ]) quit_clean ;;
    [nN])
      if (( page + 1 < pages )); then
        page=$((page + 1))
      fi
      ;;
    [pP])
      if (( page > 0 )); then
        page=$((page - 1))
      fi
      ;;
    [gG])
      echo
      prompt_set_page_size "$page_size"
      page=0
      ;;
    [fF])
      echo
      prompt_find
      ;;
    [dD])
      declare -a DEL_LIST=()
      keep_count=0

      for f in "${ALL_FILES[@]}"; do
        if [[ -n "${KEEP[$f]:-}" ]]; then
          ((keep_count++)) || true
        else
          DEL_LIST+=("$f")
        fi
      done

      del_count="${#DEL_LIST[@]}"

      echo
      if (( del_count == 0 )); then
        log "Nothing to delete (everything is KEEP)."
        printf '%s Press any key...' "$LOG_PREFIX"
        IFS= read -rsn1 _ || true
        continue
      fi

      if ! confirm_delete "$del_count" "$keep_count"; then
        continue
      fi

      [[ -n "$ARCHIVE" ]] && make_archive_for_delete_list "$ARCHIVE" "${DEL_LIST[@]}"

      delete_files_verified "${DEL_LIST[@]}"
      exit $?
      ;;
    [0-9])
      if (( on_page == 0 )); then
        continue
      fi
      [[ "$ch" == "0" ]] && continue

      sel="$(read_number_no_enter "$ch" "$on_page")"
      [[ "$sel" =~ ^[0-9]+$ ]] || continue
      if (( sel < 1 || sel > on_page )); then
        continue
      fi
      toggle_keep_by_local_index "$sel" "$start" "${VIEW_FILES[@]}" || true
      ;;
    *) ;;
  esac
done
}

troubleshoot_main() {
  local command_name="awtarchy"
  local target_user="" target_home="" state_root="" log_dir="" report="" timestamp=""
  local hypr_file="" baseline_hypr="" binds_json="" clients_json="" path="" pkg="" unit="" f=""
  local -a recent_logs=()

  if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
    target_user="$SUDO_USER"
    target_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6 || true)"
  else
    target_user="${USER:-$(id -un 2>/dev/null || printf unknown)}"
    target_home="${HOME:-}"
  fi
  if [[ -z "$target_home" || ! -d "$target_home" ]]; then
    target_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6 || true)"
  fi
  [[ -n "$target_home" && -d "$target_home" ]] \
    || die "Could not determine the user home directory for troubleshooting."

  state_root="${target_home}/.local/state"
  log_dir="${state_root}/awtarchy/logs"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  umask 077
  mkdir -p -- "$log_dir"
  report="${log_dir}/troubleshoot-${timestamp}.log"
  hypr_file="${target_home}/.config/hypr/hyprland.lua"
  baseline_hypr="${state_root}/awtarchy/baseline/home/.config/hypr/hyprland.lua"

  diag_section() {
    printf '\n================ %s ================\n' "$1"
  }

  diag_timeout() {
    if command -v timeout >/dev/null 2>&1; then
      timeout 5 "$@"
    else
      "$@"
    fi
  }

  diag_hash() {
    local candidate="$1"
    if [[ -f "$candidate" ]]; then
      printf '%s  %s\n' "$(sha256sum "$candidate" 2>/dev/null | awk '{print $1}')" "$candidate"
    elif [[ -L "$candidate" ]]; then
      printf 'SYMLINK %s -> %s\n' "$candidate" "$(readlink "$candidate" 2>/dev/null || true)"
    else
      printf 'MISSING %s\n' "$candidate"
    fi
  }

  diag_script() {
    local candidate="$1"
    printf '%-48s ' "${candidate#"${target_home}/"}"
    if [[ -x "$candidate" ]]; then
      printf 'EXECUTABLE'
    elif [[ -e "$candidate" ]]; then
      printf 'PRESENT-NOT-EXECUTABLE'
    else
      printf 'MISSING\n'
      return 0
    fi
    if [[ -f "$candidate" ]]; then
      if bash -n "$candidate" >/dev/null 2>&1; then
        printf ' bash-n=OK'
      else
        printf ' bash-n=FAIL'
      fi
      printf ' sha256=%s' "$(sha256sum "$candidate" 2>/dev/null | awk '{print $1}')"
    fi
    printf '\n'
  }

  {
    printf 'Awtarchy troubleshooting report\n'
    printf 'command=%s\n' "$command_name"
    printf 'generated_at=%s\n' "$(date -Iseconds)"
    printf 'target_user=%s\n' "$target_user"
    printf 'target_home=%s\n' "$target_home"
    printf 'read_only_checks=yes\n'

    diag_section "SYSTEM"
    uname -a 2>&1 || true
    [[ -r /etc/os-release ]] && cat /etc/os-release || true
    printf '\n--- CPU ---\n'
    diag_timeout lscpu 2>&1 | grep -E '^(Architecture|CPU\(s\)|Model name|Vendor ID):' || true
    printf '\n--- DISPLAY CONTROLLERS ---\n'
    diag_timeout lspci -nn 2>&1 | grep -Ei 'VGA compatible controller|3D controller|Display controller|2D controller' || true

    diag_section "COMMANDS AND LOCAL VERSION STATE"
    path="$(command -v awtarchy 2>/dev/null || true)"
    printf 'awtarchy=%s\n' "${path:-MISSING}"
    [[ -n "$path" ]] && diag_hash "$path"
    for f in \
      "${state_root}/awtarchy/command-version" \
      "${state_root}/awtarchy/config-version" \
      "${state_root}/awtarchy/git-testing" \
      "${state_root}/awtarchy/hardware-state" \
      "${state_root}/awtarchy/active-theme"
    do
      printf '\n--- %s ---\n' "$f"
      if [[ -r "$f" ]]; then cat "$f"; else printf 'MISSING\n'; fi
    done
    printf '\n--- installed runtimes ---\n'
    diag_hash "${target_home}/.local/share/awtarchy/awtarchy-runtime.sh"
    printf '\n--- managed package ledger ---\n'
    if [[ -r /var/lib/awtarchy/managed-packages ]]; then
      cat /var/lib/awtarchy/managed-packages
    else
      printf 'MISSING OR UNREADABLE\n'
    fi

    diag_section "RELEVANT PACKAGES"
    if command -v pacman >/dev/null 2>&1; then
      for pkg in \
        hyprland hyprland-qt-support quickshell upower playerctl \
        waybar waybar-git fuzzel wlogout mako wofi \
        network-manager-applet blueman \
        tlp tlp-pd power-profiles-daemon \
        jq python
      do
        pacman -Q "$pkg" 2>/dev/null || printf '%-30s MISSING\n' "$pkg"
      done
    else
      printf 'pacman is unavailable\n'
    fi

    diag_section "SERVICES"
    if command -v systemctl >/dev/null 2>&1; then
      for unit in tlp.service tlp-pd.service power-profiles-daemon.service; do
        printf '%-34s enabled=' "$unit"
        diag_timeout systemctl is-enabled "$unit" 2>/dev/null || printf 'not-found'
        printf ' active='
        diag_timeout systemctl is-active "$unit" 2>/dev/null || printf 'inactive/not-found'
        printf '\n'
      done
      printf '\n--- failed system units ---\n'
      diag_timeout systemctl --failed --no-pager --full 2>&1 || true
      printf '\n--- failed user units ---\n'
      diag_timeout systemctl --user --failed --no-pager --full 2>&1 || true
      printf '\n--- relevant user units ---\n'
      diag_timeout systemctl --user list-units --all --no-pager --full 2>&1 \
        | grep -Ei 'awtarchy|quick|hypr|waybar|mako|wlogout|fuzzel' || true
      printf '\n--- user timers ---\n'
      diag_timeout systemctl --user list-timers --all --no-pager --full 2>&1 || true
    else
      printf 'systemctl is unavailable\n'
    fi

    diag_section "HYPRLAND"
    if command -v hyprctl >/dev/null 2>&1; then
      printf '%s\n' '--- version ---'
      diag_timeout hyprctl version 2>&1 || true
      printf '%s\n' '--- config errors ---'
      diag_timeout hyprctl configerrors 2>&1 || true
      printf '%s\n' '--- monitors ---'
      diag_timeout hyprctl monitors -j 2>&1 || true
    else
      printf 'hyprctl is unavailable\n'
    fi

    printf '\n--- live hyprland.lua ---\n'
    diag_hash "$hypr_file"
    if [[ -r "$hypr_file" ]]; then
      if command -v lua >/dev/null 2>&1; then
        if AWTARCHY_LUA_VALIDATE_FILE="$hypr_file" lua -e 'local p=assert(os.getenv("AWTARCHY_LUA_VALIDATE_FILE")); assert(loadfile(p))' >/dev/null 2>&1; then
          printf 'lua_syntax=OK\n'
        else
          printf 'lua_syntax=FAIL\n'
        fi
      else
        printf 'lua_syntax=NOT_CHECKED(lua missing)\n'
      fi
      grep -nE -C 3 \
        'quickshell|waybar|mako|wlogout|fuzzel|hypr_quicksettings|nm-applet|blueman-applet|local (app_launcher|wlogout|power_menu|hypr_quicksettings|waybar_|bar_|mako_dismiss|notification_dismiss|clipboard_history)|SUPER \+ P|SUPER \+ SPACE|SUPER \+ ALT \+ B|SUPER \+ CTRL \+ B|SUPER \+ ALT \+ backspace' \
        "$hypr_file" 2>/dev/null || true
    fi

    printf '\n--- saved baseline hyprland.lua ---\n'
    diag_hash "$baseline_hypr"
    if [[ -r "$baseline_hypr" ]]; then
      grep -nE -C 3 \
        'quickshell|waybar|mako|wlogout|fuzzel|hypr_quicksettings|nm-applet|blueman-applet|SUPER \+ P|SUPER \+ SPACE|SUPER \+ ALT \+ B|SUPER \+ CTRL \+ B|SUPER \+ ALT \+ backspace' \
        "$baseline_hypr" 2>/dev/null || true
    fi
    printf '\n--- baseline metadata ---\n'
    [[ -r "${state_root}/awtarchy/baseline/metadata" ]] \
      && cat "${state_root}/awtarchy/baseline/metadata" \
      || printf 'MISSING\n'
    printf '\n--- baseline manifest summary ---\n'
    if [[ -r "${state_root}/awtarchy/baseline/manifest.paths" ]]; then
      printf 'entries=%s\n' "$(wc -l <"${state_root}/awtarchy/baseline/manifest.paths")"
      grep -E 'hyprland\.lua|quickshell|waybar|mako|wlogout|fuzzel|hypr_quicksettings' \
        "${state_root}/awtarchy/baseline/manifest.paths" 2>/dev/null || true
    else
      printf 'MISSING\n'
    fi

    diag_section "LOADED SHELL BINDS"
    if command -v hyprctl >/dev/null 2>&1; then
      binds_json="$(diag_timeout hyprctl binds -j 2>/dev/null || true)"
      if [[ -n "$binds_json" ]] && command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$binds_json" | jq '
          .[]
          | select(
              ((.key // "" | ascii_upcase) == "P")
              or ((.arg // "") | test("quick|waybar|mako|wlogout|fuzzel|awtarchy"; "i"))
            )
        ' 2>/dev/null || true
      else
        printf '%s\n' "${binds_json:-unavailable}"
      fi
    else
      printf 'hyprctl is unavailable\n'
    fi

    diag_section "CURRENT QUICKSHELL HELPERS"
    for f in \
      quickshell.sh \
      quickshell_launcher.sh \
      quickshell_power_menu.sh \
      quickshell_quick_settings_toggle.sh \
      quickshell_clipboard_toggle.sh \
      quickshell_notification_dismiss.sh \
      quickshell_bar_toggle.sh \
      quickshell_bar_flip.sh \
      quickshell_bar_rotate.sh \
      quickshell_resume_recover.sh \
      hypr_quicksettings.sh \
      hypr_quicksettings_core.sh
    do
      diag_script "${target_home}/.config/hypr/scripts/${f}"
    done

    diag_section "RETIRED SHELL HELPER STATUS"
    for f in \
      waybar.sh waybar_ready_sound.sh waybar_toggle.sh waybar_flip.sh waybar_rotate.sh \
      fuzzel_toggle.sh wlogout_toggle.sh mako_dismiss.sh cliphist-fuzzel.sh cliphist-wofi.sh
    do
      diag_script "${target_home}/.config/hypr/scripts/${f}"
    done
    printf '\n--- legacy desktop entry ---\n'
    diag_hash "${target_home}/.local/share/applications/hypr_quicksettings.desktop"
    if [[ -r "${target_home}/.local/share/applications/hypr_quicksettings.desktop" ]]; then
      cat "${target_home}/.local/share/applications/hypr_quicksettings.desktop"
    fi

    diag_section "QUICKSHELL CONFIG HASHES"
    if [[ -d "${target_home}/.config/quickshell/awtarchy" ]]; then
      find "${target_home}/.config/quickshell/awtarchy" -maxdepth 1 -type f -print0 2>/dev/null \
        | sort -z \
        | xargs -0 -r sha256sum 2>/dev/null || true
    else
      printf 'MISSING %s\n' "${target_home}/.config/quickshell/awtarchy"
    fi

    diag_section "RUNNING SHELL PROCESSES"
    ps -eo pid,ppid,lstart,etime,args 2>/dev/null \
      | grep -Ei '(^|[ /])(qs|quickshell|waybar|mako|wlogout|fuzzel)([ /]|$)|hypr_quicksettings|nm-applet|blueman' \
      | grep -vE 'grep -Ei|troubleshoot' || true

    diag_section "RELEVANT HYPRLAND CLIENTS"
    if command -v hyprctl >/dev/null 2>&1; then
      clients_json="$(diag_timeout hyprctl clients -j 2>/dev/null || true)"
      if [[ -n "$clients_json" ]] && command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$clients_json" | jq '
          .[]
          | select(
              ((.class // "") | test("quick|waybar|mako|wlogout|fuzzel|alacritty"; "i"))
              or ((.initialClass // "") | test("quick|waybar|mako|wlogout|fuzzel|alacritty"; "i"))
              or ((.title // "") | test("quick settings|awtarchy"; "i"))
            )
          | {address,pid,class,initialClass,title,initialTitle}
        ' 2>/dev/null || true
      else
        printf '%s\n' "${clients_json:-unavailable}"
      fi
    else
      printf 'hyprctl is unavailable\n'
    fi

    diag_section "QUICKSHELL IPC"
    printf 'qs_path=%s\n' "$(command -v qs 2>/dev/null || printf MISSING)"
    if command -v qs >/dev/null 2>&1; then
      diag_timeout qs --version 2>&1 || true
      printf '%s\n' '--- awtarchy control ping ---'
      diag_timeout qs -c awtarchy ipc call control ping 2>&1 || true
    fi

    diag_section "QUICKSHELL STATE AND LOG"
    printf '%s\n' '--- quickshell-state.json ---'
    if [[ -r "${target_home}/.cache/awtarchy/quickshell-state.json" ]]; then
      cat "${target_home}/.cache/awtarchy/quickshell-state.json"
    else
      printf 'MISSING\n'
    fi
    printf '%s\n' '--- quickshell.log (last 1000 lines) ---'
    if [[ -r "${target_home}/.cache/awtarchy/quickshell.log" ]]; then
      tail -n 1000 "${target_home}/.cache/awtarchy/quickshell.log"
    else
      printf 'MISSING\n'
    fi

    diag_section "AUTOSTART AND USER SERVICE REFERENCES"
    grep -RInE \
      'quickshell|waybar|mako|wlogout|fuzzel|hypr_quicksettings|nm-applet|blueman' \
      "${target_home}/.config/autostart" \
      "${target_home}/.config/systemd/user" \
      "${target_home}/.local/share/systemd/user" \
      "${target_home}/.bash_profile" \
      "${target_home}/.profile" \
      2>/dev/null || true

    diag_section "RECENT AWTARCHY UPDATE LOGS"
    mapfile -t recent_logs < <(
      find \
        "${state_root}/awtarchy/logs" \
        -maxdepth 1 -type f -name 'update-*.log' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -n 5 | cut -d' ' -f2-
    )
    if (( ${#recent_logs[@]} == 0 )); then
      printf 'No update logs found.\n'
    else
      for f in "${recent_logs[@]}"; do
        printf '\n---------------- %s ----------------\n' "$f"
        cat "$f" 2>/dev/null || true
      done
    fi

    diag_section "CURRENT BOOT USER JOURNAL"
    if command -v journalctl >/dev/null 2>&1; then
      diag_timeout journalctl --user -b --no-pager 2>/dev/null \
        | grep -Ei 'quickshell|(^|/)qs|hyprland|waybar|mako|wlogout|fuzzel|quick.?settings|awtarchy' \
        | tail -n 1000 || true
    else
      printf 'journalctl is unavailable\n'
    fi

    diag_section "CURRENT BOOT SYSTEM JOURNAL"
    if command -v journalctl >/dev/null 2>&1; then
      diag_timeout journalctl -b --no-pager 2>/dev/null \
        | grep -Ei 'quickshell|(^|/)qs|hyprland|waybar|mako|wlogout|fuzzel|quick.?settings|awtarchy' \
        | tail -n 1000 || true
    else
      printf 'journalctl is unavailable\n'
    fi

    diag_section "COREDUMPS"
    if command -v coredumpctl >/dev/null 2>&1; then
      diag_timeout coredumpctl --no-pager list 2>/dev/null \
        | grep -Ei 'quickshell|(^|[ /])qs([ /]|$)|hyprland|waybar|mako|wlogout|fuzzel' \
        | tail -n 100 || true
    else
      printf 'coredumpctl is unavailable\n'
    fi

    diag_section "REPORT"
    printf 'saved_to=%s\n' "$report"
    printf 'No configuration, packages, services, or shell processes were changed by this command.\n'
  } | tee "$report"
}

main_awtarchy() {
  case "${1:-}" in
    "") top_menu ;;
    dry-run|dryrun|test) shift; run_install --dry-run "$@" ;;
    install) shift; run_install "$@" ;;
    update-reset-backup|update-reset) shift; update_reset_backup_main "$@" ;;
    update-backup-cleaner|clean-backups|backup-cleaner) shift; run_backup_cleaner_entry "$@" ;;
    troubleshoot) shift; (( $# == 0 )) || die "troubleshoot does not accept options."; troubleshoot_main ;;
    __backup-cleaner) shift; update_backup_cleaner_main "$@" ;;
    help|-h|--help) usage ;;
    *) die "Unknown command: $1" ;;
  esac
}

main_awtarchy "$@"
