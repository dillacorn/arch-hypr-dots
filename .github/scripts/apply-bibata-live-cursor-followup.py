#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one marker, found {count}")
    path.write_text(text.replace(old, new, 1))


quick = ROOT / "config/quickshell/awtarchy/QuickSettings.qml"
cursor = ROOT / "config/hypr/scripts/quickshell_cursor_theme.sh"
runtime = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
test = ROOT / "tests/test-bibata-cursor-migration.sh"
history = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"

# Put the cursor chooser where users actually expect it: in the Awtarchy card.
quick_old = '''                                Text {
                                    Layout.fillWidth: true
                                    text: "Built-in manual for keybinds, Quickshell, display, gaming, packages, maintenance, networking, troubleshooting, and Extra Notes."
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Lockscreen Animation"
'''
quick_new = '''                                Text {
                                    Layout.fillWidth: true
                                    text: "Built-in manual for keybinds, Quickshell, display, gaming, packages, maintenance, networking, troubleshooting, and Extra Notes."
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }

                                CursorThemeSettings {
                                    id: awtarchyCursorThemeSection
                                    Layout.fillWidth: true
                                    active: quickSettingsWindow.visible
                                        && !root.settingsOpen
                                        && root.quickSettingsSectionVisible("awtarchy")
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Lockscreen Animation"
'''
replace_once(quick, quick_old, quick_new, "Quick Settings Awtarchy cursor placement")

# Convert the installed official XCursor Bibata variants locally to hyprcursor
# once, so Hyprland can switch its compositor cursor immediately with the
# supported hyprctl setcursor path. Keep XCursor for GTK/XWayland fallbacks.
sync_marker = '''sync_bibata_themes() {
    local theme
    for theme in Bibata-Modern-Ice Bibata-Modern-Classic; do
        if [[ -d "${ICON_ROOT}/${theme}" ]]; then
            sync_theme_to_user_icons "$theme"
        fi
    done
}
'''
ensure_block = sync_marker + '''
ensure_hyprcursor_theme() {
    local theme="$1"
    local theme_dir="${DATA_HOME}/icons/${theme}"
    local work_root extract_parent create_parent extracted="" compiled="" candidate

    if [[ -f "${theme_dir}/manifest.hl" && -d "${theme_dir}/hyprcursors" ]]; then
        return 0
    fi

    command -v hyprcursor-util >/dev/null 2>&1 || {
        printf 'quickshell_cursor_theme.sh: hyprcursor-util is unavailable; current-session compositor cursor cannot be switched.\\n' >&2
        return 1
    }
    command -v xcur2png >/dev/null 2>&1 || {
        printf 'quickshell_cursor_theme.sh: xcur2png is unavailable; current-session compositor cursor cannot be switched.\\n' >&2
        return 1
    }
    [[ -d "$theme_dir" ]] || return 1

    mkdir -p -- "${CACHE_HOME}/awtarchy"
    work_root="$(mktemp -d "${CACHE_HOME}/awtarchy/hyprcursor.XXXXXX")" || return 1
    extract_parent="${work_root}/extract"
    create_parent="${work_root}/create"
    mkdir -p -- "$extract_parent" "$create_parent"

    if ! hyprcursor-util --extract "$theme_dir" --output "$extract_parent" >/dev/null 2>&1; then
        rm -rf -- "$work_root"
        printf 'quickshell_cursor_theme.sh: failed to extract %s for hyprcursor conversion.\\n' "$theme" >&2
        return 1
    fi

    for candidate in "$extract_parent"/*; do
        if [[ -d "$candidate" && -f "$candidate/manifest.hl" ]]; then
            extracted="$candidate"
            break
        fi
    done
    if [[ -z "$extracted" ]]; then
        rm -rf -- "$work_root"
        printf 'quickshell_cursor_theme.sh: hyprcursor extraction output is missing for %s.\\n' "$theme" >&2
        return 1
    fi

    if ! hyprcursor-util --create "$extracted" --output "$create_parent" >/dev/null 2>&1; then
        rm -rf -- "$work_root"
        printf 'quickshell_cursor_theme.sh: failed to compile %s as hyprcursor.\\n' "$theme" >&2
        return 1
    fi

    for candidate in "$create_parent"/*; do
        if [[ -d "$candidate" && -f "$candidate/manifest.hl" && -d "$candidate/hyprcursors" ]]; then
            compiled="$candidate"
            break
        fi
    done
    if [[ -z "$compiled" ]]; then
        rm -rf -- "$work_root"
        printf 'quickshell_cursor_theme.sh: compiled hyprcursor output is missing for %s.\\n' "$theme" >&2
        return 1
    fi

    cp -a -- "${compiled}/manifest.hl" "${theme_dir}/manifest.hl"
    rm -rf -- "${theme_dir}/hyprcursors"
    cp -a -- "${compiled}/hyprcursors" "${theme_dir}/hyprcursors"
    rm -rf -- "$work_root"
}
'''
replace_once(cursor, sync_marker, ensure_block, "hyprcursor conversion helper")

live_old = '''apply_live_settings() {
    local theme="$1"

    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface cursor-theme "$theme" >/dev/null 2>&1 || true
        gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" >/dev/null 2>&1 || true
    fi

    if command -v flatpak >/dev/null 2>&1; then
        flatpak override --user --env="GTK_CURSOR_THEME=${theme}" >/dev/null 2>&1 || true
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user set-environment "XCURSOR_THEME=${theme}" "XCURSOR_SIZE=${CURSOR_SIZE}" >/dev/null 2>&1 || true
    fi

    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        XCURSOR_THEME="$theme" XCURSOR_SIZE="$CURSOR_SIZE" \\
            dbus-update-activation-environment --systemd XCURSOR_THEME XCURSOR_SIZE >/dev/null 2>&1 || true
    fi

    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 || true
    fi
}
'''
live_new = '''apply_live_settings() {
    local theme="$1" hyprcursor_ready=0

    if ensure_hyprcursor_theme "$theme"; then
        hyprcursor_ready=1
    fi

    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface cursor-theme "$theme" >/dev/null 2>&1 || true
        gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" >/dev/null 2>&1 || true
    fi

    if command -v flatpak >/dev/null 2>&1; then
        flatpak override --user --env="GTK_CURSOR_THEME=${theme}" >/dev/null 2>&1 || true
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user set-environment "XCURSOR_THEME=${theme}" "XCURSOR_SIZE=${CURSOR_SIZE}" >/dev/null 2>&1 || true
    fi

    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        XCURSOR_THEME="$theme" XCURSOR_SIZE="$CURSOR_SIZE" \\
            dbus-update-activation-environment --systemd XCURSOR_THEME XCURSOR_SIZE >/dev/null 2>&1 || true
    fi

    if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        hyprctl reload >/dev/null 2>&1 || true
        if (( hyprcursor_ready == 0 )); then
            return 1
        fi
        if ! hyprctl setcursor "$theme" "$CURSOR_SIZE" >/dev/null 2>&1; then
            printf 'quickshell_cursor_theme.sh: Hyprland could not switch the compositor cursor to %s.\\n' "$theme" >&2
            return 1
        fi
    fi
}
'''
replace_once(cursor, live_old, live_new, "live cursor application")

# Explicitly apply the newly installed/default cursor during updates. Persisted
# file changes alone are not enough to change an already-running compositor.
runtime_marker = '''restart_hypridle_after_update() {
'''
runtime_function = '''reapply_cursor_theme_after_update() {
  local helper="${HOME_DIR}/.config/hypr/scripts/quickshell_cursor_theme.sh"
  [[ -f "$helper" && ! -L "$helper" ]] || return 0

  log "Applying saved Bibata cursor theme to the current session..."
  if ! run_target env \\
    "HOME=${HOME_DIR}" \\
    "USER=${TARGET_USER}" \\
    "XDG_CONFIG_HOME=${HOME_DIR}/.config" \\
    "XDG_CACHE_HOME=${HOME_DIR}/.cache" \\
    "XDG_DATA_HOME=${HOME_DIR}/.local/share" \\
    bash "$helper" reapply; then
    warn "Bibata cursor settings were saved, but the current Hyprland session could not be switched live."
  fi
}

restart_hypridle_after_update() {
'''
replace_once(runtime, runtime_marker, runtime_function, "cursor post-update helper")

runtime_call_old = '''  command -v hyprctl >/dev/null 2>&1 && run_target hyprctl reload >/dev/null 2>&1 || true
  restart_hypridle_after_update
'''
runtime_call_new = '''  command -v hyprctl >/dev/null 2>&1 && run_target hyprctl reload >/dev/null 2>&1 || true
  reapply_cursor_theme_after_update
  restart_hypridle_after_update
'''
replace_once(runtime, runtime_call_old, runtime_call_new, "cursor post-update invocation")

# Focused regression coverage for both runtime failures observed on the laptop.
test_old = '''CURSOR_QML="${ROOT}/config/quickshell/awtarchy/CursorThemeSettings.qml"
FLYOUT="${ROOT}/config/quickshell/awtarchy/FlyoutSettings.qml"
HYPR="${ROOT}/config/hypr/hyprland.lua"
'''
test_new = '''CURSOR_QML="${ROOT}/config/quickshell/awtarchy/CursorThemeSettings.qml"
FLYOUT="${ROOT}/config/quickshell/awtarchy/FlyoutSettings.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
HYPR="${ROOT}/config/hypr/hyprland.lua"
'''
replace_once(test, test_old, test_new, "Quick Settings test path")

test_ui_old = '''contains "$FLYOUT" 'cursorThemeSection.implicitHeight' \\
  'Quick Settings cursor selector height is not included in panel sizing'
contains "$CURSOR_QML" 'Ice / White' \\
'''
test_ui_new = '''contains "$FLYOUT" 'cursorThemeSection.implicitHeight' \\
  'Quick Settings cursor selector height is not included in panel sizing'
python3 - "$QUICK_SETTINGS" <<'PY_QS'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start = text.index('Layout.row: root.quickSettingsSectionRow("awtarchy")')
end = text.index('Layout.row: root.quickSettingsSectionRow("smtty")', start)
section = text[start:end]
if 'id: awtarchyCursorThemeSection' not in section or 'CursorThemeSettings {' not in section:
    raise SystemExit('FAIL: cursor selector is not embedded in the Awtarchy Quick Settings card')
PY_QS
contains "$CURSOR_QML" 'Ice / White' \\
'''
replace_once(test, test_ui_old, test_ui_new, "Awtarchy card cursor assertion")

test_static_old = '''contains "$CURSOR_SCRIPT" 'Bibata-Modern-Classic' \\
  'cursor helper does not map the Classic theme directory'
contains "$STATE_SCRIPT" 'set-cursor-theme' \\
'''
test_static_new = '''contains "$CURSOR_SCRIPT" 'Bibata-Modern-Classic' \\
  'cursor helper does not map the Classic theme directory'
contains "$CURSOR_SCRIPT" 'hyprcursor-util --extract' \\
  'cursor helper does not convert the installed XCursor theme for live Hyprland switching'
contains "$CURSOR_SCRIPT" 'hyprcursor-util --create' \\
  'cursor helper does not compile the converted Bibata hyprcursor theme'
contains "$CURSOR_SCRIPT" 'hyprctl setcursor "$theme" "$CURSOR_SIZE"' \\
  'cursor helper does not use Hyprland current-session cursor switching'
contains "$RUNTIME" 'reapply_cursor_theme_after_update' \\
  'updater does not reapply the cursor to the current session'
contains "$STATE_SCRIPT" 'set-cursor-theme' \\
'''
replace_once(test, test_static_old, test_static_new, "live-switch static assertions")

test_history_old = '''assert_history_current "$CURSOR_QML" '.config/quickshell/awtarchy/CursorThemeSettings.qml'
assert_history_current "$FLYOUT" '.config/quickshell/awtarchy/FlyoutSettings.qml'
'''
test_history_new = '''assert_history_current "$CURSOR_QML" '.config/quickshell/awtarchy/CursorThemeSettings.qml'
assert_history_current "$FLYOUT" '.config/quickshell/awtarchy/FlyoutSettings.qml'
assert_history_current "$QUICK_SETTINGS" '.config/quickshell/awtarchy/QuickSettings.qml'
'''
replace_once(test, test_history_old, test_history_new, "Quick Settings managed-history assertion")

test_dirs_old = '''  "$icon_root/Bibata-Modern-Ice/cursors" \\
  "$icon_root/Bibata-Modern-Classic/cursors" \\
  "$cursor_fakebin"
printf '%s\\n' ice >"$icon_root/Bibata-Modern-Ice/cursors/marker"
printf '%s\\n' classic >"$icon_root/Bibata-Modern-Classic/cursors/marker"
'''
test_dirs_new = '''  "$icon_root/Bibata-Modern-Ice/cursors" \\
  "$icon_root/Bibata-Modern-Ice/hyprcursors" \\
  "$icon_root/Bibata-Modern-Classic/cursors" \\
  "$icon_root/Bibata-Modern-Classic/hyprcursors" \\
  "$cursor_fakebin"
printf '%s\\n' ice >"$icon_root/Bibata-Modern-Ice/cursors/marker"
printf '%s\\n' classic >"$icon_root/Bibata-Modern-Classic/cursors/marker"
printf '%s\\n' 'name = Bibata-Modern-Ice' 'cursors_directory = hyprcursors' \\
  >"$icon_root/Bibata-Modern-Ice/manifest.hl"
printf '%s\\n' 'name = Bibata-Modern-Classic' 'cursors_directory = hyprcursors' \\
  >"$icon_root/Bibata-Modern-Classic/manifest.hl"
'''
replace_once(test, test_dirs_old, test_dirs_new, "hyprcursor test fixtures")

test_env_old = '''  AWTARCHY_CURSOR_ICON_ROOT="$icon_root"
  AWTARCHY_TEST_COMMAND_LOG="$command_log"
)
'''
test_env_new = '''  AWTARCHY_CURSOR_ICON_ROOT="$icon_root"
  AWTARCHY_TEST_COMMAND_LOG="$command_log"
  HYPRLAND_INSTANCE_SIGNATURE="test-instance"
)
'''
replace_once(test, test_env_old, test_env_new, "Hyprland test session")

test_live_old = '''contains "$command_log" 'hyprctl reload' \\
  'Hyprland was not reloaded after changing the persisted XCursor environment'

status="$(env "${cursor_env[@]}" "$CURSOR_SCRIPT" status)"
'''
test_live_new = '''contains "$command_log" 'hyprctl reload' \\
  'Hyprland was not reloaded after changing the persisted XCursor environment'
contains "$command_log" 'hyprctl setcursor Bibata-Modern-Classic 24' \\
  'Classic cursor was not switched in the current Hyprland session'

status="$(env "${cursor_env[@]}" "$CURSOR_SCRIPT" status)"
'''
replace_once(test, test_live_old, test_live_new, "current-session setcursor assertion")

# Append current managed hashes; historical entries stay intact for migrations.
entries = [
    (cursor, ".config/hypr/scripts/quickshell_cursor_theme.sh"),
    (quick, ".config/quickshell/awtarchy/QuickSettings.qml"),
]
history_text = history.read_text()
new_lines = []
for source, rel in entries:
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    line = f"{digest}\t{rel}"
    if line not in history_text.splitlines():
        new_lines.append(line)
if new_lines:
    if not history_text.endswith("\n"):
        history_text += "\n"
    history_text += "# 2026-09-08 Bibata current-session switching and Awtarchy-card selector follow-up.\n"
    history_text += "\n".join(new_lines) + "\n"
    history.write_text(history_text)

print("Applied Bibata live-cursor and Quick Settings follow-up.")
