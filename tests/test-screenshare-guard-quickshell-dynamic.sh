#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$ROOT/config/hypr/hyprland.lua"
CARD="$ROOT/config/quickshell/awtarchy/ScreenShareGuardCard.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_source() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

require_source "$HYPR" 'function awtarchy_screenshare_guard_register_v1' \
    'hyprland.lua does not expose custom Screen Share Guard registration'
require_source "$HYPR" 'function awtarchy_screenshare_guard_registry_v1' \
    'hyprland.lua does not expose Screen Share Guard registry metadata'

require_source "$CARD" 'function targetModel(section)' \
    'Screen Share Guard card does not build rows from runtime section metadata'
require_source "$CARD" 'root.targetModel("protected")' \
    'protected Screen Share Guard rows are not runtime-driven'
require_source "$CARD" 'root.targetModel("optional")' \
    'optional Screen Share Guard rows are not runtime-driven'
if grep -Fq 'protectedTargetIds' "$CARD" || grep -Fq 'optionalTargetIds' "$CARD"; then
    fail 'Screen Share Guard card still hardcodes target IDs instead of rendering registry entries'
fi
require_source "$CARD" 'root.targetModel("optional").length' \
    'optional Screen Share Guard count does not follow runtime registry entries'

printf '%s\n' 'Screen Share Guard dynamic Quick Settings regression passed.'
