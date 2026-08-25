#!/usr/bin/bash
# Install and live-test the root-owned Awtarchy PolicyKit agent without
# permanently replacing the existing polkit-gnome autostart.

set -u
set -o pipefail
IFS=$'\n\t'
umask 077
export PATH=/usr/bin:/bin

SCRIPT_PATH="$(/usr/bin/readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(/usr/bin/dirname -- "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"
SOURCE_DIR="${SCRIPT_DIR}/awtarchy-polkit-agent"
SHELL_SOURCE="${SOURCE_DIR}/shell.qml"
LAUNCHER_SOURCE="${SOURCE_DIR}/launcher.sh"
GUARD_SOURCE="${SOURCE_DIR}/window-guard.sh"
SERVICE_SOURCE="${SOURCE_DIR}/awtarchy-polkit-agent.service"

RUNTIME_PARENT="/usr/local/libexec/awtarchy"
RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"
USER_UNIT_DIR="/usr/local/lib/systemd/user"
SERVICE_NAME="awtarchy-polkit-agent.service"
SERVICE_DEST="${USER_UNIT_DIR}/${SERVICE_NAME}"
GNOME_BIN="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"

GNOME_PIDS=()
STAGED_RUNTIME=""

usage() {
    printf '%s\n' \
        'Usage: awtarchy-polkit-agent-live-test.sh <install|start|test|status|stop|restore-gnome>' \
        '' \
        '  install       Install the real agent root-owned under /usr/local.' \
        '  start         Temporarily stop polkit-gnome and start the Awtarchy agent.' \
        '  test          Trigger a real harmless pkexec /usr/bin/true authentication.' \
        '  status        Show Awtarchy and GNOME agent state.' \
        '  stop          Stop the Awtarchy agent and restore polkit-gnome.' \
        '  restore-gnome Stop the Awtarchy agent and restore polkit-gnome.' \
        '' \
        'This testing controller does not enable the service, uninstall polkit-gnome,' \
        'or modify Hyprland autostart.'
}

note() {
    printf '%s\n' "$*"
}

fail() {
    printf 'awtarchy-polkit-agent-live-test: %s\n' "$*" >&2
    return 1
}

require_normal_user() {
    (( EUID != 0 )) || fail 'run this as your normal desktop user, not with sudo' || return 1
    [[ -n ${XDG_RUNTIME_DIR:-} && ${XDG_RUNTIME_DIR} == "/run/user/${EUID}" ]] \
        || fail 'XDG_RUNTIME_DIR does not match the current desktop user' || return 1
    [[ -S ${XDG_RUNTIME_DIR}/bus ]] \
        || fail 'the current systemd/D-Bus user session is unavailable' || return 1
}

require_commands() {
    local path
    for path in \
        /usr/bin/bash \
        /usr/bin/chmod \
        /usr/bin/dirname \
        /usr/bin/find \
        /usr/bin/install \
        /usr/bin/kill \
        /usr/bin/mktemp \
        /usr/bin/mv \
        /usr/bin/nohup \
        /usr/bin/pgrep \
        /usr/bin/pkcheck \
        /usr/bin/pkexec \
        /usr/bin/readlink \
        /usr/bin/rm \
        /usr/bin/sleep \
        /usr/bin/sort \
        /usr/bin/stat \
        /usr/bin/sudo \
        /usr/bin/systemctl \
        /usr/bin/test
    do
        [[ -x $path ]] || fail "required executable is unavailable: $path" || return 1
    done
}

verify_source_file() {
    local path="$1" type

    [[ -f $path && ! -L $path ]] || fail "missing or unsafe source file: $path" || return 1
    type="$(/usr/bin/stat -Lc '%F' -- "$path" 2>/dev/null)" || return 1
    [[ $type == 'regular file' ]] || fail "source is not a regular file: $path" || return 1
}

verify_sources() {
    verify_source_file "$SHELL_SOURCE" || return 1
    verify_source_file "$LAUNCHER_SOURCE" || return 1
    verify_source_file "$GUARD_SOURCE" || return 1
    verify_source_file "$SERVICE_SOURCE" || return 1

    /usr/bin/bash -n "$LAUNCHER_SOURCE" \
        || fail 'launcher source failed Bash syntax validation' || return 1
    /usr/bin/bash -n "$GUARD_SOURCE" \
        || fail 'window guard source failed Bash syntax validation' || return 1
}

verify_root_directory() {
    local path="$1" uid mode type mode_value

    /usr/bin/sudo /usr/bin/test -d "$path" \
        && ! /usr/bin/sudo /usr/bin/test -L "$path" \
        || fail "missing or unsafe root-owned directory: $path" || return 1

    IFS=' ' read -r uid mode type < <(/usr/bin/sudo /usr/bin/stat -Lc '%u %a %F' -- "$path") || return 1
    [[ $uid == 0 && $type == directory ]] \
        || fail "directory is not root-owned: $path" || return 1

    mode_value=$((8#$mode))
    (( (mode_value & 0022) == 0 )) \
        || fail "root-owned directory is group/world writable: $path" || return 1
}

verify_installed_file() {
    local path="$1" expected_mode="$2" uid mode type

    /usr/bin/sudo /usr/bin/test -f "$path" \
        && ! /usr/bin/sudo /usr/bin/test -L "$path" \
        || fail "missing or unsafe installed file: $path" || return 1

    IFS=' ' read -r uid mode type < <(/usr/bin/sudo /usr/bin/stat -Lc '%u %a %F' -- "$path") || return 1
    [[ $uid == 0 && $mode == "$expected_mode" && $type == 'regular file' ]] \
        || fail "unexpected owner/mode/type for installed file: $path" || return 1
}

verify_runtime_tree() {
    local directory="$1" actual expected

    verify_root_directory "$directory" || return 1
    verify_installed_file "${directory}/shell.qml" 644 || return 1
    verify_installed_file "${directory}/launcher" 755 || return 1
    verify_installed_file "${directory}/window-guard.sh" 755 || return 1

    actual="$(/usr/bin/sudo /usr/bin/find "$directory" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | /usr/bin/sort)" \
        || return 1
    expected=$'launcher\nshell.qml\nwindow-guard.sh'
    [[ $actual == "$expected" ]] \
        || fail "runtime contains unexpected entries: $directory" || return 1
}

verify_installed_runtime() {
    verify_runtime_tree "$RUNTIME_DIR" || return 1
    verify_root_directory "$USER_UNIT_DIR" || return 1
    verify_installed_file "$SERVICE_DEST" 644 || return 1
}

ensure_root_directory() {
    local path="$1"

    if /usr/bin/sudo /usr/bin/test -L "$path"; then
        fail "refusing symbolic-link system directory: $path"
        return 1
    fi

    if /usr/bin/sudo /usr/bin/test -e "$path"; then
        verify_root_directory "$path"
        return $?
    fi

    /usr/bin/sudo /usr/bin/install -d -m 0755 -o root -g root -- "$path" \
        || fail "could not create root-owned directory: $path" || return 1
    verify_root_directory "$path"
}

install_atomic() {
    local source="$1" destination="$2" mode="$3" directory basename temporary

    directory="$(/usr/bin/dirname -- "$destination")"
    basename="${destination##*/}"

    if /usr/bin/sudo /usr/bin/test -L "$destination"; then
        fail "refusing symbolic-link destination: $destination"
        return 1
    fi
    if /usr/bin/sudo /usr/bin/test -e "$destination"; then
        local existing_type
        existing_type="$(/usr/bin/sudo /usr/bin/stat -Lc '%F' -- "$destination")" || return 1
        [[ $existing_type == 'regular file' ]] \
            || fail "refusing non-regular destination: $destination" || return 1
    fi

    temporary="$(/usr/bin/sudo /usr/bin/mktemp "${directory}/.${basename}.awtarchy.XXXXXX")" \
        || fail "could not create temporary file in $directory" || return 1

    case "$mode" in
        0644)
            if ! /usr/bin/sudo /usr/bin/install -m 0644 -o root -g root -- "$source" "$temporary"; then
                /usr/bin/sudo /usr/bin/rm -f -- "$temporary" 2>/dev/null || true
                fail "could not stage $destination"
                return 1
            fi
            ;;
        0755)
            if ! /usr/bin/sudo /usr/bin/install -m 0755 -o root -g root -- "$source" "$temporary"; then
                /usr/bin/sudo /usr/bin/rm -f -- "$temporary" 2>/dev/null || true
                fail "could not stage $destination"
                return 1
            fi
            ;;
        *)
            /usr/bin/sudo /usr/bin/rm -f -- "$temporary" 2>/dev/null || true
            fail "unsupported install mode: $mode"
            return 1
            ;;
    esac

    if ! /usr/bin/sudo /usr/bin/mv -Tf -- "$temporary" "$destination"; then
        /usr/bin/sudo /usr/bin/rm -f -- "$temporary" 2>/dev/null || true
        fail "could not atomically install $destination"
        return 1
    fi
}

cleanup_staged_runtime() {
    if [[ -n ${STAGED_RUNTIME:-} ]]; then
        /usr/bin/sudo /usr/bin/rm -rf --one-file-system -- "$STAGED_RUNTIME" 2>/dev/null || true
        STAGED_RUNTIME=""
    fi
}

stage_runtime_tree() {
    ensure_root_directory "$RUNTIME_PARENT" || return 1

    STAGED_RUNTIME="$(/usr/bin/sudo /usr/bin/mktemp -d "${RUNTIME_PARENT}/.polkit-agent.stage.XXXXXX")" \
        || fail 'could not create root-owned runtime staging directory' || return 1

    if ! /usr/bin/sudo /usr/bin/install -m 0644 -o root -g root -- "$SHELL_SOURCE" "${STAGED_RUNTIME}/shell.qml" \
        || ! /usr/bin/sudo /usr/bin/install -m 0755 -o root -g root -- "$LAUNCHER_SOURCE" "${STAGED_RUNTIME}/launcher" \
        || ! /usr/bin/sudo /usr/bin/install -m 0755 -o root -g root -- "$GUARD_SOURCE" "${STAGED_RUNTIME}/window-guard.sh" \
        || ! /usr/bin/sudo /usr/bin/chmod 0755 -- "$STAGED_RUNTIME";
    then
        cleanup_staged_runtime
        fail 'could not build the root-owned PolicyKit runtime staging tree'
        return 1
    fi

    verify_runtime_tree "$STAGED_RUNTIME" || {
        cleanup_staged_runtime
        return 1
    }
}

replace_runtime_tree() {
    local stage="$1" previous="" failed=""

    [[ -n $stage ]] || fail 'runtime staging path is empty' || return 1
    verify_runtime_tree "$stage" || return 1

    if /usr/bin/sudo /usr/bin/test -L "$RUNTIME_DIR"; then
        fail "refusing symbolic-link runtime destination: $RUNTIME_DIR"
        return 1
    fi

    if /usr/bin/sudo /usr/bin/test -e "$RUNTIME_DIR"; then
        [[ "$(/usr/bin/sudo /usr/bin/stat -Lc '%F' -- "$RUNTIME_DIR")" == directory ]] \
            || fail "refusing non-directory runtime destination: $RUNTIME_DIR" || return 1

        previous="${RUNTIME_PARENT}/.polkit-agent.previous.${$}"
        /usr/bin/sudo /usr/bin/test ! -e "$previous" \
            || fail "temporary previous-runtime path already exists: $previous" || return 1

        /usr/bin/sudo /usr/bin/mv -Tf -- "$RUNTIME_DIR" "$previous" \
            || fail 'could not move the previous PolicyKit runtime aside' || return 1
    fi

    if ! /usr/bin/sudo /usr/bin/mv -Tf -- "$stage" "$RUNTIME_DIR"; then
        if [[ -n $previous ]]; then
            /usr/bin/sudo /usr/bin/mv -Tf -- "$previous" "$RUNTIME_DIR" 2>/dev/null || true
        fi
        fail 'could not activate the staged PolicyKit runtime'
        return 1
    fi
    STAGED_RUNTIME=""

    if ! verify_runtime_tree "$RUNTIME_DIR"; then
        failed="${RUNTIME_PARENT}/.polkit-agent.failed.${$}"
        /usr/bin/sudo /usr/bin/mv -Tf -- "$RUNTIME_DIR" "$failed" 2>/dev/null || true
        if [[ -n $previous ]]; then
            /usr/bin/sudo /usr/bin/mv -Tf -- "$previous" "$RUNTIME_DIR" 2>/dev/null || true
        fi
        /usr/bin/sudo /usr/bin/rm -rf --one-file-system -- "$failed" 2>/dev/null || true
        fail 'activated PolicyKit runtime failed verification; previous runtime restored'
        return 1
    fi

    if [[ -n $previous ]]; then
        /usr/bin/sudo /usr/bin/rm -rf --one-file-system -- "$previous" \
            || fail 'new runtime is active, but the previous test runtime could not be removed' || return 1
    fi
}

get_gnome_pids() {
    local pid resolved
    GNOME_PIDS=()

    while IFS= read -r pid; do
        [[ $pid =~ ^[1-9][0-9]*$ ]] || continue
        resolved="$(/usr/bin/readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || continue
        [[ $resolved == "$GNOME_BIN" ]] || continue
        GNOME_PIDS+=("$pid")
    done < <(/usr/bin/pgrep -u "$UID" -f -- "$GNOME_BIN" 2>/dev/null || true)
}

gnome_is_active() {
    get_gnome_pids
    ((${#GNOME_PIDS[@]} > 0))
}

stop_gnome() {
    local attempt pid

    get_gnome_pids
    ((${#GNOME_PIDS[@]} == 0)) && return 0

    for pid in "${GNOME_PIDS[@]}"; do
        /usr/bin/kill -TERM -- "$pid" 2>/dev/null || true
    done

    for attempt in {1..50}; do
        get_gnome_pids
        ((${#GNOME_PIDS[@]} == 0)) && return 0
        /usr/bin/sleep 0.05
    done

    get_gnome_pids
    for pid in "${GNOME_PIDS[@]}"; do
        /usr/bin/kill -KILL -- "$pid" 2>/dev/null || true
    done

    for attempt in {1..20}; do
        get_gnome_pids
        ((${#GNOME_PIDS[@]} == 0)) && return 0
        /usr/bin/sleep 0.05
    done

    fail 'could not stop the exact polkit-gnome agent process'
}

start_gnome() {
    local attempt

    gnome_is_active && return 0
    [[ -x $GNOME_BIN && -f $GNOME_BIN && ! -L $GNOME_BIN ]] \
        || fail "GNOME PolicyKit agent executable is unavailable or unsafe: $GNOME_BIN" || return 1

    /usr/bin/nohup "$GNOME_BIN" </dev/null >/dev/null 2>&1 &

    for attempt in {1..60}; do
        gnome_is_active && return 0
        /usr/bin/sleep 0.05
    done

    fail 'polkit-gnome did not become active'
}

restore_gnome() {
    /usr/bin/systemctl --user stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    start_gnome
}

rollback_to_gnome() {
    note 'Awtarchy agent did not reach a stable registered state. Restoring polkit-gnome.' >&2
    restore_gnome || fail 'automatic GNOME PolicyKit restoration failed'
}

install_runtime() {
    require_normal_user || return 1
    require_commands || return 1
    verify_sources || return 1

    /usr/bin/systemctl --user stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    start_gnome || return 1

    note 'Installing root-owned Awtarchy PolicyKit test runtime...'
    /usr/bin/sudo -v || fail 'sudo authentication failed; nothing was installed' || return 1

    ensure_root_directory "$RUNTIME_PARENT" || return 1
    ensure_root_directory "$USER_UNIT_DIR" || return 1

    stage_runtime_tree || return 1
    replace_runtime_tree "$STAGED_RUNTIME" || {
        cleanup_staged_runtime
        return 1
    }

    install_atomic "$SERVICE_SOURCE" "$SERVICE_DEST" 0644 || return 1
    verify_installed_runtime || return 1

    /usr/bin/systemctl --user daemon-reload \
        || fail 'systemd user-manager reload failed' || return 1

    note 'Root-owned test runtime installed. polkit-gnome is still active.'
}

import_desktop_environment() {
    [[ -n ${WAYLAND_DISPLAY:-} && ${WAYLAND_DISPLAY} != */* ]] \
        || fail 'WAYLAND_DISPLAY is unavailable or invalid' || return 1
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && ${HYPRLAND_INSTANCE_SIGNATURE} != */* ]] \
        || fail 'HYPRLAND_INSTANCE_SIGNATURE is unavailable or invalid' || return 1

    /usr/bin/systemctl --user import-environment \
        WAYLAND_DISPLAY \
        HYPRLAND_INSTANCE_SIGNATURE \
        XDG_CURRENT_DESKTOP \
        XDG_SESSION_TYPE >/dev/null \
        || fail 'could not refresh the systemd user-manager desktop environment' || return 1
}

verify_service_process() {
    local pid resolved

    pid="$(/usr/bin/systemctl --user show -p MainPID --value "$SERVICE_NAME" 2>/dev/null)" || return 1
    [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
    resolved="$(/usr/bin/readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || return 1
    [[ $resolved == /usr/bin/quickshell ]]
}

start_awtarchy_agent() {
    local attempt restarts

    require_normal_user || return 1
    require_commands || return 1
    verify_installed_runtime || {
        fail 'secure runtime is not installed; run the install action first'
        return 1
    }
    import_desktop_environment || return 1

    /usr/bin/systemctl --user stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    /usr/bin/systemctl --user reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true

    stop_gnome || return 1

    note 'Starting the root-owned Awtarchy PolicyKit agent...'
    if ! /usr/bin/systemctl --user start "$SERVICE_NAME"; then
        rollback_to_gnome
        return 1
    fi

    for attempt in {1..25}; do
        if ! /usr/bin/systemctl --user is-active --quiet "$SERVICE_NAME"; then
            rollback_to_gnome
            return 1
        fi
        /usr/bin/sleep 0.20
    done

    restarts="$(/usr/bin/systemctl --user show -p NRestarts --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"
    if [[ ! $restarts =~ ^[0-9]+$ || $restarts -ne 0 ]] || ! verify_service_process; then
        rollback_to_gnome
        return 1
    fi

    note 'Awtarchy PolicyKit agent is running from the root-owned runtime.'
}

run_real_test() {
    local status=0

    if ! /usr/bin/systemctl --user is-active --quiet "$SERVICE_NAME"; then
        start_awtarchy_agent || return 1
    else
        verify_installed_runtime || return 1
        verify_service_process || {
            fail 'service is active but the main process is not /usr/bin/quickshell'
            return 1
        }
    fi

    /usr/bin/pkcheck --revoke-temp >/dev/null 2>&1 || true

    note 'Triggering a real harmless PolicyKit request: /usr/bin/true'
    note 'You may enter your real password in the Awtarchy authentication window.'

    if /usr/bin/pkexec --disable-internal-agent /usr/bin/true; then
        status=0
    else
        status=$?
    fi

    case "$status" in
        0)
            note 'Authentication completed successfully.'
            ;;
        126)
            note 'Authentication was cancelled.'
            ;;
        *)
            fail "pkexec test failed with status $status"
            return "$status"
            ;;
    esac
}

show_status() {
    local active substate pid restarts

    active="$(/usr/bin/systemctl --user show -p ActiveState --value "$SERVICE_NAME" 2>/dev/null || printf 'not-loaded')"
    substate="$(/usr/bin/systemctl --user show -p SubState --value "$SERVICE_NAME" 2>/dev/null || printf 'not-loaded')"
    pid="$(/usr/bin/systemctl --user show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || printf '0')"
    restarts="$(/usr/bin/systemctl --user show -p NRestarts --value "$SERVICE_NAME" 2>/dev/null || printf '0')"

    printf 'Awtarchy agent: %s/%s  MainPID=%s  NRestarts=%s\n' "$active" "$substate" "$pid" "$restarts"

    get_gnome_pids
    if ((${#GNOME_PIDS[@]} > 0)); then
        printf 'polkit-gnome: active  PID(s):'
        printf ' %s' "${GNOME_PIDS[@]}"
        printf '\n'
    else
        printf '%s\n' 'polkit-gnome: inactive'
    fi

    if verify_installed_runtime 2>/dev/null; then
        printf '%s\n' 'Root-owned Awtarchy runtime: verified'
    else
        printf '%s\n' 'Root-owned Awtarchy runtime: missing or failed verification'
    fi
}

stop_and_restore() {
    note 'Stopping the Awtarchy PolicyKit agent and restoring polkit-gnome...'
    restore_gnome || return 1
    note 'polkit-gnome is active again.'
}

main() {
    local action="${1:-}"

    if (($# != 1)); then
        usage >&2
        return 2
    fi

    case "$action" in
        install)
            install_runtime
            ;;
        start)
            start_awtarchy_agent
            ;;
        test)
            run_real_test
            ;;
        status)
            require_normal_user || return 1
            require_commands || return 1
            show_status
            ;;
        stop|restore-gnome)
            require_normal_user || return 1
            require_commands || return 1
            stop_and_restore
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            usage >&2
            fail "unknown action: $action"
            return 2
            ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
