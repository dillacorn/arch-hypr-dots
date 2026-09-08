#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CURSOR_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_cursor_theme.sh"
STATE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
CURSOR_QML="${ROOT}/config/quickshell/awtarchy/CursorThemeSettings.qml"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

# Bibata exposes Modern (rounded) and Original (sharp) variants. Keep the
# existing rounded Ice/Classic state keys compatible and add sharp equivalents.
contains "$STATE_SCRIPT" '"ice-sharp"' \
  'cursor state does not allow the sharp Ice variant'
contains "$STATE_SCRIPT" '"classic-sharp"' \
  'cursor state does not allow the sharp Classic variant'
contains "$CURSOR_SCRIPT" "ice-sharp) printf '%s\\n' 'Bibata-Original-Ice'" \
  'cursor helper does not map sharp Ice to Bibata Original Ice'
contains "$CURSOR_SCRIPT" "classic-sharp) printf '%s\\n' 'Bibata-Original-Classic'" \
  'cursor helper does not map sharp Classic to Bibata Original Classic'
contains "$CURSOR_QML" 'label: "Rounded"' \
  'Quick Settings does not expose the rounded cursor style'
contains "$CURSOR_QML" 'label: "Sharp"' \
  'Quick Settings does not expose the sharp cursor style'

cursor_home="${TMP}/cursor-home"
config_home="${TMP}/cursor-config"
cache_home="${TMP}/cursor-cache"
data_home="${TMP}/cursor-data"
icon_root="${TMP}/icons"
fakebin="${TMP}/fakebin"
command_log="${TMP}/cursor-commands.log"
mkdir -p \
  "$cursor_home" \
  "$config_home/hypr/scripts" \
  "$config_home/gtk-3.0" \
  "$cache_home/awtarchy" \
  "$data_home/nwg-look" \
  "$fakebin"

for theme in \
  Bibata-Modern-Ice \
  Bibata-Modern-Classic \
  Bibata-Original-Ice \
  Bibata-Original-Classic; do
  mkdir -p "$icon_root/$theme/cursors" "$icon_root/$theme/hyprcursors"
  printf '%s\n' "$theme" >"$icon_root/$theme/cursors/marker"
  printf '%s\n' "name = $theme" 'cursors_directory = hyprcursors' \
    >"$icon_root/$theme/manifest.hl"
  printf '%s\n' cursor >"$icon_root/$theme/hyprcursors/left_ptr"
done

printf '%s\n' \
  'hl.env("XCURSOR_SIZE", "24")' \
  'hl.env("HYPRCURSOR_SIZE", "24")' \
  'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \
  'hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")' \
  >"$config_home/hypr/hyprland.lua"
printf '%s\n' '[Settings]' 'gtk-cursor-theme-name=Bibata-Modern-Ice' \
  >"$config_home/gtk-3.0/settings.ini"
printf '%s\n' 'cursor-theme=Bibata-Modern-Ice' \
  >"$data_home/nwg-look/gsettings"
printf '%s\n' 'Xcursor.theme: Bibata-Modern-Ice' 'Xcursor.size: 24' \
  >"$cursor_home/.Xresources"
printf '%s\n' '{"enabled":true,"monitors":{}}' \
  >"$cache_home/awtarchy/quickshell-state.json"

cat >"$fakebin/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'hyprctl %s\n' "$*" >>"${AWTARCHY_TEST_COMMAND_LOG:?}"
EOF_HYPRCTL
chmod +x "$fakebin/hyprctl"

cursor_env=(
  PATH="$fakebin:/usr/bin:/bin"
  HOME="$cursor_home"
  XDG_CONFIG_HOME="$config_home"
  XDG_CACHE_HOME="$cache_home"
  XDG_DATA_HOME="$data_home"
  AWTARCHY_APPLICATION_STATE_SCRIPT="$STATE_SCRIPT"
  AWTARCHY_CURSOR_ICON_ROOT="$icon_root"
  AWTARCHY_TEST_COMMAND_LOG="$command_log"
  HYPRLAND_INSTANCE_SIGNATURE="test-instance"
)

env "${cursor_env[@]}" "$CURSOR_SCRIPT" set ice-sharp
[[ $(jq -r '.cursor_variant' "$cache_home/awtarchy/quickshell-state.json") == ice-sharp ]] \
  || fail 'sharp Ice preference was not persisted'
contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Original-Ice")' \
  'sharp Ice did not select Bibata Original Ice'
contains "$command_log" 'hyprctl setcursor Bibata-Original-Ice 24' \
  'sharp Ice did not switch the live Hyprland cursor'

env "${cursor_env[@]}" "$CURSOR_SCRIPT" set classic-sharp
[[ $(jq -r '.cursor_variant' "$cache_home/awtarchy/quickshell-state.json") == classic-sharp ]] \
  || fail 'sharp Classic preference was not persisted'
contains "$config_home/hypr/hyprland.lua" 'hl.env("HYPRCURSOR_THEME", "Bibata-Original-Classic")' \
  'sharp Classic did not select Bibata Original Classic'
contains "$command_log" 'hyprctl setcursor Bibata-Original-Classic 24' \
  'sharp Classic did not switch the live Hyprland cursor'

# Rounded Ice remains the release/default state and legacy key.
env "${cursor_env[@]}" "$CURSOR_SCRIPT" set ice
contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \
  'rounded Ice no longer maps to Bibata Modern Ice'

# Once Bibata is installed, updater migration must offer removal of the old
# xcursor-comix package even when an old installation predates ownership data.
contains "$RECONCILER" "confirm_yes_no 'Bibata replaces xcursor-comix for Awtarchy. Uninstall xcursor-comix now?' 0" \
  'Bibata migration does not offer an explicit xcursor-comix uninstall prompt'
contains "$RECONCILER" 'AWTARCHY_BIBATA_REMOVE_XCURSOR_COMIX_CONFIRMED' \
  'Bibata migration has no explicit-confirmation path for automated validation'

package_case="${TMP}/package"
package_home="${package_case}/home"
package_fakebin="${package_case}/fakebin"
package_state="${package_case}/installed"
managed="${package_case}/managed-packages"
runtime_stub="${package_case}/awtarchy-runtime.sh"
mkdir -p "$package_home" "$package_fakebin"
printf '%s\n' bibata-cursor-theme-bin xcursor-comix >"$package_state"
: >"$managed"

cat >"$runtime_stub" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=(
  "Themes:papirus-icon-theme materia-gtk-theme kvantum-theme-materia"
)
declare -a OPTIONAL_ARCH_PACKAGES=()
declare -a PACKAGES_AUR=(bibata-cursor-theme-bin)
declare -a OPTIONAL_AUR_PACKAGES=()
declare -a FLATPAK_CATALOG=()
EOF_RUNTIME

cat >"$package_fakebin/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${AWTARCHY_TEST_PACKAGE_STATE:?}"
case "${1:-}" in
  -Q|-Qq)
    [[ -n ${2:-} ]] || { cat "$state"; exit 0; }
    grep -Fxq -- "$2" "$state"
    ;;
  -R)
    shift
    [[ ${1:-} == --noconfirm ]] && shift
    tmp="${state}.tmp"
    cp -- "$state" "$tmp"
    for pkg in "$@"; do
      grep -Fxv -- "$pkg" "$tmp" >"${tmp}.next" || true
      mv -f -- "${tmp}.next" "$tmp"
    done
    mv -f -- "$tmp" "$state"
    ;;
  *)
    printf 'unexpected pacman invocation:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    exit 90
    ;;
esac
EOF_PACMAN
chmod +x "$package_fakebin/pacman"

cat >"$package_fakebin/sudo" <<'EOF_SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${1:-} == -- ]] && shift
"$@"
EOF_SUDO
chmod +x "$package_fakebin/sudo"

PATH="$package_fakebin:/usr/bin:/bin" \
HOME="$package_home" \
USER=tester \
AWTARCHY_RUNTIME="$runtime_stub" \
AWTARCHY_MANAGED_PACKAGES_FILE="$managed" \
AWTARCHY_TEST_PACKAGE_STATE="$package_state" \
AWTARCHY_BIBATA_REMOVE_XCURSOR_COMIX_CONFIRMED=1 \
AWTARCHY_TEST_MODE=1 \
"$RECONCILER" --migrate-replacements

if grep -Fxq xcursor-comix "$package_state"; then
  fail 'explicitly approved unowned xcursor-comix package was not removed'
fi

grep -Fxq bibata-cursor-theme-bin "$package_state" \
  || fail 'Bibata was removed while retiring xcursor-comix'

printf 'PASS: Bibata sharp/rounded selection and explicit old-package removal are covered.\n'
