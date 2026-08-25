#!/usr/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HYPR="${ROOT_DIR}/config/hypr/hyprland.lua"
BAR="${ROOT_DIR}/config/quickshell/awtarchy/Bar.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

require_contains() {
    local file="$1" pattern="$2"
    grep -Fq -- "$pattern" "$file" || fail "$file missing: $pattern"
}

# The persistent authentication terminal is an internal service window. It is
# born directly on its private special workspace so users never see a startup
# flash, but Awtarchy must not advertise it as a user scratchpad/task window.
require_contains "$HYPR" 'name = "awtarchy-polkit-agent-internal"'
require_contains "$HYPR" 'match = { class = "awtarchy-polkit-agent" }'
require_contains "$HYPR" 'workspace = "special:awtarchy-polkit-agent silent"'
require_contains "$HYPR" 'no_initial_focus = true'
require_contains "$HYPR" 'no_anim = true'

require_contains "$BAR" '"awtarchy-polkit-agent"'
require_contains "$BAR" 'function internalServiceWindow(toplevel)'
require_contains "$BAR" '!bar.internalServiceWindow(toplevel)'

echo 'Polkit internal-window UI contract passed.'
