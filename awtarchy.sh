#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# awtarchy.sh
# Single-file Awtarchy installer / updater / backup cleaner.

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
  "Window Management:hyprland hyprpaper hyprlock hypridle hyprpicker hyprsunset wofi fuzzel grim satty slurp wl-clipboard cliphist zbar wf-recorder zenity qt5ct qt5-wayland kvantum-qt5 qt6ct qt6-wayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk mako libnotify nwg-look"
  "Fonts:woff2-font-awesome otf-font-awesome ttf-dejavu ttf-liberation ttf-noto-nerd noto-fonts-emoji"
  "Themes:papirus-icon-theme materia-gtk-theme xcursor-comix kvantum-theme-materia"
  "Terminal Apps:nano micro fastfetch btop htop curl passt devtools wget git dos2unix brightnessctl ipcalc cmatrix asciiquarium figlet termdown espeak-ng cava man-db man-pages unzip xarchiver ncdu ddcutil scx-scheds scx-tools"
  "Utilities:polkit-gnome gnome-keyring networkmanager network-manager-applet bluez bluez-utils blueman wiremix pcmanfm-qt gvfs gvfs-smb gvfs-mtp gvfs-afc speedcrunch imagemagick pipewire pipewire-pulse pipewire-alsa ufw jq earlyoom libsixel xdg-utils python usbutils awww"
  "Multimedia:ffmpeg avahi mpv cheese exiv2 zathura zathura-pdf-mupdf mousai"
  "Development:base-devel archlinux-keyring bubblewrap gnupg coreutils clang ninja go rust virt-manager qemu qemu-hw-usb-host virt-viewer vde2 libguestfs dmidecode gamemode gamescope nftables swtpm"
  "Network Tools:firefox wireguard-tools wireplumber openssh iptables systemd-resolvconf bridge-utils qemu-guest-agent dnsmasq dhcpcd inetutils openbsd-netcat"
)

declare -a PACKAGES_AUR=(
  smtty
  awtwall
  mpvpaper
  wlogout
  qimgv
  alacritty-graphics
  waybar-git
  obs-pipewire-audio-capture-bin
)

# Format: selected|friendly name|Flathub app ID
# Selected defaults preserve the current install_flatpak_apps.sh behavior.
declare -a FLATPAK_CATALOG=(
  "1|Flatseal|com.github.tchx84.Flatseal"
  "0|Vesktop|dev.vencord.Vesktop"
  "0|Moonlight|com.moonlight_stream.Moonlight"
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

TMP_SUDOERS=""
AUR_SUDOERS_FILE=""

cleanup_install_temp() {
  if [[ -n "${TMP_SUDOERS:-}" ]]; then
    rm -f -- "${TMP_SUDOERS}" 2>/dev/null || true
  fi
  if [[ -n "${AUR_SUDOERS_FILE:-}" ]]; then
    rm -f -- "${AUR_SUDOERS_FILE}" 2>/dev/null || true
  fi
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
  awtarchy.sh update-reset-backup [--tag <tag>]
  awtarchy.sh update-backup-cleaner [options]
  awtarchy.sh clean-backups [options]
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
  REPO_DIR="${HOME_DIR}/awtarchy"
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

run_target_gsettings() {
  local target_uid runtime_dir
  target_uid="$(id -u "${TARGET_USER}" 2>/dev/null || true)"
  runtime_dir="/run/user/${target_uid}"

  local -a user_env=(
    env
    "HOME=${HOME_DIR}"
    "USER=${TARGET_USER}"
    "LOGNAME=${TARGET_USER}"
  )

  if [[ "$target_uid" =~ ^[0-9]+$ && -S "${runtime_dir}/bus" ]]; then
    user_env+=(
      "XDG_RUNTIME_DIR=${runtime_dir}"
      "DBUS_SESSION_BUS_ADDRESS=unix:path=${runtime_dir}/bus"
    )
    run_as_target "${user_env[@]}" gsettings "$@"
  elif have dbus-run-session; then
    run_as_target "${user_env[@]}" dbus-run-session -- gsettings "$@"
  else
    run_as_target "${user_env[@]}" gsettings "$@"
  fi
}

apply_awtarchy_gsettings_defaults() {
  local schema="org.gnome.nm-applet"
  local key="disable-connected-notifications"
  local current=""

  if ! have gsettings; then
    warn "gsettings is unavailable; skipping Awtarchy desktop defaults."
    return 0
  fi

  if ! run_target_gsettings list-schemas 2>/dev/null | grep -Fxq "$schema"; then
    log "nm-applet settings schema is unavailable; skipping its notification default."
    return 0
  fi

  current="$(run_target_gsettings get "$schema" "$key" 2>/dev/null || true)"
  if [[ "$current" == "true" ]]; then
    return 0
  fi

  log "Disabling routine NetworkManager connected notifications for ${TARGET_USER}..."
  if ! run_target_gsettings set "$schema" "$key" true; then
    warn "Could not set ${schema} ${key} for ${TARGET_USER}."
    return 0
  fi

  current="$(run_target_gsettings get "$schema" "$key" 2>/dev/null || true)"
  if [[ "$current" != "true" ]]; then
    warn "NetworkManager connected-notification default did not persist for ${TARGET_USER}."
  fi
}

create_directory() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    retry_command mkdir -p "$dir" || die "Failed to create directory: $dir"
  fi
  retry_command chown "${TARGET_USER}:${TARGET_USER}" "$dir"
  retry_command chmod 755 "$dir"
}

pacman_install_one() {
  local package="$1"
  if ! pacman -Qi "$package" >/dev/null 2>&1; then
    printf '%s\n' "${COLOR_CYAN}Installing ${package}...${COLOR_RESET}"
    pacman -S --needed --noconfirm "$package"
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

# ──────────────────────────────────────────────────────────────────────────────
# Built-in raw-key terminal UI
# ──────────────────────────────────────────────────────────────────────────────
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

  retry_command pacman -S --needed --noconfirm git ipcalc dos2unix reflector xcursor-comix || exit 1

  if [[ ! -d "$REPO_DIR" ]]; then
    log "Cloning awtarchy repository to ${REPO_DIR}..."
    retry_command git clone https://github.com/dillacorn/awtarchy "$REPO_DIR" || exit 1
  fi
  retry_command chown -R "${TARGET_USER}:${TARGET_USER}" "$REPO_DIR"

  log "Converting repository files to Unix line endings..."
  find "$REPO_DIR" -type f -exec dos2unix {} + 2>/dev/null || true
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
    if [[ "$IS_LAPTOP" == true ]]; then
      log "Configuring laptop power savings..."
      if pacman_install_one tlp; then
        systemctl enable --now tlp || true
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

remove_temp_sudoers_for_aur() {
  if [[ -n "${AUR_SUDOERS_FILE:-}" ]]; then
    rm -f -- "$AUR_SUDOERS_FILE"
    AUR_SUDOERS_FILE=""
  fi
}

create_temp_sudoers_for_aur() {
  remove_temp_sudoers_for_aur

  TMP_SUDOERS="$(mktemp /tmp/awtarchy-aur-sudoers.XXXXXX)"
  AUR_SUDOERS_FILE="/etc/sudoers.d/awtarchy_aur_${TARGET_USER}_$$"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$TARGET_USER" > "$TMP_SUDOERS"

  if ! visudo -c -f "$TMP_SUDOERS" >/dev/null 2>&1; then
    rm -f -- "$TMP_SUDOERS"
    TMP_SUDOERS=""
    AUR_SUDOERS_FILE=""
    die "Generated sudoers file is invalid."
  fi

  install -m 0440 "$TMP_SUDOERS" "$AUR_SUDOERS_FILE"
  rm -f -- "$TMP_SUDOERS"
  TMP_SUDOERS=""
}

ensure_aur_guard_requirements() {
  log "Installing AUR Guard requirements..."
  pacman -S --needed --noconfirm \
    base-devel git bubblewrap devtools gnupg coreutils jq libarchive file curl
}

run_aur_guard_as_target() {
  local command_name="$1"
  shift

  local guard_bashrc="${REPO_DIR}/bashrc"
  [[ -f "$guard_bashrc" ]] || die "Missing AUR Guard configuration: ${guard_bashrc}"
  grep -q '^aurinstall()' "$guard_bashrc" || die "${guard_bashrc} does not contain the AUR Guard aurinstall function."

  # Variables in this embedded script intentionally expand in the child Bash.
  # shellcheck disable=SC2016
  run_as_target env \
    HOME="$HOME_DIR" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    bash --noprofile --norc -c '
      guard_bashrc=$1
      shift
      source <(sed -n "/^# --- AUR Guard ---/,\$p" "$guard_bashrc")
      "$@"
    ' awtarchy-aur-guard "$guard_bashrc" "$command_name" "$@"
}

ensure_yay() {
  if have yay; then return 0; fi
  if run_as_target bash -lc 'command -v yay >/dev/null 2>&1'; then return 0; fi

  warn "yay not found. Installing it through AUR Guard practical mode..."
  run_aur_guard_as_target aurinstall yay
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

  tmp_dir="$(mktemp -d /tmp/awtarchy-obs-pipewire-audio.XXXXXX)"
  archive="${tmp_dir}/linux-pipewire-audio.tar.gz"

  curl -fL --retry 3 --retry-delay 2 -o "$archive" "$release_url"

  if tar -tzf "$archive" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
    rm -rf -- "$tmp_dir"
    die "OBS PipeWire audio capture archive contains unsafe paths."
  fi

  if ! tar -tzf "$archive" | grep -q '^linux-pipewire-audio/'; then
    rm -rf -- "$tmp_dir"
    die "OBS PipeWire audio capture archive has unexpected layout."
  fi

  rm -rf -- "$plugin_root"
  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$plugin_dir"

  tar -xzf "$archive" -C "$plugin_dir"
  chown -R "$TARGET_USER:$TARGET_USER" "$plugin_root"
  chmod -R u+rwX,go+rX "$plugin_root"

  rm -rf -- "$tmp_dir"

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

  if run_aur_guard_as_target aurinstall "$pkg"; then
    return 0
  fi

  warn "${pkg} failed through AUR Guard. Falling back to upstream per-user OBS plugin install."
  install_obs_pipewire_audio_capture_user_plugin
}

install_aur_repo_apps_stage() {
  (( INSTALL_AUR == 1 )) || { warn "Skipping AUR application install."; return 0; }

  ensure_aur_guard_requirements
  create_temp_sudoers_for_aur
  ensure_yay

  if (( ${#AUR_SELECTED[@]} == 0 )); then
    warn "No AUR packages selected. Skipping package loop."
  else
    log "Installing selected AUR packages through AUR Guard practical mode..."
    local pkg
    for pkg in "${AUR_SELECTED[@]}"; do
      if aur_selected_package_installed "$pkg"; then
        printf '%s\n' "${COLOR_YELLOW}${pkg} or an equivalent installation is already present. Skipping...${COLOR_RESET}"
      else
        printf '%s\n' "${COLOR_CYAN}Verifying and installing ${pkg}...${COLOR_RESET}"
        if [[ "$pkg" == "obs-pipewire-audio-capture" ]]; then
          install_obs_pipewire_audio_capture_package
        else
          run_aur_guard_as_target aurinstall "$pkg"
        fi
        printf '%s\n' "${COLOR_GREEN}${pkg} installed successfully.${COLOR_RESET}"
      fi
    done
  fi

  if [[ "$IS_LAPTOP" == true && "$IS_VM" == false ]]; then
    if pacman -Q tlpui >/dev/null 2>&1; then
      printf '%s\n' "${COLOR_YELLOW}tlpui already installed. Skipping...${COLOR_RESET}"
    else
      log "Installing tlpui through AUR Guard practical mode..."
      run_aur_guard_as_target aurinstall tlpui || true
    fi
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

  remove_temp_sudoers_for_aur
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
        {
          printf '\n# Automatically apply --user flag for Flatpak on non-Btrfs or user-scope systems\n'
          printf '%s\n' "$alias_line"
        } >> "$rc_path"
        chown "${TARGET_USER}:${TARGET_USER}" "$rc_path"
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
  mkdir -p "$target_dir"
  chown "${TARGET_USER}:${TARGET_USER}" "$target_dir"

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
  tmp1="$(mktemp -d)"
  tmp2="$(mktemp -d)"
  trap 'rm -rf "${tmp1:-}" "${tmp2:-}" 2>/dev/null || true; cleanup_install_temp' EXIT
  have jq && have_jq=1

  log "Cloning Micro theme sources..."
  git clone --depth=1 "$repo_url1" "$tmp1" >/dev/null
  git clone --depth=1 "$repo_url2" "$tmp2" >/dev/null

  install -d -m 0755 "$color_dir"
  compgen -G "${tmp1}/themes/*.micro" >/dev/null && cp -f "${tmp1}/themes/"*.micro "$color_dir/"
  compgen -G "${tmp2}/runtime/colorschemes/*.micro" >/dev/null && cp -f "${tmp2}/runtime/colorschemes/"*.micro "$color_dir/"
  chown -R "${TARGET_USER}:${TARGET_USER}" "$config_root"

  install -d -m 0755 "$micro_dir"
  cat > "${settings_json}.tmp" <<JSON
{
  "colorscheme": "${target_colorscheme}"
}
JSON
  (( have_jq == 1 )) && jq -e . "${settings_json}.tmp" >/dev/null
  mv -f "${settings_json}.tmp" "$settings_json"
  chown "${TARGET_USER}:${TARGET_USER}" "$settings_json"

  [[ -f "$settings_json" ]] || die "Failed to create ${settings_json}"
  if [[ ! -f "${color_dir}/${target_colorscheme}.micro" ]]; then
    warn "${target_colorscheme}.micro not found in ${color_dir}"
  fi
}

enable_keyring_pam_stage() {
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

copy_awtarchy_configs_stage() {
  log "Copying Awtarchy configuration files..."
  mkdir -p "${HOME_DIR}/.config"
  chown "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.config"

  local config_file
  for config_file in bashrc bash_profile; do
    local src="${REPO_DIR}/${config_file}"
    local dest="${HOME_DIR}/.${config_file}"
    [[ -f "$src" ]] || { warn "Missing ${src}. Skipping."; continue; }
    if [[ -f "$dest" ]]; then
      if [[ "$config_file" == "bashrc" && "$OVERWRITE_BASHRC" != "1" ]]; then warn "Keeping existing ${dest}"; continue; fi
      if [[ "$config_file" == "bash_profile" && "$OVERWRITE_BASH_PROFILE" != "1" ]]; then warn "Keeping existing ${dest}"; continue; fi
    fi
    retry_command cp "$src" "$dest"
    if findmnt -n -o FSTYPE / | grep -qi btrfs; then
      sed -i '/alias flatpak=.flatpak --user./ s/^/#/' "$dest" || true
    fi
    retry_command chown "${TARGET_USER}:${TARGET_USER}" "$dest"
    retry_command chmod 644 "$dest"
  done

  local -a config_dirs=(hypr waybar alacritty wlogout mako wofi fuzzel gtk-3.0 Kvantum SpeedCrunch fastfetch pcmanfm-qt yazi xdg-desktop-portal qt5ct qt6ct lsfg-vk wiremix cava micro ddcutil)
  local dir
  for dir in "${config_dirs[@]}"; do
    if [[ -d "${REPO_DIR}/config/${dir}" ]]; then
      retry_command cp -r "${REPO_DIR}/config/${dir}" "${HOME_DIR}/.config/" || exit 1
      retry_command chown -R "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.config/${dir}"
    else
      warn "Missing config/${dir}; skipping."
    fi
  done

  create_directory "${HOME_DIR}/.local/share/nwg-look"
  create_directory "${HOME_DIR}/.local/share/SpeedCrunch"
  create_directory "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes"

  [[ -f "${REPO_DIR}/Xresources" ]] && retry_command cp "${REPO_DIR}/Xresources" "${HOME_DIR}/.Xresources"
  [[ -f "${REPO_DIR}/config/mimeapps.list" ]] && retry_command cp "${REPO_DIR}/config/mimeapps.list" "${HOME_DIR}/.config/"
  [[ -f "${REPO_DIR}/config/gamemode.ini" ]] && retry_command cp "${REPO_DIR}/config/gamemode.ini" "${HOME_DIR}/.config/"
  [[ -f "${REPO_DIR}/local/share/nwg-look/gsettings" ]] && retry_command cp "${REPO_DIR}/local/share/nwg-look/gsettings" "${HOME_DIR}/.local/share/nwg-look/"

  chown "${TARGET_USER}:${TARGET_USER}" \
    "${HOME_DIR}/.Xresources" \
    "${HOME_DIR}/.config/mimeapps.list" \
    "${HOME_DIR}/.config/gamemode.ini" \
    "${HOME_DIR}/.local/share/nwg-look/gsettings" 2>/dev/null || true
  chmod 644 \
    "${HOME_DIR}/.Xresources" \
    "${HOME_DIR}/.config/mimeapps.list" \
    "${HOME_DIR}/.config/gamemode.ini" \
    "${HOME_DIR}/.local/share/nwg-look/gsettings" 2>/dev/null || true

  if compgen -G "${REPO_DIR}/local/share/SpeedCrunch/color-schemes/*.json" >/dev/null; then
    retry_command cp "${REPO_DIR}/local/share/SpeedCrunch/color-schemes/"*.json "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes/"
    retry_command chown -R "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.local/share/SpeedCrunch"
    chmod 644 "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes/"*.json || true
  fi

  create_directory "${HOME_DIR}/.local/share/applications"
  if [[ -d "${REPO_DIR}/local/share/applications" ]]; then
    retry_command cp -r "${REPO_DIR}/local/share/applications/." "${HOME_DIR}/.local/share/applications"
    retry_command chown -R "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.local/share/applications"
    find "${HOME_DIR}/.local/share/applications" -type d -exec chmod 755 {} +
    find "${HOME_DIR}/.local/share/applications" -type f -exec chmod 644 {} +
  fi

  create_directory "${HOME_DIR}/.local/share/icons/ComixCursors-White"
  if [[ -d /usr/share/icons/ComixCursors-White ]]; then
    retry_command cp -r /usr/share/icons/ComixCursors-White/. "${HOME_DIR}/.local/share/icons/ComixCursors-White/"
    retry_command chown -R "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.local/share/icons/ComixCursors-White"
    find "${HOME_DIR}/.local/share/icons/ComixCursors-White" -type d -exec chmod 755 {} +
    find "${HOME_DIR}/.local/share/icons/ComixCursors-White" -type f -exec chmod 644 {} +
  fi

  install -d -m 755 /usr/share/icons/default
  cat > /usr/share/icons/default/index.theme <<'EOF'
[Icon Theme]
Inherits=ComixCursors-White
EOF
  chmod 644 /usr/share/icons/default/index.theme

  if have flatpak; then
    run_as_target flatpak override --user --env=GTK_CURSOR_THEME=ComixCursors-White || true
  fi

  create_directory "${HOME_DIR}/Pictures/wallpapers"
  create_directory "${HOME_DIR}/Pictures/Screenshots"
  local -a wallpapers=(awtarchy_geology.png awtarchy_space.png)
  local wallpaper
  for wallpaper in "${wallpapers[@]}"; do
    [[ -f "${REPO_DIR}/${wallpaper}" ]] || { warn "Missing ${wallpaper}; skipping."; continue; }
    retry_command cp "${REPO_DIR}/${wallpaper}" "${HOME_DIR}/Pictures/wallpapers/"
    chown "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/Pictures/wallpapers/${wallpaper}"
    chmod 644 "${HOME_DIR}/Pictures/wallpapers/${wallpaper}"
  done

  find "${HOME_DIR}/.config" -type d -exec chmod 755 {} + 2>/dev/null || true
  find "${HOME_DIR}/.config" -type f -exec chmod 644 {} + 2>/dev/null || true
  if [[ -d "${HOME_DIR}/.config/hypr/scripts" ]]; then
    find "${HOME_DIR}/.config/hypr/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
  fi
  if [[ -d "${HOME_DIR}/.config/hypr/themes" ]]; then
    find "${HOME_DIR}/.config/hypr/themes" -type f -exec chmod +x {} + 2>/dev/null || true
  fi
  if [[ -d "${HOME_DIR}/.config/waybar/scripts" ]]; then
    find "${HOME_DIR}/.config/waybar/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
  fi
}

repair_home_ownership_stage() {
  log "Repairing ownership under ${HOME_DIR}..."
  retry_command chown "${TARGET_USER}:${TARGET_USER}" "$HOME_DIR"
  find "$HOME_DIR" -mindepth 1 ! -user "$TARGET_USER" -exec chown -h "${TARGET_USER}:${TARGET_USER}" {} + 2>/dev/null || true
  if [[ -d "${HOME_DIR}/.ssh" ]]; then
    retry_command chown -R "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.ssh"
    chmod 700 "${HOME_DIR}/.ssh"
    find "${HOME_DIR}/.ssh" -type f -exec chmod 600 {} +
  fi
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
  copy_awtarchy_configs_stage
  apply_awtarchy_gsettings_defaults
  repair_home_ownership_stage

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
      "Update/reset Awtarchy configs from latest release" \
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
        update_reset_backup_main
        ;;
      3)
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
  as_root pacman -S --needed --noconfirm "$@"
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
  if have paru; then
    as_user paru -S --needed --noconfirm "$@"
    return 0
  fi
  if have yay; then
    as_user yay -S --needed --noconfirm "$@"
    return 0
  fi
  bootstrap_yay
  as_user yay -S --needed --noconfirm "$@"
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
  bootstrap_yay

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
  bootstrap_yay

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
BACKUPS=()

run_target() {
  if [[ "${EUID}" -eq 0 ]]; then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$TARGET_USER" -- "$@"
    elif command -v sudo >/dev/null 2>&1; then
      sudo -u "$TARGET_USER" -H -- "$@"
    else
      die "Running as root but neither runuser nor sudo is available to run commands as ${TARGET_USER}"
    fi
  else
    "$@"
  fi
}

init_target_user() {
  if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
  else
    TARGET_USER="${USER}"
  fi

  HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
  [[ -n "${HOME_DIR}" && -d "${HOME_DIR}" ]] || die "Could not resolve HOME for user: ${TARGET_USER}"
}

curl_headers() {
  CURL_ARGS=(
    -fsSL
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

  json="$(curl "${CURL_ARGS[@]}" -H "Accept: application/vnd.github+json" "$api")" || die "Failed to query GitHub latest release API"

  python3 - <<'PY' "$json"
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
# Keep "/" unescaped (rare but possible in tags), encode everything else that could break URLs (like '#').
print(quote(sys.argv[1], safe="/-._~"))
PY
}

download_release_tarball() {
  local tag="$1"
  local out="$2"
  local tag_enc
  tag_enc="$(urlencode_path_segment "$tag")"

  local url="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/tags/${tag_enc}.tar.gz"
  curl "${CURL_ARGS[@]}" -L -o "$out" "$url" || die "Failed to download release tarball: $url"
}

tar_topdir() {
  local tgz="$1"
  local top
  top="$(tar -tzf "$tgz" | head -n 1 | cut -d/ -f1)"
  [[ -n "$top" ]] || die "Could not determine tarball top directory"
  printf '%s\n' "$top"
}

make_backup_file() {
  local dest="$1"
  [[ -e "$dest" || -L "$dest" ]] || return 0

  local b="${dest}.backup"
  if [[ -e "$b" || -L "$b" ]]; then
    b="${dest}.backup.$(stamp)"
  fi
  mkdir -p -- "$(dirname "$b")"
  cp -a -- "$dest" "$b"
  BACKUPS+=("$b")
}

same_symlink_target() {
  local a="$1" b="$2"
  [[ -L "$a" && -L "$b" ]] || return 1
  [[ "$(readlink "$a")" == "$(readlink "$b")" ]]
}

files_equal() {
  local src="$1" dest="$2"

  if [[ -L "$src" || -L "$dest" ]]; then
    same_symlink_target "$src" "$dest"
    return $?
  fi

  [[ -f "$src" && -f "$dest" ]] || return 1
  cmp -s -- "$src" "$dest"
}

atomic_copy() {
  local src="$1" dest="$2"

  if [[ -f "$src" && ! -L "$src" && ! -s "$src" ]]; then
    warn "Skipping empty upstream file (refusing to overwrite): $dest"
    return 0
  fi

  mkdir -p -- "$(dirname "$dest")"

  local tmp
  tmp="$(mktemp --tmpdir="$(dirname "$dest")" ".awtarchy.tmp.XXXXXX")"
  rm -f -- "$tmp" 2>/dev/null || true

  cp -a --no-preserve=ownership -- "$src" "$tmp"

  if [[ "${EUID}" -eq 0 ]]; then
    chown -h "${TARGET_USER}:${TARGET_USER}" "$tmp" 2>/dev/null || true
  fi

  mv -Tf -- "$tmp" "$dest"
}

deploy_file() {
  local src="$1" dest="$2"

  if [[ -e "$dest" || -L "$dest" ]]; then
    if files_equal "$src" "$dest"; then
      return 0
    fi
    make_backup_file "$dest"
    if [[ -d "$dest" && ! -d "$src" ]]; then
      rm -rf -- "$dest"
    fi
  fi

  atomic_copy "$src" "$dest"
}

deploy_tree() {
  local src_root="$1" dest_root="$2"

  [[ -d "$src_root" ]] || die "Missing upstream directory: $src_root"
  mkdir -p -- "$dest_root"

  while IFS= read -r -d '' d; do
    local rel="${d#"$src_root"/}"
    mkdir -p -- "${dest_root}/${rel}"
  done < <(find "$src_root" -mindepth 1 -type d -print0)

  while IFS= read -r -d '' f; do
    local rel="${f#"$src_root"/}"
    deploy_file "$f" "${dest_root}/${rel}"
  done < <(find "$src_root" -mindepth 1 \( -type f -o -type l \) -print0)

  if [[ "${EUID}" -eq 0 ]]; then
    chown -R "${TARGET_USER}:${TARGET_USER}" "$dest_root" 2>/dev/null || true
  fi
}

fix_managed_perms() {
  local -a dirs=("$@")

  for d in "${dirs[@]}"; do
    local root="${HOME_DIR}/.config/${d}"
    [[ -d "$root" ]] || continue
    find "$root" -type d -exec chmod 755 {} + 2>/dev/null || true
    find "$root" -type f -exec chmod 644 {} + 2>/dev/null || true
  done

  if [[ -d "${HOME_DIR}/.config/hypr/scripts" ]]; then
    find "${HOME_DIR}/.config/hypr/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
  fi
  if [[ -d "${HOME_DIR}/.config/hypr/themes" ]]; then
    find "${HOME_DIR}/.config/hypr/themes" -type f -exec chmod +x {} + 2>/dev/null || true
  fi
  if [[ -d "${HOME_DIR}/.config/waybar/scripts" ]]; then
    find "${HOME_DIR}/.config/waybar/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
  fi
}

maybe_hyprctl_reload() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  run_target hyprctl reload >/dev/null 2>&1 || true
}

write_version_stamp() {
  local tag="$1"
  local dest="${HOME_DIR}/.cache/awtarchy/version"
  mkdir -p -- "$(dirname "$dest")"
  {
    printf '%s\n' "tag=${tag}"
    printf '%s\n' "updated_at=$(ts)"
  } >"$dest"
  if [[ "${EUID}" -eq 0 ]]; then
    chown "${TARGET_USER}:${TARGET_USER}" "$dest" 2>/dev/null || true
  fi
}

update_system_cursor_default() {
  [[ "${EUID}" -eq 0 ]] || return 0
  install -d -m 755 /usr/share/icons/default
  printf '%s\n' "[Icon Theme]" "Inherits=ComixCursors-White" | tee /usr/share/icons/default/index.theme >/dev/null
  chmod 644 /usr/share/icons/default/index.theme 2>/dev/null || true
}

is_interactive_tty() {
  [[ -t 0 && -t 1 ]]
}

ask_yes_no() {
  local prompt="$1"
  local ans=""
  if ! is_interactive_tty; then
    warn "Non-interactive shell detected; skipping prompt: ${prompt}"
    return 1
  fi

  while true; do
    read -r -p "${prompt} [y/n] " ans
    case "${ans}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf '%s\n' "Please answer y or n." ;;
    esac
  done
}

print_wrapped_list() {
  local -n _items_ref="$1"
  local prefix="${2:-  - }"
  local i
  for i in "${_items_ref[@]}"; do
    printf '%s%s\n' "${prefix}" "${i}"
  done
}

parse_bash_array_from_script() {
  local file="$1"
  local array_name="$2"
  local mode="$3" # plain | arch-groups

  python3 - "$file" "$array_name" "$mode" <<'PY'
import re
import shlex
import sys
from pathlib import Path

path, array_name, mode = sys.argv[1], sys.argv[2], sys.argv[3]
text = Path(path).read_text(encoding="utf-8")

m = re.search(rf'(?ms)^\s*(?:declare\s+-a\s+)?{re.escape(array_name)}=\(\s*(.*?)^\s*\)', text)
if not m:
    raise SystemExit(2)

body = m.group(1)

lex = shlex.shlex(body, posix=True)
lex.whitespace_split = True
lex.commenters = '#'
items = list(lex)

out = []
seen = set()

def emit(token: str):
    token = token.strip()
    if not token:
        return
    if token in seen:
        return
    seen.add(token)
    out.append(token)

if mode == "arch-groups":
    for entry in items:
        if ":" in entry:
            _, pkg_blob = entry.split(":", 1)
        else:
            pkg_blob = entry
        for pkg in pkg_blob.split():
            emit(pkg)
elif mode == "plain":
    for entry in items:
        emit(entry)
else:
    raise SystemExit(3)

sys.stdout.write("\n".join(out))
PY
}

pkg_installed_pacman() {
  local pkg="$1"
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Qq "$pkg" >/dev/null 2>&1 && return 0
  pkg_equivalent_installed_pacman "$pkg"
}

pkg_equivalent_installed_pacman() {
  local pkg="$1"
  command -v pacman >/dev/null 2>&1 || return 1

  case "$pkg" in
    obs-pipewire-audio-capture|obs-pipewire-audio-capture-bin)
      pacman -Qq obs-pipewire-audio-capture >/dev/null 2>&1         && return 0
      pacman -Qq obs-pipewire-audio-capture-bin >/dev/null 2>&1         && return 0
      obs_pipewire_audio_capture_user_plugin_installed         && return 0
      return 1
      ;;
  esac

  local -a equivalents=()
  case "$pkg" in
    alacritty|alacritty-graphics)
      equivalents=(alacritty alacritty-graphics)
      ;;
    qimgv|qimgv-git)
      equivalents=(qimgv qimgv-git)
      ;;
    *)
      return 1
      ;;
  esac

  local alt=""
  for alt in "${equivalents[@]}"; do
    pacman -Qq "$alt" >/dev/null 2>&1 && return 0
  done

  return 1
}

flatpak_app_installed_any_scope() {
  local app_id="$1"
  command -v flatpak >/dev/null 2>&1 || return 1

  flatpak info --system "$app_id" >/dev/null 2>&1 && return 0
  run_target flatpak --user info "$app_id" >/dev/null 2>&1 && return 0
  flatpak info "$app_id" >/dev/null 2>&1 && return 0
  return 1
}

detect_repo_scripts_dir() {
  local downloaded_repo_dir="${1:-}"
  local self_dir="" pwd_dir=""

  self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  pwd_dir="$(pwd -P)"

  if [[ -d "${self_dir}/scripts" ]]; then
    printf '%s\n' "${self_dir}/scripts"
    return 0
  fi

  if [[ -d "${pwd_dir}/scripts" ]]; then
    printf '%s\n' "${pwd_dir}/scripts"
    return 0
  fi

  if [[ -n "${downloaded_repo_dir}" && -d "${downloaded_repo_dir}/scripts" ]]; then
    printf '%s\n' "${downloaded_repo_dir}/scripts"
    return 0
  fi

  return 1
}

flatpak_effective_install_scope() {
  if [[ "${EUID}" -ne 0 ]]; then
    printf '%s\n' "user"
    return 0
  fi
  local root_fs_type=""
  root_fs_type="$(df -T / | awk 'NR==2 {print $2}' 2>/dev/null || true)"
  if [[ "${root_fs_type}" == "btrfs" ]]; then
    printf '%s\n' "system"
  else
    printf '%s\n' "user"
  fi
}

ensure_flatpak_remote_for_scope() {
  local scope="$1"
  local remote_name="flathub"
  local remote_url="https://flathub.org/repo/flathub.flatpakrepo"

  if [[ "${scope}" == "user" ]]; then
    run_target flatpak --user remotes --columns=name | grep -Fxq "${remote_name}" \
      || run_target flatpak --user remote-add --if-not-exists "${remote_name}" "${remote_url}"
  else
    flatpak remotes --columns=name | grep -Fxq "${remote_name}" \
      || flatpak remote-add --if-not-exists "${remote_name}" "${remote_url}"
  fi
}

install_missing_arch_repo_packages() {
  local -a pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0

  if ! command -v pacman >/dev/null 2>&1; then
    warn "pacman not found; cannot install Arch repo packages."
    return 1
  fi
  if [[ "${EUID}" -ne 0 ]]; then
    warn "Arch repo installs require root. Re-run update-reset-backup.sh with sudo to install missing packages."
    return 1
  fi

  log "Installing missing Arch repo packages (${#pkgs[@]}):"
  print_wrapped_list pkgs "  - "
  pacman -S --needed --noconfirm "${pkgs[@]}"
}

run_update_aur_guard_package() {
  local guard_bashrc="$1"
  local pkg="$2"

  # The single-quoted script expands inside the child Bash process.
  # shellcheck disable=SC2016
  run_target env \
    HOME="$HOME_DIR" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    bash --noprofile --norc -c '
      guard_bashrc=$1
      pkg=$2
      source <(sed -n "/^# --- AUR Guard ---/,$p" "$guard_bashrc")
      aurinstall "$pkg"
    ' awtarchy-update-aur "$guard_bashrc" "$pkg"
}

install_missing_aur_packages() {
  local guard_bashrc="$1"
  shift
  local -a pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0

  if [[ "${EUID}" -ne 0 ]]; then
    warn "AUR installs require root. Re-run update-reset-backup with sudo to install missing packages."
    return 1
  fi

  [[ -f "$guard_bashrc" ]] || {
    warn "AUR Guard configuration not found: ${guard_bashrc}"
    return 1
  }
  grep -q '^aurinstall()' "$guard_bashrc" || {
    warn "AUR Guard aurinstall function not found in: ${guard_bashrc}"
    return 1
  }

  log "Installing AUR Guard requirements for missing-package restoration..."
  pacman -S --needed --noconfirm \
    base-devel git bubblewrap devtools gnupg coreutils jq libarchive file curl sudo

  local sudoers_tmp="" sudoers_file=""
  sudoers_tmp="$(mktemp /tmp/awtarchy-update-aur-sudoers.XXXXXX)"
  sudoers_file="/etc/sudoers.d/awtarchy_update_aur_${TARGET_USER}_$$"

  (
    trap 'rm -f -- "$sudoers_tmp" "$sudoers_file"' EXIT HUP INT TERM

    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$TARGET_USER" > "$sudoers_tmp"
    if ! visudo -c -f "$sudoers_tmp" >/dev/null 2>&1; then
      warn "Generated temporary sudoers file is invalid."
      exit 1
    fi

    install -m 0440 "$sudoers_tmp" "$sudoers_file"
    rm -f -- "$sudoers_tmp"

    log "Installing missing AUR packages through AUR Guard practical mode (${#pkgs[@]}):"
    print_wrapped_list pkgs "  - "

    local pkg=""
    for pkg in "${pkgs[@]}"; do
      if [[ "$pkg" == "obs-pipewire-audio-capture" ]]; then
        if obs_pipewire_audio_capture_user_plugin_installed; then
          printf '%s\n' "${COLOR_YELLOW}${pkg} already installed in OBS user plugins. Skipping...${COLOR_RESET}"
          continue
        fi

        if run_update_aur_guard_package "$guard_bashrc" "$pkg"; then
          continue
        fi

        warn "${pkg} failed through AUR Guard during update missing-package restoration. Falling back to upstream per-user OBS plugin install."
        install_obs_pipewire_audio_capture_user_plugin
      else
        run_update_aur_guard_package "$guard_bashrc" "$pkg"
      fi
    done
  )
}

install_missing_flatpak_apps() {
  local -a app_ids=("$@")
  (( ${#app_ids[@]} )) || return 0

  if ! command -v flatpak >/dev/null 2>&1; then
    if [[ "${EUID}" -eq 0 ]]; then
      log "flatpak not found. Installing flatpak package first."
      pacman -S --needed --noconfirm flatpak
    else
      warn "flatpak is not installed and this script is not running as root. Skipping Flatpak app installs."
      return 1
    fi
  fi

  local scope=""
  scope="$(flatpak_effective_install_scope)"
  ensure_flatpak_remote_for_scope "${scope}"

  log "Installing missing Flatpak apps in ${scope} scope (${#app_ids[@]}):"
  print_wrapped_list app_ids "  - "
  if [[ "${scope}" == "user" ]]; then
    run_target flatpak --user install -y flathub "${app_ids[@]}"
  else
    flatpak install -y flathub "${app_ids[@]}"
  fi
}

check_and_offer_missing_installs() {
  local downloaded_repo_dir="${1:-}"
  local scripts_dir=""

  if ! scripts_dir="$(detect_repo_scripts_dir "${downloaded_repo_dir}")"; then
    warn "Could not locate repo scripts directory for package checks."
    return 0
  fi

  local arch_script="${scripts_dir}/install_arch_repo_apps.sh"
  local aur_script="${scripts_dir}/install_aur_repo_apps.sh"
  local flatpak_script="${scripts_dir}/install_flatpak_apps.sh"

  if [[ ! -f "${arch_script}" || ! -f "${aur_script}" || ! -f "${flatpak_script}" ]]; then
    warn "Package install scripts not found in ${scripts_dir}; skipping missing package checks."
    return 0
  fi

  log "Checking installed packages against:"
  printf '  %s\n' "${arch_script}"
  printf '  %s\n' "${aur_script}"
  printf '  %s\n' "${flatpak_script}"

  local -a declared_arch=() declared_aur=() declared_flatpak=()
  local -a missing_arch=() missing_aur=() missing_flatpak=()
  local item=""

  if ! mapfile -t declared_arch < <(parse_bash_array_from_script "${arch_script}" "PKG_GROUPS" "arch-groups"); then
    warn "Failed to parse PKG_GROUPS from ${arch_script}"
    declared_arch=()
  fi

  if ! mapfile -t declared_aur < <(parse_bash_array_from_script "${aur_script}" "PACKAGES_AUR" "plain"); then
    warn "Failed to parse PACKAGES_AUR from ${aur_script}"
    declared_aur=()
  fi

  if ! mapfile -t declared_flatpak < <(parse_bash_array_from_script "${flatpak_script}" "FLATPAK_APPS" "plain"); then
    warn "Failed to parse FLATPAK_APPS from ${flatpak_script}"
    declared_flatpak=()
  fi

  for item in "${declared_arch[@]}"; do
    [[ -n "${item}" ]] || continue
    if ! pkg_installed_pacman "${item}"; then
      missing_arch+=("${item}")
    fi
  done

  for item in "${declared_aur[@]}"; do
    [[ -n "${item}" ]] || continue
    if ! pkg_installed_pacman "${item}"; then
      missing_aur+=("${item}")
    fi
  done

  for item in "${declared_flatpak[@]}"; do
    [[ -n "${item}" ]] || continue
    if ! flatpak_app_installed_any_scope "${item}"; then
      missing_flatpak+=("${item}")
    fi
  done

  if (( ${#declared_arch[@]} )); then
    if (( ${#missing_arch[@]} )); then
      warn "Missing Arch repo packages (${#missing_arch[@]}) from install_arch_repo_apps.sh:"
      print_wrapped_list missing_arch "  - "
      if ask_yes_no "Install all missing Arch repo packages now?"; then
        install_missing_arch_repo_packages "${missing_arch[@]}" || true
      else
        log "Skipped Arch repo package installation."
      fi
    else
      log "Arch repo package check: nothing missing."
    fi
  fi

  if (( ${#declared_aur[@]} )); then
    if (( ${#missing_aur[@]} )); then
      warn "Missing AUR packages (${#missing_aur[@]}) from install_aur_repo_apps.sh:"
      print_wrapped_list missing_aur "  - "
      if ask_yes_no "Install all missing AUR packages now?"; then
        install_missing_aur_packages "${repo_dir}/bashrc" "${missing_aur[@]}" || true
      else
        log "Skipped AUR package installation."
      fi
    else
      log "AUR package check: nothing missing."
    fi
  fi

  if (( ${#declared_flatpak[@]} )); then
    if (( ${#missing_flatpak[@]} )); then
      warn "Missing Flatpak apps (${#missing_flatpak[@]}) from install_flatpak_apps.sh:"
      print_wrapped_list missing_flatpak "  - "
      if ask_yes_no "Install all missing Flatpak apps now?"; then
        install_missing_flatpak_apps "${missing_flatpak[@]}" || true
      else
        log "Skipped Flatpak app installation."
      fi
    else
      log "Flatpak app check: nothing missing."
    fi
  fi
}

main() {
  need_cmd curl
  need_cmd tar
  need_cmd find
  need_cmd cmp
  need_cmd mktemp
  need_cmd getent
  need_cmd python3

  init_target_user
  curl_headers

  local tag=""
  if [[ "${1:-}" == "--tag" ]]; then
    tag="${2:-}"
    [[ -n "$tag" ]] || die "Usage: $0 [--tag <tag>]"
  else
    tag="$(fetch_latest_release_tag)" || die "No GitHub release found for ${REPO_OWNER}/${REPO_NAME}"
  fi

  log "Target user: ${TARGET_USER}"
  log "Release tag: ${tag}"

  local tmpd
  tmpd="$(mktemp -d)"
  trap 'rm -rf -- "${tmpd:-}" 2>/dev/null || true' EXIT

  local tgz="${tmpd}/awtarchy.tgz"
  download_release_tarball "$tag" "$tgz"

  local top repo_dir
  top="$(tar_topdir "$tgz")"
  tar -xzf "$tgz" -C "$tmpd"
  repo_dir="${tmpd}/${top}"
  [[ -d "$repo_dir" ]] || die "Extracted repo dir missing: $repo_dir"

  log "Deploying (latest Release tag; backups on change; refuses empty overwrites)."

  if [[ -f "${repo_dir}/bashrc" ]]; then
    deploy_file "${repo_dir}/bashrc" "${HOME_DIR}/.bashrc"
  else
    warn "Upstream missing: bashrc (skipped)"
  fi

  if [[ -f "${repo_dir}/bash_profile" ]]; then
    deploy_file "${repo_dir}/bash_profile" "${HOME_DIR}/.bash_profile"
  else
    warn "Upstream missing: bash_profile (skipped)"
  fi

  if [[ -f "${repo_dir}/Xresources" ]]; then
    deploy_file "${repo_dir}/Xresources" "${HOME_DIR}/.Xresources"
  else
    warn "Upstream missing: Xresources (skipped)"
  fi

  if [[ -f "${repo_dir}/config/mimeapps.list" ]]; then
    deploy_file "${repo_dir}/config/mimeapps.list" "${HOME_DIR}/.config/mimeapps.list"
  else
    warn "Upstream missing: config/mimeapps.list (skipped)"
  fi

  if [[ -f "${repo_dir}/config/gamemode.ini" ]]; then
    deploy_file "${repo_dir}/config/gamemode.ini" "${HOME_DIR}/.config/gamemode.ini"
  else
    warn "Upstream missing: config/gamemode.ini (skipped)"
  fi

  local -a CONFIG_DIRS=(
    "hypr" "waybar" "alacritty" "wlogout" "mako" "fuzzel"
    "gtk-3.0" "Kvantum" "SpeedCrunch" "fastfetch" "pcmanfm-qt" "yazi"
    "xdg-desktop-portal" "qt5ct" "qt6ct" "lsfg-vk" "wiremix" "cava" "YouTube Music" "ddcutil"
  )

  for d in "${CONFIG_DIRS[@]}"; do
    if [[ -d "${repo_dir}/config/${d}" ]]; then
      deploy_tree "${repo_dir}/config/${d}" "${HOME_DIR}/.config/${d}"
    else
      warn "Upstream missing dir: config/${d} (skipped)"
    fi
  done

  if [[ -f "${repo_dir}/local/share/nwg-look/gsettings" ]]; then
    deploy_file "${repo_dir}/local/share/nwg-look/gsettings" "${HOME_DIR}/.local/share/nwg-look/gsettings"
  fi

  if [[ -d "${repo_dir}/local/share/SpeedCrunch/color-schemes" ]]; then
    deploy_tree "${repo_dir}/local/share/SpeedCrunch/color-schemes" "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes"
  fi

  if [[ -d "${repo_dir}/local/share/applications" ]]; then
    deploy_tree "${repo_dir}/local/share/applications" "${HOME_DIR}/.local/share/applications"
  fi

  mkdir -p -- "${HOME_DIR}/Pictures/wallpapers" "${HOME_DIR}/Pictures/Screenshots"
  if [[ -f "${repo_dir}/awtarchy_geology.png" ]]; then
    deploy_file "${repo_dir}/awtarchy_geology.png" "${HOME_DIR}/Pictures/wallpapers/awtarchy_geology.png"
  fi

  mkdir -p -- "${HOME_DIR}/.local/share/icons/ComixCursors-White"
  if [[ -d "/usr/share/icons/ComixCursors-White" ]]; then
    cp -a --no-preserve=ownership /usr/share/icons/ComixCursors-White/. "${HOME_DIR}/.local/share/icons/ComixCursors-White/" 2>/dev/null || true
    if [[ "${EUID}" -eq 0 ]]; then
      chown -R "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.local/share/icons/ComixCursors-White" 2>/dev/null || true
    fi
  fi

  update_system_cursor_default

  if command -v flatpak >/dev/null 2>&1; then
    run_target flatpak override --user --env=GTK_CURSOR_THEME=ComixCursors-White >/dev/null 2>&1 || true
  fi

  fix_managed_perms "${CONFIG_DIRS[@]}"
  write_version_stamp "$tag"
  maybe_hyprctl_reload
  check_and_offer_missing_installs "${repo_dir}"
  apply_awtarchy_gsettings_defaults

  if (( ${#BACKUPS[@]} )); then
    warn "Backups created:"
    for b in "${BACKUPS[@]}"; do
      printf '  %s\n' "$b"
    done
  else
    log "No backups created."
  fi

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
  update-backup-cleaner.sh [options]

IMPORTANT:
  - Do NOT run with sudo. This scans under your $HOME. Running with sudo usually makes $HOME=/root.

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
      AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_DEFAULT=40 ./update-backup-cleaner.sh
    or press [G] in the menu (saved in ~/.config/awtarchy/backup_clean_page_size)

Examples:
  cd ~/awtarchy
  chmod +x ./update-backup-cleaner.sh
  ./update-backup-cleaner.sh

  ./update-backup-cleaner.sh --dry-run
EOF
}

# Refuse sudo/root: this script is designed to run as the user who owns the backups.
if [[ "${EUID}" -eq 0 ]]; then
  die "Do not run this with sudo. Run as your normal user.
Example:
  cd ~/awtarchy
  chmod +x ./update-backup-cleaner.sh
  ./update-backup-cleaner.sh"
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

main_awtarchy() {
  case "${1:-}" in
    "") top_menu ;;
    dry-run|dryrun|test) shift; run_install --dry-run "$@" ;;
    install) shift; run_install "$@" ;;
    update-reset-backup|update-reset) shift; update_reset_backup_main "$@" ;;
    update-backup-cleaner|clean-backups|backup-cleaner) shift; run_backup_cleaner_entry "$@" ;;
    __backup-cleaner) shift; update_backup_cleaner_main "$@" ;;
    help|-h|--help) usage ;;
    *) die "Unknown command: $1" ;;
  esac
}

main_awtarchy "$@"
