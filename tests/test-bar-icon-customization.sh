#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

CACHE_HOME="${TMP}/cache"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
mkdir -p "$(dirname -- "$STATE_FILE")" "$TMP/home"

cat >"$STATE_FILE" <<'JSON'
{
  "enabled": true,
  "update_notifications_enabled": true,
  "monitors": {
    "DP-1": {
      "position": "left",
      "bar_size": 36,
      "icon_scale": 100
    }
  },
  "quick_settings_layouts": {
    "DP-1": {
      "order": ["bar", "brightness"],
      "hidden": []
    }
  },
  "unrelated": {
    "preserve": "yes"
  }
}
JSON

run_state() {
    env \
        HOME="$TMP/home" \
        XDG_CACHE_HOME="$CACHE_HOME" \
        HYPR_QUICKSHELL_SCRIPT="$TMP/missing-quickshell.sh" \
        bash "$STATE_SCRIPT" "$@"
}

assert_unrelated_state() {
    jq -e '
        .enabled == true
        and .update_notifications_enabled == true
        and .monitors["DP-1"].position == "left"
        and .monitors["DP-1"].bar_size == 36
        and .monitors["DP-1"].icon_scale == 100
        and .quick_settings_layouts["DP-1"].order == ["bar", "brightness"]
        and .unrelated.preserve == "yes"
    ' "$STATE_FILE" >/dev/null \
        || fail 'bar icon persistence changed unrelated state'
}

expect_rejected_unchanged() {
    local label="$1"
    shift
    cp "$STATE_FILE" "$TMP/before-invalid.json"
    if run_state "$@" >/dev/null 2>&1; then
        fail "$label was accepted"
    fi
    cmp -s "$STATE_FILE" "$TMP/before-invalid.json" \
        || fail "$label modified persistent state before rejection"
}

run_state set-workspace-style half-left
jq -e '.bar_appearance.workspace_style == "half-left"' "$STATE_FILE" >/dev/null \
    || fail 'workspace style was not persisted'
assert_unrelated_state

run_state set-workspace-custom-label '◐'
jq -e '.bar_appearance.workspace_custom_label == "◐"' "$STATE_FILE" >/dev/null \
    || fail 'global custom workspace label was not persisted'

run_state set-workspace-override 1 '1◐'
run_state set-workspace-override 10 '⑩'
jq -e '
    .bar_appearance.workspace_overrides["1"] == "1◐"
    and .bar_appearance.workspace_overrides["10"] == "⑩"
' "$STATE_FILE" >/dev/null \
    || fail 'workspace overrides were not persisted by workspace number'

run_state clear-workspace-override 1
jq -e '
    (.bar_appearance.workspace_overrides["1"] | not)
    and .bar_appearance.workspace_overrides["10"] == "⑩"
' "$STATE_FILE" >/dev/null \
    || fail 'individual workspace override reset changed the wrong workspace'

run_state clear-workspace-overrides
jq -e '(.bar_appearance.workspace_overrides | length) == 0' "$STATE_FILE" >/dev/null \
    || fail 'workspace override reset-all did not clear overrides'

run_state set-launcher-icon '★'
jq -e '.bar_appearance.launcher_icon == "★"' "$STATE_FILE" >/dev/null \
    || fail 'launcher icon was not persisted'

run_state reset-workspace-icons
jq -e '
    (.bar_appearance.workspace_style | not)
    and (.bar_appearance.workspace_custom_label | not)
    and (.bar_appearance.workspace_overrides | not)
    and .bar_appearance.launcher_icon == "★"
' "$STATE_FILE" >/dev/null \
    || fail 'workspace reset did not preserve launcher identity'

run_state reset-launcher-icon
jq -e '(.bar_appearance.launcher_icon | not)' "$STATE_FILE" >/dev/null \
    || fail 'launcher reset did not restore stock state'

run_state set-workspace-style three-quarter-circle
run_state set-workspace-custom-label '◕'
run_state set-workspace-override 4 '4◕'
run_state set-launcher-icon '◆'
run_state reset-bar-icons
jq -e '(.bar_appearance | not) or (.bar_appearance | length == 0)' "$STATE_FILE" >/dev/null \
    || fail 'Reset Bar Icons did not clear all identity state'
assert_unrelated_state

expect_rejected_unchanged 'workspace 0' set-workspace-override 0 '●'
expect_rejected_unchanged 'workspace 11' set-workspace-override 11 '●'
expect_rejected_unchanged 'unknown workspace style' set-workspace-style not-a-style
expect_rejected_unchanged 'blank custom label' set-workspace-custom-label '   '
expect_rejected_unchanged 'newline custom label' set-workspace-custom-label $'bad\nline'
expect_rejected_unchanged 'C0 control custom label' set-workspace-custom-label $'bad\x01'
expect_rejected_unchanged '9-code-point custom label' set-workspace-custom-label '123456789'
expect_rejected_unchanged 'blank launcher label' set-launcher-icon '   '
expect_rejected_unchanged '9-code-point launcher label' set-launcher-icon 'abcdefghi'

printf '%s\n' 'PASS: bar icon identity persistence is global, validated, resettable, and preserves unrelated Quickshell state.'
