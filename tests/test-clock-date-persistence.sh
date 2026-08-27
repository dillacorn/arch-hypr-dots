#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Integration contract: command dispatch, per-monitor state, and both bar orientations must stay aligned.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

CACHE_HOME="${TMP}/cache"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
mkdir -p "$(dirname -- "$STATE_FILE")"

cat >"$STATE_FILE" <<'JSON'
{
  "enabled": true,
  "update_notifications_enabled": true,
  "monitors": {
    "DP-1": {
      "position": "bottom",
      "enabled": true,
      "bar_size": 34
    },
    "DP-2": {
      "position": "top",
      "clock_date": true
    }
  },
  "launcher_sizes": {
    "DP-1": {
      "saved": true,
      "width": 500,
      "height": 600
    }
  }
}
JSON

XDG_CACHE_HOME="$CACHE_HOME" "$STATE_SCRIPT" set-clock-date DP-1 true

jq -e '.monitors["DP-1"].clock_date == true' "$STATE_FILE" >/dev/null \
    || fail 'clock/date state was not enabled for the requested monitor'
jq -e '.monitors["DP-1"].position == "bottom" and .monitors["DP-1"].bar_size == 34' "$STATE_FILE" >/dev/null \
    || fail 'clock/date persistence overwrote unrelated monitor settings'
jq -e '.monitors["DP-2"].clock_date == true and .monitors["DP-2"].position == "top"' "$STATE_FILE" >/dev/null \
    || fail 'clock/date persistence changed another monitor'
jq -e '.launcher_sizes["DP-1"].width == 500 and .launcher_sizes["DP-1"].height == 600' "$STATE_FILE" >/dev/null \
    || fail 'clock/date persistence changed unrelated application state'

XDG_CACHE_HOME="$CACHE_HOME" "$STATE_SCRIPT" set-clock-date DP-1 false
jq -e '.monitors["DP-1"].clock_date == false' "$STATE_FILE" >/dev/null \
    || fail 'clock/date state was not disabled for the requested monitor'

if XDG_CACHE_HOME="$CACHE_HOME" "$STATE_SCRIPT" set-clock-date DP-1 maybe >/dev/null 2>&1; then
    fail 'clock/date persistence accepted an invalid boolean'
fi

# QML must default to time when clock_date is absent and read each monitor independently.
grep -Fq 'function clockDateFor(name)' "$BAR_STATE" \
    || fail 'BarState has no per-monitor clock/date getter'
grep -Fq 'return monitorState(name).clock_date === true;' "$BAR_STATE" \
    || fail 'BarState does not default missing clock/date state to time'

grep -Fq 'property bool clockDate: BarState.clockDateFor(monitorName)' "$BAR_QML" \
    || fail 'Bar does not initialize clock/date mode from persistent per-monitor state'
grep -Fq 'function toggleClockDate()' "$BAR_QML" \
    || fail 'Bar has no shared clock/date toggle path'
grep -Fq '[stateScript, "set-clock-date", monitorName, clockDate ? "true" : "false"]' "$BAR_QML" \
    || fail 'Bar does not persist clock/date mode through the locked state writer'
grep -Fq 'id: clockDateWriter' "$BAR_QML" \
    || fail 'Bar has no serialized clock/date persistence process'
grep -Fq 'clockDatePersistPending = true' "$BAR_QML" \
    || fail 'rapid clock/date toggles are not coalesced while persistence is active'

[[ $(grep -Fc 'onClicked: bar.toggleClockDate()' "$BAR_QML") -eq 2 ]] \
    || fail 'horizontal and vertical clocks do not share the persistent click toggle'
[[ $(grep -Fc 'onRightClicked: bar.toggleClockDate()' "$BAR_QML") -eq 2 ]] \
    || fail 'horizontal and vertical clocks do not share the persistent right-click toggle'
[[ $(grep -Fc 'onWheelUp: bar.toggleClockDate()' "$BAR_QML") -eq 2 ]] \
    || fail 'horizontal and vertical clocks do not share the persistent wheel-up toggle'
[[ $(grep -Fc 'onWheelDown: bar.toggleClockDate()' "$BAR_QML") -eq 2 ]] \
    || fail 'horizontal and vertical clocks do not share the persistent wheel-down toggle'

# Keep restart/reboot persistence and per-monitor isolation as the permanent contract.
printf '%s\n' 'Clock/date per-monitor persistence regression test passed.'
