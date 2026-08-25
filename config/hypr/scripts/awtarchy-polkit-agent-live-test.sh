#!/usr/bin/bash
# Install and live-test the root-owned Awtarchy terminal PolicyKit agent without
# permanently removing the existing polkit-gnome fallback.

set -u
set -o pipefail
IFS=$'\n\t'
umask 077
export PATH=/usr/bin:/bin

SCRIPT_PATH="$(/usr/bin/readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(/usr/bin/dirname -- "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"
SOURCE_DIR="${SCRIPT_DIR}/awtarchy-polkit-agent"
AGENT_SOURCE="${SOURCE_DIR}/agent.py"
TUI_SOURCE="${SOURCE_DIR}/tui.py"
TERMINAL_CONFIG_SOURCE="${SOURCE_DIR}/alacritty.toml"
LAUNCHER_SOURCE="${SOURCE_DIR}/launcher.sh"
SERVICE_SOURCE="${SOURCE_DIR}/awtarchy-polkit-agent.service"

RUNTIME_PARENT="/usr/local/libexec/awtarchy"
RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"
USER_UNIT_DIR="/usr/local/lib/systemd/user"
SERVICE_NAME="awtarchy-polkit-agent.service"
SERVICE_DEST="${USER_UNIT_DIR}/${SERVICE_NAME}"
GNOME_BIN="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"

GNOME_PIDS=()
STAGED_RUNTIME=""
PREVIOUS_RUNTIME=""
PREVIOUS_SERVICE=""

usage() {
    printf '%s\n' \
        'Usage: awtarchy-polkit-agent-live-test.sh <install|start|test|status|stop|restore-gnome>' \
        '' \
        '  install       Install the real terminal agent root-owned under /usr/local.' \
        '  start         Temporarily stop polkit-gnome and start the Awtarchy terminal agent.' \
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
    [[ -n ${WAYLAND_DISPLAY:-} && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -n ${XDG_SESSION_ID:-} ]] \
        || fail 'this command must run inside the active Hyprland/logind desktop session' || return 1
}

require_commands() {
    local path
    for path in \
        /usr/bin/alacritty \
        /usr/bin/bash \
        /usr/bin/chmod \
        /usr/bin/dirname \
        /usr/bin/find \
        /usr/bin/hyprctl \
        /usr/bin/install \
        /usr/bin/journalctl \
        /usr/bin/kill \
        /usr/bin/mktemp \
        /usr/bin/mv \
        /usr/bin/nohup \
        /usr/bin/pacman \
        /usr/bin/pgrep \
        /usr/bin/pkcheck \
        /usr/bin/pkexec \
        /usr/bin/python3 \
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

ensure_test_prerequisites() {
    local pkg
    local -a missing=()

    for pkg in polkit python-gobject; do
        /usr/bin/pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if ((${#missing[@]} > 0)); then
        note "Installing terminal PolicyKit test prerequisites: ${missing[*]}"
        /usr/bin/sudo /usr/bin/pacman -S --needed --noconfirm "${missing[@]}" \
            || fail 'could not install terminal PolicyKit test prerequisites' || return 1
    fi

    /usr/bin/python3 -I -c 'import gi; gi.require_version("Polkit", "1.0"); gi.require_version("PolkitAgent", "1.0"); from gi.repository import Gio, GLib, Polkit, PolkitAgent' \
        || fail 'PolicyKit Python bindings are unavailable after prerequisite installation' || return 1
}

verify_python_source() {
    local path="$1"
    /usr/bin/python3 - "$path" <<'PY'
import ast
from pathlib import Path
import sys

path = Path(sys.argv[1])
try:
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
except (OSError, SyntaxError, UnicodeError) as exc:
    print(f"Python source validation failed for {path}: {exc}", file=sys.stderr)
    raise SystemExit(1)
PY
}

verify_source_file() {
    local path="$1" type

    [[ -f $path && ! -L $path ]] || fail "missing or unsafe source file: $path" || return 1
    type="$(/usr/bin/stat -Lc '%F' -- "$path" 2>/dev/null)" || return 1
    [[ $type == 'regular file' ]] || fail "source is not a regular file: $path" || return 1
}

verify_sources() {
    verify_source_file "$AGENT_SOURCE" || return 1
    verify_source_file "$TUI_SOURCE" || return 1
    verify_source_file "$TERMINAL_CONFIG_SOURCE" || return 1
    verify_source_file "$LAUNCHER_SOURCE" || return 1
    verify_source_file "$SERVICE_SOURCE" || return 1

    /usr/bin/bash -n "$LAUNCHER_SOURCE" \
        || fail 'launcher source failed Bash syntax validation' || return 1
    verify_python_source "$AGENT_SOURCE" \
        || fail 'agent source failed Python syntax validation' || return 1
    verify_python_source "$TUI_SOURCE" \
        || fail 'TUI source failed Python syntax validation' || return 1
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
    verify_installed_file "${directory}/agent.py" 644 || return 1
    verify_installed_file "${directory}/alacritty.toml" 644 || return 1
    verify_installed_file "${directory}/launcher" 755 || return 1
    verify_installed_file "${directory}/tui.py" 644 || return 1

    actual="$(/usr/bin/sudo /usr/bin/find "$directory" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | /usr/bin/sort)" \
        || return 1
    expected=$'agent.py\nalacritty.toml\nlauncher\ntui.py'
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

    if ! /usr/bin/sudo /usr/bin/install -m 0644 -o root -g root -- "$AGENT_SOURCE" "${STAGED_RUNTIME}/agent.py" \
        || ! /usr/bin/sudo /usr/bin/install -m 0644 -o root -g root -- "$TUI_SOURCE" "${STAGED_RUNTIME}/tui.py" \
        || ! /usr/bin/sudo /usr/bin/install -m 0644 -o root -g root -- "$TERMINAL_CONFIG_SOURCE" "${STAGED_RUNTIME}/alacritty.toml" \
        || ! /usr/bin/sudo /usr/bin/install -m 0755 -o root -g root -- "$LAUNCHER_SOURCE" "${STAGED_RUNTIME}/launcher" \
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

restore_previous_runtime() {
    local failed=""

    if [[ -n ${PREVIOUS_RUNTIME:-} ]] && /usr/bin/sudo /usr/bin/test -e "$PREVIOUS_RUNTIME"; then
        if /usr/bin/sudo /usr/bin/test -e "$RUNTIME_DIR"; then
            failed="${RUNTIME_PARENT}/.polkit-agent.failed.${$}"
            /usr/bin/sudo /usr/bin/mv -Tf -- "$RUNTIME_DIR" "$failed" 2>/dev/null || true
        fi
        /usr/bin/sudo /usr/bin/mv -Tf -- "$PREVIOUS_RUNTIME" "$RUNTIME_DIR" 2>/dev/null || true
        PREVIOUS_RUNTIME=""
        [[ -z $failed ]] || /usr/bin/sudo /usr/bin/rm -rf --one-file-system -- "$failed" 2>/dev/null || true
    fi
}

replace_runtime_tree() {
    local stage="$1" previous=""

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
    PREVIOUS_RUNTIME="$previous"

    if ! verify_runtime_tree "$RUNTIME_DIR"; then
        restore_previous_runtime
        fail 'activated PolicyKit runtime failed verification; previous runtime restored'
        return 1
    fi
}

backup_service() {
    PREVIOUS_SERVICE=""
    if /usr/bin/sudo /usr/bin/test -L "$SERVICE_DEST"; then
        fail "refusing symbolic-link service destination: $SERVICE_DEST"
        return 1
    fi
    if /usr/bin/sudo /usr/bin/test -e "$SERVICE_DEST"; then
        [[ "$(/usr/bin/sudo /usr/bin/stat -Lc '%F' -- "$SERVICE_DEST")" == 'regular file' ]] \
            || fail "refusing non-regular service destination: $SERVICE_DEST" || return 1
        PREVIOUS_SERVICE="${USER_UNIT_DIR}/.awtarchy-polkit-agent.service.previous.${$}"
        /usr/bin/sudo /usr/bin/test ! -e "$PREVIOUS_SERVICE" || return 1
        /usr/bin/sudo /usr/bin/mv -Tf -- "$SERVICE_DEST" "$PREVIOUS_SERVICE" \
            || fail 'could not move previous PolicyKit service aside' || return 1
    fi
}

restore_previous_service() {
    if [[ -n ${PREVIOUS_SERVICE:-} ]] && /usr/bin/sudo /usr/bin/test -e "$PREVIOUS_SERVICE"; then
        /usr/bin/sudo /usr/bin/rm -f -- "$SERVICE_DEST" 2>/dev/null || true
        /usr/bin/sudo /usr/bin/mv -Tf -- "$PREVIOUS_SERVICE" "$SERVICE_DEST" 2>/dev/null || true
        PREVIOUS_SERVICE=""
    fi
}

install_service() {
    local temporary

    ensure_root_directory "$USER_UNIT_DIR" || return 1
    backup_service || return 1
    temporary="$(/usr/bin/sudo /usr/bin/mktemp "${USER_UNIT_DIR}/.awtarchy-polkit-agent.service.XXXXXX")" \
        || { restore_previous_service; return 1; }

    if ! /usr/bin/sudo /usr/bin/install -m 0644 -o root -g root -- "$SERVICE_SOURCE" "$temporary" \
        || ! /usr/bin/sudo /usr/bin/mv -Tf -- "$temporary" "$SERVICE_DEST";
    then
        /usr/bin/sudo /usr/bin/rm -f -- "$temporary" 2>/dev/null || true
        restore_previous_service
        fail 'could not install PolicyKit user service'
        return 1
    fi
}

commit_install_transaction() {
    [[ -z ${PREVIOUS_RUNTIME:-} ]] \
        || /usr/bin/sudo /usr/bin/rm -rf --one-file-system -- "$PREVIOUS_RUNTIME" || return 1
    [[ -z ${PREVIOUS_SERVICE:-} ]] \
        || /usr/bin/sudo /usr/bin/rm -f -- "$PREVIOUS_SERVICE" || return 1
    PREVIOUS_RUNTIME=""
    PREVIOUS_SERVICE=""
}

rollback_install_transaction() {
    restore_previous_service
    restore_previous_runtime
    /usr/bin/systemctl --user daemon-reload >/dev/null 2>&1 || true
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

    fail 'could not restore the GNOME PolicyKit authentication agent'
}

import_desktop_environment() {
    /usr/bin/systemctl --user import-environment \
        DISPLAY \
        WAYLAND_DISPLAY \
        HYPRLAND_INSTANCE_SIGNATURE \
        XDG_SESSION_ID \
        XDG_CURRENT_DESKTOP \
        XDG_SESSION_DESKTOP \
        XDG_SESSION_TYPE \
        LANG >/dev/null \
        || fail 'could not refresh the systemd user-manager desktop environment' || return 1
}

process_has_agent_command() {
    local root_pid="$1" expected_python child parent children_raw child_exe
    local -a queue=() children=() argv=()

    expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)" || return 1
    queue=("$root_pid")

    while ((${#queue[@]} > 0)); do
        parent="${queue[0]}"
        queue=("${queue[@]:1}")
        children_raw=""
        if [[ -r /proc/${parent}/task/${parent}/children ]]; then
            IFS= read -r children_raw <"/proc/${parent}/task/${parent}/children" || true
        fi
        children=()
        IFS=' ' read -r -a children <<<"$children_raw"
        for child in "${children[@]}"; do
            [[ $child =~ ^[1-9][0-9]*$ ]] || continue
            queue+=("$child")
            child_exe="$(/usr/bin/readlink -f -- "/proc/${child}/exe" 2>/dev/null)" || continue
            [[ $child_exe == "$expected_python" ]] || continue
            argv=()
            mapfile -d '' -t argv <"/proc/${child}/cmdline" 2>/dev/null || continue
            if [[ ${argv[0]:-} == /usr/bin/python3 \
                && ${argv[1]:-} == -I \
                && ${argv[2]:-} == "${RUNTIME_DIR}/agent.py" ]];
            then
                return 0
            fi
        done
    done

    return 1
}

verify_service_process() {
    local pid resolved expected_alacritty

    pid="$(/usr/bin/systemctl --user show -p MainPID --value "$SERVICE_NAME" 2>/dev/null)" || return 1
    [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
    expected_alacritty="$(/usr/bin/readlink -f -- /usr/bin/alacritty 2>/dev/null)" || return 1
    resolved="$(/usr/bin/readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || return 1
    [[ $resolved == "$expected_alacritty" ]] || return 1
    process_has_agent_command "$pid"
}

stop_awtarchy_agent() {
    /usr/bin/systemctl --user stop "$SERVICE_NAME" >/dev/null 2>&1 || true
}

show_startup_diagnostics() {
    local active substate result main_pid main_status restarts executable="unavailable"

    active="$(/usr/bin/systemctl --user show -p ActiveState --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"
    substate="$(/usr/bin/systemctl --user show -p SubState --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"
    result="$(/usr/bin/systemctl --user show -p Result --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"
    main_pid="$(/usr/bin/systemctl --user show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || printf '0')"
    main_status="$(/usr/bin/systemctl --user show -p ExecMainStatus --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"
    restarts="$(/usr/bin/systemctl --user show -p NRestarts --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"

    if [[ $main_pid =~ ^[1-9][0-9]*$ ]]; then
        executable="$(/usr/bin/readlink -f -- "/proc/${main_pid}/exe" 2>/dev/null || printf 'unavailable')"
    fi

    fail "startup diagnostics: ActiveState=${active:-unknown} SubState=${substate:-unknown} Result=${result:-unknown} MainPID=${main_pid:-0} ExecMainStatus=${main_status:-unknown} NRestarts=${restarts:-unknown}"
    fail "startup diagnostics: MainPID executable=${executable}"
    if [[ $main_pid =~ ^[1-9][0-9]*$ ]] && process_has_agent_command "$main_pid"; then
        fail 'startup diagnostics: Python agent child is present but full service verification failed'
    else
        fail 'startup diagnostics: Python agent child was not found under the service MainPID'
    fi

    /usr/bin/journalctl --user -u "$SERVICE_NAME" -b --no-pager -n 30 >&2 || true
}

rollback_to_gnome() {
    fail 'Awtarchy terminal PolicyKit agent failed; restoring polkit-gnome.'
    stop_awtarchy_agent
    start_gnome || fail 'automatic GNOME fallback also failed; start the GNOME agent manually'
}

start_awtarchy_agent() {
    local attempt restarts

    verify_installed_runtime || return 1
    import_desktop_environment || return 1
    stop_gnome || return 1

    if ! /usr/bin/systemctl --user start "$SERVICE_NAME"; then
        rollback_to_gnome
        return 1
    fi

    for attempt in {1..80}; do
        if /usr/bin/systemctl --user is-active --quiet "$SERVICE_NAME" \
            && verify_service_process;
        then
            break
        fi
        /usr/bin/sleep 0.10
    done

    if ! /usr/bin/systemctl --user is-active --quiet "$SERVICE_NAME" \
        || ! verify_service_process;
    then
        show_startup_diagnostics
        rollback_to_gnome
        return 1
    fi

    # Give registration/startup failures time to surface before declaring the
    # test agent stable.
    /usr/bin/sleep 1.5
    restarts="$(/usr/bin/systemctl --user show -p NRestarts --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"
    if [[ ! $restarts =~ ^[0-9]+$ || $restarts -ne 0 ]] || ! verify_service_process; then
        show_startup_diagnostics
        rollback_to_gnome
        return 1
    fi

    note 'Awtarchy terminal PolicyKit agent is running from the root-owned runtime.'
}

install_test_runtime() {
    require_normal_user || return 1
    require_commands || return 1
    verify_sources || return 1

    note 'Installing root-owned Awtarchy terminal PolicyKit test runtime...'
    stop_awtarchy_agent
    start_gnome || return 1

    /usr/bin/sudo -v || fail 'sudo authentication failed' || return 1
    ensure_test_prerequisites || return 1
    ensure_root_directory "$RUNTIME_PARENT" || return 1
    ensure_root_directory "$USER_UNIT_DIR" || return 1

    cleanup_staged_runtime
    stage_runtime_tree || return 1
    if ! replace_runtime_tree "$STAGED_RUNTIME"; then
        cleanup_staged_runtime
        return 1
    fi

    if ! install_service; then
        rollback_install_transaction
        return 1
    fi

    if ! /usr/bin/systemctl --user daemon-reload; then
        rollback_install_transaction
        return 1
    fi

    if ! verify_installed_runtime; then
        rollback_install_transaction
        fail 'installed terminal PolicyKit runtime failed verification'
        return 1
    fi

    commit_install_transaction || return 1
    note 'Root-owned terminal test runtime installed. polkit-gnome is still active.'
}

show_status() {
    local active main_pid restarts

    if /usr/bin/systemctl --user is-active --quiet "$SERVICE_NAME"; then
        active='active/running'
    else
        active='inactive'
    fi
    main_pid="$(/usr/bin/systemctl --user show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || printf '0')"
    restarts="$(/usr/bin/systemctl --user show -p NRestarts --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"
    printf 'Awtarchy terminal agent: %s  MainPID=%s  NRestarts=%s\n' "$active" "$main_pid" "$restarts"

    if gnome_is_active; then
        printf '%s\n' 'polkit-gnome: active'
    else
        printf '%s\n' 'polkit-gnome: inactive'
    fi

    if verify_installed_runtime >/dev/null 2>&1; then
        printf '%s\n' 'Root-owned Awtarchy runtime: verified'
    else
        printf '%s\n' 'Root-owned Awtarchy runtime: missing or invalid'
    fi

    if [[ $active == 'active/running' ]] && verify_service_process; then
        printf '%s\n' 'Process tree: verified Alacritty -> python3 -I agent.py'
    elif [[ $active == 'active/running' ]]; then
        printf '%s\n' 'Process tree: invalid'
    fi
}

trigger_test() {
    local rc=0

    require_normal_user || return 1
    require_commands || return 1

    if ! /usr/bin/systemctl --user is-active --quiet "$SERVICE_NAME"; then
        start_awtarchy_agent || return 1
    else
        verify_installed_runtime || return 1
        verify_service_process || {
            fail 'service is active but the Alacritty/Python agent process tree is invalid'
            return 1
        }
        gnome_is_active && {
            fail 'both Awtarchy and polkit-gnome appear active; refusing an ambiguous authentication test'
            return 1
        }
    fi

    /usr/bin/pkcheck --revoke-temp >/dev/null 2>&1 || true
    note 'Triggering a real harmless PolicyKit request: /usr/bin/true'
    note 'Enter your real password in the Awtarchy terminal authentication window.'

    /usr/bin/pkexec --disable-internal-agent /usr/bin/true || rc=$?
    case "$rc" in
        0)
            note 'Authentication completed successfully.'
            return 0
            ;;
        126)
            note 'Authentication was cancelled.'
            return 0
            ;;
        *)
            fail "pkexec authentication test failed with status $rc"
            return "$rc"
            ;;
    esac
}

restore_gnome() {
    stop_awtarchy_agent
    start_gnome || return 1
    note 'Awtarchy terminal agent stopped; polkit-gnome restored.'
}

main() {
    local action="${1:-}"

    case "$action" in
        install)
            (( $# == 1 )) || { usage; return 2; }
            install_test_runtime
            ;;
        start)
            (( $# == 1 )) || { usage; return 2; }
            require_normal_user || return 1
            require_commands || return 1
            note 'Starting the root-owned Awtarchy terminal PolicyKit agent...'
            start_awtarchy_agent
            ;;
        test)
            (( $# == 1 )) || { usage; return 2; }
            trigger_test
            ;;
        status)
            (( $# == 1 )) || { usage; return 2; }
            require_normal_user || return 1
            require_commands || return 1
            show_status
            ;;
        stop|restore-gnome)
            (( $# == 1 )) || { usage; return 2; }
            require_normal_user || return 1
            require_commands || return 1
            restore_gnome
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
