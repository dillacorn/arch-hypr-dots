#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER = ROOT / "local/share/awtarchy/awtarchy-package-reconcile.sh"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}")
    path.write_text(text.replace(old, new, 1))


def replace_count(path: Path, old: str, new: str, expected: int) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} matches, found {count}")
    path.write_text(text.replace(old, new))


replace_once(
    RUNTIME,
    '''declare -a PKG_GROUPS=(
  "Window Management:hyprland hyprpaper hyprlock hypridle hyprpicker hyprsunset quickshell grim satty slurp wl-clipboard cliphist zbar wf-recorder zenity qt5ct qt5-wayland kvantum-qt5 qt6ct qt6-wayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk libnotify nwg-look"
  "Fonts:woff2-font-awesome otf-font-awesome ttf-dejavu ttf-liberation ttf-noto-nerd noto-fonts-emoji"
  "Themes:papirus-icon-theme materia-gtk-theme xcursor-comix kvantum-theme-materia"
  "Terminal Apps:nano micro fastfetch btop htop curl passt devtools wget git dos2unix brightnessctl ipcalc cmatrix asciiquarium figlet espeak-ng cava man-db man-pages unzip xarchiver ncdu ddcutil scx-scheds scx-tools"
  "Utilities:upower polkit python-gobject gnome-keyring networkmanager bluez bluez-utils wiremix pcmanfm-qt gvfs gvfs-smb gvfs-mtp gvfs-afc speedcrunch imagemagick pipewire pipewire-pulse pipewire-alsa ufw jq earlyoom libsixel xdg-utils python usbutils awww"
  "Multimedia:ffmpeg avahi nss-mdns mpv snapshot exiv2 zathura zathura-pdf-mupdf mousai"
  "Development:base-devel archlinux-keyring bubblewrap gnupg coreutils clang ninja go rust virt-manager qemu qemu-hw-usb-host virt-viewer vde2 libguestfs dmidecode gamemode gamescope nftables swtpm"
  "Network Tools:firefox wireguard-tools wireplumber openssh iptables systemd-resolvconf qemu-guest-agent dnsmasq dhcpcd inetutils openbsd-netcat"
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

# Format: selected|friendly name|Flathub app ID
# Selected defaults preserve the current install_flatpak_apps.sh behavior.
declare -a FLATPAK_CATALOG=(
  "1|Flatseal|com.github.tchx84.Flatseal"
  "0|Vesktop|dev.vencord.Vesktop"
  "0|Moonlight|com.moonlight_stream.Moonlight"
)
''',
    '''declare -a PKG_GROUPS=(
  "Window Management:hyprland hyprpaper hyprlock hypridle hyprpicker hyprsunset quickshell grim satty slurp wl-clipboard cliphist zbar wf-recorder zenity qt5ct qt5-wayland kvantum-qt5 qt6ct qt6-wayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk libnotify nwg-look"
  "Fonts:woff2-font-awesome otf-font-awesome ttf-dejavu ttf-liberation ttf-noto-nerd noto-fonts-emoji"
  "Themes:papirus-icon-theme materia-gtk-theme xcursor-comix kvantum-theme-materia"
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
''',
)

replace_once(
    RUNTIME,
    '''build_arch_picker_arrays() {
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
  done < <(printf '%s\\n' "${PKG_GROUPS[@]}")
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
''',
    '''build_arch_picker_arrays() {
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
  done < <(printf '%s\\n' "${PKG_GROUPS[@]}")
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
''',
)

replace_once(
    RUNTIME,
    '''build_flatpak_picker_arrays() {
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
''',
    '''build_flatpak_picker_arrays() {
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
''',
)

replace_once(
    RUNTIME,
    '''    view_indices+=("-100")
    view_indices+=("-104")
    view_indices+=("-101")
    view_indices+=("-102")
    view_indices+=("-103")
''',
    '''    view_indices+=("-100")
    view_indices+=("-104")
    view_indices+=("-201")
    view_indices+=("-202")
    view_indices+=("-101")
    view_indices+=("-102")
    view_indices+=("-103")
''',
)

replace_once(
    RUNTIME,
    '''        -100) printf '%s [✓] Done with this list\\n' "$prefix" ;;
        -104) printf '%s [<] Back\\n' "$prefix" ;;
        -101) printf '%s [?] Search/filter list\\n' "$prefix" ;;
''',
    '''        -100) printf '%s [✓] Done with this list\\n' "$prefix" ;;
        -104) printf '%s [<] Back\\n' "$prefix" ;;
        -201) printf '%s [✓] Select all in this list\\n' "$prefix" ;;
        -202) printf '%s [ ] Clear all in this list\\n' "$prefix" ;;
        -101) printf '%s [?] Search/filter list\\n' "$prefix" ;;
''',
)

replace_count(
    RUNTIME,
    '''          -101)
            clear_screen
            filter="$(prompt_line "Search/filter ${type}: ")"
            index=0
            ;;
''',
    '''          -201)
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
''',
    2,
)

replace_count(
    RUNTIME,
    '''            elif [[ "${kinds_ref[$selected_index]}" == "item" ]]; then
              if [[ "${selected_ref[selected_index]}" == "1" ]]; then
                selected_ref[selected_index]=0
              else
                selected_ref[selected_index]=1
              fi
            fi
''',
    '''            elif [[ "${kinds_ref[$selected_index]}" == "item" ]]; then
              if [[ "${selected_ref[selected_index]}" == "1" ]]; then
                selected_ref[selected_index]=0
              else
                selected_ref[selected_index]=1
              fi
              sync_virt_manager_bundle_selection \
                "${values_ref[selected_index]}" "${selected_ref[selected_index]}" \
                "$values_name" "$selected_name"
            fi
''',
    2,
)

replace_once(
    RECONCILER,
    '''declare -a ARCH_CATALOG=()
declare -a AUR_CATALOG=()
declare -a FLATPAK_IDS=()
declare -a FLATPAK_NAMES=()
declare -a MISSING_REQUIRED=()
declare -a MISSING_ARCH=()
declare -a MISSING_AUR=()
declare -a MISSING_FLATPAK_IDS=()
declare -a MISSING_FLATPAK_NAMES=()
''',
    '''declare -a ARCH_CATALOG=()
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
''',
)

replace_once(
    RECONCILER,
    '''load_catalogs() {
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
''',
    '''load_catalogs() {
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
''',
)

replace_once(
    RECONCILER,
    '''    obs-pipewire-audio-capture|obs-pipewire-audio-capture-bin)
      for alt in obs-pipewire-audio-capture obs-pipewire-audio-capture-bin; do
        package_installed "$alt" && return 0
      done
      obs_pipewire_audio_capture_user_plugin_installed
      ;;
''',
    '''    vesktop|vesktop-bin)
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
''',
)

replace_once(
    RECONCILER,
    '''collect_state() {
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

  for pkg in "${AUR_CATALOG[@]}"; do
    aur_package_satisfied "$pkg" || MISSING_AUR+=("$pkg")
  done

  for i in "${!FLATPAK_IDS[@]}"; do
    flatpak_app_installed "${FLATPAK_IDS[$i]}" && continue
    MISSING_FLATPAK_IDS+=("${FLATPAK_IDS[$i]}")
    MISSING_FLATPAK_NAMES+=("${FLATPAK_NAMES[$i]}")
  done

  for pkg in "${RETIRED_ARCH[@]}"; do
''',
    '''collect_state() {
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
''',
)

replace_once(
    RECONCILER,
    '''  printf 'Arch catalog packages: %d\\n' "${#ARCH_CATALOG[@]}"
  printf 'AUR catalog packages: %d\\n' "${#AUR_CATALOG[@]}"
  printf 'Flatpak catalog apps: %d\\n' "${#FLATPAK_IDS[@]}"
''',
    '''  printf 'Arch catalog packages: %d (%d default, %d optional)\\n' \
    "$(( ${#ARCH_CATALOG[@]} + ${#OPTIONAL_ARCH_CATALOG[@]} ))" \
    "${#ARCH_CATALOG[@]}" "${#OPTIONAL_ARCH_CATALOG[@]}"
  printf 'AUR catalog packages: %d (%d default, %d optional)\\n' \
    "$(( ${#AUR_CATALOG[@]} + ${#OPTIONAL_AUR_CATALOG[@]} ))" \
    "${#AUR_CATALOG[@]}" "${#OPTIONAL_AUR_CATALOG[@]}"
  printf 'Flatpak catalog apps: %d (%d default, %d optional)\\n' \
    "$(( ${#FLATPAK_IDS[@]} + ${#OPTIONAL_FLATPAK_IDS[@]} ))" \
    "${#FLATPAK_IDS[@]}" "${#OPTIONAL_FLATPAK_IDS[@]}"
''',
)

replace_once(
    RECONCILER,
    '''  print_list 'Other missing current Arch catalog packages:' "${MISSING_ARCH[@]}"
  printf '\\n'
  print_list 'Missing current AUR catalog packages:' "${MISSING_AUR[@]}"
  printf '\\n'
  if (( ${#MISSING_FLATPAK_IDS[@]} )); then
''',
    '''  print_list 'Other missing current Arch catalog packages:' "${MISSING_ARCH[@]}"
  printf '\\n'
  print_list 'Optional Arch packages not installed:' "${MISSING_OPTIONAL_ARCH[@]}"
  printf '\\n'
  print_list 'Missing current AUR catalog packages:' "${MISSING_AUR[@]}"
  printf '\\n'
  print_list 'Optional AUR packages not installed:' "${MISSING_OPTIONAL_AUR[@]}"
  printf '\\n'
  if (( ${#MISSING_FLATPAK_IDS[@]} )); then
''',
)

replace_once(
    RECONCILER,
    '''  else
    printf '%s\\n' 'Missing current Flatpak catalog apps:' '  (none)'
  fi
  printf '\\n'
  print_list 'Retired Awtarchy-owned packages eligible for removal:' "${RETIRED_MANAGED[@]}"
''',
    '''  else
    printf '%s\\n' 'Missing current Flatpak catalog apps:' '  (none)'
  fi
  printf '\\n'
  if (( ${#MISSING_OPTIONAL_FLATPAK_IDS[@]} )); then
    printf '%s\\n' 'Optional Flatpak apps not installed:'
    local i
    for i in "${!MISSING_OPTIONAL_FLATPAK_IDS[@]}"; do
      printf '  - %s (%s)\\n' "${MISSING_OPTIONAL_FLATPAK_NAMES[$i]}" "${MISSING_OPTIONAL_FLATPAK_IDS[$i]}"
    done
  else
    printf '%s\\n' 'Optional Flatpak apps not installed:' '  (none)'
  fi
  printf '\\n'
  print_list 'Retired Awtarchy-owned packages eligible for removal:' "${RETIRED_MANAGED[@]}"
''',
)

replace_once(
    RECONCILER,
    '''    printf '%s\\n\\n' 'Arrow keys move, Space toggles, Enter accepts, Esc cancels.' >/dev/tty
''',
    '''    printf '%s\\n\\n' 'Arrow keys move, Space toggles, A selects all, C clears all, Enter accepts, Esc cancels.' >/dev/tty
''',
)

replace_once(
    RECONCILER,
    '''      ' ')
        if (( selected[current] == 1 )); then selected[current]=0; else selected[current]=1; fi
        ;;
      ''|$'\\n'|$'\\r')
''',
    '''      ' ')
        if (( selected[current] == 1 )); then selected[current]=0; else selected[current]=1; fi
        ;;
      a|A)
        for i in "${!selected[@]}"; do selected[i]=1; done
        ;;
      c|C)
        for i in "${!selected[@]}"; do selected[i]=0; done
        ;;
      ''|$'\\n'|$'\\r')
''',
)

replace_once(
    RECONCILER,
    '''print_review >/dev/tty
printf '\\nMissing current packages below start selected; Space opts out.\\n' >/dev/tty
printf 'Installed current packages are preserved even when not selected here.\\n\\n' >/dev/tty
confirm_yes_no 'Continue to package choices?' 1 || { log 'Package reconciliation canceled.'; exit 0; }

# Missing optional Arch packages.
declare -a arch_labels=("${MISSING_ARCH[@]}")
declare -a arch_flags=()
declare -a selected_arch=()
for _ in "${arch_labels[@]}"; do arch_flags+=(1); done
if (( ${#arch_labels[@]} )); then
  multi_select 'Optional missing Arch packages' arch_labels arch_flags \\
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values arch_labels arch_flags selected_arch

# Missing AUR packages.
declare -a aur_labels=("${MISSING_AUR[@]}")
declare -a aur_flags=()
declare -a selected_aur=()
for _ in "${aur_labels[@]}"; do aur_flags+=(1); done
if (( ${#aur_labels[@]} )); then
  multi_select 'Optional missing AUR packages' aur_labels aur_flags \\
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values aur_labels aur_flags selected_aur

# Missing Flatpak apps.
declare -a flatpak_labels=()
declare -a flatpak_flags=()
declare -a selected_flatpak=()
for i in "${!MISSING_FLATPAK_IDS[@]}"; do
  flatpak_labels+=("${MISSING_FLATPAK_NAMES[$i]} (${MISSING_FLATPAK_IDS[$i]})")
  flatpak_flags+=(1)
done
if (( ${#flatpak_labels[@]} )); then
  multi_select 'Optional missing Flatpak apps' flatpak_labels flatpak_flags \\
    || { log 'Package reconciliation canceled.'; exit 0; }
  for i in "${!MISSING_FLATPAK_IDS[@]}"; do
    (( flatpak_flags[i] == 1 )) && selected_flatpak+=("${MISSING_FLATPAK_IDS[$i]}")
  done
fi
''',
    '''print_review >/dev/tty
printf '\\nOptional choices are listed first and start unchecked.\\n' >/dev/tty
printf 'Missing default packages start selected; Space opts out.\\n' >/dev/tty
printf 'Installed current packages are preserved even when not selected here.\\n\\n' >/dev/tty
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
  multi_select 'Arch packages to install' arch_labels arch_flags \\
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
  multi_select 'AUR packages to install' aur_labels aur_flags \\
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
  multi_select 'Flatpak apps to install' flatpak_labels flatpak_flags \\
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values flatpak_values flatpak_flags selected_flatpak
''',
)

print("Applied optional package defaults and native app catalog migration.")
