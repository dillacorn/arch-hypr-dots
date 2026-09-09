#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

[[ -f "$SCENE" ]] || fail 'secure lock scene is missing'
[[ -f "$PREVIEW" ]] || fail 'desktop lock preview scene is missing'

require_text "$SCENE" 'readonly property var logoBridgePairs:' \
    'logo has no predefined cohesion neighbor map'
require_text "$SCENE" 'readonly property real logoBridgeMaxDistance:' \
    'logo bridges have no explicit short-range cutoff'
require_text "$SCENE" 'readonly property real logoBridgeInteractionBoost:' \
    'logo bridges do not strengthen subtly during interaction'
require_text "$SCENE" 'id: logoBridgeCanvas' \
    'logo has no cohesion bridge canvas behind its blocks'
require_text "$SCENE" 'ctx.lineCap = "round"' \
    'logo cohesion bridges are not rounded'
require_text "$SCENE" 'distance >= root.logoBridgeMaxDistance' \
    'logo cohesion does not drop bridges once pieces separate too far'
require_text "$SCENE" 'root.logoBridgeInteractionBoost' \
    'logo bridge rendering ignores interaction energy'
require_text "$SCENE" 'logoBridgeCanvas.requestPaint()' \
    'logo bridge layer is not repainted with interactive physics'
require_text "$SCENE" 'onPaint: {' \
    'logo bridge canvas has no deterministic paint path'

reject_text "$SCENE" 'ShaderEffect {' \
    'logo cohesion uses a shader-heavy effect instead of restrained connectors'
reject_text "$SCENE" 'FastBlur {' \
    'logo cohesion uses a heavy blur instead of restrained connectors'

cmp -s "$SCENE" "$PREVIEW" \
    || fail 'secure lock scene and desktop preview scene diverge'

printf 'PASS: lockscreen logo cohesion contracts\n'
