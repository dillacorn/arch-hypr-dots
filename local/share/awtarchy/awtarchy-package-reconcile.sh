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
MIGRATE_REPLACEMENTS_ONLY=0
NEEDS_ACTION_ONLY=0

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
  termdown
)

declare -a ARCH_CATALOG=()
declare -a OPTIONAL_ARCH_CATALOG=()
declare -a AUR_CATALOG=()
declare -a OPTIONAL_AUR_CATALOG=()
declare -a FLATPAK_IDS=()
declare -a FLATPAK_NAMES=()
declare -a OPTIONAL_FLATPAK_IDS=()
declare -a OPTIONAL_FLATPAK_NAMES=()
declare -a MISSING_REQUIRED=()
declare -a MISSING_ARCH=()
declare -a MISSING_OPTIONAL_ARCH=()
declare -a MISSING_AUR=()
declare -a MISSING_OPTIONAL_AUR=()
declare -a MISSING_FLATPAK_IDS=()
declare -a MISSING_FLATPAK_NAMES=()
declare -a MISSING_OPTIONAL_FLATPAK_IDS=()
declare -a MISSING_OPTIONAL_FLATPAK_NAMES=()
declare -a RETIRED_MANAGED=()
declare -a RETIRED_UNOWNED=()
declare -a FAILED_AUR=()
SYSTEM_TYPE="unknown"
LY_STATUS="not installed"
CHEESE_REPLACEMENT_NEEDED=0
AUR_SCAN_BIN="/usr/bin/aur-scan"
PACKAGE_SUDO_KEEPALIVE_PID=""
if [[ ${AWTARCHY_TEST_MODE:-0} == 1 && -n ${AWTARCHY_AUR_SCAN_BIN:-} ]]; then
  AUR_SCAN_BIN="$AWTARCHY_AUR_SCAN_BIN"
fi

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
    --migrate-replacements)
      MIGRATE_REPLACEMENTS_ONLY=1
      ;;
    --needs-action)
      NEEDS_ACTION_ONLY=1
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
    $0 ~ "^declare -a " name "=\\(" {
      line=$0
      sub("^.*=\\(", "", line)
      if (line ~ /\)[[:space:]]*$/) {
        sub(/\)[[:space:]]*$/, "", line)
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line != "" && line !~ /^#/) print line
        exit
      }
      inside=1
      next
    }
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
  local raw entry package_text pkg selected friendly app_id
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
    OPTIONAL_ARCH_CATALOG+=("$entry")
  done < <(runtime_array_lines OPTIONAL_ARCH_PACKAGES)

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    [[ $entry =~ ^[A-Za-z0-9@._+:-]+$ ]] || continue
    AUR_CATALOG+=("$entry")
  done < <(runtime_array_lines PACKAGES_AUR)

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    [[ $entry =~ ^[A-Za-z0-9@._+:-]+$ ]] || continue
    OPTIONAL_AUR_CATALOG+=("$entry")
  done < <(runtime_array_lines OPTIONAL_AUR_PACKAGES)

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    IFS='|' read -r selected friendly app_id <<<"$entry"
    [[ -n ${friendly:-} && -n ${app_id:-} ]] || continue
    if [[ $selected == 0 ]]; then
      OPTIONAL_FLATPAK_NAMES+=("$friendly")
      OPTIONAL_FLATPAK_IDS+=("$app_id")
    else
      FLATPAK_NAMES+=("$friendly")
      FLATPAK_IDS+=("$app_id")
    fi
  done < <(runtime_array_lines FLATPAK_CATALOG)

  sort_unique_array ARCH_CATALOG
  sort_unique_array OPTIONAL_ARCH_CATALOG
  sort_unique_array AUR_CATALOG
  sort_unique_array OPTIONAL_AUR_CATALOG
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
    gamescope|gamescope-git)
      package_installed gamescope || package_installed gamescope-git
      ;;
    *)
      return 1
      ;;
  esac
}

obs_pipewire_audio_capture_user_plugin_installed() {
  [[ -f "${HOME}/.config/obs-studio/plugins/linux-pipewire-audio/bin/64bit/linux-pipewire-audio.so" ]]
}

aur_package_satisfied() {
  local pkg="$1" alt=""

  case "$pkg" in
    alacritty|alacritty-graphics)
      for alt in alacritty alacritty-graphics; do
        package_installed "$alt" && return 0
      done
      return 1
      ;;
    qimgv|qimgv-git)
      for alt in qimgv qimgv-git; do
        package_installed "$alt" && return 0
      done
      return 1
      ;;
    hyprmoncfg|hyprmoncfg-bin|hyprmoncfg-git)
      for alt in hyprmoncfg hyprmoncfg-bin hyprmoncfg-git; do
        package_installed "$alt" && return 0
      done
      return 1
      ;;
    vesktop|vesktop-bin)
      for alt in vesktop vesktop-bin; do
        package_installed "$alt" && return 0
      done
      return 1
      ;;
    obs-pipewire-audio-capture|obs-pipewire-audio-capture-bin)
      for alt in obs-pipewire-audio-capture obs-pipewire-audio-capture-bin; do
        package_installed "$alt" && return 0
      done
      obs_pipewire_audio_capture_user_plugin_installed
      ;;
    *)
      package_installed "$pkg"
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
  package_installed cheese && CHEESE_REPLACEMENT_NEEDED=1

  for pkg in "${REQUIRED_ARCH[@]}"; do
    package_installed "$pkg" || MISSING_REQUIRED+=("$pkg")
  done

  for pkg in "${ARCH_CATALOG[@]}"; do
    package_satisfied "$pkg" && continue
    array_contains "$pkg" "${REQUIRED_ARCH[@]}" && continue
    [[ $pkg == ly ]] && continue
    MISSING_ARCH+=("$pkg")
  done

  for pkg in "${OPTIONAL_ARCH_CATALOG[@]}"; do
    package_satisfied "$pkg" || MISSING_OPTIONAL_ARCH+=("$pkg")
  done

  for pkg in "${AUR_CATALOG[@]}"; do
    aur_package_satisfied "$pkg" || MISSING_AUR+=("$pkg")
  done

  for pkg in "${OPTIONAL_AUR_CATALOG[@]}"; do
    aur_package_satisfied "$pkg" || MISSING_OPTIONAL_AUR+=("$pkg")
  done

  for i in "${!FLATPAK_IDS[@]}"; do
    flatpak_app_installed "${FLATPAK_IDS[$i]}" && continue
    MISSING_FLATPAK_IDS+=("${FLATPAK_IDS[$i]}")
    MISSING_FLATPAK_NAMES+=("${FLATPAK_NAMES[$i]}")
  done

  for i in "${!OPTIONAL_FLATPAK_IDS[@]}"; do
    flatpak_app_installed "${OPTIONAL_FLATPAK_IDS[$i]}" && continue
    MISSING_OPTIONAL_FLATPAK_IDS+=("${OPTIONAL_FLATPAK_IDS[$i]}")
    MISSING_OPTIONAL_FLATPAK_NAMES+=("${OPTIONAL_FLATPAK_NAMES[$i]}")
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
  printf 'Arch catalog packages: %d (%d default, %d optional)\n'     "$(( ${#ARCH_CATALOG[@]} + ${#OPTIONAL_ARCH_CATALOG[@]} ))"     "${#ARCH_CATALOG[@]}" "${#OPTIONAL_ARCH_CATALOG[@]}"
  printf 'AUR catalog packages: %d (%d default, %d optional)\n'     "$(( ${#AUR_CATALOG[@]} + ${#OPTIONAL_AUR_CATALOG[@]} ))"     "${#AUR_CATALOG[@]}" "${#OPTIONAL_AUR_CATALOG[@]}"
  printf 'Flatpak catalog apps: %d (%d default, %d optional)\n'     "$(( ${#FLATPAK_IDS[@]} + ${#OPTIONAL_FLATPAK_IDS[@]} ))"     "${#FLATPAK_IDS[@]}" "${#OPTIONAL_FLATPAK_IDS[@]}"
  printf 'Ly TTY login manager: %s\n' "$LY_STATUS"
  printf '\n'
  printf '%s\n' 'Required package replacements:'
  if (( CHEESE_REPLACEMENT_NEEDED == 1 )); then
    printf '  - cheese -> snapshot\n'
  else
    printf '  (none)\n'
  fi
  printf '\n'
  print_list 'Missing required Awtarchy packages:' "${MISSING_REQUIRED[@]}"
  printf '\n'
  print_list 'Other missing current Arch catalog packages:' "${MISSING_ARCH[@]}"
  printf '\n'
  print_list 'Optional Arch packages not installed:' "${MISSING_OPTIONAL_ARCH[@]}"
  printf '\n'
  print_list 'Missing current AUR catalog packages:' "${MISSING_AUR[@]}"
  printf '\n'
  print_list 'Optional AUR packages not installed:' "${MISSING_OPTIONAL_AUR[@]}"
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
  if (( ${#MISSING_OPTIONAL_FLATPAK_IDS[@]} )); then
    printf '%s\n' 'Optional Flatpak apps not installed:'
    local i
    for i in "${!MISSING_OPTIONAL_FLATPAK_IDS[@]}"; do
      printf '  - %s (%s)\n' "${MISSING_OPTIONAL_FLATPAK_NAMES[$i]}" "${MISSING_OPTIONAL_FLATPAK_IDS[$i]}"
    done
  else
    printf '%s\n' 'Optional Flatpak apps not installed:' '  (none)'
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
    printf '%s\n\n' 'Arrow keys move, Space toggles, A selects all, C clears all, Enter accepts, Esc cancels.' >/dev/tty
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
      a|A)
        for i in "${!selected[@]}"; do selected[i]=1; done
        ;;
      c|C)
        for i in "${!selected[@]}"; do selected[i]=0; done
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

choose_ly_action() {
  install_ly=0
  enable_ly=0

  case "$LY_STATUS" in
    'not installed')
      if confirm_yes_no 'Install and enable Ly on tty2?' 0; then
        install_ly=1
        enable_ly=1
      fi
      ;;
    'installed, not enabled on tty2')
      if confirm_yes_no 'Enable installed Ly on tty2?' 0; then
        enable_ly=1
      fi
      ;;
    'installed and enabled on tty2')
      printf '\nLy is already installed and enabled on tty2; leaving it unchanged.\n' >/dev/tty
      ;;
    *)
      printf '\nLy state is %s; leaving it unchanged.\n' "$LY_STATUS" >/dev/tty
      ;;
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

stop_package_privilege_keepalive() {
  local pid="${PACKAGE_SUDO_KEEPALIVE_PID:-}"
  PACKAGE_SUDO_KEEPALIVE_PID=""
  [[ $pid =~ ^[1-9][0-9]*$ ]] || return 0
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
}

start_package_privilege_keepalive() {
  (( EUID != 0 )) || return 0
  [[ -z ${PACKAGE_SUDO_KEEPALIVE_PID:-} ]] || return 0
  (
    while sleep "${AWTARCHY_SUDO_KEEPALIVE_SECONDS:-45}"; do
      sudo -n -v >/dev/null 2>&1 || break
    done
  ) &
  PACKAGE_SUDO_KEEPALIVE_PID=$!
}

resume_package_privilege_keepalive() {
  (( EUID != 0 )) || return 0
  sudo -n -v >/dev/null 2>&1 || return 0
  start_package_privilege_keepalive
  trap stop_package_privilege_keepalive EXIT HUP INT TERM
}

root_free_mib() {
  local available_kib=""
  available_kib="$(/usr/bin/df -Pk / 2>/dev/null | awk 'NR == 2 { print $4 }')"
  [[ $available_kib =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$(( available_kib / 1024 ))"
}

recover_package_disk_headroom() {
  local preferred_mib="${AWTARCHY_UPDATE_PREFERRED_FREE_MIB:-4096}"
  local required_mib="${AWTARCHY_UPDATE_REQUIRED_FREE_MIB:-1024}"
  local free_mib="" paccache_bin=""

  [[ $preferred_mib =~ ^[0-9]+$ && $required_mib =~ ^[0-9]+$ ]] \
    || die "Invalid update disk-space threshold override."
  (( preferred_mib >= required_mib )) \
    || die "Preferred update disk-space threshold cannot be below the required threshold."

  free_mib="$(root_free_mib)" \
    || die "Could not determine free space on the root filesystem."
  (( free_mib >= preferred_mib )) && return 0

  for paccache_bin in /usr/bin/paccache /usr/sbin/paccache; do
    [[ -x $paccache_bin ]] && break
    paccache_bin=""
  done

  if [[ -n $paccache_bin ]]; then
    log "Root filesystem has ${free_mib} MiB free; pruning old pacman cache entries while keeping two package versions..."
    if (( EUID == 0 )); then
      "$paccache_bin" -rk2
    elif ! sudo -n "$paccache_bin" -rk2; then
      die "Automatic pacman cache pruning failed after sudo authorization."
    fi
    free_mib="$(root_free_mib)" \
      || die "Could not re-check free space after pacman cache pruning."
  fi

  (( free_mib >= required_mib )) \
    || die "Root filesystem has only ${free_mib} MiB free; at least ${required_mib} MiB is required before continuing package installation."

  if (( free_mib < preferred_mib )); then
    warn "Root filesystem has ${free_mib} MiB free; continuing above the ${required_mib} MiB hard minimum."
  fi
}

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo -- "$@"
  fi
}

ensure_aur_scanner() {
  if [[ -x "$AUR_SCAN_BIN" ]] && "$AUR_SCAN_BIN" --version >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$AUR_SCAN_BIN" != /usr/bin/aur-scan ]]; then
    warn "Configured aur-scan test binary is unavailable: ${AUR_SCAN_BIN}"
    return 1
  fi

  if [[ ! -x /usr/bin/yay ]] || ! /usr/bin/yay --version >/dev/null 2>&1; then
    warn "aur-scanner is missing and a usable /usr/bin/yay is unavailable for the one-time bootstrap."
    return 1
  fi

  log "Installing stable aur-scanner through yay for the one-time bootstrap..."
  if ! /usr/bin/yay -S --noconfirm --pgpfetch aur-scanner; then
    warn "Failed to bootstrap stable aur-scanner."
    return 1
  fi

  if [[ ! -x /usr/bin/aur-scan ]] || ! /usr/bin/aur-scan --version >/dev/null 2>&1; then
    warn "aur-scanner installed without a usable /usr/bin/aur-scan."
    return 1
  fi

  AUR_SCAN_BIN="/usr/bin/aur-scan"
}

install_selected_aur_packages() {
  local pkg

  for pkg in "$@"; do
    if aur_package_satisfied "$pkg"; then
      log "${pkg} or an equivalent installation is already present; skipping."
      continue
    fi

    if (( EUID != 0 )); then
      sudo -k
    fi
    log "Installing AUR package through upstream aur-scanner: ${pkg}"
    if ! "$AUR_SCAN_BIN" install "$pkg" --noconfirm; then
      warn "AUR package failed: ${pkg}. Continuing with remaining package actions."
      FAILED_AUR+=("$pkg")
      continue
    fi

    if ! aur_package_satisfied "$pkg"; then
      warn "aur-scanner returned success but ${pkg} is still not detected. Continuing with remaining package actions."
      FAILED_AUR+=("$pkg")
      continue
    fi

    if ! record_managed_packages "$pkg"; then
      warn "${pkg} installed, but Awtarchy could not update its managed-package ledger."
    fi
  done

  return 0
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

apply_cheese_snapshot_replacement() {
  (( CHEESE_REPLACEMENT_NEEDED == 1 )) || return 0

  require_sudo
  log "Replacing retired Cheese camera app with Snapshot..."
  if ! package_installed snapshot; then
    as_root pacman -S --needed --noconfirm snapshot
  fi
  record_managed_packages snapshot
  as_root pacman -R --noconfirm cheese
  forget_managed_packages cheese
  CHEESE_REPLACEMENT_NEEDED=0
  log "Replaced Cheese with Snapshot."
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

package_reconciliation_needs_action() {
  (( CHEESE_REPLACEMENT_NEEDED == 1 )) && return 0
  (( ${#MISSING_REQUIRED[@]} > 0 )) && return 0
  (( ${#MISSING_ARCH[@]} > 0 )) && return 0
  (( ${#MISSING_AUR[@]} > 0 )) && return 0
  (( ${#MISSING_FLATPAK_IDS[@]} > 0 )) && return 0
  (( ${#RETIRED_MANAGED[@]} > 0 )) && return 0
  return 1
}

collect_state

if (( NEEDS_ACTION_ONLY == 1 )); then
  if package_reconciliation_needs_action; then
    exit 10
  fi
  exit 0
fi

if (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then
  apply_cheese_snapshot_replacement
  exit 0
fi

if (( REVIEW_ONLY == 1 )); then
  print_review
  exit 0
fi

[[ -r /dev/tty && -w /dev/tty ]] || die "Interactive package reconciliation requires a terminal."

print_review >/dev/tty
printf '\nOptional choices are listed first and start unchecked.\n' >/dev/tty
printf 'Missing default packages start selected; Space opts out.\n' >/dev/tty
printf 'Installed current packages are preserved even when not selected here.\n\n' >/dev/tty
confirm_yes_no 'Continue to package choices?' 1 || { log 'Package reconciliation canceled.'; exit 0; }

# Optional Arch packages are shown first and unchecked; missing defaults follow selected.
declare -a arch_labels=()
declare -a arch_values=()
declare -a arch_flags=()
declare -a selected_arch=()
for pkg in "${MISSING_OPTIONAL_ARCH[@]}"; do
  arch_labels+=("${pkg} (optional)")
  arch_values+=("$pkg")
  arch_flags+=(0)
done
for pkg in "${MISSING_ARCH[@]}"; do
  arch_labels+=("$pkg")
  arch_values+=("$pkg")
  arch_flags+=(1)
done
if (( ${#arch_labels[@]} )); then
  multi_select 'Arch packages to install' arch_labels arch_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values arch_values arch_flags selected_arch

# Optional AUR packages are shown first and unchecked; missing defaults follow selected.
declare -a aur_labels=()
declare -a aur_values=()
declare -a aur_flags=()
declare -a selected_aur=()
for pkg in "${MISSING_OPTIONAL_AUR[@]}"; do
  aur_labels+=("${pkg} (optional)")
  aur_values+=("$pkg")
  aur_flags+=(0)
done
for pkg in "${MISSING_AUR[@]}"; do
  aur_labels+=("$pkg")
  aur_values+=("$pkg")
  aur_flags+=(1)
done
if (( ${#aur_labels[@]} )); then
  multi_select 'AUR packages to install' aur_labels aur_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values aur_values aur_flags selected_aur

# Optional Flatpaks are shown first and unchecked; missing defaults follow selected.
declare -a flatpak_labels=()
declare -a flatpak_values=()
declare -a flatpak_flags=()
declare -a selected_flatpak=()
for i in "${!MISSING_OPTIONAL_FLATPAK_IDS[@]}"; do
  flatpak_labels+=("${MISSING_OPTIONAL_FLATPAK_NAMES[$i]} (${MISSING_OPTIONAL_FLATPAK_IDS[$i]}) (optional)")
  flatpak_values+=("${MISSING_OPTIONAL_FLATPAK_IDS[$i]}")
  flatpak_flags+=(0)
done
for i in "${!MISSING_FLATPAK_IDS[@]}"; do
  flatpak_labels+=("${MISSING_FLATPAK_NAMES[$i]} (${MISSING_FLATPAK_IDS[$i]})")
  flatpak_values+=("${MISSING_FLATPAK_IDS[$i]}")
  flatpak_flags+=(1)
done
if (( ${#flatpak_labels[@]} )); then
  multi_select 'Flatpak apps to install' flatpak_labels flatpak_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values flatpak_values flatpak_flags selected_flatpak

install_ly=0
enable_ly=0
choose_ly_action

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

if (( CHEESE_REPLACEMENT_NEEDED == 1 )); then
  array_contains cheese "${selected_retired[@]}" || selected_retired+=(cheese)
fi

install_arch=("${MISSING_REQUIRED[@]}" "${selected_arch[@]}")
if (( CHEESE_REPLACEMENT_NEEDED == 1 )) && ! package_installed snapshot; then
  install_arch+=(snapshot)
fi
sort_unique_array install_arch
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
if (( enable_ly == 1 )); then printf '\nLy: enable ly@tty2.service and disable getty@tty2.service\n' >/dev/tty; fi
printf '\nNo current installed package will be removed merely because it was not selected; explicit replacements may be migrated.\n\n' >/dev/tty

if (( ${#install_arch[@]} == 0 && ${#selected_aur[@]} == 0 && ${#selected_flatpak[@]} == 0 && ${#selected_retired[@]} == 0 && enable_ly == 0 )); then
  log 'No package changes selected.'
  exit 0
fi

confirm_yes_no 'Apply this package plan?' 0 || { log 'Package reconciliation canceled.'; exit 0; }
require_sudo
start_package_privilege_keepalive
trap stop_package_privilege_keepalive EXIT HUP INT TERM
recover_package_disk_headroom

if (( ${#install_arch[@]} )); then
  log "Installing Arch packages with a full system upgrade: ${install_arch[*]}"
  as_root pacman -Syu --needed --noconfirm "${install_arch[@]}"
  record_managed_packages "${install_arch[@]}"
fi

if (( enable_ly == 1 )); then
  have systemctl || die "Ly is installed but systemctl is unavailable for tty2 setup."
  as_root systemctl disable getty@tty2.service >/dev/null 2>&1 || true
  as_root systemctl enable ly@tty2.service
  log 'Ly enabled on tty2; getty@tty2 disabled.'
fi

if (( ${#selected_aur[@]} )); then
  stop_package_privilege_keepalive
  trap - EXIT HUP INT TERM
  if (( EUID != 0 )); then
    sudo -k
  fi
  log 'AUR build privilege isolation enabled; makepkg may request sudo independently.'
  if ensure_aur_scanner; then
    install_selected_aur_packages "${selected_aur[@]}"
  else
    warn 'aur-scanner is unavailable; recording selected AUR packages as failed and continuing with remaining package actions.'
    FAILED_AUR+=("${selected_aur[@]}")
  fi
  resume_package_privilege_keepalive
fi

if (( ${#selected_flatpak[@]} )); then
  have flatpak || die "Flatpak installation was selected but flatpak is unavailable after package installation."
  scope="$(flatpak_scope)"
  log "Installing Flatpak apps in ${scope} scope: ${selected_flatpak[*]}"
  install_flatpak_apps "$scope" "${selected_flatpak[@]}"
fi

if (( ${#selected_retired[@]} )); then
  log "Removing selected retired packages: ${selected_retired[*]}"
  as_root pacman -R --noconfirm "${selected_retired[@]}"
  forget_managed_packages "${selected_retired[@]}"
fi

if (( ${#FAILED_AUR[@]} )); then
  sort_unique_array FAILED_AUR
  printf '\n'
  print_list 'AUR packages that could not be installed:' "${FAILED_AUR[@]}"
  warn 'AUR failures do not stop package reconciliation; all other selected package actions were still processed.'
  log 'Package reconciliation completed with AUR package failures.'
else
  log 'Package reconciliation complete.'
fi

stop_package_privilege_keepalive
trap - EXIT HUP INT TERM
