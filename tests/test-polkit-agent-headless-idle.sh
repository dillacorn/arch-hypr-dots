#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
LIVE_TEST="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-live-test.sh"
BAR="${ROOT_DIR}/config/quickshell/awtarchy/Bar.qml"
HYPR="${ROOT_DIR}/config/hypr/hyprland.lua"

fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 still contains: $2"; }

# Idle service must be the isolated Python backend itself, not Alacritty.
require_contains "$RUNTIME" 'expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)"'
require_contains "$RUNTIME" '[[ "$resolved" == "$expected_python" ]] || return 1'
require_contains "$RUNTIME" "mapfile -d '' -t argv <\"/proc/\${pid}/cmdline\""
reject_contains "$RUNTIME" '[[ "$resolved" == "$expected_alacritty" ]] || return 1'

require_contains "$LIVE_TEST" 'expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)"'
require_contains "$LIVE_TEST" 'verify_no_idle_frontend'
require_contains "$LIVE_TEST" 'wait_for_frontend_exit'
reject_contains "$LIVE_TEST" 'Process tree: verified Alacritty -> python3 -I agent.py'

# There is no persistent/private authentication workspace anymore.
reject_contains "$HYPR" 'special:awtarchy-polkit-agent'
reject_contains "$BAR" 'internalServiceWindow'
require_contains "$BAR" 'toplevel.workspace && toplevel.workspace.id < 0).length'

printf '%s\n' 'headless Polkit idle contract passed'
