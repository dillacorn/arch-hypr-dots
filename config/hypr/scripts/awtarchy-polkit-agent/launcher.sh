#!/usr/bin/bash
# Root-owned runtime launcher for the Awtarchy PolicyKit agent.

set -euo pipefail
IFS=$'\n\t'
umask 077

RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"
SHELL_QML="${RUNTIME_DIR}/shell.qml"
GUARD="${RUNTIME_DIR}/window-guard.sh"
QUICKSHELL="/usr/bin/quickshell"

fail() {
    printf 'awtarchy-polkit-agent: %s\n' "$*" >&2
    return 1
}

verify_root_owned_directory() {
    local path="$1" uid mode type mode_value

    [[ -d $path && ! -L $path ]] || fail "unsafe runtime directory: $path" || return 1
    read -r uid mode type < <(/usr/bin/stat -Lc '%u %a %F' -- "$path") || return 1
    [[ $uid == 0 && $type == directory ]] || fail "runtime directory must be root-owned: $path" || return 1

    mode_value=$((8#$mode))
    (( (mode_value & 0022) == 0 )) || fail "runtime directory is group/world writable: $path" || return 1
}

verify_root_owned_file() {
    local path="$1" uid mode type mode_value

    [[ -f $path && ! -L $path ]] || fail "unsafe runtime file: $path" || return 1
    read -r uid mode type < <(/usr/bin/stat -Lc '%u %a %F' -- "$path") || return 1
    [[ $uid == 0 && $type == 'regular file' ]] || fail "runtime file must be root-owned and regular: $path" || return 1

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

main() {
    local account_info account home_dir runtime_dir expected_runtime
    local wayland_display="${WAYLAND_DISPLAY:-}"
    local hypr_signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
    local runtime_from_env="${XDG_RUNTIME_DIR:-}"
    local lang_value="${LANG:-C.UTF-8}"

    [[ -x $QUICKSHELL && -f $QUICKSHELL && ! -L $QUICKSHELL ]] \
        || fail "Quickshell executable is unavailable or unsafe: $QUICKSHELL" || return 1

    verify_root_owned_directory "$RUNTIME_DIR" || return 1
    verify_root_owned_file "$SHELL_QML" || return 1
    verify_root_owned_file "$GUARD" || return 1
    verify_root_owned_file "${RUNTIME_DIR}/launcher" || return 1

    account_info="$(validated_account)" || return 1
    IFS=$'\t' read -r account home_dir <<<"$account_info"

    expected_runtime="/run/user/${EUID}"
    [[ $runtime_from_env == "$expected_runtime" && -d $runtime_from_env && ! -L $runtime_from_env ]] \
        || fail "unexpected XDG_RUNTIME_DIR: ${runtime_from_env:-unset}" || return 1
    [[ -n $wayland_display && $wayland_display != */* ]] \
        || fail 'WAYLAND_DISPLAY is unavailable or invalid' || return 1
    [[ -n $hypr_signature && $hypr_signature != */* ]] \
        || fail 'HYPRLAND_INSTANCE_SIGNATURE is unavailable or invalid' || return 1

    # Do not allow a user-manager environment injection to alter QML/plugin/library
    # resolution or enable Polkit credential debugging in this process.
    unset QML2_IMPORT_PATH QML_IMPORT_PATH QT_PLUGIN_PATH LD_PRELOAD LD_LIBRARY_PATH POLKIT_DEBUG
    unset QS_CONFIG_PATH QS_CONFIG_NAME QS_APP_ID

    /usr/bin/bash "$GUARD" >/dev/null 2>&1 &

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
        XDG_CURRENT_DESKTOP=Hyprland \
        XDG_SESSION_DESKTOP=Hyprland \
        XDG_SESSION_TYPE=wayland \
        QT_QPA_PLATFORM=wayland \
        QS_DISABLE_FILE_WATCHER=1 \
        QS_DISABLE_CRASH_HANDLER=1 \
        "$QUICKSHELL" -n -p "$RUNTIME_DIR"
}

main "$@"
