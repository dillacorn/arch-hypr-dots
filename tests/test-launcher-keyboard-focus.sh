#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="${ROOT}/config/quickshell/awtarchy/Launcher.qml"
POSITIONER="${ROOT}/config/hypr/scripts/quickshell_launcher_position.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_source() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail "$description"
}

# Give the search item QML focus, then start Hyprland's focus-grab protocol
# with only the launcher surface. This produces keyboard entry without a
# compositor focus dispatcher or any pointer operation. Bar surfaces may join
# only after the launcher has been the sole initial keyboard target.
require_source "$LAUNCHER" 'search.forceActiveFocus();' \
  'launcher search field is not assigned active QML focus'
require_source "$LAUNCHER" 'property bool launcherFocusGrabExpanded: false' \
  'launcher does not track staged focus-grab expansion'
require_source "$LAUNCHER" 'windows: root.launcherFocusGrabExpanded' \
  'launcher does not stage its focus-grab whitelist'
require_source "$LAUNCHER" '            : [launcherWindow]' \
  'launcher is not the sole initial focus-grab surface'
require_source "$LAUNCHER" 'root.launcherFocusGrabExpanded = true;' \
  'launcher never expands its focus-grab whitelist after activation'

for forbidden in \
  'hl.dsp.focus(' \
  'dispatch focuswindow' \
  'dispatch movecursor' \
  'hl.dsp.cursor' \
  'requestActivate' \
  'warpCursor' \
  'setCursorPosition'
do
  if grep -Fq -- "$forbidden" "$LAUNCHER" "$POSITIONER"; then
    fail "launcher keyboard focus path contains pointer-affecting compositor operation: ${forbidden}"
  fi
done

printf '%s\n' 'Launcher keyboard focus regression test passed.'
