#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CARD="${ROOT}/config/quickshell/awtarchy/BatteryCareCard.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_source() {
    local needle="$1" message="$2"
    grep -Fq -- "$needle" "$CARD" || fail "$message"
}

[[ -f "$CARD" ]] || fail 'BatteryCareCard.qml is missing'
require_source 'writable: false' 'Battery Care empty status does not default writes to disabled'
require_source 'compatibility: "unsupported"' 'Battery Care empty status has no compatibility classification'
require_source '&& Boolean(statusData.writable)' 'Battery Care controls do not require validated writable support'

printf '%s\n' 'PASS: Battery Care QML gates writes on validated detector support.'
