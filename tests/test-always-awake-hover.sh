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
require_file_text "$TOOLTIP" 'text: "Always Awake"' \
    'idle-eye hover card does not lead with the stronger mode'
require_file_text "$TOOLTIP" 'text: "Keeps the session unlocked and displays on after 4 hours idle."' \
    'idle-eye hover card does not explain the stronger mode'
require_file_text "$TOOLTIP" 'text: SystemState.idleMode === "always-awake" ? "Disable Always Awake" : "Enable Always Awake (Not Recommended)"' \
    'idle-eye hover card does not put the not-recommended warning in the stronger-mode action'
require_file_text "$TOOLTIP" 'text: SystemState.idleMode === "keep-awake" ? "Keep Awake: On" : "Keep Awake: Off"' \
    'idle-eye hover card does not report normal Keep Awake separately from Always Awake'
require_file_text "$TOOLTIP" 'Recommended: click the eye to toggle Keep Awake. The 4-hour safety stays active.' \
    'idle-eye hover card does not recommend the normal eye action'
require_file_text "$TOOLTIP" 'Recommended: click the eye to disable Always Awake. Click again for normal Keep Awake.' \
    'idle-eye hover card does not explain how to leave Always Awake using the eye'
require_file_text "$TOOLTIP" 'SystemState.setIdleMode(' \
    'idle-eye hover card cannot select the shared Always Awake mode'
require_file_text "$TOOLTIP" 'SystemState.idleMode === "always-awake" ? "off" : "always-awake"' \
    'idle-eye hover card does not toggle the explicit Always Awake mode'
require_file_text "$TOOLTIP" 'width: root.idleControl ? popup.width : 0' \
    'idle-eye hover card is not pointer-interactive while normal tooltips remain click-through'
require_file_text "$TOOLTIP" 'acceptedButtons: Qt.NoButton' \
    'idle hover surface does not preserve non-button hover tracking'

always_awake_line="$(grep -nF 'text: "Always Awake"' "$TOOLTIP" | head -n1 | cut -d: -f1)"
keep_awake_line="$(grep -nF 'text: SystemState.idleMode === "keep-awake" ? "Keep Awake: On" : "Keep Awake: Off"' "$TOOLTIP" | head -n1 | cut -d: -f1)"
[[ -n "$always_awake_line" && -n "$keep_awake_line" && "$always_awake_line" -lt "$keep_awake_line" ]] \
    || fail 'Always Awake action is not positioned above normal Keep Awake status'

right_click_count="$(grep -Fc 'onRightClicked: SystemState.toggleIdle()' "$BAR")"
[[ "$right_click_count" -ge 2 ]] \
    || fail 'horizontal and vertical idle eyes do not both keep right-click as normal Keep Awake'

printf '%s\n' 'PASS: idle-eye hover prioritizes warned Always Awake while recommending normal Keep Awake clicks.'
