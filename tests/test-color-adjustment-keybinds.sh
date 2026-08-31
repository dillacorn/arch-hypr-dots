#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$ROOT/config/hypr/hyprland.lua"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_count() {
    local needle="$1" expected="$2" message="$3" count
    count="$(grep -Fc -- "$needle" "$HYPR" || true)"
    [[ "$count" == "$expected" ]] || fail "$message (expected $expected, found $count)"
}

reject() {
    if grep -Fq -- "$1" "$HYPR"; then
        fail "$2"
    fi
}

# Normal mode + noalt submap must expose the same Night Light controls.
require_count 'hl.bind("SUPER + ALT + CTRL + N", hl.dsp.exec_cmd(hyprsunset_ctl .. " toggle"), {})' 2 \
    'Night Light toggle is not consistently bound to CTRL+SUPER+ALT+N'
require_count 'hl.bind("SUPER + ALT + CTRL + bracketleft", hl.dsp.exec_cmd(hyprsunset_ctl .. " down"), {})' 2 \
    'Night Light warmer adjustment is not consistently bound to CTRL+SUPER+ALT+['
require_count 'hl.bind("SUPER + ALT + CTRL + bracketright", hl.dsp.exec_cmd(hyprsunset_ctl .. " up"), {})' 2 \
    'Night Light cooler adjustment is not consistently bound to CTRL+SUPER+ALT+]'

reject 'hl.bind("SUPER + ALT + CTRL + equal", hl.dsp.exec_cmd(hyprsunset_ctl .. " up"), {})' \
    'old Night Light CTRL+SUPER+ALT+= binding still exists'
reject 'hl.bind("SUPER + ALT + CTRL + minus", hl.dsp.exec_cmd(hyprsunset_ctl .. " down"), {})' \
    'old Night Light CTRL+SUPER+ALT+- binding still exists'
reject 'hl.bind("SUPER + ALT + CTRL + backspace", hl.dsp.exec_cmd(hyprsunset_ctl .. " toggle"), {})' \
    'old Night Light CTRL+SUPER+ALT+Backspace binding still exists'

# Digital vibrance keeps the lighter modifier layer for quick adjustment.
require_count 'hl.bind("SUPER + ALT + bracketleft", hl.dsp.exec_cmd(vibrance_shader .. " down"), {})' 2 \
    'digital vibrance decrease is not consistently bound to SUPER+ALT+['
require_count 'hl.bind("SUPER + ALT + bracketright", hl.dsp.exec_cmd(vibrance_shader .. " up"), {})' 2 \
    'digital vibrance increase is not consistently bound to SUPER+ALT+]'
require_count 'hl.bind("SUPER + ALT + CTRL + V", hl.dsp.exec_cmd(vibrance_shader .. " toggle"), {})' 2 \
    'digital vibrance toggle is not consistently bound to CTRL+SUPER+ALT+V'

printf '%s\n' 'PASS: Night Light and digital vibrance use the approved paired keybind scheme.'
