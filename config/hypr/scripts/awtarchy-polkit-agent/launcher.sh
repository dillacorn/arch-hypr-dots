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

main() {
    local account_info account home_dir expected_runtime
    local wayland_display="${WAYLAND_DISPLAY:-}"
    local hypr_signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
    local session_id="${XDG_SESSION_ID:-}"
    local runtime_from_env="${XDG_RUNTIME_DIR:-}"
    local lang_value="${LANG:-C.UTF-8}"

    verify_system_binary "$ALACRITTY" || return 1
    verify_system_binary "$PYTHON" || return 1
    verify_system_binary "$HYPRCTL" || return 1

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
        --class "$APP_ID,$APP_ID" \
        --title "$APP_ID" \
        -e "$PYTHON" -I "$AGENT"
}

main "$@"
