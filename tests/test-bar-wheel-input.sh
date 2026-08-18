#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BAR_BUTTON="${ROOT}/config/quickshell/awtarchy/BarButton.qml"
LIST_SCROLLBAR="${ROOT}/config/quickshell/awtarchy/ListScrollBar.qml"
NETWORK_VPN="${ROOT}/config/quickshell/awtarchy/NetworkVpnSection.qml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file_source() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail "$description"
}

require_source() {
  require_file_source "$BAR_BUTTON" "$1" "$2"
}

require_source 'scrollGestureEnabled: true' \
  'BarButton does not explicitly accept trackpad scroll gestures'
require_source 'const rawPixelDelta = Number(wheel.pixelDelta.y);' \
  'BarButton does not read smooth pixel deltas'
require_source 'const pixelDelta = -rawPixelDelta;' \
  'BarButton does not reverse the smooth trackpad direction'
require_source 'const angleDelta = Number(wheel.angleDelta.y);' \
  'BarButton does not retain discrete mouse-wheel deltas'
require_source 'wheelPixelRemainder += pixelDelta;' \
  'BarButton does not accumulate smooth trackpad movement'
require_source 'wheelAngleRemainder += angleDelta;' \
  'BarButton does not accumulate high-resolution wheel movement'
require_source 'readonly property real wheelPixelStep: 24' \
  'BarButton is missing the bounded trackpad step threshold'
require_source 'onWheel: wheel => root.handleWheel(wheel)' \
  'BarButton bypasses the shared wheel normalizer'
require_source 'wheel.accepted = false;' \
  'BarButton does not release unhandled zero or horizontal events'

if grep -Fq 'if (wheel.angleDelta.y > 0)' "$BAR_BUTTON"; then
  fail 'legacy angle-only wheel handling is still present'
fi

if grep -Fq 'wheel.inverted' "$BAR_BUTTON"; then
  fail 'trackpad direction still depends on the unreliable WheelEvent.inverted flag'
fi

require_file_source "$LIST_SCROLLBAR" 'WheelHandler {' \
  'flyout scrollbars do not handle wheel input across the full scrollable surface'
require_file_source "$LIST_SCROLLBAR" 'parent: root.flickable' \
  'flyout wheel handling is not scoped to the associated scrollable surface'
require_file_source "$LIST_SCROLLBAR" 'target: null' \
  'flyout WheelHandler may apply an unintended automatic property change'
require_file_source "$LIST_SCROLLBAR" \
  'acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad' \
  'flyout WheelHandler does not explicitly accept mouse and touchpad input'
require_file_source "$LIST_SCROLLBAR" \
  'const target = flickable.contentY - wheel.angleDelta.y;' \
  'flyout wheel handling does not match the responsive launcher/clipboard scroll delta'
require_file_source "$LIST_SCROLLBAR" \
  'Math.min(maximumContentY, target)' \
  'flyout wheel handling does not clamp to the scrollable content range'

require_file_source "$NETWORK_VPN" 'id: profileFlick' \
  'WireGuard profile list is missing its named scroll surface'
require_file_source "$NETWORK_VPN" 'flickable: profileFlick' \
  'WireGuard profile list does not use the shared flyout scroll handling'

printf '%s\n' 'Bar and flyout wheel input regression test passed.'
