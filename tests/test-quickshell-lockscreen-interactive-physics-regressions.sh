#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
AUDIO_QML="${ROOT}/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

# High-polling-rate mice can move less than the raw event threshold per event.
# Trail sampling must therefore compare against the last rendered ghost head so
# many tiny movements accumulate instead of leaving the ghost visually stuck.
require_text "$SURFACE_QML" 'const ghostDx = x - ghostHeadX;' \
    'ghost sampling does not accumulate movement from the rendered head'
require_text "$SURFACE_QML" 'const ghostDy = y - ghostHeadY;' \
    'ghost sampling does not accumulate vertical movement from the rendered head'
require_text "$SURFACE_QML" 'const ghostDistance = Math.sqrt(ghostDx * ghostDx + ghostDy * ghostDy);' \
    'ghost sampling has no cumulative movement distance'
require_text "$SURFACE_QML" 'ghostDistance >= pointerMovementThreshold' \
    'ghost sampling still thresholds only individual raw mouse events'

# Pointer and audio offsets are individually bounded, but their sum must also
# be capped so simultaneous pointer/audio activity cannot exceed the physical
# displacement envelope promised by the lockscreen design.
require_text "$SURFACE_QML" 'readonly property real combinedOffsetX:' \
    'wordmark final X displacement is not explicitly clamped'
require_text "$SURFACE_QML" 'readonly property real combinedOffsetY:' \
    'wordmark final Y displacement is not explicitly clamped'
require_text "$SURFACE_QML" '+ combinedOffsetX' \
    'wordmark X position does not use the clamped combined displacement'
require_text "$SURFACE_QML" '+ combinedOffsetY' \
    'wordmark Y position does not use the clamped combined displacement'

# Formation Off is not a hidden effects master switch. Mouse and audio have
# independent gates so users can evaluate or disable either effect separately.
require_text "$SURFACE_QML" 'readonly property bool pointerEffectsEnabled: root.mouseInteractive && root.pointerActive' \
    'pointer physics is not independently gated'
require_text "$SURFACE_QML" 'readonly property bool audioEffectsEnabled: root.audioReactive && root.audioLevel > root.audioSilenceThreshold' \
    'audio physics is not independently gated'
if grep -Fq -- 'interactiveEffectsEnabled: root.animationPreference !== "off"' "$SURFACE_QML"; then
    fail 'formation Off still acts as an effects master switch'
fi

# Audio smoothing must stop once it reaches the current target, including the
# zero target after CAVA exits or is unavailable.
require_text "$AUDIO_QML" 'function settled()' \
    'audio analyzer has no explicit settled state'
require_text "$AUDIO_QML" 'if (root.settled())' \
    'audio smoothing does not stop after settling'

printf 'PASS: lockscreen interactive physics regressions\n'
