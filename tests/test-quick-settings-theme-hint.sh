#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$ROOT/config/hypr/hyprland.lua"
QUICK="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

count="$(grep -Fc -- '{ "SUPER + T", theme_select },' "$HYPR" || true)"
[[ "$count" == "2" ]] || fail "Themes is not consistently bound to SUPER+T in normal and noalt modes (found $count)"

grep -Fq -- 'text: "Themes: SUPER+T"' "$QUICK" \
    || fail 'Bar card does not tell the user that SUPER+T opens Themes'

printf '%s\n' 'PASS: Bar card documents the real SUPER+T Themes shortcut.'
