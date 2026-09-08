#!/usr/bin/env bash
set -euo pipefail

# TDD regression for persistent per-workspace bar visibility.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_HELPER="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
BAR="$ROOT/config/quickshell/awtarchy/Bar.qml"
FLYOUT_MANAGER="$ROOT/config/quickshell/awtarchy/FlyoutManager.qml"
HYPRLAND="$ROOT/config/hypr/hyprland.lua"
BAR_TOGGLE="$ROOT/config/hypr/scripts/quickshell_bar_toggle.sh"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/cache/awtarchy" "$TMP/bin"

cat >"$TMP/cache/awtarchy/quickshell-state.json" <<'JSON'
{
  "enabled": true,
  "monitors": {"DP-1": {"enabled": true}},
  "bar_appearance": {
    "workspace_icon_style": "awtarchy"
  },
  "unrelated": {"keep": true}
}
JSON

cat >"$TMP/bin/quickshell.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/bin/quickshell.sh"

run_state() {
    XDG_CACHE_HOME="$TMP/cache" \
    HYPR_QUICKSHELL_SCRIPT="$TMP/bin/quickshell.sh" \
    "$STATE_HELPER" "$@"
}

run_state set-bar-workspace-visible 1 false
jq -e '.bar_appearance.hidden_workspaces == [1] and .bar_appearance.workspace_icon_style == "awtarchy" and .unrelated.keep == true' \
    "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
    || { echo 'FAIL: hiding workspace 1 did not persist cleanly' >&2; exit 1; }

run_state reset-bar-icons
jq -e '.bar_appearance.hidden_workspaces == [1] and (.bar_appearance.workspace_icon_style | not) and .unrelated.keep == true' \
    "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
    || { echo 'FAIL: resetting bar icons destroyed workspace visibility state' >&2; exit 1; }

run_state set-bar-workspace-visible 2 false
jq -e '.bar_appearance.hidden_workspaces == [1,2]' \
    "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
    || { echo 'FAIL: hiding workspace 2 did not preserve workspace 1' >&2; exit 1; }

run_state set-bar-workspace-visible 1 true
jq -e '.bar_appearance.hidden_workspaces == [2]' \
    "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
    || { echo 'FAIL: restoring workspace 1 did not remove only workspace 1' >&2; exit 1; }

run_state set-bar-workspace-visible 2 true
jq -e '(.bar_appearance.hidden_workspaces | not) and .unrelated.keep == true' \
    "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
    || { echo 'FAIL: restoring the last hidden workspace did not clean up only the visibility state' >&2; exit 1; }

if run_state set-bar-workspace-visible 11 false >/dev/null 2>&1; then
    echo 'FAIL: invalid workspace 11 was accepted' >&2
    exit 1
fi

python3 - "$BAR_STATE" "$QUICK_SETTINGS" "$BAR" "$FLYOUT_MANAGER" "$HYPRLAND" "$BAR_TOGGLE" <<'PY'
from pathlib import Path
import sys

bar_state, quick, bar, manager, hyprland, toggle = [Path(p).read_text() for p in sys.argv[1:]]

def need(text, needle, message):
    if needle not in text:
        raise SystemExit('FAIL: ' + message)

need(bar_state, 'function workspaceVisible(id)', 'BarState does not expose workspace visibility')
need(bar_state, 'hidden_workspaces', 'BarState does not read persisted hidden workspaces')
need(bar_state, 'function activeWorkspaceIdForMonitor(name)', 'BarState cannot resolve the active workspace for a monitor')
need(bar_state, 'function workspaceHiddenForMonitor(name)', 'BarState cannot suppress only the monitor showing a hidden workspace')
need(bar_state, 'if (workspaceHiddenForMonitor(name))', 'BarState.enabledFor does not honor hidden workspaces')

need(bar, 'BarState.enabledFor(monitorName)', 'Bar window is not driven by effective BarState visibility')
need(bar, '!workspaceFullscreenForMonitor(monitorName)', 'fullscreen bar suppression regressed')
need(manager, 'BarState.enabledFor(monitor)', 'FlyoutManager does not use effective bar visibility')
need(manager, '!workspaceFullscreenForMonitor(monitor)', 'FlyoutManager fullscreen fallback regressed')

need(quick, 'property bool barVisibilityOpen: false', 'Quick Settings has no compact workspace visibility expander state')
need(quick, 'label: root.barStatus.enabled ? "Visible" : "Hidden"', 'existing visibility status label was lost')
need(quick, 'root.barVisibilityOpen = !root.barVisibilityOpen', 'Visible button does not expand workspace visibility controls')
need(quick, 'model: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]', 'workspace visibility menu does not expose workspaces 1-10')
need(quick, 'active: BarState.workspaceVisible(Number(modelData))', 'workspace buttons do not highlight visible workspaces')
need(quick, '"set-bar-workspace-visible", String(modelData)', 'workspace buttons do not persist visibility through the shared state helper')

visible_label = quick.index('label: root.barStatus.enabled ? "Visible" : "Hidden"')
visible_block_end = quick.find('SettingsButton {', visible_label + 1)
visible_block = quick[visible_label: visible_block_end if visible_block_end >= 0 else len(quick)]
if '"bar-enabled"' in visible_block:
    raise SystemExit('FAIL: Visible button still directly toggles per-monitor visibility instead of opening the workspace menu')

need(hyprland, '{ "SUPER + ALT + CTRL + B", bar_toggle }', 'focused-monitor bar toggle keybind changed')
need(toggle, '""|--focused|-f) exec "$QS_SH" toggle-autohide-focused', 'bar auto-hide helper no longer targets the focused monitor')

print('PASS: per-workspace bar visibility contract')
PY
