#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
BAR_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarSettingsSection.qml"
BAR_ICON_SETTINGS="${ROOT}/config/quickshell/awtarchy/BarIconSettings.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
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

contains "$BAR_STATE" 'bar_appearance: {}' \
    'BarState does not normalize bar identity state'
contains "$BAR_STATE" 'readonly property var workspaceStylePresets:' \
    'BarState does not own the workspace preset catalog'
contains "$BAR_STATE" 'readonly property var launcherIconPresets:' \
    'BarState does not own launcher icon presets'
contains "$BAR_STATE" 'function workspaceStyle()' \
    'BarState has no normalized workspace-style getter'
contains "$BAR_STATE" 'function workspaceCustomLabel()' \
    'BarState has no global custom workspace-label getter'
contains "$BAR_STATE" 'function workspaceOverrideFor(id)' \
    'BarState has no per-workspace override getter'
contains "$BAR_STATE" 'function workspaceLabelFor(id)' \
    'BarState has no horizontal workspace-label resolver'
contains "$BAR_STATE" 'function workspaceVerticalLabelFor(id)' \
    'BarState has no compact vertical workspace-label resolver'
contains "$BAR_STATE" 'function launcherIcon()' \
    'BarState has no launcher-icon resolver'
contains "$BAR_STATE" 'return "";' \
    'BarState launcher fallback is not the stock Awtarchy icon'

for style in \
    awtarchy numbers icons circled-numbers filled-dot hollow-dot bullet tiny-dot \
    bullseye fisheye half-left half-right half-bottom half-top quarter-circle \
    three-quarter-circle filled-diamond hollow-diamond center-diamond filled-square \
    hollow-square small-square filled-triangle hollow-triangle star hollow-star spark \
    minimal-bar custom-symbol
do
    contains "$BAR_STATE" "\"${style}\"" \
        "BarState preset catalog is missing ${style}"
done

for symbol in '①' '⑩' '●' '○' '•' '◦' '◎' '◉' '◐' '◑' '◒' '◓' '◔' '◕' \
    '◆' '◇' '◈' '■' '□' '▪' '▲' '△' '★' '☆' '✦' '━'
do
    contains "$BAR_STATE" "$symbol" \
        "BarState preset catalog is missing ${symbol}"
done

if grep -Fq 'function workspaceIcon(id)' "$BAR_QML"; then
    fail 'Bar still owns the old hardcoded workspace icon map'
fi
if grep -Fq 'workspaceIcon(modelData.id).replace(" ", "\\n")' "$BAR_QML"; then
    fail 'vertical workspaces still stack the number and icon'
fi
contains "$BAR_QML" 'label: BarState.workspaceLabelFor(modelData.id)' \
    'horizontal workspaces do not use the shared state resolver'
contains "$BAR_QML" 'label: BarState.workspaceVerticalLabelFor(modelData.id)' \
    'vertical workspaces do not use the compact single-row resolver'
[[ $(grep -Fc 'label: BarState.launcherIcon()' "$BAR_QML") -eq 2 ]] \
    || fail 'horizontal and vertical launcher buttons are not both state-driven'

[[ -f "$BAR_ICON_SETTINGS" ]] \
    || fail 'focused BarIconSettings component is missing'
contains "$BAR_SETTINGS" 'BarIconSettings {' \
    'existing Bar Appearance card does not host global icon customization'
contains "$BAR_ICON_SETTINGS" 'readonly property string identityStateScript:' \
    'Bar icon settings have no direct global identity-state writer path'
contains "$BAR_ICON_SETTINGS" 'model: BarState.workspaceStylePresets' \
    'Bar icon settings do not expose visual workspace presets'
contains "$BAR_ICON_SETTINGS" 'model: BarState.launcherIconPresets' \
    'Bar icon settings do not expose launcher presets'
contains "$BAR_ICON_SETTINGS" 'id: identityWriter' \
    'Bar icon settings have no serialized identity persistence process'
contains "$BAR_ICON_SETTINGS" '"set-workspace-style"' \
    'workspace preset selection is not persisted'
contains "$BAR_ICON_SETTINGS" '"set-workspace-custom-label"' \
    'global custom workspace symbol is not persisted'
contains "$BAR_ICON_SETTINGS" '"set-workspace-override"' \
    'per-workspace custom labels are not persisted'
contains "$BAR_ICON_SETTINGS" '"clear-workspace-override"' \
    'per-workspace reset is missing'
contains "$BAR_ICON_SETTINGS" '"set-launcher-icon"' \
    'custom launcher identity is not persisted'
contains "$BAR_ICON_SETTINGS" '"reset-workspace-icons"' \
    'workspace identity reset is missing'
contains "$BAR_ICON_SETTINGS" '"reset-launcher-icon"' \
    'launcher identity reset is missing'
contains "$BAR_ICON_SETTINGS" '"reset-bar-icons"' \
    'combined icon reset is missing'
contains "$BAR_ICON_SETTINGS" 'model: 10' \
    'Bar icon settings do not expose workspace overrides 1 through 10'
contains "$BAR_ICON_SETTINGS" 'property int workspaceId: index + 1' \
    'workspace override rows are not keyed to workspace number'

reset_geometry_block="$(sed -n '/function resetAppearance()/,/function runNextCommand()/p' "$BAR_SETTINGS")"
if grep -Fq 'reset-bar-icons' <<<"$reset_geometry_block"; then
    fail 'existing monitor-targeted Reset was expanded to destructive global icon reset'
fi

printf '%s\n' 'PASS: bar icon identity persistence, resolver, rendering, and control contracts are validated.'
