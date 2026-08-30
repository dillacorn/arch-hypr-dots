#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("config/hypr/scripts/quickshell_floating_windows.sh")
history_path = Path("local/share/awtarchy/quickshell-managed-history.sha256")
text = path.read_text()
old = r'''notify=0
case "${1:-}" in
    status)
        [[ $# -eq 1 ]] || die 'usage: quickshell_floating_windows.sh status'
        emit_state "$(current_state)" 0
        ;;
    set)
        if [[ $# -eq 3 && "${3:-}" == '--notify' ]]; then
            notify=1
        elif [[ $# -ne 2 ]]; then
            die 'usage: quickshell_floating_windows.sh set on|off [--notify]'
        fi
        emit_state "$(set_state "$2")" "$notify"
        ;;
    toggle)
        if [[ $# -eq 2 && "${2:-}" == '--notify' ]]; then
            notify=1
        elif [[ $# -ne 1 ]]; then
            die 'usage: quickshell_floating_windows.sh toggle [--notify]'
        fi
        if [[ "$(current_state)" == 'enabled' ]]; then
            emit_state "$(set_state off)" "$notify"
        else
            emit_state "$(set_state on)" "$notify"
        fi
        ;;
    *)
        die 'usage: quickshell_floating_windows.sh status | set on|off [--notify] | toggle [--notify]'
        ;;
esac
'''
new = r'''notify=0
state=''
current=''
case "${1:-}" in
    status)
        [[ $# -eq 1 ]] || die 'usage: quickshell_floating_windows.sh status'
        state="$(current_state)" || exit $?
        emit_state "$state" 0
        ;;
    set)
        if [[ $# -eq 3 && "${3:-}" == '--notify' ]]; then
            notify=1
        elif [[ $# -ne 2 ]]; then
            die 'usage: quickshell_floating_windows.sh set on|off [--notify]'
        fi
        state="$(set_state "$2")" || exit $?
        emit_state "$state" "$notify"
        ;;
    toggle)
        if [[ $# -eq 2 && "${2:-}" == '--notify' ]]; then
            notify=1
        elif [[ $# -ne 1 ]]; then
            die 'usage: quickshell_floating_windows.sh toggle [--notify]'
        fi
        current="$(current_state)" || exit $?
        if [[ "$current" == 'enabled' ]]; then
            state="$(set_state off)" || exit $?
        else
            state="$(set_state on)" || exit $?
        fi
        emit_state "$state" "$notify"
        ;;
    *)
        die 'usage: quickshell_floating_windows.sh status | set on|off [--notify] | toggle [--notify]'
        ;;
esac
'''
if text.count(old) != 1:
    raise SystemExit("expected one generated floating helper CLI block")
path.write_text(text.replace(old, new, 1))

digest = hashlib.sha256(path.read_bytes()).hexdigest()
entry = f"{digest}\t.config/hypr/scripts/quickshell_floating_windows.sh"
history = history_path.read_text()
if entry not in history.splitlines():
    if history and not history.endswith("\n"):
        history += "\n"
    history += entry + "\n"
    history_path.write_text(history)
