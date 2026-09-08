#!/usr/bin/env python3
from pathlib import Path
import re


def replace_once(path: str, old: str, new: str, label: str) -> None:
    target = Path(path)
    text = target.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    target.write_text(text.replace(old, new, 1))


runtime = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = runtime.read_text()
for old, new, label in [
    (
        '"Themes:papirus-icon-theme materia-gtk-theme xcursor-comix kvantum-theme-materia"',
        '"Themes:papirus-icon-theme materia-gtk-theme kvantum-theme-materia"',
        "runtime theme package group",
    ),
    (
        "  hyprmoncfg-bin\n  mpvpaper\n",
        "  hyprmoncfg-bin\n  bibata-cursor-theme-bin\n  mpvpaper\n",
        "runtime AUR catalog",
    ),
    (
        "retry_command pacman -S --needed --noconfirm git ipcalc dos2unix reflector xcursor-comix || exit 1",
        "retry_command pacman -S --needed --noconfirm git ipcalc dos2unix reflector || exit 1",
        "runtime bootstrap package install",
    ),
]:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)

block_re = re.compile(
    r'  create_directory "\$\{HOME_DIR\}/\.local/share/icons/ComixCursors-White"\n'
    r'  if \[\[ -d /usr/share/icons/ComixCursors-White \]\]; then\n'
    r'.*?\n  fi\n',
    re.S,
)
replacement = '''  local cursor_theme
  for cursor_theme in Bibata-Modern-Ice Bibata-Modern-Classic; do
    create_directory "${HOME_DIR}/.local/share/icons/${cursor_theme}"
    if [[ -d "/usr/share/icons/${cursor_theme}" ]]; then
      retry_command run_as_target cp -r "/usr/share/icons/${cursor_theme}/." "${HOME_DIR}/.local/share/icons/${cursor_theme}/"
      run_as_target find "${HOME_DIR}/.local/share/icons/${cursor_theme}" -type d -exec chmod 0755 {} +
      run_as_target find "${HOME_DIR}/.local/share/icons/${cursor_theme}" -type f -exec chmod 0644 {} +
    fi
  done
'''
text, count = block_re.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(f"runtime cursor icon block: expected 1 match, found {count}")
text = text.replace("ComixCursors-White", "Bibata-Modern-Ice")
if "xcursor-comix" in text or "ComixCursor" in text:
    raise SystemExit("retired Comix cursor remains in current runtime")
runtime.write_text(text)

reconciler = Path("local/share/awtarchy/awtarchy-package-reconcile.sh")
text = reconciler.read_text()
marker = "\nmigrate_lockscreen_retirement() {\n"
function = r'''
apply_bibata_cursor_replacement() {
  array_contains bibata-cursor-theme-bin "${AUR_CATALOG[@]}" || return 0

  if ! aur_package_satisfied bibata-cursor-theme-bin; then
    if [[ ! -x "$AUR_SCAN_BIN" ]] || ! "$AUR_SCAN_BIN" --version >/dev/null 2>&1; then
      warn "Bibata cursor migration requires a usable aur-scan; leaving the existing cursor package untouched."
      return 0
    fi
    log "Installing Bibata cursor theme through upstream aur-scanner..."
    install_selected_aur_packages bibata-cursor-theme-bin
  fi

  if ! aur_package_satisfied bibata-cursor-theme-bin; then
    warn "Bibata cursor theme is not installed; leaving the existing cursor package untouched."
    return 0
  fi

  package_installed xcursor-comix || return 0
  if ! managed_package xcursor-comix; then
    log "xcursor-comix is installed but is not recorded as Awtarchy-owned; leaving it installed."
    return 0
  fi

  log "Removing retired Awtarchy-owned xcursor-comix package..."
  if ! as_root pacman -R --noconfirm xcursor-comix; then
    warn "Could not remove retired xcursor-comix; leaving it installed for a later retry."
    return 0
  fi
  if package_installed xcursor-comix; then
    warn "xcursor-comix is still detected after package removal."
    return 0
  fi
  forget_managed_packages xcursor-comix
  log "Replaced Awtarchy-owned xcursor-comix with Bibata."
}
'''
if text.count(marker) != 1:
    raise SystemExit("reconciler migration insertion point missing or non-unique")
text = text.replace(marker, "\n" + function + marker.lstrip("\n"), 1)
old = "if (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then\n  apply_cheese_snapshot_replacement\n  exit 0\nfi"
new = "if (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then\n  apply_cheese_snapshot_replacement\n  apply_bibata_cursor_replacement\n  exit 0\nfi"
if text.count(old) != 1:
    raise SystemExit("migration-only replacement anchor missing or non-unique")
reconciler.write_text(text.replace(old, new, 1))

replace_once(
    "config/hypr/hyprland.lua",
    'hl.env("XCURSOR_THEME", "ComixCursors-White")',
    'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")',
    "Hyprland cursor default",
)
replace_once(
    "config/gtk-3.0/settings.ini",
    "gtk-cursor-theme-name=ComixCursor-White",
    "gtk-cursor-theme-name=Bibata-Modern-Ice",
    "GTK cursor default",
)
replace_once(
    "local/share/nwg-look/gsettings",
    "cursor-theme=ComixCursors-White",
    "cursor-theme=Bibata-Modern-Ice",
    "nwg-look cursor default",
)
replace_once(
    "Xresources",
    "Xcursor.theme: ComixCursors-White",
    "Xcursor.theme: Bibata-Modern-Ice",
    "Xresources cursor default",
)

state = Path("config/hypr/scripts/quickshell_application_state.sh")
text = state.read_text()
old = "LOCKSCREEN_ANIMATIONS_JSON='[\"random\",\"swarm\",\"edges\",\"center\",\"split\",\"off\"]'\n"
if text.count(old) != 1:
    raise SystemExit("state cursor variants insertion point missing or non-unique")
text = text.replace(old, old + "CURSOR_VARIANTS_JSON='[\"ice\",\"classic\"]'\n", 1)
marker = "\nvalidate_workspace_style() {\n"
function = r'''
validate_cursor_variant() {
    local value="$1"
    if ! jq -e -n \
        --arg value "$value" \
        --argjson allowed "$CURSOR_VARIANTS_JSON" \
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid cursor variant: %s\n' "$value" >&2
        exit 2
    fi
}

set_cursor_theme() {
    local value="$1"
    validate_cursor_variant "$value"
    new_tmp
    jq --arg value "$value" '.cursor_variant = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
'''
if text.count(marker) != 1:
    raise SystemExit("state writer insertion point missing or non-unique")
text = text.replace(marker, "\n" + function + marker.lstrip("\n"), 1)
old = 'case "$cmd" in\n    set-lockscreen-animation)'
new = 'case "$cmd" in\n    set-cursor-theme)\n        [[ -n ${2:-} ]] || exit 2\n        set_cursor_theme "$2"\n        ;;\n    set-lockscreen-animation)'
if text.count(old) != 1:
    raise SystemExit("state dispatch insertion point missing or non-unique")
text = text.replace(old, new, 1)
old = "{set-lockscreen-animation <random|swarm|edges|center|split|off>|"
new = "{set-cursor-theme <ice|classic>|set-lockscreen-animation <random|swarm|edges|center|split|off>|"
if text.count(old) != 1:
    raise SystemExit("state usage insertion point missing or non-unique")
state.write_text(text.replace(old, new, 1))

flyout = Path("config/quickshell/awtarchy/FlyoutSettings.qml")
text = flyout.read_text()
old = "? 139 + displayScaleSection.implicitHeight\n            + quickSettingsSectionControls.implicitHeight + 3"
new = "? 139 + displayScaleSection.implicitHeight\n            + cursorThemeSection.implicitHeight\n            + quickSettingsSectionControls.implicitHeight + 3"
if text.count(old) != 1:
    raise SystemExit("Quick Settings height insertion point missing or non-unique")
text = text.replace(old, new, 1)
display_block = '''        DisplayScaleSettings {
            id: displayScaleSection
            Layout.fillWidth: true
            visible: root.surfaceLabel === "Quick Settings"
            active: visible
            monitorName: root.monitorName
        }
'''
cursor_block = '''
        CursorThemeSettings {
            id: cursorThemeSection
            Layout.fillWidth: true
            visible: root.surfaceLabel === "Quick Settings"
            active: visible
        }
'''
if text.count(display_block) != 1:
    raise SystemExit("FlyoutSettings DisplayScale block was not unique")
flyout.write_text(text.replace(display_block, display_block + cursor_block, 1))

manager = Path("config/hypr/scripts/quickshell.sh")
text = manager.read_text()
old = 'REPORT_SCRIPT="${AWTARCHY_REPORT_SCRIPT:-${CONFIG_HOME}/hypr/scripts/awtarchy_report_failure.sh}"\n'
new = old + 'CURSOR_THEME_SCRIPT="${AWTARCHY_CURSOR_THEME_SCRIPT:-${CONFIG_HOME}/hypr/scripts/quickshell_cursor_theme.sh}"\n'
if text.count(old) != 1:
    raise SystemExit("Quickshell manager cursor helper variable insertion point missing or non-unique")
text = text.replace(old, new, 1)
needle = '''    flock -x 8
    ensure_state
    flock -u 8

    if is_running; then
'''
replacement = '''    flock -x 8
    ensure_state
    flock -u 8

    if [[ -f "$CURSOR_THEME_SCRIPT" && ! -L "$CURSOR_THEME_SCRIPT" ]]; then
        bash "$CURSOR_THEME_SCRIPT" reapply >/dev/null 2>&1 \
            || printf 'quickshell.sh: could not reapply the saved Bibata cursor theme.\n' >&2
    fi

    if is_running; then
'''
if text.count(needle) != 1:
    raise SystemExit("Quickshell start insertion point missing or non-unique")
manager.write_text(text.replace(needle, replacement, 1))

helper = Path("config/hypr/scripts/quickshell_cursor_theme.sh")
text = helper.read_text()
text, count = re.subn(
    r"\nupdate_managed_files\(\) \{.*?\n\}\n\nwrite_managed_files\(\)",
    "\nwrite_managed_files()",
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit("cursor helper cleanup block was not found")
old = '    require_bibata_themes || return 1\n    sync_bibata_themes\n    write_managed_files "$theme"\n'
new = '    require_bibata_themes || return 1\n    sync_bibata_themes\n    mkdir -p -- "${DATA_HOME}/icons/default"\n    printf "[Icon Theme]\\nInherits=%s\\n" "$theme" >"${DATA_HOME}/icons/default/index.theme"\n    write_managed_files "$theme"\n'
if text.count(old) != 1:
    raise SystemExit("cursor helper apply insertion point missing or non-unique")
helper.write_text(text.replace(old, new, 1))

catalog_test = Path("tests/test-current-package-catalog.sh")
text = catalog_test.read_text()
old = "for stale in bridge-utils cheese termdown; do"
if text.count(old) != 1:
    raise SystemExit("package catalog stale-list anchor missing or non-unique")
text = text.replace(old, "for stale in bridge-utils cheese termdown xcursor-comix; do", 1)
old = "for pkg in smtty hyprmoncfg-bin obs-pipewire-audio-capture-bin; do"
if text.count(old) != 1:
    raise SystemExit("package catalog AUR-list anchor missing or non-unique")
catalog_test.write_text(
    text.replace(
        old,
        "for pkg in smtty hyprmoncfg-bin bibata-cursor-theme-bin obs-pipewire-audio-capture-bin; do",
        1,
    )
)

cursor_test = Path("tests/test-bibata-cursor-migration.sh")
text = cursor_test.read_text()
old = "contains \"$FLYOUT\" 'CursorThemeSettings {' \\\n  'Quick Settings settings panel does not host the cursor selector'\n"
new = old + "contains \"$FLYOUT\" 'cursorThemeSection.implicitHeight' \\\n  'Quick Settings cursor selector height is not included in panel sizing'\n"
if text.count(old) != 1:
    raise SystemExit("cursor test flyout selector anchor missing or non-unique")
text = text.replace(old, new, 1)
old = "[[ -f \"$data_home/icons/Bibata-Modern-Classic/cursors/marker\" ]] \\\n  || fail 'Bibata Classic was not exposed in the user icon directory'\n"
new = old + "contains \"$data_home/icons/default/index.theme\" 'Inherits=Bibata-Modern-Classic' \\\n  'Classic cursor was not applied to the user XCursor fallback alias'\n"
if text.count(old) != 1:
    raise SystemExit("cursor test Classic icon anchor missing or non-unique")
text = text.replace(old, new, 1)
old = "contains \"$config_home/hypr/hyprland.lua\" 'hl.env(\"XCURSOR_THEME\", \"Bibata-Modern-Ice\")' \\\n  'Ice cursor was not reapplied to Hyprland config'\n"
new = old + "contains \"$data_home/icons/default/index.theme\" 'Inherits=Bibata-Modern-Ice' \\\n  'Ice cursor was not reapplied to the user XCursor fallback alias'\n"
if text.count(old) != 1:
    raise SystemExit("cursor test Ice config anchor missing or non-unique")
cursor_test.write_text(text.replace(old, new, 1))
