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

# Upstream Bibata ships 12 Linux variants:
# Amber/Classic/Ice x Modern(round)/Original(sharp) x Normal/Right Hand.
# Preserve the existing rounded normal Ice/Classic state keys for compatibility.
declare -A THEMES=(
  [amber]='Bibata-Modern-Amber'
  [classic]='Bibata-Modern-Classic'
  [ice]='Bibata-Modern-Ice'
  [amber-sharp]='Bibata-Original-Amber'
  [classic-sharp]='Bibata-Original-Classic'
  [ice-sharp]='Bibata-Original-Ice'
  [amber-right]='Bibata-Modern-Amber-Right'
  [classic-right]='Bibata-Modern-Classic-Right'
  [ice-right]='Bibata-Modern-Ice-Right'
  [amber-sharp-right]='Bibata-Original-Amber-Right'
  [classic-sharp-right]='Bibata-Original-Classic-Right'
  [ice-sharp-right]='Bibata-Original-Ice-Right'
)

for variant in "${!THEMES[@]}"; do
  theme="${THEMES[$variant]}"
  contains "$STATE_SCRIPT" "\"${variant}\"" \
    "cursor state does not allow ${variant}"
  contains "$CURSOR_SCRIPT" "${variant}) printf '%s\\n' '${theme}'" \
    "cursor helper does not map ${variant} to ${theme}"
done

contains "$CURSOR_QML" 'label: "Ice / White"' \
  'Quick Settings does not expose Ice/white'
contains "$CURSOR_QML" 'label: "Classic / Black"' \
  'Quick Settings does not expose Classic/black'
contains "$CURSOR_QML" 'label: "Amber"' \
  'Quick Settings does not expose Amber'
contains "$CURSOR_QML" 'label: "Rounded"' \
  'Quick Settings does not expose the rounded cursor style'
contains "$CURSOR_QML" 'label: "Sharp"' \
  'Quick Settings does not expose the sharp cursor style'
contains "$CURSOR_QML" 'label: "Normal"' \
  'Quick Settings does not expose normal handedness'
contains "$CURSOR_QML" 'label: "Right Hand"' \
  'Quick Settings does not expose right-hand variants'

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

for theme in "${THEMES[@]}"; do
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

for variant in \
  ice classic amber \
  ice-sharp classic-sharp amber-sharp \
  ice-right classic-right amber-right \
  ice-sharp-right classic-sharp-right amber-sharp-right; do
  theme="${THEMES[$variant]}"
  : >"$command_log"
  env "${cursor_env[@]}" "$CURSOR_SCRIPT" set "$variant"
  [[ $(jq -r '.cursor_variant' "$cache_home/awtarchy/quickshell-state.json") == "$variant" ]] \
    || fail "${variant} preference was not persisted"
  contains "$config_home/hypr/hyprland.lua" "hl.env(\"XCURSOR_THEME\", \"${theme}\")" \
    "${variant} did not persist ${theme} as XCursor"
  contains "$config_home/hypr/hyprland.lua" "hl.env(\"HYPRCURSOR_THEME\", \"${theme}\")" \
    "${variant} did not persist ${theme} as hyprcursor"
  contains "$command_log" "hyprctl setcursor ${theme} 24" \
    "${variant} did not switch the live Hyprland cursor"
done

# Rounded normal Ice remains the release/default state and legacy key.
env "${cursor_env[@]}" "$CURSOR_SCRIPT" set ice
contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \
  'default Ice no longer maps to Bibata Modern Ice'

# Once Bibata is installed, xcursor-comix is obsolete for Awtarchy and must be
# removed automatically even when the old installation predates ownership data.
if grep -Fq -- "confirm_yes_no 'Bibata replaces xcursor-comix for Awtarchy. Uninstall xcursor-comix now?'" "$RECONCILER"; then
  fail 'Bibata migration still prompts before removing xcursor-comix'
fi
if grep -Fq -- 'AWTARCHY_BIBATA_REMOVE_XCURSOR_COMIX_CONFIRMED' "$RECONCILER"; then
  fail 'Bibata migration still depends on a one-time xcursor-comix confirmation override'
fi

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
AWTARCHY_TEST_MODE=1 \
"$RECONCILER" --migrate-replacements

if grep -Fxq xcursor-comix "$package_state"; then
  fail 'legacy xcursor-comix package was not removed automatically'
fi

grep -Fxq bibata-cursor-theme-bin "$package_state" \
  || fail 'Bibata was removed while retiring xcursor-comix'

printf 'PASS: all 12 Bibata variants and automatic old-package removal are covered.\n'
