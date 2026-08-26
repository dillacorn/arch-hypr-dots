#!/usr/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HYPR="${ROOT_DIR}/config/hypr/hyprland.lua"
BAR="${ROOT_DIR}/config/quickshell/awtarchy/Bar.qml"
TUI="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/tui.py"

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
    ! grep -Fq -- "$pattern" "$file" || fail "$file still contains: $pattern"
}

# The authentication terminal exists only during an active request. Hyprland
# may float the exact class, but it must never park it on a special workspace.
require_contains "$HYPR" 'name = "awtarchy-polkit-agent-auth"'
require_contains "$HYPR" 'match = { class = "awtarchy-polkit-agent" }'
require_contains "$HYPR" 'float = true'
reject_contains "$HYPR" 'special:awtarchy-polkit-agent'
reject_contains "$TUI" 'HIDDEN_WORKSPACE'
reject_contains "$TUI" 'prime_hidden'

# The transient prompt is omitted from the normal task strip while it exists,
# but scratchpad accounting no longer has a service-window exception.
require_contains "$BAR" '"awtarchy-polkit-agent"'
reject_contains "$BAR" 'function internalServiceWindow(toplevel)'
reject_contains "$BAR" '!bar.internalServiceWindow(toplevel)'
require_contains "$BAR" 'toplevel.workspace && toplevel.workspace.id < 0).length'

echo 'Polkit transient-window UI contract passed.'
