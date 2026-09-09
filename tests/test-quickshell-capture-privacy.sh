#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML_DIR="$ROOT_DIR/config/quickshell/awtarchy"
SCRIPT_DIR="$ROOT_DIR/config/hypr/scripts"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "missing file: ${1#"$ROOT_DIR"/}"
}

require_contains() {
    local file="$1" needle="$2"
    grep -Fq -- "$needle" "$file" || fail "${file#"$ROOT_DIR"/} missing: $needle"
}

require_sequence() {
    local file="$1" needle="$2" content
    content="$(<"$file")"
    [[ "$content" == *"$needle"* ]] || fail "${file#"$ROOT_DIR"/} missing ordered sequence"
}

require_not_contains() {
    local file="$1" needle="$2"
    if grep -Fq -- "$needle" "$file"; then
        fail "${file#"$ROOT_DIR"/} still contains: $needle"
    fi
}

capture_button="$QML_DIR/CaptureEyeButton.qml"
flyout_settings="$QML_DIR/FlyoutSettings.qml"
launcher="$QML_DIR/Launcher.qml"
network_menu="$QML_DIR/NetworkMenu.qml"
vpn_section="$QML_DIR/NetworkVpnSection.qml"
bluetooth_menu="$QML_DIR/BluetoothMenu.qml"
battery_menu="$QML_DIR/BatteryMenu.qml"
quick_settings="$QML_DIR/QuickSettings.qml"
clipboard_menu="$QML_DIR/ClipboardMenu.qml"
notifications="$QML_DIR/Notifications.qml"
shell_qml="$QML_DIR/shell.qml"
numlock_tweak="$QML_DIR/NumlockSessionTweak.qml"
runtime_rules="$SCRIPT_DIR/quickshell_runtime_rules.sh"
capture_lock="$SCRIPT_DIR/quickshell_sensitive_capture.sh"
wireguard_helper="$SCRIPT_DIR/quickshell_wireguard.sh"

for file in \
    "$capture_button" "$flyout_settings" "$launcher" "$network_menu" "$vpn_section" \
    "$bluetooth_menu" "$battery_menu" "$quick_settings" "$clipboard_menu" "$notifications" \
    "$shell_qml" "$numlock_tweak" "$runtime_rules" "$capture_lock" \
    "$wireguard_helper"; do
    require_file "$file"
done

[[ -x "$capture_lock" ]] || fail "quickshell_sensitive_capture.sh must be executable"

# Every FlyoutManager surface exposes the same immediate capture indicator.
require_contains "$capture_button" 'text: root.captureAllowed ? "" : ""'
require_contains "$capture_button" 'property bool locked: false'
require_contains "$capture_button" 'enabled: !root.locked'

for file in "$launcher" "$clipboard_menu" "$notifications" "$quick_settings" "$network_menu" "$bluetooth_menu" "$battery_menu"; do
    require_contains "$file" 'CaptureEyeButton {'
done

require_contains "$launcher" 'root.toggleCaptureAllowed();'
for file in "$clipboard_menu" "$notifications" "$quick_settings" "$network_menu" "$bluetooth_menu" "$battery_menu"; do
    require_contains "$file" 'onClicked: root.toggleCaptureAllowed()'
done

# Capture visibility is no longer buried in any settings panel, and VPN content
# may only exist behind NetworkMenu's dedicated protected VPN view.
require_not_contains "$launcher" 'Allow in screenshots and screen recordings'
require_not_contains "$flyout_settings" 'Allow in screenshots and screen recordings'
require_not_contains "$flyout_settings" 'NetworkVpnSection {'

# Connectivity and Battery own their persisted capture state just like the other flyouts.
require_contains "$network_menu" 'readonly property bool captureAllowed:'
require_contains "$network_menu" '["set-capture", "network", next ? "true" : "false"]'
require_contains "$bluetooth_menu" 'readonly property bool captureAllowed:'
require_contains "$bluetooth_menu" '["set-capture", "bluetooth", next ? "true" : "false"]'
require_contains "$battery_menu" 'readonly property bool captureAllowed:'
require_contains "$battery_menu" '["set-capture", "battery", next ? "true" : "false"]'
require_contains "$runtime_rules" 'battery_protected=true'
require_contains "$runtime_rules" 'capture_allowed battery && battery_protected=false'
require_contains "$runtime_rules" 'awtarchy_battery_window_privacy_rule_v1:set_enabled(${battery_protected})'

# VPN is fail-closed. The sensitive lock must be installed before vpnOpen becomes
# true and the already-mapped Network window must be remapped before VPN content
# is shown. Otherwise an existing shareable surface could keep the old rule.
require_contains "$network_menu" 'property bool vpnPrivacyOpening: false'
require_contains "$network_menu" 'vpnPrivacyProcess.exec([root.sensitiveCaptureScript, "network", "lock"])'
require_contains "$network_menu" 'if (exitCode !== 0)'
require_contains "$network_menu" 'function showVpnAfterPrivacyLock()'
require_sequence "$network_menu" $'networkWindow.visible = false;\n        vpnPrivacyOpening = false;\n        vpnOpen = true;\n        Qt.callLater(() => {'
require_contains "$network_menu" 'if (FlyoutManager.activeSurface !== "network" || !root.vpnOpen)'
require_contains "$network_menu" 'root.showVpnAfterPrivacyLock();'
require_contains "$network_menu" 'function remapNetworkAfterVpnUnlock()'
require_sequence "$network_menu" $'networkWindow.visible = false;\n        Qt.callLater(() => {\n            if (FlyoutManager.activeSurface !== "network"'
require_contains "$network_menu" 'root.remapNetworkAfterVpnUnlock();'
require_contains "$network_menu" 'root.vpnOpen = false;'
require_contains "$network_menu" 'vpnPrivacyProcess.exec([root.sensitiveCaptureScript, "network", "unlock"])'
require_contains "$network_menu" 'locked: root.vpnOpen || root.vpnPrivacyOpening'
require_sequence "$network_menu" $'Component.onCompleted: {\n        networkWindow.visible = false;\n        root.vpnPrivacyAction = "unlock";'
require_contains "$runtime_rules" 'network_sensitive_locked=true'
require_contains "$runtime_rules" "[[ -e \"\$NETWORK_SENSITIVE_LOCK\" ]] && network_sensitive_locked=true"
require_contains "$runtime_rules" "if [[ \"\$network_sensitive_locked\" == true ]]; then"
require_contains "$runtime_rules" 'network_protected=true'
require_contains "$runtime_rules" 'awtarchy_vpn_editor_privacy_rule_v1:set_enabled(true)'
require_contains "$runtime_rules" 'awtarchy_public_ip_privacy_rule_v1:set_enabled(true)'
require_contains "$capture_lock" 'network-sensitive-capture.lock'
require_contains "$capture_lock" "exec \"\$RUNTIME_RULES\""

# VPN/public-IP tools stay inside the protected VPN view. myip.wtf remains an
# explicit external diagnostic option and uses the cleaner alias for both page
# and plain-text IP lookup.
require_contains "$vpn_section" 'text: "󰒃 WireGuard VPN"'
require_contains "$vpn_section" 'label: "myip.wtf"'
require_contains "$vpn_section" 'outside this protected VPN panel'
require_contains "$wireguard_helper" 'WTFISMYIP_URL="https://myip.wtf/"'
require_contains "$wireguard_helper" 'WTFISMYIP_TEXT_URL="https://myip.wtf/text"'

# Num Lock is controlled by the singleton, not duplicate Quick Settings processes.
# It is reapplied after Hyprland config reloads and only retries for a bounded
# startup window instead of polling forever. Keep its root Singleton explicitly
# qualified so a managed update cannot leave the desktop shell resolving an
# unqualified/stale Singleton type during startup.
require_contains "$shell_qml" 'readonly property bool numlockTweakReady:'
require_contains "$shell_qml" 'NumlockSessionTweak.enforce()'
require_contains "$numlock_tweak" 'import Quickshell as Qs'
require_contains "$numlock_tweak" 'Qs.Singleton {'
require_contains "$numlock_tweak" 'path: Qs.Quickshell.statePath("quick-settings-tweaks.json")'
require_contains "$numlock_tweak" 'property int startupAttemptsRemaining: 0'
require_contains "$numlock_tweak" 'function beginEnforcementBurst()'
require_contains "$numlock_tweak" 'startupAttemptsRemaining = 4;'
require_contains "$numlock_tweak" 'interval: 1500'
require_contains "$numlock_tweak" 'repeat: true'
require_contains "$numlock_tweak" 'running: root.enabled && root.startupAttemptsRemaining > 0'
require_not_contains "$quick_settings" 'id: numlockPrimeProcess'
require_not_contains "$quick_settings" 'id: numlockOffProcess'
require_contains "$quick_settings" 'NumlockSessionTweak.enforce()'

printf 'Quickshell capture privacy and Num Lock regression checks passed.\n'
