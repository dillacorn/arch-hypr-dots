#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_HELPER="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$STATE_HELPER" ]] || fail 'quickshell application state helper is missing or not executable'
command -v jq >/dev/null 2>&1 || fail 'jq is required'
command -v flock >/dev/null 2>&1 || fail 'flock is required'

export XDG_CACHE_HOME="$TMP/cache"
export HYPR_QUICKSHELL_SCRIPT=/bin/false
STATE_FILE="$XDG_CACHE_HOME/awtarchy/quickshell-state.json"

"$STATE_HELPER" save-flyout battery eDP-1 610 590 115 125 false
jq -e '
  .battery_views["eDP-1"] == {
    width:610,
    height:590,
    text_scale:115,
    icon_scale:125,
    saved:true,
    save_version:2
  }
  and .capture_allowed.battery == false
' "$STATE_FILE" >/dev/null || fail 'Battery save-flyout state is incorrect'

"$STATE_HELPER" copy-flyout battery 610 590 115 125 HDMI-A-1 DP-2
jq -e '
  .battery_views["HDMI-A-1"].width == 610
  and .battery_views["HDMI-A-1"].height == 590
  and .battery_views["HDMI-A-1"].text_scale == 115
  and .battery_views["HDMI-A-1"].icon_scale == 125
  and .battery_views["HDMI-A-1"].saved == true
  and .battery_views["HDMI-A-1"].save_version == 2
  and .battery_views["DP-2"].width == 610
  and .battery_views["DP-2"].height == 590
' "$STATE_FILE" >/dev/null || fail 'Battery copy-flyout state is incorrect'

"$STATE_HELPER" set-capture battery true
jq -e '.capture_allowed.battery == true' "$STATE_FILE" >/dev/null \
  || fail 'Battery capture state did not persist'

"$STATE_HELPER" reset-flyout battery eDP-1
jq -e '
  (.battery_views | has("eDP-1") | not)
  and .battery_views["HDMI-A-1"].width == 610
  and .battery_views["DP-2"].width == 610
  and .capture_allowed.battery == false
' "$STATE_FILE" >/dev/null || fail 'Battery reset-flyout did not reset only the requested monitor'

printf '%s\n' 'Battery flyout state persistence regression test passed.'
