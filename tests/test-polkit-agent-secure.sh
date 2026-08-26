#!/usr/bin/env bash
# Static/security contract for Awtarchy's headless PolicyKit backend and transient terminal.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_DIR="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent"
AGENT="${SOURCE_DIR}/agent.py"
TUI="${SOURCE_DIR}/tui.py"
TERMINAL_CONFIG="${SOURCE_DIR}/alacritty.toml"
LAUNCHER="${SOURCE_DIR}/launcher.sh"
SERVICE="${SOURCE_DIR}/awtarchy-polkit-agent.service"
QML="${SOURCE_DIR}/shell.qml"
GUARD="${SOURCE_DIR}/window-guard.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
require_file() { [[ -f $1 ]] || fail "missing $1"; }
require_contains() { local file="$1" pattern="$2"; grep -Fq -- "$pattern" "$file" || fail "$file missing: $pattern"; }
reject_regex() { local file="$1" pattern="$2"; ! grep -Eq -- "$pattern" "$file" || fail "$file contains forbidden regex: $pattern"; }

test_agent_contract() {
    require_file "$AGENT"
    /usr/bin/python3 -m py_compile "$AGENT"

    require_contains "$AGENT" 'gi.require_version("Polkit", "1.0")'
    require_contains "$AGENT" 'gi.require_version("PolkitAgent", "1.0")'
    require_contains "$AGENT" 'OBJECT_PATH = "/org/awtarchy/PolkitAgent"'
    require_contains "$AGENT" 'org.freedesktop.PolicyKit1.AuthenticationAgent'
    require_contains "$AGENT" 'register_authentication_agent_sync'
    require_contains "$AGENT" 'PolkitAgent.Session.new('
    require_contains "$AGENT" '.response(response)'
    require_contains "$AGENT" 'self.subject = Polkit.UnixSession.new(session_id)'
    reject_regex "$AGENT" 'Polkit\.UnixSession\.new_for_process(_sync)?'

    # The only credential transport outside PolkitAgent.Session is the per-request
    # anonymous inherited AF_UNIX/SOCK_SEQPACKET socketpair to the root-owned TUI.
    require_contains "$AGENT" 'socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)'
    require_contains "$AGENT" 'pass_fds=(child_fd,)'
    require_contains "$AGENT" 'close_fds=True'
    require_contains "$AGENT" 'if packet_type == "submit":'
    require_contains "$AGENT" 'response = packet.get("response")'
    require_contains "$AGENT" 'MAX_RESPONSE_BYTES = 4096'
    reject_regex "$AGENT" '\.bind\(|\.listen\(|AF_INET|AF_INET6|/tmp/.*(password|response)|sudo[[:space:]]+-S'
    reject_regex "$AGENT" 'print\([^\n]*(password|response)|logging\.[a-z]+\([^\n]*(password|response)'
    reject_regex "$AGENT" 'open\([^\n]*(password|response)|write_text\([^\n]*(password|response)'
    reject_regex "$AGENT" 'env\[[^]]+\][[:space:]]*=.*response|command.*response'

    # Persistent backend must remain headless.
    reject_regex "$AGENT" 'from tui import TerminalUI|self\.ui[[:space:]]*=[[:space:]]*TerminalUI|os\.open\("/dev/tty"'
}

test_tui_contract() {
    require_file "$TUI"
    /usr/bin/python3 -m py_compile "$TUI"

    require_contains "$TUI" 'APP_ID = "awtarchy-polkit-agent"'
    require_contains "$TUI" 'WINDOW_WIDTH = 900'
    require_contains "$TUI" 'WINDOW_HEIGHT = 520'
    require_contains "$TUI" 'socket.SOCK_SEQPACKET'
    require_contains "$TUI" 'def send_packet('
    require_contains "$TUI" 'def recv_packet('
    require_contains "$TUI" 'def run_frontend(ipc_fd: int) -> int:'
    require_contains "$TUI" 'on_submit=lambda response: frontend_send({"type": "submit", "response": response})'
    require_contains "$TUI" 'os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)'
    require_contains "$TUI" 'MOUSE_ENABLE = b"\x1b[?1000h\x1b[?1006h"'
    require_contains "$TUI" 'NORMAL_CLEAR = b"\x1b[3J\x1b[2J\x1b[H"'
    require_contains "$TUI" 'SPINNER_FRAMES = ('
    require_contains "$TUI" 'Authentication Required'
    require_contains "$TUI" '[ Cancel ]'
    require_contains "$TUI" '[ Authenticate ]'
    reject_regex "$TUI" 'HIDDEN_WORKSPACE|special:awtarchy-polkit-agent|sudo[[:space:]]+-S|/tmp/.*password'
}

test_launcher_contract() {
    require_file "$LAUNCHER"
    bash -n "$LAUNCHER"
    require_contains "$LAUNCHER" 'RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"'
    require_contains "$LAUNCHER" '/usr/bin/python3'
    require_contains "$LAUNCHER" '/usr/bin/env -i'
    require_contains "$LAUNCHER" 'PYTHONPATH'
    require_contains "$LAUNCHER" 'PYTHONHOME'
    require_contains "$LAUNCHER" 'LD_PRELOAD'
    require_contains "$LAUNCHER" 'LD_LIBRARY_PATH'
    require_contains "$LAUNCHER" 'stat -Lc'
    require_contains "$LAUNCHER" '! -L $path'
    require_contains "$LAUNCHER" 'AWTARCHY_POLKIT_ALACRITTY_OPTIONS="$appearance_text"'
    require_contains "$LAUNCHER" '"$PYTHON" -I "$AGENT"'
    require_contains "$LAUNCHER" 'XDG_SESSION_ID="$session_id"'
    require_contains "$LAUNCHER" 'gi.require_version("Polkit", "1.0")'
    require_contains "$LAUNCHER" 'PolicyKit Python bindings are unavailable'
    reject_regex "$LAUNCHER" '/usr/bin/quickshell|shell\.qml'
    reject_regex "$LAUNCHER" '(^|[^[:alnum:]_])eval([[:space:]]|$)'
}

test_terminal_config_contract() {
    require_file "$TERMINAL_CONFIG"
    require_contains "$TERMINAL_CONFIG" '[window]'
    require_contains "$TERMINAL_CONFIG" '[font]'
}

test_service_contract() {
    require_file "$SERVICE"
    require_contains "$SERVICE" 'ExecStart=/usr/local/libexec/awtarchy/polkit-agent/launcher'
    require_contains "$SERVICE" 'Restart=on-failure'
    require_contains "$SERVICE" 'RestartPreventExitStatus=78'
    reject_regex "$SERVICE" '%h/|HOME=|EnvironmentFile=|WantedBy=default.target'
}

[[ ! -e $QML && ! -L $QML ]] || fail "obsolete QML authentication runtime still exists: $QML"
[[ ! -e $GUARD && ! -L $GUARD ]] || fail "obsolete Quickshell window guard still exists: $GUARD"
test_agent_contract
test_tui_contract
test_launcher_contract
test_terminal_config_contract
test_service_contract

printf '%s\n' 'secure headless/transient Polkit agent tests passed'
