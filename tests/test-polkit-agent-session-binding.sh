#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AGENT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/agent.py"
LAUNCHER="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"
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

require_contains "$HYPR" 'XDG_SESSION_ID'
require_contains "$HYPR" 'dbus-update-activation-environment --systemd'
require_contains "$HYPR" 'systemctl --user import-environment'

require_contains "$RUNTIME" 'XDG_SESSION_ID'

# Update/reset commands can run after privilege transitions that no longer carry
# the graphical shell environment. Recover the allowlisted session variables
# from the target user's systemd manager before deciding that no live Hyprland
# session exists. Recovered values must be exported so later updater children,
# including hyprctl reload, inherit the same live-session environment.
require_contains "$RUNTIME" 'awtarchy_polkit_recover_session_environment()'
require_contains "$RUNTIME" '/usr/bin/systemctl --user show-environment'
require_contains "$RUNTIME" 'awtarchy_polkit_recover_session_environment || return 2'
require_contains "$RUNTIME" 'export WAYLAND_DISPLAY="$value"'
require_contains "$RUNTIME" 'export HYPRLAND_INSTANCE_SIGNATURE="$value"'
require_contains "$RUNTIME" 'export XDG_SESSION_ID="$value"'
require_contains "$RUNTIME" 'export XDG_CURRENT_DESKTOP="$value"'
require_contains "$RUNTIME" 'export XDG_SESSION_DESKTOP="$value"'
require_contains "$RUNTIME" 'export XDG_SESSION_TYPE="$value"'

printf '%s\n' 'terminal Polkit graphical-session binding contract passed'
