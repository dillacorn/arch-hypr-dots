#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AGENT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/agent.py"
LAUNCHER="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"
CONTROLLER="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-live-test.sh"
HYPR="${ROOT_DIR}/config/hypr/hyprland.lua"
RUNTIME="${ROOT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

require_contains() {
    local file="$1" pattern="$2"
    grep -Fq -- "$pattern" "$file" || fail "$file missing: $pattern"
}

reject_contains() {
    local file="$1" pattern="$2"
    if grep -Fq -- "$pattern" "$file"; then
        fail "$file still contains: $pattern"
    fi
}

# A systemd --user service may not itself belong to the graphical logind
# session. Bind PolicyKit registration to the explicit session exported by the
# active Hyprland process instead of asking PolicyKit to infer it from the
# service/Python PID.
require_contains "$AGENT" 'session_id = os.environ.get("XDG_SESSION_ID", "")'
require_contains "$AGENT" 'self.subject = Polkit.UnixSession.new(session_id)'
reject_contains "$AGENT" 'Polkit.UnixSession.new_for_process_sync(os.getpid(), None)'

require_contains "$LAUNCHER" 'local session_id="${XDG_SESSION_ID:-}"'
require_contains "$LAUNCHER" 'XDG_SESSION_ID="$session_id"'

require_contains "$CONTROLLER" 'XDG_SESSION_ID'
require_contains "$CONTROLLER" 'systemctl --user import-environment'

require_contains "$HYPR" 'XDG_SESSION_ID'
require_contains "$HYPR" 'dbus-update-activation-environment --systemd'
require_contains "$HYPR" 'systemctl --user import-environment'

require_contains "$RUNTIME" 'XDG_SESSION_ID'

printf '%s\n' 'terminal Polkit graphical-session binding contract passed'
