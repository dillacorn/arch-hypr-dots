#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PICKER="${ROOT}/config/quickshell/awtarchy/ThemePicker.qml"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
BAR_ICON_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarIconSettings.qml"
STATE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

if grep -Eq '^[[:space:]]*radius:[[:space:]]*[1-9]' "$PICKER"; then
    fail 'ThemePicker still contains rounded corners'
fi
contains "$PICKER" 'function activateThemeCard(index)' \
    'ThemePicker has no selected-card activation helper'
contains "$PICKER" 'if (selectedIndex === index)' \
    'ThemePicker does not distinguish a second click on the selected card'
contains "$PICKER" 'onClicked: root.activateThemeCard(card.index)' \
    'Theme card click does not use selected-card activation behavior'

contains "$BAR_STATE" 'readonly property var workspaceIconStylePresets:' \
    'BarState does not expose composable workspace icon styles'
contains "$BAR_STATE" '{ key: "off", label: "Off"' \
    'Workspace icon styles do not expose Off'
contains "$BAR_STATE" 'function workspaceNumbersEnabled()' \
    'BarState has no independent workspace numbers toggle getter'
contains "$BAR_STATE" 'function workspaceIconStyle()' \
    'BarState has no independent workspace icon-style getter'
contains "$BAR_STATE" 'function workspaceIconFor(id)' \
    'BarState has no workspace icon resolver'
contains "$BAR_STATE" 'function composeWorkspaceLabel(id, vertical)' \
    'BarState does not compose numbers and icons independently'
contains "$BAR_STATE" 'appearance.workspace_numbers_enabled' \
    'BarState does not read persisted workspace number visibility'
contains "$BAR_STATE" 'appearance.workspace_icon_style' \
    'BarState does not read persisted workspace icon style'
contains "$BAR_STATE" 'appearance.workspace_style' \
    'BarState does not retain legacy workspace_style compatibility'

contains "$BAR_ICON_SETTINGS" 'text: "Numbers"' \
    'Bar icon settings do not expose a Numbers control'
contains "$BAR_ICON_SETTINGS" 'label: "On"' \
    'Bar icon settings do not expose Numbers On'
contains "$BAR_ICON_SETTINGS" 'label: "Off"' \
    'Bar icon settings do not expose an Off choice'
contains "$BAR_ICON_SETTINGS" 'model: BarState.workspaceIconStylePresets' \
    'Bar icon settings do not expose composable icon styles'
contains "$BAR_ICON_SETTINGS" '"set-workspace-numbers"' \
    'Numbers toggle is not persisted independently'
contains "$BAR_ICON_SETTINGS" '"set-workspace-icon-style"' \
    'Workspace icon style is not persisted independently'

CACHE_HOME="${TMP}/cache"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
mkdir -p "$(dirname -- "$STATE_FILE")" "$TMP/home"
cat >"$STATE_FILE" <<'JSON'
{
  "enabled": true,
  "bar_appearance": {
    "workspace_style": "filled-diamond"
  },
  "unrelated": {
    "preserve": true
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

run_state set-workspace-numbers on
jq -e '
    .bar_appearance.workspace_numbers_enabled == true
    and .unrelated.preserve == true
' "$STATE_FILE" >/dev/null \
    || fail 'Numbers On was not persisted without damaging unrelated state'

run_state set-workspace-icon-style workflow
jq -e '
    .bar_appearance.workspace_icon_style == "workflow"
    and .unrelated.preserve == true
' "$STATE_FILE" >/dev/null \
    || fail 'Workspace icon style was not persisted without damaging unrelated state'

run_state set-workspace-numbers off
jq -e '.bar_appearance.workspace_numbers_enabled == false' "$STATE_FILE" >/dev/null \
    || fail 'Numbers Off was not persisted'

run_state set-workspace-icon-style off
jq -e '.bar_appearance.workspace_icon_style == "off"' "$STATE_FILE" >/dev/null \
    || fail 'Workspace icon Off was not persisted'

run_state reset-workspace-icons
jq -e '
    (.bar_appearance.workspace_numbers_enabled | not)
    and (.bar_appearance.workspace_icon_style | not)
    and (.bar_appearance.workspace_style | not)
    and (.bar_appearance.workspace_custom_label | not)
    and (.bar_appearance.workspace_overrides | not)
    and .unrelated.preserve == true
' "$STATE_FILE" >/dev/null \
    || fail 'Workspace reset did not restore composable defaults cleanly'

printf '%s\n' 'PASS: theme picker square styling and composable workspace number/icon controls are validated.'
