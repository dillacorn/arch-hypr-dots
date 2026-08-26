#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def sub_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    new, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: expected one regex match, found {count}")
    path.write_text(new, encoding="utf-8")


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected exactly one literal match")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


live = ROOT / "config/hypr/scripts/awtarchy-polkit-agent-live-test.sh"
sub_once(
    live,
    r"process_has_agent_command\(\) \{.*?\n\}\n\nverify_service_process\(\) \{.*?\n\}\n\n(?=stop_awtarchy_agent\(\))",
    r'''verify_service_process() {
    local pid resolved expected_python
    local -a argv=()

    pid="$(/usr/bin/systemctl --user show -p MainPID --value "$SERVICE_NAME" 2>/dev/null)" || return 1
    [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
    expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)" || return 1
    resolved="$(/usr/bin/readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || return 1
    [[ $resolved == "$expected_python" ]] || return 1
    mapfile -d '' -t argv <"/proc/${pid}/cmdline" 2>/dev/null || return 1
    [[ ${argv[0]:-} == /usr/bin/python3 \
        && ${argv[1]:-} == -I \
        && ${argv[2]:-} == "${RUNTIME_DIR}/agent.py" ]]
}

frontend_process_exists() {
    local proc pid resolved expected_alacritty i
    local -a argv=()

    expected_alacritty="$(/usr/bin/readlink -f -- /usr/bin/alacritty 2>/dev/null)" || return 1
    for proc in /proc/[0-9]*; do
        pid="${proc##*/}"
        [[ -r ${proc}/status && -r ${proc}/cmdline ]] || continue
        [[ "$(/usr/bin/awk '/^Uid:/{print $2; exit}' "${proc}/status" 2>/dev/null)" == "$UID" ]] || continue
        resolved="$(/usr/bin/readlink -f -- "${proc}/exe" 2>/dev/null)" || continue
        [[ $resolved == "$expected_alacritty" ]] || continue
        argv=()
        mapfile -d '' -t argv <"${proc}/cmdline" 2>/dev/null || continue
        for ((i = 0; i + 1 < ${#argv[@]}; i++)); do
            if [[ ${argv[i]} == --class && ${argv[i + 1]} == awtarchy-polkit-agent,awtarchy-polkit-agent ]]; then
                return 0
            fi
        done
    done
    return 1
}

verify_no_idle_frontend() {
    ! frontend_process_exists
}

wait_for_frontend_exit() {
    local attempt
    for attempt in {1..80}; do
        verify_no_idle_frontend && return 0
        /usr/bin/sleep 0.05
    done
    fail 'transient authentication terminal remained alive after the PolicyKit request'
}

''',
)
replace_once(
    live,
    """    if [[ $main_pid =~ ^[1-9][0-9]*$ ]] && process_has_agent_command "$main_pid"; then
        fail 'startup diagnostics: Python agent child is present but full service verification failed'
    else
        fail 'startup diagnostics: Python agent child was not found under the service MainPID'
    fi
""",
    """    if [[ $main_pid =~ ^[1-9][0-9]*$ ]] && verify_service_process; then
        fail 'startup diagnostics: headless Python backend is present but another startup check failed'
    else
        fail 'startup diagnostics: headless Python backend MainPID verification failed'
    fi
""",
)
replace_once(
    live,
    """    if [[ ! $restarts =~ ^[0-9]+$ || $restarts -ne 0 ]] || ! verify_service_process; then
        show_startup_diagnostics
        rollback_to_gnome
        return 1
    fi

    note 'Awtarchy terminal PolicyKit agent is running from the root-owned runtime.'
""",
    """    if [[ ! $restarts =~ ^[0-9]+$ || $restarts -ne 0 ]] || ! verify_service_process || ! verify_no_idle_frontend; then
        show_startup_diagnostics
        rollback_to_gnome
        return 1
    fi

    note 'Awtarchy PolicyKit backend is running headless from the root-owned runtime.'
""",
)
replace_once(
    live,
    """    if [[ $active == 'active/running' ]] && verify_service_process; then
        printf '%s\\n' 'Process tree: verified Alacritty -> python3 -I agent.py'
    elif [[ $active == 'active/running' ]]; then
        printf '%s\\n' 'Process tree: invalid'
    fi
""",
    """    if [[ $active == 'active/running' ]] && verify_service_process; then
        printf '%s\\n' 'Process: verified headless python3 -I agent.py'
        if verify_no_idle_frontend; then
            printf '%s\\n' 'Idle authentication terminal: absent'
        else
            printf '%s\\n' 'Idle authentication terminal: unexpectedly present'
        fi
    elif [[ $active == 'active/running' ]]; then
        printf '%s\\n' 'Process: invalid'
    fi
""",
)
replace_once(
    live,
    """        verify_service_process || {
            fail 'service is active but the Alacritty/Python agent process tree is invalid'
            return 1
        }
""",
    """        verify_service_process || {
            fail 'service is active but the headless Python agent process is invalid'
            return 1
        }
""",
)
replace_once(
    live,
    """    /usr/bin/pkexec --disable-internal-agent /usr/bin/true || rc=$?
    case "$rc" in
""",
    """    /usr/bin/pkexec --disable-internal-agent /usr/bin/true || rc=$?
    wait_for_frontend_exit || return 1
    verify_service_process || fail 'headless PolicyKit backend stopped after authentication' || return 1
    case "$rc" in
""",
)

runtime = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
sub_once(
    runtime,
    r"awtarchy_polkit_verify_service_process\(\) \{.*?\n\}\n",
    r'''awtarchy_polkit_verify_service_process() {
  local pid resolved expected_python
  local -a argv=()
  pid="$(awtarchy_polkit_user_command /usr/bin/systemctl --user show -p MainPID --value "$AWTARCHY_POLKIT_SERVICE_NAME" 2>/dev/null)" || return 1
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)" || return 1
  resolved="$(/usr/bin/readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || return 1
  [[ "$resolved" == "$expected_python" ]] || return 1
  mapfile -d '' -t argv <"/proc/${pid}/cmdline" 2>/dev/null || return 1
  [[ "${argv[0]:-}" == /usr/bin/python3 \
    && "${argv[1]:-}" == -I \
    && "${argv[2]:-}" == "${AWTARCHY_POLKIT_RUNTIME_DIR}/agent.py" ]]
}
''',
)

bar = ROOT / "config/quickshell/awtarchy/Bar.qml"
sub_once(
    bar,
    r"\n    function internalServiceWindow\(toplevel\) \{.*?\n    \}\n\n    function scratchpadCount\(\) \{.*?\n    \}\n",
    '''
    function scratchpadCount() {
        return Hyprland.toplevels.values.filter(toplevel =>
            toplevel.workspace && toplevel.workspace.id < 0).length;
    }
''',
)
