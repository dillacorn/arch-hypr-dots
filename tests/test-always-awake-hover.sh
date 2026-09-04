#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLTIP="$ROOT/config/quickshell/awtarchy/BarTooltip.qml"
BAR="$ROOT/config/quickshell/awtarchy/Bar.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_file_text() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

# The normal eye click remains the fast Keep Awake action. Hovering the eye
# exposes the stronger mode, but it must be explicit about the safety tradeoff.
require_file_text "$TOOLTIP" 'readonly property bool idleControl:' \
    'bar tooltip does not identify the idle-eye control'
require_file_text "$TOOLTIP" 'text: "Always Awake — Not Recommended"' \
    'idle-eye hover card lacks the explicit not-recommended warning'
require_file_text "$TOOLTIP" 'text: "Keeps the session unlocked and displays on after 4 hours idle."' \
    'idle-eye hover card does not explain the stronger mode'
require_file_text "$TOOLTIP" 'Normal Keep Awake keeps the 4-hour safety active.' \
    'idle-eye hover card does not distinguish normal Keep Awake safety'
require_file_text "$TOOLTIP" 'SystemState.setIdleMode(' \
    'idle-eye hover card cannot select the shared Always Awake mode'
require_file_text "$TOOLTIP" 'SystemState.idleMode === "always-awake" ? "off" : "always-awake"' \
    'idle-eye hover card does not toggle the explicit Always Awake mode'
require_file_text "$TOOLTIP" 'width: root.idleControl ? popup.width : 0' \
    'idle-eye hover card is not pointer-interactive while normal tooltips remain click-through'
require_file_text "$TOOLTIP" 'acceptedButtons: Qt.NoButton' \
    'idle hover surface does not preserve non-button hover tracking'
require_file_text "$BAR" 'onRightClicked: SystemState.toggleIdle()' \
    'horizontal idle eye no longer keeps right-click as normal Keep Awake'

printf '%s\n' 'PASS: idle-eye hover exposes the warned Always Awake control without replacing normal clicks.'
