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

# Item focus and compositor focus are separate. Keep the search field prepared
# in QML, then focus the exact mapped launcher toplevel after positioning it.
require_source "$LAUNCHER" 'search.forceActiveFocus();' \
  'launcher search field is not assigned active QML focus after positioning'
require_source "$POSITIONER" \
  'focus_lua="hl.dispatch(hl.dsp.focus({ window = \"${selector_lua}\" }))"' \
  'launcher positioner does not focus the exact mapped launcher window'
require_source "$POSITIONER" '${focus_lua}' \
  'launcher positioner does not dispatch its prepared focus operation'

focus_dispatch_line="$(grep -nF '    ${focus_lua}' "$POSITIONER" | head -n1 | cut -d: -f1)"
opacity_line="$(grep -nF 'prop = \"opacity_fullscreen_override\"' "$POSITIONER" | head -n1 | cut -d: -f1)"

[[ -n "$focus_dispatch_line" && -n "$opacity_line" ]] \
  || fail 'could not locate launcher focus sequencing statements'
(( focus_dispatch_line > opacity_line )) \
  || fail 'launcher is focused before its final geometry and visibility are applied'

printf '%s\n' 'Launcher keyboard focus regression test passed.'
