#!/usr/bin/env bash
# Static/security contract for the real terminal Awtarchy PolicyKit agent.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_DIR="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent"
AGENT="${SOURCE_DIR}/agent.py"
TUI="${SOURCE_DIR}/tui.py"
TERMINAL_CONFIG="${SOURCE_DIR}/alacritty.toml"
LAUNCHER="${SOURCE_DIR}/launcher.sh"
SERVICE="${SOURCE_DIR}/awtarchy-polkit-agent.service"
CONTROLLER="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-live-test.sh"
QML="${SOURCE_DIR}/shell.qml"
GUARD="${SOURCE_DIR}/window-guard.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

require_file() {
    [[ -f $1 ]] || fail "missing $1"
}

require_contains() {
    local file="$1" pattern="$2"
    grep -Fq -- "$pattern" "$file" || fail "$file missing: $pattern"
}

require_regex() {
    local file="$1" pattern="$2"
    grep -Eq -- "$pattern" "$file" || fail "$file missing regex: $pattern"
}

reject_regex() {
    local file="$1" pattern="$2"
    if grep -Eq -- "$pattern" "$file"; then
        fail "$file contains forbidden regex: $pattern"
    fi
}

test_agent_contract() {
    require_file "$AGENT"
    /usr/bin/python3 -m py_compile "$AGENT"

    require_contains "$AGENT" 'gi.require_version("Polkit", "1.0")'
    require_contains "$AGENT" 'gi.require_version("PolkitAgent", "1.0")'
    require_contains "$AGENT" 'from gi.repository import Gio, GLib, Polkit, PolkitAgent'
    require_contains "$AGENT" 'OBJECT_PATH = "/org/awtarchy/PolkitAgent"'
    require_contains "$AGENT" 'org.freedesktop.PolicyKit1.AuthenticationAgent'
    require_contains "$AGENT" 'register_object('
    require_contains "$AGENT" 'session_id = os.environ.get("XDG_SESSION_ID", "")'
    require_contains "$AGENT" 'self.subject = Polkit.UnixSession.new(session_id)'
    reject_regex "$AGENT" 'Polkit\.UnixSession\.new_for_process(_sync)?'
    require_contains "$AGENT" 'register_authentication_agent_sync'
    require_contains "$AGENT" 'PolkitAgent.Session.new('
    require_contains "$AGENT" '.connect("request"'
    require_contains "$AGENT" '.connect("show-info"'
    require_contains "$AGENT" '.connect("show-error"'
    require_contains "$AGENT" '.connect("completed"'
    require_contains "$AGENT" '.response(response)'
    require_contains "$AGENT" '.cancel()'

    # Credentials must never leave the PolicyKit session conversation through
    # logs, argv, temporary files, shell helpers, or custom IPC.
    reject_regex "$AGENT" 'sudo[[:space:]]+-S|pkexec.*(password|response)|/tmp/.*(password|response)|socket\.|AF_UNIX|subprocess.*(password|response)'
    reject_regex "$AGENT" 'print\([^\n]*(password|response)|logging\.[a-z]+\([^\n]*(password|response)'
    reject_regex "$AGENT" 'open\([^\n]*(password|response)|write_text\([^\n]*(password|response)'
}

test_tui_contract() {
    require_file "$TUI"
    /usr/bin/python3 -m py_compile "$TUI"

    require_contains "$TUI" 'APP_ID = "awtarchy-polkit-agent"'
    require_contains "$TUI" 'WINDOW_WIDTH = 900'
    require_contains "$TUI" 'WINDOW_HEIGHT = 520'
    require_contains "$TUI" 'HIDDEN_WORKSPACE = "special:awtarchy-polkit-agent"'
    require_contains "$TUI" 'MOUSE_ENABLE = b"\x1b[?1000h\x1b[?1006h"'
    require_contains "$TUI" 'MOUSE_DISABLE = b"\x1b[?1000l\x1b[?1006l"'
    require_contains "$TUI" 'def parse_sgr_mouse('
    require_contains "$TUI" 'def render_password_field_only('
    require_contains "$TUI" 'Password not entered.'
    require_contains "$TUI" '/usr/bin/hyprctl'
    require_contains "$TUI" 'Authentication Required'
    require_contains "$TUI" '[ Cancel ]'
    require_contains "$TUI" '[ Authenticate ]'

    reject_regex "$TUI" 'password[[:space:]]*=.*(log|print)|/tmp/.*password|sudo[[:space:]]+-S'
}

test_launcher_contract() {
    require_file "$LAUNCHER"
    bash -n "$LAUNCHER"
    require_contains "$LAUNCHER" 'RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"'
    require_contains "$LAUNCHER" '/usr/bin/alacritty'
    require_contains "$LAUNCHER" '/usr/bin/python3'
    require_contains "$LAUNCHER" '/usr/bin/hyprctl'
    require_contains "$LAUNCHER" '/usr/bin/env -i'
    require_contains "$LAUNCHER" 'PYTHONPATH'
    require_contains "$LAUNCHER" 'PYTHONHOME'
    require_contains "$LAUNCHER" 'LD_PRELOAD'
    require_contains "$LAUNCHER" 'LD_LIBRARY_PATH'
    require_contains "$LAUNCHER" 'stat -Lc'
    require_contains "$LAUNCHER" '! -L $path'
    require_contains "$LAUNCHER" '--config-file'
    require_contains "$LAUNCHER" '--class'
    require_contains "$LAUNCHER" '-I'
    require_contains "$LAUNCHER" 'local session_id="${XDG_SESSION_ID:-}"'
    require_contains "$LAUNCHER" 'XDG_SESSION_ID="$session_id"'
    require_contains "$LAUNCHER" 'gi.require_version("Polkit", "1.0")'
    require_contains "$LAUNCHER" 'gi.require_version("PolkitAgent", "1.0")'
    require_contains "$LAUNCHER" 'PolicyKit Python bindings are unavailable'
    reject_regex "$LAUNCHER" '/usr/bin/quickshell|quickshell[[:space:]].*--config|shell\.qml'
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

test_controller_contract() {
    require_file "$CONTROLLER"
    bash -n "$CONTROLLER"
    require_contains "$CONTROLLER" 'RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"'
    require_contains "$CONTROLLER" 'USER_UNIT_DIR="/usr/local/lib/systemd/user"'
    require_contains "$CONTROLLER" 'GNOME_BIN="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"'
    require_contains "$CONTROLLER" 'install -m 0644 -o root -g root'
    require_contains "$CONTROLLER" 'install -m 0755 -o root -g root'
    require_contains "$CONTROLLER" 'systemctl --user daemon-reload'
    require_contains "$CONTROLLER" 'systemctl --user start "$SERVICE_NAME"'
    require_contains "$CONTROLLER" 'XDG_SESSION_ID'
    require_contains "$CONTROLLER" 'restore_gnome'
    require_contains "$CONTROLLER" '/usr/bin/pkcheck --revoke-temp'
    require_contains "$CONTROLLER" '/usr/bin/pkexec --disable-internal-agent /usr/bin/true'
    require_contains "$CONTROLLER" '/usr/bin/readlink -f -- "/proc/${pid}/exe"'
    require_contains "$CONTROLLER" 'verify_installed_runtime'
    require_contains "$CONTROLLER" 'rollback_to_gnome'
    require_contains "$CONTROLLER" '/usr/bin/alacritty'
    require_contains "$CONTROLLER" '/usr/bin/python3'
    require_contains "$CONTROLLER" 'ensure_test_prerequisites'
    require_contains "$CONTROLLER" 'python-gobject'
    require_contains "$CONTROLLER" '/usr/bin/pacman -S --needed --noconfirm'

    # Testing must not uninstall GNOME or rewrite permanent Hyprland autostart.
    reject_regex "$CONTROLLER" 'pacman[[:space:]].*-R|hyprland\.lua|sed[[:space:]].*polkit-gnome'
}

[[ ! -e $QML && ! -L $QML ]] || fail "obsolete QML authentication runtime still exists: $QML"
[[ ! -e $GUARD && ! -L $GUARD ]] || fail "obsolete Quickshell window guard still exists: $GUARD"

test_agent_contract
test_tui_contract
test_launcher_contract
test_terminal_config_contract
test_service_contract
test_controller_contract

printf '%s\n' 'secure terminal Polkit agent static/security tests passed'
