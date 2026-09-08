#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="$ROOT/config/hypr/scripts/quickshell.sh"
TOGGLE="$ROOT/config/hypr/scripts/quickshell_bar_toggle.sh"
BACKEND="$ROOT/config/hypr/scripts/hypr_quicksettings.sh"
BAR_STATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
BAR="$ROOT/config/quickshell/awtarchy/Bar.qml"
SHELL="$ROOT/config/quickshell/awtarchy/shell.qml"
SETTINGS="$ROOT/config/quickshell/awtarchy/BarSettingsSection.qml"
QUICK="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
HYPRLAND="$ROOT/config/hypr/hyprland.lua"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

contains() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

contains "$MANAGER" 'auto_hide:false' 'quickshell monitor defaults do not include auto-hide disabled'
contains "$MANAGER" 'getautohide()' 'quickshell manager has no auto-hide getter'
contains "$MANAGER" 'set_monitor_auto_hide()' 'quickshell manager has no per-monitor auto-hide setter'
contains "$MANAGER" 'toggle_auto_hide_mon()' 'quickshell manager has no per-monitor auto-hide toggle'
contains "$MANAGER" 'toggle-autohide-focused' 'quickshell manager has no focused-monitor auto-hide command'
contains "$MANAGER" 'setautohide <MON> <true|false>' 'quickshell manager usage does not document per-monitor auto-hide'
contains "$MANAGER" 'auto_hide,' 'copy-bar-settings does not copy auto-hide state'
contains "$TOGGLE" 'toggle-autohide-focused' 'CTRL+SUPER+ALT+B helper still hard-hides the focused monitor'
contains "$HYPRLAND" '{ "SUPER + ALT + CTRL + B", bar_toggle }' 'bar auto-hide keybind changed unexpectedly'

contains "$BAR_STATE" 'function autoHideFor(name)' 'BarState does not expose persistent per-monitor auto-hide'
contains "$BAR_STATE" 'function workspaceHiddenForMonitor(name)' 'workspace hard-hide state was lost'
contains "$BAR_STATE" 'if (idleHidden())' 'idle hard-hide precedence was lost'
contains "$BAR" 'BarState.enabledFor(monitorName)' 'bar no longer honors effective hard-hide state'
contains "$BAR" '!workspaceFullscreenForMonitor(monitorName)' 'fullscreen hard-hide behavior was lost'

contains "$SHELL" 'readonly property bool autoHide: BarState.autoHideFor(monitorName)' 'bar instance does not consume BarState auto-hide state'
contains "$SHELL" 'exclusiveZone: autoHide ? 0 : BarState.barSizeFor(monitorName, vertical)' 'auto-hide mode still reserves the bar exclusive zone'
contains "$SHELL" 'property bool autoHideRevealed: true' 'bar instance has no transient reveal state'
contains "$SHELL" 'property real autoHideOffset:' 'bar instance has no animated slide offset'
contains "$SHELL" 'duration: 170' 'bar auto-hide slide animation is missing or unexpectedly slow'
contains "$SHELL" 'interval: 2000' 'initial auto-hide delay is missing'
contains "$SHELL" 'interval: 700' 'pointer-leave auto-hide delay is missing'
contains "$SHELL" 'interval: 150' 'edge reveal hover delay is missing'
contains "$SHELL" 'implicitWidth: edgeVertical ? 2 : 0' 'edge activation region is not 2 px on vertical edges'
contains "$SHELL" 'implicitHeight: edgeVertical ? 0 : 2' 'edge activation region is not 2 px on horizontal edges'
contains "$SHELL" 'color: "transparent"' 'edge activation region is visibly painted'
contains "$SHELL" 'anchors.top: edgePosition === "top" || edgeVertical' 'top/vertical edge activation anchoring is missing'
contains "$SHELL" 'anchors.bottom: edgePosition === "bottom" || edgeVertical' 'bottom/vertical edge activation anchoring is missing'
contains "$SHELL" 'anchors.left: edgePosition === "left" || !edgeVertical' 'left/horizontal edge activation anchoring is missing'
contains "$SHELL" 'anchors.right: edgePosition === "right" || !edgeVertical' 'right/horizontal edge activation anchoring is missing'
contains "$SHELL" 'FlyoutManager.activeMonitorName === monitorName' 'active flyouts do not hold the auto-hidden bar open'
contains "$SHELL" 'targetBar.visible && targetBar.autoHide && !targetBar.autoHideRevealed' 'edge reveal is not gated by actual hard-visible bar state'

contains "$SETTINGS" 'text: "Auto-hide"' 'Appearance settings no longer expose auto-hide'
contains "$SETTINGS" 'active: root.autoHideActive()' 'Appearance auto-hide control does not reflect persistent state'
contains "$SETTINGS" 'onClicked: root.toggleAutoHide()' 'Appearance auto-hide control does not toggle the configured target'
contains "$QUICK" 'active: BarState.workspaceVisible(Number(modelData))' 'workspace hard-hide controls were removed from Quick Settings'
contains "$QUICK" '"set-bar-workspace-visible", String(modelData)' 'workspace hard-hide persistence was removed from Quick Settings'

# Auto-hide must also be directly visible next to the Visible/Hidden control in
# the main Bar card. It targets the display that owns the open Quick Settings
# panel while the Appearance copy remains available for bulk-target workflows.
# shellcheck disable=SC2016
contains "$BACKEND" 'BAR_AUTO_HIDE="$(run_capture "$QUICKSHELL_SCRIPT" getautohide "$panel_monitor" || true)"' 'Quick Settings status does not read auto-hide for the panel display'
# shellcheck disable=SC2016
contains "$BACKEND" 'auto_hide:($bar_auto_hide == "true")' 'Quick Settings status JSON does not expose auto-hide'
contains "$BACKEND" 'bar-auto-hide)' 'Quick Settings backend has no direct bar auto-hide action'
# shellcheck disable=SC2016
contains "$BACKEND" '"$QUICKSHELL_SCRIPT" setautohide "$monitor" "$value"' 'Quick Settings backend does not persist direct auto-hide changes'
contains "$QUICK" 'label: root.barStatus.auto_hide ? "Auto-hide: On" : "Auto-hide: Off"' 'main Bar card has no always-visible auto-hide toggle'
contains "$QUICK" 'active: Boolean(root.barStatus.auto_hide)' 'main Bar card auto-hide toggle does not clearly reflect active state'
contains "$QUICK" '"bar-auto-hide", root.activeMonitorName,' 'main Bar card auto-hide toggle does not target the panel display'

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cache/awtarchy" "$TMP/home"

cat >"$TMP/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
    'monitors -j')
        printf '%s\n' '[{"name":"DP-1","focused":true,"disabled":false},{"name":"HDMI-A-1","focused":false,"disabled":false}]'
        ;;
    'activeworkspace -j')
        printf '%s\n' '{"monitor":"DP-1"}'
        ;;
    *)
        exit 1
        ;;
esac
SH
chmod +x "$TMP/bin/hyprctl"

cat >"$TMP/bin/qs" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$TMP/bin/qs"

printf '%s\n' '{"enabled":true,"monitors":{}}' >"$TMP/cache/awtarchy/quickshell-state.json"

run_manager() {
    PATH="$TMP/bin:$PATH" \
    HOME="$TMP/home" \
    XDG_CACHE_HOME="$TMP/cache" \
    "$MANAGER" "$@"
}

[[ "$(run_manager getautohide DP-1)" == false ]] \
    || fail 'new monitors do not default to constant visibility'
[[ "$(run_manager getautohide HDMI-A-1)" == false ]] \
    || fail 'auto-hide default leaked across monitors'

run_manager setautohide DP-1 true
[[ "$(run_manager getautohide DP-1)" == true ]] \
    || fail 'per-monitor auto-hide did not persist'
[[ "$(run_manager getautohide HDMI-A-1)" == false ]] \
    || fail 'setting DP-1 auto-hide changed HDMI-A-1'

run_manager copy-bar-settings DP-1 HDMI-A-1
[[ "$(run_manager getautohide HDMI-A-1)" == true ]] \
    || fail 'copy-bar-settings did not copy auto-hide state'

run_manager reset-mon DP-1
[[ "$(run_manager getautohide DP-1)" == false ]] \
    || fail 'reset-mon did not restore constant visibility'

run_manager toggle-autohide-mon DP-1
[[ "$(run_manager getautohide DP-1)" == true ]] \
    || fail 'toggle-autohide-mon did not enable auto-hide'
run_manager toggle-autohide-mon DP-1
[[ "$(run_manager getautohide DP-1)" == false ]] \
    || fail 'toggle-autohide-mon did not disable auto-hide'

printf 'PASS: bar auto-hide state, precedence, edge reveal, and controls contract\n'
