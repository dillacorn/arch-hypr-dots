#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# Reconcile current Awtarchy package requirements and retired replacements.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

RUNTIME="${AWTARCHY_RUNTIME:-${HOME}/.local/share/awtarchy/awtarchy-runtime.sh}"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/awtarchy"
HARDWARE_FILE="${AWTARCHY_HARDWARE_FILE:-${STATE_DIR}/hardware-state}"
MANAGED_PACKAGES_FILE="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
REVIEW_ONLY=0

# Packages required by currently exposed Awtarchy shell/runtime features.
# Keep this list small. The full installer catalog remains authoritative for
# optional package selection below.
declare -a REQUIRED_ARCH=(
  quickshell
  wl-clipboard
  cliphist
  upower
  playerctl
  hyprland-qt-support
  polkit
  python-gobject
  jq
)

# Explicit replacements retired by the Quickshell migration. An installed
# package is preselected for removal only when Awtarchy recorded ownership.
declare -a RETIRED_ARCH=(
  waybar
  waybar-git
  fuzzel
  wlogout
  mako
  wofi
  network-manager-applet
  blueman
)

declare -a ARCH_CATALOG=()
declare -a AUR_CATALOG=()
declare -a FLATPAK_IDS=()
declare -a FLATPAK_NAMES=()
declare -a MISSING_REQUIRED=()
declare -a MISSING_ARCH=()
declare -a MISSING_AUR=()
declare -a MISSING_FLATPAK_IDS=()
declare -a MISSING_FLATPAK_NAMES=()
declare -a RETIRED_MANAGED=()
declare -a RETIRED_UNOWNED=()
SYSTEM_TYPE="unknown"
LY_STATUS="not installed"

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage:
  awtarchy packages
  awtarchy packages --review

Without options, opens an installer-style package reconciliation UI.

The reconciler:
  - installs missing dependencies required by current Awtarchy features;
  - offers other missing current Arch/AUR/Flatpak catalog entries;
  - optionally installs/enables Ly on tty2;
  - offers removal of explicitly retired/replaced shell packages;
  - preselects retired package removal only for Awtarchy-owned packages.

Deselecting a current package never uninstalls it.
EOF
}

while (( $# )); do
  case "$1" in
    --review)
      REVIEW_ONLY=1
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      die "Unknown packages option: $1"
      ;;
  esac
  shift
done

[[ -r "$RUNTIME" && ! -L "$RUNTIME" ]] \
  || die "Awtarchy runtime is unavailable or unsafe: ${RUNTIME}"
have pacman || die "pacman is required for package reconciliation."

strip_outer_quotes() {
  local value="$1"
  if [[ ${#value} -ge 2 && ${value:0:1} == '"' && ${value: -1} == '"' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s\n' "$value"
}

runtime_array_lines() {
  local name="$1"
  awk -v name="$name" '
    $0 ~ "^declare -a " name "=\\(" { inside=1; next }
    inside && /^[[:space:]]*\)[[:space:]]*$/ { exit }
    inside {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "" && line !~ /^#/) print line
    }
  ' "$RUNTIME"
}

sort_unique_array() {
  local -n target="$1"
  local tmp
  (( ${#target[@]} )) || return 0
  tmp="$(mktemp)"
  printf '%s\n' "${target[@]}" | LC_ALL=C sort -u >"$tmp"
  mapfile -t target <"$tmp"
  rm -f -- "$tmp"
}

array_contains() {
  local needle="$1" item
  shift || true
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

load_catalogs() {
  local raw entry package_text pkg friendly app_id
  local -a words=()

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    [[ $entry == *:* ]] || continue
    package_text="${entry#*:}"
    words=()
    IFS=' ' read -r -a words <<<"$package_text"
    for pkg in "${words[@]}"; do
      [[ -n $pkg ]] && ARCH_CATALOG+=("$pkg")
    done
  done < <(runtime_array_lines PKG_GROUPS)

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    [[ $entry =~ ^[A-Za-z0-9@._+:-]+$ ]] || continue
    AUR_CATALOG+=("$entry")
  done < <(runtime_array_lines PACKAGES_AUR)

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    IFS='|' read -r _ friendly app_id <<<"$entry"
    [[ -n ${friendly:-} && -n ${app_id:-} ]] || continue
    FLATPAK_NAMES+=("$friendly")
    FLATPAK_IDS+=("$app_id")
  done < <(runtime_array_lines FLATPAK_CATALOG)

  sort_unique_array ARCH_CATALOG
  sort_unique_array AUR_CATALOG
}

package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

package_satisfied() {
  local pkg="$1"
  package_installed "$pkg" && return 0

  case "$pkg" in
    zathura-pdf-mupdf)
      package_installed zathura-pdf-poppler
      ;;
    zathura-pdf-poppler)
      package_installed zathura-pdf-mupdf
      ;;
    *)
      return 1
      ;;
  esac
}

managed_package() {
  [[ -r "$MANAGED_PACKAGES_FILE" ]] || return 1
  grep -Fxq -- "$1" "$MANAGED_PACKAGES_FILE"
}

flatpak_app_installed() {
  local app="$1"
  have flatpak || return 1
  flatpak --user list --app --columns=application 2>/dev/null | grep -Fxq -- "$app" \
    && return 0
  flatpak --system list --app --columns=application 2>/dev/null | grep -Fxq -- "$app"
}

detect_system_type() {
  local saved="" chassis=""
  if [[ -r "$HARDWARE_FILE" ]]; then
    saved="$(sed -n 's/^is_laptop=//p' "$HARDWARE_FILE" | head -n1)"
    case "$saved" in
      true) SYSTEM_TYPE="laptop"; return 0 ;;
      false) SYSTEM_TYPE="desktop"; return 0 ;;
    esac
  fi

  shopt -s nullglob
  local batteries=(/sys/class/power_supply/BAT*)
  shopt -u nullglob
  if (( ${#batteries[@]} )); then
    SYSTEM_TYPE="laptop"
    return 0
  fi

  if [[ -r /sys/class/dmi/id/chassis_type ]]; then
    chassis="$(tr -d '\r\n' </sys/class/dmi/id/chassis_type)"
    case "$chassis" in
      8|9|10|11|14|30|31|32) SYSTEM_TYPE="laptop"; return 0 ;;
      3|4|5|6|7|13|15|16|17|23|24|35|36) SYSTEM_TYPE="desktop"; return 0 ;;
    esac
  fi

  SYSTEM_TYPE="unknown"
}

detect_ly_status() {
  if ! package_installed ly; then
    LY_STATUS="not installed"
    return 0
  fi
  if have systemctl && systemctl is-enabled --quiet ly@tty2.service 2>/dev/null; then
    LY_STATUS="installed and enabled on tty2"
  else
    LY_STATUS="installed, not enabled on tty2"
  fi
}

collect_state() {
  local pkg i
  load_catalogs
  detect_system_type
  detect_ly_status

  for pkg in "${REQUIRED_ARCH[@]}"; do
    package_installed "$pkg" || MISSING_REQUIRED+=("$pkg")
  done

  for pkg in "${ARCH_CATALOG[@]}"; do
    package_satisfied "$pkg" && continue
    array_contains "$pkg" "${REQUIRED_ARCH[@]}" && continue
    [[ $pkg == ly ]] && continue
    MISSING_ARCH+=("$pkg")
  done

  for pkg in "${AUR_CATALOG[@]}"; do
    package_installed "$pkg" || MISSING_AUR+=("$pkg")
  done

  for i in "${!FLATPAK_IDS[@]}"; do
    flatpak_app_installed "${FLATPAK_IDS[$i]}" && continue
    MISSING_FLATPAK_IDS+=("${FLATPAK_IDS[$i]}")
    MISSING_FLATPAK_NAMES+=("${FLATPAK_NAMES[$i]}")
  done

  for pkg in "${RETIRED_ARCH[@]}"; do
    package_installed "$pkg" || continue
    if managed_package "$pkg"; then
      RETIRED_MANAGED+=("$pkg")
    else
      RETIRED_UNOWNED+=("$pkg")
    fi
  done
}

print_list() {
  local heading="$1"
  shift || true
  printf '%s\n' "$heading"
  if (( $# == 0 )); then
    printf '  (none)\n'
    return 0
  fi
  printf '  - %s\n' "$@"
}

print_review() {
  printf '%s\n' 'Awtarchy package reconciliation review'
  printf 'System type: %s\n' "$SYSTEM_TYPE"
  printf 'Arch catalog packages: %d\n' "${#ARCH_CATALOG[@]}"
  printf 'AUR catalog packages: %d\n' "${#AUR_CATALOG[@]}"
  printf 'Flatpak catalog apps: %d\n' "${#FLATPAK_IDS[@]}"
  printf 'Ly TTY login manager: %s\n' "$LY_STATUS"
  printf '\n'
  print_list 'Missing required Awtarchy packages:' "${MISSING_REQUIRED[@]}"
  printf '\n'
  print_list 'Other missing current Arch catalog packages:' "${MISSING_ARCH[@]}"
  printf '\n'
  print_list 'Missing current AUR catalog packages:' "${MISSING_AUR[@]}"
  printf '\n'
  if (( ${#MISSING_FLATPAK_IDS[@]} )); then
    printf '%s\n' 'Missing current Flatpak catalog apps:'
    local i
    for i in "${!MISSING_FLATPAK_IDS[@]}"; do
      printf '  - %s (%s)\n' "${MISSING_FLATPAK_NAMES[$i]}" "${MISSING_FLATPAK_IDS[$i]}"
    done
  else
    printf '%s\n' 'Missing current Flatpak catalog apps:' '  (none)'
  fi
  printf '\n'
  print_list 'Retired Awtarchy-owned packages eligible for removal:' "${RETIRED_MANAGED[@]}"
  printf '\n'
  print_list 'Retired packages installed but not Awtarchy-owned (kept by default):' "${RETIRED_UNOWNED[@]}"
}

read_key() {
  local key rest
  IFS= read -rsn1 key </dev/tty || return 1
  if [[ $key == $'\033' ]]; then
    IFS= read -rsn2 -t 0.03 rest </dev/tty || true
    key+="$rest"
  fi
  printf '%s' "$key"
}

multi_select() {
  local title="$1" labels_name="$2" defaults_name="$3"
  local -n labels="$labels_name"
  local -n selected="$defaults_name"
  local current=0 key rows page start end i marker pointer

  (( ${#labels[@]} )) || return 0
  [[ -r /dev/tty && -w /dev/tty ]] || die "Interactive package reconciliation requires a terminal."

  while true; do
    rows="$(tput lines 2>/dev/null || printf '24')"
    [[ $rows =~ ^[0-9]+$ ]] || rows=24
    page=$(( rows - 8 ))
    (( page < 5 )) && page=5
    (( page > 18 )) && page=18
    start=$(( current - page / 2 ))
    (( start < 0 )) && start=0
    if (( start + page > ${#labels[@]} )); then
      start=$(( ${#labels[@]} - page ))
      (( start < 0 )) && start=0
    fi
    end=$(( start + page ))
    (( end > ${#labels[@]} )) && end=${#labels[@]}

    printf '\033[H\033[2J' >/dev/tty
    printf '%s\n\n' "$title" >/dev/tty
    printf '%s\n\n' 'Arrow keys move, Space toggles, Enter accepts, Esc cancels.' >/dev/tty
    for (( i=start; i<end; i++ )); do
      pointer=' '
      (( i == current )) && pointer='>'
      marker=' '
      (( selected[i] == 1 )) && marker='x'
      printf '%s [%s] %s\n' "$pointer" "$marker" "${labels[$i]}" >/dev/tty
    done
    if (( ${#labels[@]} > page )); then
      printf '\n%d-%d of %d\n' "$((start + 1))" "$end" "${#labels[@]}" >/dev/tty
    fi

    key="$(read_key)" || return 1
    case "$key" in
      $'\033[A'|k)
        if (( current > 0 )); then
          ((current--))
        fi
        ;;
      $'\033[B'|j)
        if (( current + 1 < ${#labels[@]} )); then
          ((current++))
        fi
        ;;
      ' ')
        if (( selected[current] == 1 )); then selected[current]=0; else selected[current]=1; fi
        ;;
      ''|$'\n'|$'\r')
        return 0
        ;;
      $'\033'|q|Q)
        return 1
        ;;
    esac
  done
}

confirm_yes_no() {
  local prompt="$1" default_yes="${2:-0}" answer=""
  local suffix='[y/N]'
  (( default_yes == 1 )) && suffix='[Y/n]'
  printf '%s %s ' "$prompt" "$suffix" >/dev/tty
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    '') (( default_yes == 1 )) ;;
    *) return 1 ;;
  esac
}

selected_values() {
  local values_name="$1" flags_name="$2" output_name="$3"
  local -n values="$values_name"
  local -n flags="$flags_name"
  local -n output="$output_name"
  local i
  output=()
  for i in "${!values[@]}"; do
    (( flags[i] == 1 )) && output+=("${values[$i]}")
  done
}

require_sudo() {
  if (( EUID == 0 )); then
    return 0
  fi
  have sudo || die "sudo is required to apply package reconciliation."
  sudo -v || die "sudo authentication failed; no package changes were applied."
}

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo -- "$@"
  fi
}

record_managed_packages() {
  local -a add=("$@")
  local tmp pkg
  (( ${#add[@]} )) || return 0
  tmp="$(mktemp)"
  if [[ -r "$MANAGED_PACKAGES_FILE" ]]; then
    cat -- "$MANAGED_PACKAGES_FILE" >"$tmp"
  else
    : >"$tmp"
  fi
  for pkg in "${add[@]}"; do
    package_installed "$pkg" && printf '%s\n' "$pkg" >>"$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"
  as_root install -d -m 0755 -- "$(dirname -- "$MANAGED_PACKAGES_FILE")"
  as_root install -m 0644 -- "$tmp" "$MANAGED_PACKAGES_FILE"
  rm -f -- "$tmp"
}

forget_managed_packages() {
  local -a remove=("$@")
  local tmp pkg
  (( ${#remove[@]} )) || return 0
  [[ -r "$MANAGED_PACKAGES_FILE" ]] || return 0
  tmp="$(mktemp)"
  cat -- "$MANAGED_PACKAGES_FILE" >"$tmp"
  for pkg in "${remove[@]}"; do
    sed -i "/^$(printf '%s' "$pkg" | sed 's/[][\\.^$*+?{}|()]/\\&/g')$/d" "$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"
  as_root install -m 0644 -- "$tmp" "$MANAGED_PACKAGES_FILE"
  rm -f -- "$tmp"
}

flatpak_scope() {
  local fs=""
  if have findmnt; then
    fs="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
  fi
  if [[ $fs == btrfs ]]; then printf '%s\n' system; else printf '%s\n' user; fi
}

install_flatpak_apps() {
  local scope="$1"
  shift
  local -a apps=("$@") cmd=()
  (( ${#apps[@]} )) || return 0

  if [[ $scope == user ]]; then
    cmd=(flatpak --user)
  else
    cmd=(as_root flatpak --system)
  fi

  if ! "${cmd[@]}" remotes --columns=name 2>/dev/null | grep -Fxq flathub; then
    "${cmd[@]}" remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
  "${cmd[@]}" install -y flathub "${apps[@]}"
}

collect_state

if (( REVIEW_ONLY == 1 )); then
  print_review
  exit 0
fi

[[ -r /dev/tty && -w /dev/tty ]] || die "Interactive package reconciliation requires a terminal."

print_review >/dev/tty
printf '\nRequired missing packages above will be selected automatically.\n' >/dev/tty
printf 'Installed current packages are preserved even when not selected here.\n\n' >/dev/tty
confirm_yes_no 'Continue to package choices?' 1 || { log 'Package reconciliation canceled.'; exit 0; }

# Missing optional Arch packages.
declare -a arch_labels=("${MISSING_ARCH[@]}")
declare -a arch_flags=()
declare -a selected_arch=()
for _ in "${arch_labels[@]}"; do arch_flags+=(0); done
if (( ${#arch_labels[@]} )); then
  multi_select 'Optional missing Arch packages' arch_labels arch_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values arch_labels arch_flags selected_arch

# Missing AUR packages.
declare -a aur_labels=("${MISSING_AUR[@]}")
declare -a aur_flags=()
declare -a selected_aur=()
for _ in "${aur_labels[@]}"; do aur_flags+=(0); done
if (( ${#aur_labels[@]} )); then
  multi_select 'Optional missing AUR packages' aur_labels aur_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values aur_labels aur_flags selected_aur

# Missing Flatpak apps.
declare -a flatpak_labels=()
declare -a flatpak_flags=()
declare -a selected_flatpak=()
for i in "${!MISSING_FLATPAK_IDS[@]}"; do
  flatpak_labels+=("${MISSING_FLATPAK_NAMES[$i]} (${MISSING_FLATPAK_IDS[$i]})")
  flatpak_flags+=(0)
done
if (( ${#flatpak_labels[@]} )); then
  multi_select 'Optional missing Flatpak apps' flatpak_labels flatpak_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
  for i in "${!MISSING_FLATPAK_IDS[@]}"; do
    (( flatpak_flags[i] == 1 )) && selected_flatpak+=("${MISSING_FLATPAK_IDS[$i]}")
  done
fi

install_ly=0
if [[ $LY_STATUS == 'not installed' ]]; then
  if confirm_yes_no 'Install and enable Ly on tty2?' 0; then install_ly=1; fi
else
  printf '\nLy is already %s; this reconciler will leave it installed.\n' "$LY_STATUS" >/dev/tty
fi

# Retired packages: Awtarchy-owned defaults selected; unowned defaults kept.
declare -a retired_labels=()
declare -a retired_values=()
declare -a retired_flags=()
declare -a selected_retired=()
for pkg in "${RETIRED_MANAGED[@]}"; do
  retired_labels+=("${pkg} (Awtarchy-owned, replaced)")
  retired_values+=("$pkg")
  retired_flags+=(1)
done
for pkg in "${RETIRED_UNOWNED[@]}"; do
  retired_labels+=("${pkg} (not Awtarchy-owned, keep unless selected)")
  retired_values+=("$pkg")
  retired_flags+=(0)
done
if (( ${#retired_labels[@]} )); then
  multi_select 'Retired/replaced packages to remove' retired_labels retired_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values retired_values retired_flags selected_retired

install_arch=("${MISSING_REQUIRED[@]}" "${selected_arch[@]}")
if (( install_ly == 1 )); then install_arch+=(ly); fi
if (( ${#selected_flatpak[@]} )) && ! have flatpak; then
  install_arch+=(flatpak)
fi
sort_unique_array install_arch

printf '\033[H\033[2J' >/dev/tty
printf '%s\n\n' 'Awtarchy package reconciliation plan' >/dev/tty
print_list 'Install from Arch repositories:' "${install_arch[@]}" >/dev/tty
printf '\n' >/dev/tty
print_list 'Install from AUR:' "${selected_aur[@]}" >/dev/tty
printf '\n' >/dev/tty
print_list 'Install Flatpak apps:' "${selected_flatpak[@]}" >/dev/tty
printf '\n' >/dev/tty
print_list 'Remove retired/replaced packages:' "${selected_retired[@]}" >/dev/tty
if (( install_ly == 1 )); then printf '\nLy: enable ly@tty2.service and disable getty@tty2.service\n' >/dev/tty; fi
printf '\nNo current installed package will be removed merely because it was not selected.\n\n' >/dev/tty

if (( ${#install_arch[@]} == 0 && ${#selected_aur[@]} == 0 && ${#selected_flatpak[@]} == 0 && ${#selected_retired[@]} == 0 && install_ly == 0 )); then
  log 'No package changes selected.'
  exit 0
fi

confirm_yes_no 'Apply this package plan?' 0 || { log 'Package reconciliation canceled.'; exit 0; }
require_sudo

if (( ${#install_arch[@]} )); then
  log "Installing Arch packages with a full system upgrade: ${install_arch[*]}"
  as_root pacman -Syu --needed --noconfirm "${install_arch[@]}"
  record_managed_packages "${install_arch[@]}"
fi

if (( ${#selected_aur[@]} )); then
  aur_helper=""
  if have paru; then aur_helper=paru; elif have yay; then aur_helper=yay; fi
  [[ -n $aur_helper ]] || die "AUR packages were selected but neither paru nor yay is installed."
  log "Installing AUR packages with ${aur_helper}: ${selected_aur[*]}"
  "$aur_helper" -S --needed --noconfirm "${selected_aur[@]}"
  record_managed_packages "${selected_aur[@]}"
fi

if (( ${#selected_flatpak[@]} )); then
  have flatpak || die "Flatpak installation was selected but flatpak is unavailable after package installation."
  scope="$(flatpak_scope)"
  log "Installing Flatpak apps in ${scope} scope: ${selected_flatpak[*]}"
  install_flatpak_apps "$scope" "${selected_flatpak[@]}"
fi

if (( install_ly == 1 )); then
  have systemctl || die "Ly was installed but systemctl is unavailable for tty2 setup."
  as_root systemctl disable getty@tty2.service >/dev/null 2>&1 || true
  as_root systemctl enable ly@tty2.service
  log 'Ly enabled on tty2; getty@tty2 disabled.'
fi

if (( ${#selected_retired[@]} )); then
  log "Removing selected retired packages: ${selected_retired[*]}"
  as_root pacman -Rns --noconfirm "${selected_retired[@]}"
  forget_managed_packages "${selected_retired[@]}"
fi

log 'Package reconciliation complete.'
