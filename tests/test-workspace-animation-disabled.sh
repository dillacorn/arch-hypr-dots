#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPRLAND="${ROOT}/config/hypr/hyprland.lua"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local text="$1" message="$2"
    grep -Fq -- "$text" "$HYPRLAND" || fail "$message"
}

require_text '{ leaf = "workspaces", enabled = 0' \
    'standard workspace animation is still enabled'
require_text '{ leaf = "workspacesIn", enabled = 0' \
    'workspace-enter animation is still enabled'
require_text '{ leaf = "workspacesOut", enabled = 0' \
    'workspace-exit animation is still enabled'

# Keep special-workspace behavior independent. This request removes normal
# workspace switching animation only, not every Hyprland animation.
require_text '{ leaf = "specialWorkspace", enabled = 1' \
    'special workspace animation changed unexpectedly'

printf 'PASS: standard workspace switching animations are disabled\n'
