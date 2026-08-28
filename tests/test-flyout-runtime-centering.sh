#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="${ROOT}/config/quickshell/awtarchy/FlyoutManager.qml"
LAUNCHER="${ROOT}/config/quickshell/awtarchy/Launcher.qml"
CLIPBOARD="${ROOT}/config/quickshell/awtarchy/ClipboardMenu.qml"
NOTIFICATIONS="${ROOT}/config/quickshell/awtarchy/Notifications.qml"
NETWORK="${ROOT}/config/quickshell/awtarchy/NetworkMenu.qml"
BLUETOOTH="${ROOT}/config/quickshell/awtarchy/BluetoothMenu.qml"
HYPR="${ROOT}/config/hypr/hyprland.lua"
TOGGLE="${ROOT}/config/hypr/scripts/quickshell_notifications_toggle.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_count() {
    local file="$1" needle="$2" expected="$3" message="$4"
    local actual
    actual="$(grep -Fc -- "$needle" "$file" || true)"
    [[ "$actual" == "$expected" ]] || fail "$message (expected $expected, got $actual)"
}

# Shared effective bar visibility must mirror the bar's real runtime visibility,
# including fullscreen suppression, while still having a deterministic fallback
# before the per-monitor Bar instances are available.
assert_contains "$MANAGER" 'function workspaceFullscreenForMonitor(name)' \
    'FlyoutManager has no per-monitor fullscreen helper'
assert_contains "$MANAGER" 'workspace.active && workspace.hasFullscreen' \
    'FlyoutManager fullscreen detection does not match Bar visibility semantics'
assert_contains "$MANAGER" 'function barVisibleOnMonitor(name)' \
    'FlyoutManager has no shared effective bar visibility helper'
assert_contains "$MANAGER" 'const matches = barWindows.filter(window =>' \
    'effective bar visibility does not inspect actual per-monitor Bar windows'
assert_contains "$MANAGER" 'return matches.some(window => Boolean(window.visible));' \
    'effective bar visibility does not honor the actual Bar visible state'
assert_contains "$MANAGER" 'return BarState.enabledFor(monitor) && !workspaceFullscreenForMonitor(monitor);' \
    'effective bar visibility has no state/fullscreen fallback'

# All keyboard-callable/prepared flyouts in this feature must center when the
# bar is not actually visible, not merely when it is disabled in saved state.
assert_count "$LAUNCHER" 'FlyoutManager.barVisibleOnMonitor(targetScreen.name)' 2 \
    'launcher does not use shared effective bar visibility in both placement paths'
assert_count "$CLIPBOARD" 'FlyoutManager.barVisibleOnMonitor(targetScreen.name)' 1 \
    'clipboard does not use shared effective bar visibility'
assert_count "$NOTIFICATIONS" 'FlyoutManager.barVisibleOnMonitor(targetScreen.name)' 1 \
    'notifications do not use shared effective bar visibility'
assert_count "$NETWORK" 'FlyoutManager.barVisibleOnMonitor(targetScreen.name)' 1 \
    'network flyout does not use shared effective bar visibility'
assert_count "$BLUETOOTH" 'FlyoutManager.barVisibleOnMonitor(targetScreen.name)' 1 \
    'Bluetooth flyout does not use shared effective bar visibility'

# Keyboard-opened notifications should be centered along a visible bar edge.
# Bar-item opens keep their exact item anchor, and a hidden/no bar returns a
# fully centered placement through placementForScreen().
assert_contains "$NOTIFICATIONS" 'property bool edgeCentered: false' \
    'notifications do not track keyboard edge-centering separately from item anchoring'
assert_contains "$NOTIFICATIONS" 'function centeredAnchorForScreen(targetScreen)' \
    'notifications have no centered bar-edge anchor helper'
assert_contains "$NOTIFICATIONS" 'edgeCentered = !anchorItem && placement !== "center";' \
    'notification keyboard opens are not distinguished from bar-item opens'
assert_contains "$NOTIFICATIONS" '? centeredAnchorForScreen(targetScreen) : anchorCoordinate(anchorItem);' \
    'notification keyboard and bar-item anchor paths are not preserved separately'
assert_contains "$NOTIFICATIONS" 'if (edgeCentered && activeScreen)' \
    'notification edge-centering is not maintained when panel size changes'

# SUPER+N is intentionally available only in default and noalt. Existing
# application launcher and power-menu behavior must remain unchanged.
[[ -f "$TOGGLE" ]] || fail 'notification toggle wrapper does not exist'
assert_contains "$TOGGLE" 'exec qs -c awtarchy ipc call notifications toggle' \
    'notification toggle wrapper does not call the Notifications IPC target'
assert_contains "$HYPR" 'local notifications_toggle = "~/.config/hypr/scripts/quickshell_notifications_toggle.sh"' \
    'Hyprland config does not define the notification toggle command'
assert_count "$HYPR" 'hl.bind("SUPER + N", hl.dsp.exec_cmd(notifications_toggle), {})' 2 \
    'SUPER+N must exist exactly once in default mode and once in noalt'
assert_count "$HYPR" '{ "ALT + P", app_launcher },' 2 \
    'ALT+P application launcher binding changed unexpectedly'
assert_count "$HYPR" '{ "SUPER + D", app_launcher },' 2 \
    'SUPER+D application launcher binding changed unexpectedly'
assert_count "$HYPR" 'hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})' 2 \
    'SUPER+P power-menu binding changed unexpectedly'

python3 - "$HYPR" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
blocks = {
    name: body
    for name, body in re.findall(
        r'hl\.define_submap\("([^"]+)", function\(\)(.*?)(?=\nhl\.define_submap\(|\Z)',
        text,
        re.S,
    )
}
for name in ("mouse", "vm"):
    body = blocks.get(name)
    if body is None:
        raise SystemExit(f"FAIL: could not locate {name} submap")
    if "notifications_toggle" in body or 'hl.bind("SUPER + N"' in body:
        raise SystemExit(f"FAIL: notification bind leaked into {name} submap")

noalt = blocks.get("noalt")
if noalt is None or 'hl.bind("SUPER + N", hl.dsp.exec_cmd(notifications_toggle), {})' not in noalt:
    raise SystemExit("FAIL: SUPER+N is not present in noalt submap")
PY

printf '%s\n' 'PASS: flyouts center when the bar is not effectively visible; notifications keep edge/item behavior and expected binds.'
