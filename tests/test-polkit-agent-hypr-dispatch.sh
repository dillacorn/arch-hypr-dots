#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TUI="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/tui.py"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

require_contains() {
    local pattern="$1"
    grep -Fq -- "$pattern" "$TUI" || fail "$TUI missing: $pattern"
}

reject_contains() {
    local pattern="$1"
    if grep -Fq -- "$pattern" "$TUI"; then
        fail "$TUI still contains: $pattern"
    fi
}

# Hyprland 0.55+ native Lua dispatchers support exact-window workspace moves.
# Do not route special-workspace movement through the legacy text dispatcher;
# that path failed live on Hyprland 0.55 after successful PolicyKit registration.
require_contains 'hl.dispatch(hl.dsp.window.move({ workspace = workspace, follow = false, window = w }))'
require_contains 'hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))'
require_contains 'hl.dispatch(hl.dsp.focus({ window = w }))'
reject_contains 'movetoworkspacesilent'
reject_contains 'action = "set"'
reject_contains 'dispatch", "focuswindow"'

printf '%s\n' 'terminal Polkit Hyprland dispatcher contract passed'
