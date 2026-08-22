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

# Application results and keyboard navigation must keep the same top-to-bottom
# direction regardless of whether the bar itself is attached to the top or
# bottom edge. The bottom layout may move the search/settings row, but it must
# not reverse the application model or arrow-key direction.
require_source "$LAUNCHER" 'verticalLayoutDirection: GridView.TopToBottom' \
  'launcher application results are not always laid out top-to-bottom'
require_source "$LAUNCHER" 'Layout.row: root.bottomEdgeLayout ? 2 : 0' \
  'bottom launcher search/settings row placement changed'
require_source "$LAUNCHER" 'Layout.row: root.bottomEdgeLayout ? 0 : 2' \
  'bottom launcher application-list placement changed'
require_source "$LAUNCHER" 'Math.max(0, appList.currentIndex) + appList.columnCount);' \
  'Down-key launcher navigation does not move forward through results'
require_source "$LAUNCHER" 'Math.max(0, appList.currentIndex) - appList.columnCount);' \
  'Up-key launcher navigation does not move backward through results'

for forbidden in \
  'verticalLayoutDirection: root.bottomEdgeLayout' \
  'const downIndex = root.bottomEdgeLayout' \
  'const upIndex = root.bottomEdgeLayout' \
  'hl.dsp.focus(' \
  'dispatch focuswindow' \
  'dispatch movecursor' \
  'hl.dsp.cursor' \
  'requestActivate' \
  'warpCursor' \
  'setCursorPosition'
do
  if grep -Fq -- "$forbidden" "$LAUNCHER" "$POSITIONER"; then
    fail "launcher keyboard/result path contains forbidden operation: ${forbidden}"
  fi
done

printf '%s\n' 'Launcher keyboard focus and result-direction regression test passed.'
