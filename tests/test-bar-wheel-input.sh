#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BAR_BUTTON="${ROOT}/config/quickshell/awtarchy/BarButton.qml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_source() {
  local expected="$1" description="$2"
  grep -Fq -- "$expected" "$BAR_BUTTON" || fail "$description"
}

require_source 'scrollGestureEnabled: true' \
  'BarButton does not explicitly accept trackpad scroll gestures'
require_source 'const pixelDelta = Number(wheel.pixelDelta.y);' \
  'BarButton does not read smooth pixel deltas'
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

printf '%s\n' 'Bar wheel input regression test passed.'
