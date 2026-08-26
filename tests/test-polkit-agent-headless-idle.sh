#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
AGENT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/agent.py"
BAR="${ROOT_DIR}/config/quickshell/awtarchy/Bar.qml"
HYPR="${ROOT_DIR}/config/hypr/hyprland.lua"

fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 still contains: $2"; }

require_contains "$RUNTIME" 'expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)"'
require_contains "$RUNTIME" '[[ "$resolved" == "$expected_python" ]] || return 1'
reject_contains "$RUNTIME" '[[ "$resolved" == "$expected_alacritty" ]] || return 1'

require_contains "$AGENT" 'socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)'
require_contains "$AGENT" 'self.frontend_process: Optional[subprocess.Popen] = None'
require_contains "$AGENT" 'def _spawn_frontend(self, request: dict) -> None:'
require_contains "$AGENT" 'def _close_frontend(self) -> None:'

reject_contains "$HYPR" 'special:awtarchy-polkit-agent'
reject_contains "$BAR" 'internalServiceWindow'
require_contains "$BAR" 'toplevel.workspace && toplevel.workspace.id < 0).length'

printf '%s\n' 'headless Polkit idle contract passed'
