#!/usr/bin/bash
# Root-owned runtime launcher for the Awtarchy terminal PolicyKit agent.

set -euo pipefail
IFS=$'\n\t'
umask 077

RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"
AGENT="${RUNTIME_DIR}/agent.py"
TUI="${RUNTIME_DIR}/tui.py"
TERMINAL_CONFIG="${RUNTIME_DIR}/alacritty.toml"
LAUNCHER="${RUNTIME_DIR}/launcher"
ALACRITTY="/usr/bin/alacritty"
PYTHON="/usr/bin/python3"
HYPRCTL="/usr/bin/hyprctl"
SYSTEMD_CAT="/usr/bin/systemd-cat"
APP_ID="awtarchy-polkit-agent"

fail() {
    printf 'awtarchy-polkit-agent: %s\n' "$*" >&2
    return 1
}

verify_root_owned_directory() {
    local path="$1" uid mode type mode_value

    [[ -d $path && ! -L $path ]] || fail "unsafe runtime directory: $path" || return 1
    IFS=' ' read -r uid mode type < <(/usr/bin/stat -Lc '%u %a %F' -- "$path") || return 1
    [[ $uid == 0 && $type == directory ]] || fail "runtime directory must be root-owned: $path" || return 1

    mode_value=$((8#$mode))
    (( (mode_value & 0022) == 0 )) || fail "runtime directory is group/world writable: $path" || return 1
}

verify_root_owned_file() {
    local path="$1" expected_mode="$2" uid mode type mode_value

    [[ -f $path && ! -L $path ]] || fail "unsafe runtime file: $path" || return 1
    IFS=' ' read -r uid mode type < <(/usr/bin/stat -Lc '%u %a %F' -- "$path") || return 1
    [[ $uid == 0 && $type == 'regular file' ]] || fail "runtime file must be root-owned and regular: $path" || return 1
    [[ $mode == "$expected_mode" ]] || fail "unexpected runtime mode for $path: $mode" || return 1

    mode_value=$((8#$mode))
    (( (mode_value & 0022) == 0 )) || fail "runtime file is group/world writable: $path" || return 1
}

validated_account() {
    local account passwd_entry passwd_name passwd_uid passwd_home

    (( EUID != 0 )) || fail 'refusing to run the desktop authentication agent as root' || return 1

    account="$(/usr/bin/id -un)" || return 1
    passwd_entry="$(/usr/bin/getent passwd "$account")" || return 1
    IFS=: read -r passwd_name _ passwd_uid _ _ passwd_home _ <<<"$passwd_entry"

    [[ $passwd_name == "$account" && $passwd_uid =~ ^[0-9]+$ && $passwd_uid -eq EUID ]] \
        || fail 'could not validate the desktop account' || return 1
    [[ $passwd_home == /* && $passwd_home != / && -d $passwd_home && ! -L $passwd_home ]] \
        || fail 'could not validate the desktop home directory' || return 1

    printf '%s\t%s\n' "$account" "$passwd_home"
}

verify_system_binary() {
    local path="$1"
    [[ $path == /usr/bin/* && -x $path ]] \
        || fail "required system executable is unavailable: $path" || return 1
}

collect_appearance_options() {
    local config_path="$1" home_dir="$2"

    [[ -f $config_path ]] || return 0

    "$PYTHON" -I - "$config_path" "$home_dir" <<'PY'
# AWTARCHY_POLKIT_APPEARANCE_PY_BEGIN
from __future__ import annotations

import json
from pathlib import Path
import re
import sys
import tomllib

config_path = Path(sys.argv[1])
home = Path(sys.argv[2]).resolve()
MAX_BYTES = 2 * 1024 * 1024
MAX_DEPTH = 8
COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


def inside_home(path: Path) -> bool:
    try:
        path.relative_to(home)
        return True
    except ValueError:
        return False


def resolve_path(raw: str, relative_to: Path) -> Path | None:
    if raw.startswith("~/"):
        candidate = home / raw[2:]
    elif raw.startswith("/"):
        candidate = Path(raw)
    else:
        candidate = relative_to.parent / raw
    try:
        resolved = candidate.resolve(strict=True)
    except (OSError, RuntimeError):
        return None
    return resolved if inside_home(resolved) else None


def merge(dst: dict, src: dict) -> None:
    for key, value in src.items():
        if isinstance(value, dict) and isinstance(dst.get(key), dict):
            merge(dst[key], value)
        elif isinstance(value, dict):
            nested: dict = {}
            merge(nested, value)
            dst[key] = nested
        else:
            dst[key] = value


def load_config(path: Path, seen: set[Path], depth: int) -> dict:
    if depth > MAX_DEPTH or path in seen or not inside_home(path):
        return {}
    try:
        stat = path.stat()
        if not path.is_file() or stat.st_size > MAX_BYTES:
            return {}
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError):
        return {}

    seen.add(path)
    merged: dict = {}
    general = data.get("general")
    imports = general.get("import") if isinstance(general, dict) else None
    if isinstance(imports, list):
        for raw in imports:
            if not isinstance(raw, str) or len(raw) > 1024:
                continue
            imported = resolve_path(raw, path)
            if imported is not None:
                merge(merged, load_config(imported, seen, depth + 1))
    merge(merged, data)
    seen.remove(path)
    return merged


def emit(key: str, value) -> None:
    if isinstance(value, bool):
        print(f"{key}={'true' if value else 'false'}")
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        print(f"{key}={value}")
    elif isinstance(value, str):
        print(f"{key}={json.dumps(value, ensure_ascii=False)}")


def text_value(value, *, limit: int = 128) -> str | None:
    if not isinstance(value, str) or not value or len(value) > limit:
        return None
    if any(ord(char) < 0x20 for char in value):
        return None
    return value


def color_value(value) -> str | None:
    if not isinstance(value, str):
        return None
    if COLOR_RE.fullmatch(value):
        return value
    if value in {"CellForeground", "CellBackground"}:
        return value
    return None


try:
    root = config_path.resolve(strict=True)
except (OSError, RuntimeError):
    raise SystemExit(0)
if not inside_home(root):
    raise SystemExit(0)

config = load_config(root, set(), 0)

window = config.get("window") if isinstance(config.get("window"), dict) else {}
opacity = window.get("opacity")
if isinstance(opacity, (int, float)) and not isinstance(opacity, bool) and 0.0 <= float(opacity) <= 1.0:
    emit("window.opacity", opacity)
padding = window.get("padding") if isinstance(window.get("padding"), dict) else {}
for axis in ("x", "y"):
    value = padding.get(axis)
    if isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 256:
        emit(f"window.padding.{axis}", value)
if isinstance(window.get("dynamic_padding"), bool):
    emit("window.dynamic_padding", window["dynamic_padding"])
decorations = window.get("decorations")
if decorations in {"Full", "None", "Transparent", "Buttonless"}:
    emit("window.decorations", decorations)

font = config.get("font") if isinstance(config.get("font"), dict) else {}
font_size = font.get("size")
if isinstance(font_size, (int, float)) and not isinstance(font_size, bool) and 4.0 <= float(font_size) <= 72.0:
    emit("font.size", font_size)
for style_name in ("normal", "bold", "italic", "bold_italic"):
    style = font.get(style_name) if isinstance(font.get(style_name), dict) else {}
    for field in ("family", "style"):
        value = text_value(style.get(field))
        if value is not None:
            emit(f"font.{style_name}.{field}", value)
for offset_name in ("offset", "glyph_offset"):
    offset = font.get(offset_name) if isinstance(font.get(offset_name), dict) else {}
    for axis in ("x", "y"):
        value = offset.get(axis)
        if isinstance(value, int) and not isinstance(value, bool) and -64 <= value <= 64:
            emit(f"font.{offset_name}.{axis}", value)

colors = config.get("colors") if isinstance(config.get("colors"), dict) else {}
for boolean_key in ("transparent_background_colors", "draw_bold_text_with_bright_colors"):
    if isinstance(colors.get(boolean_key), bool):
        emit(f"colors.{boolean_key}", colors[boolean_key])

color_groups = {
    "primary": ("background", "foreground", "dim_foreground", "bright_foreground"),
    "normal": ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"),
    "bright": ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"),
    "dim": ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"),
    "cursor": ("text", "cursor"),
    "vi_mode_cursor": ("text", "cursor"),
    "selection": ("text", "background"),
}
for group_name, fields in color_groups.items():
    group = colors.get(group_name) if isinstance(colors.get(group_name), dict) else {}
    for field in fields:
        value = color_value(group.get(field))
        if value is not None:
            emit(f"colors.{group_name}.{field}", value)
# AWTARCHY_POLKIT_APPEARANCE_PY_END
PY
}

main() {
    local account_info account home_dir expected_runtime appearance_text option
    local wayland_display="${WAYLAND_DISPLAY:-}"
    local hypr_signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
    local session_id="${XDG_SESSION_ID:-}"
    local runtime_from_env="${XDG_RUNTIME_DIR:-}"
    local lang_value="${LANG:-C.UTF-8}"
    local -a appearance_args=()

    verify_system_binary "$ALACRITTY" || return 1
    verify_system_binary "$PYTHON" || return 1
    verify_system_binary "$HYPRCTL" || return 1
    verify_system_binary "$SYSTEMD_CAT" || return 1

    verify_root_owned_directory "$RUNTIME_DIR" || return 1
    verify_root_owned_file "$AGENT" 644 || return 1
    verify_root_owned_file "$TUI" 644 || return 1
    verify_root_owned_file "$TERMINAL_CONFIG" 644 || return 1
    verify_root_owned_file "$LAUNCHER" 755 || return 1

    account_info="$(validated_account)" || return 1
    IFS=$'\t' read -r account home_dir <<<"$account_info"

    expected_runtime="/run/user/${EUID}"
    [[ $runtime_from_env == "$expected_runtime" && -d $runtime_from_env && ! -L $runtime_from_env ]] \
        || fail "unexpected XDG_RUNTIME_DIR: ${runtime_from_env:-unset}" || return 1
    [[ -S ${expected_runtime}/bus ]] \
        || fail 'the current user D-Bus session is unavailable' || return 1
    [[ -n $wayland_display && $wayland_display != */* && $wayland_display != *$'\n'* ]] \
        || fail 'WAYLAND_DISPLAY is unavailable or invalid' || return 1
    [[ -n $hypr_signature && $hypr_signature != */* && $hypr_signature != *$'\n'* ]] \
        || fail 'HYPRLAND_INSTANCE_SIGNATURE is unavailable or invalid' || return 1
    [[ $session_id =~ ^[A-Za-z0-9_.:-]{1,128}$ ]] \
        || fail 'XDG_SESSION_ID is unavailable or invalid' || return 1

    # User-manager environment values must not alter Python imports, dynamic
    # libraries, terminal plugins, or PolicyKit debugging behavior.
    unset PYTHONPATH PYTHONHOME PYTHONSTARTUP PYTHONINSPECT PYTHONUSERBASE
    unset LD_PRELOAD LD_LIBRARY_PATH GTK_PATH GIO_EXTRA_MODULES GI_TYPELIB_PATH
    unset QT_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH POLKIT_DEBUG

    # Mirror only visual values from the user's current Alacritty config and its
    # imports. The trusted parser above whitelists appearance keys and emits
    # fixed-key --option overrides; shell commands, bindings, env and other
    # executable configuration never enter the authentication terminal.
    appearance_text="$(collect_appearance_options "${home_dir}/.config/alacritty/alacritty.toml" "$home_dir" 2>/dev/null || true)"
    if [[ -n $appearance_text ]]; then
        while IFS= read -r option; do
            [[ -n $option ]] || continue
            appearance_args+=(--option "$option")
        done <<<"$appearance_text"
    fi

    # Fail before Alacritty owns stderr so missing PyGObject/PolicyKit bindings
    # are visible in the systemd journal instead of flashing in a closing PTY.
    if ! /usr/bin/env -i \
        PATH=/usr/bin:/bin \
        LANG=C.UTF-8 \
        LC_ALL=C.UTF-8 \
        "$PYTHON" -I -c 'import gi; gi.require_version("Polkit", "1.0"); gi.require_version("PolkitAgent", "1.0"); from gi.repository import Gio, GLib, Polkit, PolkitAgent';
    then
        printf '%s\n' 'awtarchy-polkit-agent: PolicyKit Python bindings are unavailable; install polkit and python-gobject.' >&2
        return 78
    fi

    exec /usr/bin/env -i \
        HOME="$home_dir" \
        USER="$account" \
        LOGNAME="$account" \
        PATH=/usr/bin:/bin \
        LANG="$lang_value" \
        LC_ALL=C.UTF-8 \
        XDG_RUNTIME_DIR="$expected_runtime" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${expected_runtime}/bus" \
        WAYLAND_DISPLAY="$wayland_display" \
        HYPRLAND_INSTANCE_SIGNATURE="$hypr_signature" \
        XDG_SESSION_ID="$session_id" \
        XDG_CURRENT_DESKTOP=Hyprland \
        XDG_SESSION_DESKTOP=Hyprland \
        XDG_SESSION_TYPE=wayland \
        "$ALACRITTY" \
        --config-file "$TERMINAL_CONFIG" \
        "${appearance_args[@]}" \
        --class "$APP_ID,$APP_ID" \
        --title "$APP_ID" \
        -e "$SYSTEMD_CAT" \
        --identifier=awtarchy-polkit-agent \
        "$PYTHON" -I "$AGENT"
}

main "$@"
