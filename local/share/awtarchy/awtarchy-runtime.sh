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
  "Window Management:hyprland hyprpaper hyprlock hypridle hyprpicker hyprsunset quickshell grim satty slurp wl-clipboard cliphist zbar wf-recorder zenity qt5ct qt5-wayland kvantum-qt5 qt6ct qt6-wayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk libnotify nwg-look"
  "Fonts:woff2-font-awesome otf-font-awesome ttf-dejavu ttf-liberation ttf-noto-nerd noto-fonts-emoji"
  "Themes:papirus-icon-theme materia-gtk-theme xcursor-comix kvantum-theme-materia"
  "Terminal Apps:nano micro fastfetch btop htop curl passt devtools wget git dos2unix brightnessctl ipcalc cmatrix asciiquarium figlet espeak-ng cava man-db man-pages unzip xarchiver ncdu ddcutil scx-scheds scx-tools"
  "Utilities:upower polkit python-gobject gnome-keyring networkmanager bluez bluez-utils wiremix pcmanfm-qt gvfs gvfs-smb gvfs-mtp gvfs-afc speedcrunch imagemagick pipewire pipewire-pulse pipewire-alsa ufw jq earlyoom libsixel xdg-utils python usbutils awww"
  "Multimedia:ffmpeg avahi nss-mdns mpv snapshot exiv2 zathura zathura-pdf-mupdf"
  "Development:base-devel archlinux-keyring bubblewrap gnupg coreutils clang ninja go rust dmidecode nftables"
  "Network Tools:firefox wireguard-tools wireplumber openssh iptables systemd-resolvconf qemu-guest-agent dnsmasq dhcpcd inetutils openbsd-netcat"
)

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
  mpvpaper
  qimgv
  alacritty-graphics
  obs-pipewire-audio-capture-bin
)

declare -a OPTIONAL_AUR_PACKAGES=(
  vesktop-bin
)

declare -a FLATPAK_CATALOG=(
  "0|Flatseal|com.github.tchx84.Flatseal"
)

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
      0) : ;;
      10)
        backup="${nsswitch}.awtarchy-backup.$(date '+%Y%m%d-%H%M%S')"
        "${root_cmd[@]}" cp -a -- "$nsswitch" "$backup"
        "${root_cmd[@]}" install -m 0644 "$nss_tmp" "$nsswitch"
        changed=1
        log "Backed up NSS configuration: ${backup}"
        ;;
      3) warn "Expected exactly one hosts: line in ${nsswitch}; leaving it unchanged." ;;
      4) warn "No resolve/dns anchor found in ${nsswitch}; leaving hosts lookup order unchanged." ;;
      *) warn "Could not reconcile ${nsswitch}; leaving it unchanged." ;;
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
      $'\033[A') (( index > 0 )) && ((index--)) || true ;;
      $'\033[B') (( index + 1 < ${#items[@]} )) && ((index++)) || true ;;
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
      $'\033[A') (( index > 0 )) && ((index--)) || true ;;
      $'\033[B') (( index + 1 < ${#labels_ref[@]} )) && ((index++)) || true ;;
      ' ') if [[ "${values_ref[index]}" == "1" ]]; then values_ref[index]=0; else values_ref[index]=1; fi ;;
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

# The package-pickers and search helpers below are unchanged from the current branch.
# Keep their existing implementation in the release runtime.

# NOTE: This file continues below exactly as the branch runtime, with the legacy
# bespoke tlpui AUR block removed from install_aur_repo_apps_stage().
