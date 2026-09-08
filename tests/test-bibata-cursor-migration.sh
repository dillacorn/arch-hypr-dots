#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
STATE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
CURSOR_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_cursor_theme.sh"
CURSOR_QML="${ROOT}/config/quickshell/awtarchy/CursorThemeSettings.qml"
FLYOUT="${ROOT}/config/quickshell/awtarchy/FlyoutSettings.qml"
HYPR="${ROOT}/config/hypr/hyprland.lua"
GTK3="${ROOT}/config/gtk-3.0/settings.ini"
NWG="${ROOT}/local/share/nwg-look/gsettings"
XRESOURCES="${ROOT}/Xresources"
HISTORY="${ROOT}/local/share/awtarchy/quickshell-managed-history.sha256"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

contains() {
  grep -Fq -- "$2" "$1" || fail "$3"
}

not_contains() {
  if grep -Fq -- "$2" "$1"; then
    fail "$3"
  fi
}

assert_history_current() {
  local source="$1" rel="$2" hash
  hash="$(sha256sum "$source" | awk '{print $1}')"
  grep -Fq -- "${hash}"$'\t'"${rel}" "$HISTORY" \
    || fail "managed history is missing the current hash for ${rel}"
}

bash -n "$RUNTIME"
bash -n "$RECONCILER"
bash -n "$STATE_SCRIPT"
[[ -f "$CURSOR_SCRIPT" ]] || fail 'cursor application helper is missing'
[[ -f "$CURSOR_QML" ]] || fail 'Quick Settings cursor selector is missing'
bash -n "$CURSOR_SCRIPT"

# Fresh installs: Bibata is a default AUR package and Comix is no longer current.
contains "$RUNTIME" 'bibata-cursor-theme-bin' \
  'Bibata AUR package is not present in the current runtime catalog'
not_contains "$RUNTIME" 'xcursor-comix' \
  'retired xcursor-comix is still present in the current install runtime'

# Stock configuration defaults must all agree on Bibata Modern Ice.
contains "$HYPR" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \
  'Hyprland does not default to Bibata Modern Ice'
contains "$GTK3" 'gtk-cursor-theme-name=Bibata-Modern-Ice' \
  'GTK3 does not default to Bibata Modern Ice'
contains "$NWG" 'cursor-theme=Bibata-Modern-Ice' \
  'nwg-look does not default to Bibata Modern Ice'
contains "$XRESOURCES" 'Xcursor.theme: Bibata-Modern-Ice' \
  'Xresources does not default to Bibata Modern Ice'

# Quick Settings must expose both evidence-backed Bibata variants.
contains "$FLYOUT" 'CursorThemeSettings {' \
  'Quick Settings settings panel does not host the cursor selector'
contains "$CURSOR_QML" 'Ice / White' \
  'cursor selector does not expose the white Ice option'
contains "$CURSOR_QML" 'Classic / Black' \
  'cursor selector does not expose the black Classic option'
contains "$CURSOR_SCRIPT" 'Bibata-Modern-Ice' \
  'cursor helper does not map the Ice theme directory'
contains "$CURSOR_SCRIPT" 'Bibata-Modern-Classic' \
  'cursor helper does not map the Classic theme directory'
contains "$STATE_SCRIPT" 'set-cursor-theme' \
  'cursor preference is not persisted through the existing Quickshell state writer'

# Current managed bytes must be recognized by updater history.
assert_history_current "$STATE_SCRIPT" '.config/hypr/scripts/quickshell_application_state.sh'
assert_history_current "$CURSOR_SCRIPT" '.config/hypr/scripts/quickshell_cursor_theme.sh'
assert_history_current "$CURSOR_QML" '.config/quickshell/awtarchy/CursorThemeSettings.qml'
assert_history_current "$FLYOUT" '.config/quickshell/awtarchy/FlyoutSettings.qml'

# Package migration: install Bibata through aur-scan before removing an
# Awtarchy-owned xcursor-comix package.
package_case="${TMP}/package"
home="${package_case}/home"
fakebin="${package_case}/fakebin"
state="${package_case}/installed"
managed="${package_case}/managed-packages"
runtime_stub="${package_case}/awtarchy-runtime.sh"
aur_log="${package_case}/aur-scan.log"
mkdir -p "$home" "$fakebin"
printf '%s\n' xcursor-comix >"$state"
printf '%s\n' xcursor-comix >"$managed"

cat >"$runtime_stub" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=(
  "Themes:papirus-icon-theme materia-gtk-theme kvantum-theme-materia"
)
declare -a OPTIONAL_ARCH_PACKAGES=()
declare -a PACKAGES_AUR=(
  bibata-cursor-theme-bin
)
declare -a OPTIONAL_AUR_PACKAGES=()
declare -a FLATPAK_CATALOG=()
EOF_RUNTIME

cat >"$fakebin/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${AWTARCHY_TEST_PACKAGE_STATE:?}"
case "${1:-}" in
  -Q)
    grep -Fxq -- "${2:-}" "$state"
    ;;
  -Qq)
    if (( $# == 1 )); then
      cat "$state"
    else
      grep -Fxq -- "${2:-}" "$state"
    fi
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
chmod +x "$fakebin/pacman"

cat >"$fakebin/sudo" <<'EOF_SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == -k || ${1:-} == -v ]]; then
  exit 0
fi
[[ ${1:-} == -- ]] && shift
exec "$@"
EOF_SUDO
chmod +x "$fakebin/sudo"

cat >"$fakebin/aur-scan" <<'EOF_AUR_SCAN'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${AWTARCHY_TEST_PACKAGE_STATE:?}"
log="${AWTARCHY_TEST_AUR_LOG:?}"
printf '%s\n' "$*" >>"$log"
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'aur-scan test'
  exit 0
fi
if [[ ${1:-} == install && ${2:-} == bibata-cursor-theme-bin && ${3:-} == --noconfirm ]]; then
  if [[ ${AWTARCHY_TEST_AUR_FAIL:-0} == 1 ]]; then
    exit 1
  fi
  grep -Fxq bibata-cursor-theme-bin "$state" \
    || printf '%s\n' bibata-cursor-theme-bin >>"$state"
  exit 0
fi
exit 91
EOF_AUR_SCAN
chmod +x "$fakebin/aur-scan"

run_replacement() {
  PATH="$fakebin:/usr/bin:/bin" \
  HOME="$home" \
  USER=tester \
  AWTARCHY_RUNTIME="$runtime_stub" \
  AWTARCHY_MANAGED_PACKAGES_FILE="$managed" \
  AWTARCHY_TEST_PACKAGE_STATE="$state" \
  AWTARCHY_TEST_AUR_LOG="$aur_log" \
  AWTARCHY_AUR_SCAN_BIN="$fakebin/aur-scan" \
  AWTARCHY_TEST_MODE=1 \
  "$RECONCILER" --migrate-replacements
}

run_replacement
contains "$aur_log" 'install bibata-cursor-theme-bin --noconfirm' \
  'cursor migration did not use aur-scan install for Bibata'
grep -Fxq bibata-cursor-theme-bin "$state" \
  || fail 'cursor migration did not install Bibata'
if grep -Fxq xcursor-comix "$state"; then
  fail 'cursor migration did not remove Awtarchy-owned xcursor-comix'
fi
grep -Fxq bibata-cursor-theme-bin "$managed" \
  || fail 'cursor migration did not record Bibata as Awtarchy-managed'
if grep -Fxq xcursor-comix "$managed"; then
  fail 'cursor migration did not remove xcursor-comix from the managed-package ledger'
fi

# Unowned old cursor packages are preserved even after Bibata becomes current.
printf '%s\n' xcursor-comix >"$state"
: >"$managed"
: >"$aur_log"
run_replacement
grep -Fxq bibata-cursor-theme-bin "$state" \
  || fail 'unowned migration case did not install Bibata'
grep -Fxq xcursor-comix "$state" \
  || fail 'unowned xcursor-comix was removed without ownership evidence'

# A failed Bibata install must never remove the working old managed cursor.
printf '%s\n' xcursor-comix >"$state"
printf '%s\n' xcursor-comix >"$managed"
: >"$aur_log"
AWTARCHY_TEST_AUR_FAIL=1 run_replacement
grep -Fxq xcursor-comix "$state" \
  || fail 'old cursor was removed even though Bibata installation failed'

# Preference/application: use the existing Quickshell state file, apply the
# chosen variant to every cursor surface Awtarchy already manages, and reapply
# the saved choice after a stock config reset.
cursor_case="${TMP}/cursor"
cursor_home="${cursor_case}/home"
config_home="${cursor_case}/config"
cache_home="${cursor_case}/cache"
data_home="${cursor_case}/data"
icon_root="${cursor_case}/usr-share-icons"
cursor_fakebin="${cursor_case}/fakebin"
command_log="${cursor_case}/commands.log"
mkdir -p \
  "$cursor_home" \
  "$config_home/hypr/scripts" \
  "$config_home/gtk-3.0" \
  "$cache_home/awtarchy" \
  "$data_home/nwg-look" \
  "$icon_root/Bibata-Modern-Ice/cursors" \
  "$icon_root/Bibata-Modern-Classic/cursors" \
  "$cursor_fakebin"
printf '%s\n' ice >"$icon_root/Bibata-Modern-Ice/cursors/marker"
printf '%s\n' classic >"$icon_root/Bibata-Modern-Classic/cursors/marker"
printf '%s\n' 'hl.env("XCURSOR_SIZE", "24")' 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \
  >"$config_home/hypr/hyprland.lua"
printf '%s\n' '[Settings]' 'gtk-cursor-theme-name=Bibata-Modern-Ice' \
  >"$config_home/gtk-3.0/settings.ini"
printf '%s\n' 'cursor-theme=Bibata-Modern-Ice' \
  >"$data_home/nwg-look/gsettings"
printf '%s\n' 'Xcursor.theme: Bibata-Modern-Ice' 'Xcursor.size: 24' \
  >"$cursor_home/.Xresources"
printf '%s\n' '{"enabled":true,"monitors":{}}' \
  >"$cache_home/awtarchy/quickshell-state.json"

for command in hyprctl gsettings flatpak systemctl dbus-update-activation-environment; do
  cat >"$cursor_fakebin/$command" <<'EOF_COMMAND'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s %s\n' "${0##*/}" "$*" >>"${AWTARCHY_TEST_COMMAND_LOG:?}"
exit 0
EOF_COMMAND
  chmod +x "$cursor_fakebin/$command"
done

cursor_env=(
  PATH="$cursor_fakebin:/usr/bin:/bin"
  HOME="$cursor_home"
  XDG_CONFIG_HOME="$config_home"
  XDG_CACHE_HOME="$cache_home"
  XDG_DATA_HOME="$data_home"
  AWTARCHY_APPLICATION_STATE_SCRIPT="$STATE_SCRIPT"
  AWTARCHY_CURSOR_ICON_ROOT="$icon_root"
  AWTARCHY_TEST_COMMAND_LOG="$command_log"
)

status="$(env "${cursor_env[@]}" "$CURSOR_SCRIPT" status)"
[[ $status == ice ]] || fail "cursor status default is not Ice: ${status}"

env "${cursor_env[@]}" "$CURSOR_SCRIPT" set classic
[[ $(jq -r '.cursor_variant // empty' "$cache_home/awtarchy/quickshell-state.json") == classic ]] \
  || fail 'Classic cursor preference was not persisted in quickshell-state.json'
contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")' \
  'Classic cursor was not persisted into Hyprland config'
contains "$config_home/gtk-3.0/settings.ini" 'gtk-cursor-theme-name=Bibata-Modern-Classic' \
  'Classic cursor was not applied to GTK3 settings'
contains "$data_home/nwg-look/gsettings" 'cursor-theme=Bibata-Modern-Classic' \
  'Classic cursor was not applied to nwg-look settings'
contains "$cursor_home/.Xresources" 'Xcursor.theme: Bibata-Modern-Classic' \
  'Classic cursor was not applied to Xresources'
[[ -f "$data_home/icons/Bibata-Modern-Ice/cursors/marker" ]] \
  || fail 'Bibata Ice was not exposed in the user icon directory'
[[ -f "$data_home/icons/Bibata-Modern-Classic/cursors/marker" ]] \
  || fail 'Bibata Classic was not exposed in the user icon directory'
contains "$command_log" 'gsettings set org.gnome.desktop.interface cursor-theme Bibata-Modern-Classic' \
  'Classic cursor was not applied through GTK gsettings'
contains "$command_log" 'flatpak override --user --env=GTK_CURSOR_THEME=Bibata-Modern-Classic' \
  'Classic cursor was not applied to the existing Flatpak cursor override'
contains "$command_log" 'hyprctl reload' \
  'Hyprland was not reloaded after changing the persisted XCursor environment'

status="$(env "${cursor_env[@]}" "$CURSOR_SCRIPT" status)"
[[ $status == classic ]] || fail 'cursor preference did not survive a Quickshell-style status reload'

# Simulate an updater restoring the stock Ice config. Reapply must restore the
# persisted Classic choice without changing state.
printf '%s\n' 'hl.env("XCURSOR_SIZE", "24")' 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \
  >"$config_home/hypr/hyprland.lua"
env "${cursor_env[@]}" "$CURSOR_SCRIPT" reapply
contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")' \
  'persisted Classic cursor was not reapplied after a stock config reset'

# Switching back to the release default must persist and apply Ice.
env "${cursor_env[@]}" "$CURSOR_SCRIPT" set ice
[[ $(jq -r '.cursor_variant // empty' "$cache_home/awtarchy/quickshell-state.json") == ice ]] \
  || fail 'Ice cursor preference was not persisted'
contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \
  'Ice cursor was not reapplied to Hyprland config'

if env "${cursor_env[@]}" "$CURSOR_SCRIPT" set amber >/dev/null 2>&1; then
  fail 'cursor helper accepted an unsupported Bibata variant'
fi

printf 'PASS: Bibata cursor migration, persistence, Quick Settings selection, and conservative replacement behavior are covered.\n'
