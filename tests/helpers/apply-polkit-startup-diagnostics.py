#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


agent = Path("config/hypr/scripts/awtarchy-polkit-agent/agent.py")
controller = Path("config/hypr/scripts/awtarchy-polkit-agent-live-test.sh")

replace_once(
    agent,
    'PKACTION = "/usr/bin/pkaction"\nSESSION_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")',
    'PKACTION = "/usr/bin/pkaction"\nSYSTEMD_CAT = "/usr/bin/systemd-cat"\nSESSION_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")',
    "agent journald binary",
)

replace_once(
    agent,
    '\n\nclass TerminalPolkitAgent:\n',
    '''\n\ndef journal_message(priority: str, message: str) -> None:\n    """Write non-secret startup diagnostics to the user journal."""\n    try:\n        subprocess.run(\n            [\n                SYSTEMD_CAT,\n                "--identifier=awtarchy-polkit-agent",\n                f"--priority={priority}",\n            ],\n            input=f"{message}\\n",\n            text=True,\n            stdout=subprocess.DEVNULL,\n            stderr=subprocess.DEVNULL,\n            env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},\n            timeout=2.0,\n            check=False,\n        )\n    except (OSError, subprocess.SubprocessError):\n        pass\n\n\nclass TerminalPolkitAgent:\n''',
    "agent journald helper",
)

replace_once(
    agent,
    '        self.registered = True\n\n        # Alacritty is already mapped',
    '        self.registered = True\n        journal_message("info", "startup: PolicyKit authentication agent registered")\n\n        # Alacritty is already mapped',
    "agent registration readiness log",
)

replace_once(
    agent,
    '        self.ui.prime_hidden()\n\n        conditions =',
    '        self.ui.prime_hidden()\n        journal_message("info", "startup: authentication terminal hidden and ready")\n\n        conditions =',
    "agent terminal readiness log",
)

replace_once(
    agent,
    '''    except (GLib.Error, OSError, RuntimeError) as exc:\n        print(f"awtarchy-polkit-agent: {exc}", file=sys.stderr)\n        return 78\n''',
    '''    except Exception as exc:\n        message = f"fatal startup: {type(exc).__name__}: {exc}"\n        journal_message("err", message)\n        print(f"awtarchy-polkit-agent: {message}", file=sys.stderr)\n        return 78\n''',
    "agent fatal startup logging",
)

replace_once(
    controller,
    '        /usr/bin/install \\\n        /usr/bin/kill \\\n',
    '        /usr/bin/install \\\n        /usr/bin/journalctl \\\n        /usr/bin/kill \\\n',
    "controller journalctl prerequisite",
)

replace_once(
    controller,
    '''stop_awtarchy_agent() {\n    /usr/bin/systemctl --user stop "$SERVICE_NAME" >/dev/null 2>&1 || true\n}\n\nrollback_to_gnome() {\n''',
    '''stop_awtarchy_agent() {\n    /usr/bin/systemctl --user stop "$SERVICE_NAME" >/dev/null 2>&1 || true\n}\n\nshow_startup_diagnostics() {\n    local active substate result main_pid main_status restarts executable="unavailable"\n\n    active="$(/usr/bin/systemctl --user show -p ActiveState --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"\n    substate="$(/usr/bin/systemctl --user show -p SubState --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"\n    result="$(/usr/bin/systemctl --user show -p Result --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"\n    main_pid="$(/usr/bin/systemctl --user show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || printf '0')"\n    main_status="$(/usr/bin/systemctl --user show -p ExecMainStatus --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"\n    restarts="$(/usr/bin/systemctl --user show -p NRestarts --value "$SERVICE_NAME" 2>/dev/null || printf 'unknown')"\n\n    if [[ $main_pid =~ ^[1-9][0-9]*$ ]]; then\n        executable="$(/usr/bin/readlink -f -- "/proc/${main_pid}/exe" 2>/dev/null || printf 'unavailable')"\n    fi\n\n    fail "startup diagnostics: ActiveState=${active:-unknown} SubState=${substate:-unknown} Result=${result:-unknown} MainPID=${main_pid:-0} ExecMainStatus=${main_status:-unknown} NRestarts=${restarts:-unknown}"\n    fail "startup diagnostics: MainPID executable=${executable}"\n    if [[ $main_pid =~ ^[1-9][0-9]*$ ]] && process_has_agent_command "$main_pid"; then\n        fail 'startup diagnostics: Python agent child is present but full service verification failed'\n    else\n        fail 'startup diagnostics: Python agent child was not found under the service MainPID'\n    fi\n\n    /usr/bin/journalctl --user -u "$SERVICE_NAME" -b --no-pager -n 30 >&2 || true\n}\n\nrollback_to_gnome() {\n''',
    "controller startup diagnostics function",
)

replace_once(
    controller,
    '''    if ! /usr/bin/systemctl --user is-active --quiet "$SERVICE_NAME" \\\n        || ! verify_service_process;\n    then\n        rollback_to_gnome\n        return 1\n    fi\n''',
    '''    if ! /usr/bin/systemctl --user is-active --quiet "$SERVICE_NAME" \\\n        || ! verify_service_process;\n    then\n        show_startup_diagnostics\n        rollback_to_gnome\n        return 1\n    fi\n''',
    "controller initial startup failure diagnostics",
)

replace_once(
    controller,
    '''    if [[ ! $restarts =~ ^[0-9]+$ || $restarts -ne 0 ]] || ! verify_service_process; then\n        rollback_to_gnome\n        return 1\n    fi\n''',
    '''    if [[ ! $restarts =~ ^[0-9]+$ || $restarts -ne 0 ]] || ! verify_service_process; then\n        show_startup_diagnostics\n        rollback_to_gnome\n        return 1\n    fi\n''',
    "controller stability failure diagnostics",
)
