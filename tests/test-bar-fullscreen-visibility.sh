#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BAR="${ROOT}/config/quickshell/awtarchy/Bar.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local needle="$1" message="$2"
    grep -Fq -- "$needle" "$BAR" || fail "$message"
}

assert_contains 'function workspaceFullscreenForMonitor(name)' \
    'Bar has no per-monitor fullscreen visibility helper'
assert_contains 'workspace.monitor && workspace.monitor.name === name' \
    'Fullscreen visibility is not scoped to the bar monitor'
assert_contains 'workspace.active && workspace.hasFullscreen' \
    'Bar does not use the active workspace fullscreen state'
assert_contains '&& !workspaceFullscreenForMonitor(monitorName)' \
    'Bar visibility does not suppress itself for fullscreen workspaces'

printf '%s\n' 'PASS: bar visibility is explicitly suppressed on a fullscreen active workspace.'
