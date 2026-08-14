#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
QML = ROOT / "config/quickshell/awtarchy"
SCRIPTS = ROOT / "config/hypr/scripts"


def load(path: Path) -> str:
    return path.read_text()


def save(path: Path, text: str) -> None:
    path.write_text(text)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def sub_once(text: str, pattern: str, replacement: str, label: str, flags: int = 0) -> str:
    result, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected one regex match, found {count}")
    return result


def insert_before(text: str, marker: str, addition: str, label: str) -> str:
    count = text.count(marker)
    if count != 1:
        raise SystemExit(f"{label}: expected one marker, found {count}")
    return text.replace(marker, addition + marker, 1)


def replace_function(text: str, name: str, replacement: str) -> str:
    start_marker = f"    function {name}("
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f"function {name}: start marker missing")
    next_function = text.find("\n    function ", start + len(start_marker))
    if next_function < 0:
        raise SystemExit(f"function {name}: next function marker missing")
    return text[:start] + replacement.rstrip() + "\n" + text[next_function + 1:]


def remove_section_between(text: str, start_marker: str, end_marker: str, label: str) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f"{label}: start marker missing")
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"{label}: end marker missing")
    return text[:start] + text[end:]


network_path = QML / "NetworkMenu.qml"
network_original = load(network_path)
if "property bool vpnPrivacyOpening: false" in network_original:
    print("Privacy patch already present.")
    raise SystemExit(0)

# FlyoutSettings no longer owns capture visibility UI or an alternate VPN path.
path = QML / "FlyoutSettings.qml"
text = load(path)
text = replace_once(
    text,
    '    implicitHeight: copyOpen ? 104\n'
    '        : (effectiveShowCaptureControl ? 170 : 139)\n'
    '            + (surfaceLabel === "Network" ? vpnSection.implicitHeight + 6 : 0)\n'
    '            + (surfaceLabel === "Quick Settings" ? barSection.implicitHeight + 6 : 0)\n',
    '    implicitHeight: copyOpen ? 104\n'
    '        : 139 + (surfaceLabel === "Quick Settings" ? barSection.implicitHeight + 6 : 0)\n',
    "FlyoutSettings height",
)
capture_visible = "            visible: !root.copyOpen && root.effectiveShowCaptureControl\n"
visible_at = text.find(capture_visible)
if visible_at < 0:
    raise SystemExit("FlyoutSettings capture row marker missing")
capture_start = text.rfind("        RowLayout {\n", 0, visible_at)
vpn_start = text.find("        NetworkVpnSection {\n", visible_at)
if capture_start < 0 or vpn_start < 0:
    raise SystemExit("FlyoutSettings capture row bounds missing")
text = text[:capture_start] + text[vpn_start:]
text = remove_section_between(
    text,
    "        NetworkVpnSection {\n",
    "        BarSettingsSection {\n",
    "FlyoutSettings embedded VPN",
)
save(path, text)

# Existing flyouts already own capture state. Put the indicator in their headers.
path = QML / "ClipboardMenu.qml"
text = load(path)
gear = '''                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 26
                            color: root.settingsOpen ? Theme.focus
'''
eye = '''                        CaptureEyeButton {
                            captureAllowed: root.captureAllowed
                            textSize: Math.max(11, Math.round(13 * root.effectiveIconScale / 100))
                            onClicked: root.toggleCaptureAllowed()
                        }

'''
text = insert_before(text, gear, eye, "Clipboard capture eye")
save(path, text)

path = QML / "Notifications.qml"
text = load(path)
text = insert_before(text, gear, eye, "Notifications capture eye")
save(path, text)

path = QML / "QuickSettings.qml"
text = load(path)
text = sub_once(
    text,
    r'    function forceNumlockOff\(\) \{.*?\n    \}\n\n(?=    function toggleNumlockSessionStart)',
    "",
    "QuickSettings duplicate Num Lock function",
    re.S,
)
text = replace_once(
    text,
    "            forceNumlockOff();\n",
    "            NumlockSessionTweak.enforce();\n",
    "QuickSettings Num Lock toggle",
)
text = replace_once(
    text,
    "                Qt.callLater(() => root.forceNumlockOff());\n",
    "                Qt.callLater(() => NumlockSessionTweak.enforce());\n",
    "QuickSettings Num Lock load",
)
text = sub_once(
    text,
    r'\n    Process \{\n        id: numlockPrimeProcess\n.*?\n    Process \{\n        id: numlockOffProcess\n    \}\n',
    "\n",
    "QuickSettings duplicate Num Lock processes",
    re.S,
)
gear_settings = '''                        SettingsButton {
                            label: ""
                            active: root.settingsOpen
'''
eye_settings = '''                        CaptureEyeButton {
                            captureAllowed: root.captureAllowed
                            textSize: root.scaledIcon(12)
                            onClicked: root.toggleCaptureAllowed()
                        }

'''
text = insert_before(text, gear_settings, eye_settings, "QuickSettings capture eye")
save(path, text)

# Network gets its own persistent capture state plus a fail-closed sensitive VPN gate.
path = network_path
text = network_original
text = replace_once(
    text,
    "    property bool vpnOpen: false\n",
    "    property bool vpnOpen: false\n"
    "    property bool vpnPrivacyOpening: false\n"
    "    property bool vpnPrivacyUnlockPending: false\n"
    "    property string vpnPrivacyAction: \"\"\n",
    "Network VPN privacy state",
)
text = replace_once(
    text,
    "    property int iconScaleOverride: -1\n",
    "    property int iconScaleOverride: -1\n"
    "    property int captureAllowedOverride: -1\n"
    "    property bool privacyRemapPending: false\n",
    "Network capture state",
)
text = replace_once(
    text,
    "        iconScale: 100\n    })\n",
    "        iconScale: 100,\n        captureAllowed: false\n    })\n",
    "Network saved capture default",
)
text = replace_once(
    text,
    '    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"\n',
    '    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"\n'
    '    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"\n'
    '    readonly property string sensitiveCaptureScript: configHome + "/hypr/scripts/quickshell_sensitive_capture.sh"\n',
    "Network privacy helper paths",
)
text = replace_once(
    text,
    "    readonly property int effectiveIconScale: iconScaleOverride >= 0\n"
    "        ? iconScaleOverride : BarState.networkViewFor(activeMonitorName).iconScale\n",
    "    readonly property int effectiveIconScale: iconScaleOverride >= 0\n"
    "        ? iconScaleOverride : BarState.networkViewFor(activeMonitorName).iconScale\n"
    "    readonly property bool captureAllowed: captureAllowedOverride >= 0\n"
    "        ? captureAllowedOverride === 1 : BarState.captureAllowedFor(\"network\")\n",
    "Network effective capture state",
)
text = replace_once(
    text,
    "        || savedView.iconScale !== effectiveIconScale\n",
    "        || savedView.iconScale !== effectiveIconScale\n"
    "        || savedView.captureAllowed !== captureAllowed\n",
    "Network capture dirty state",
)
text = replace_once(
    text,
    "        iconScaleOverride = persisted.iconScale;\n        savedView = ({\n",
    "        iconScaleOverride = persisted.iconScale;\n"
    "        captureAllowedOverride = BarState.captureAllowedFor(\"network\") ? 1 : 0;\n"
    "        savedView = ({\n",
    "Network load capture",
)
text = replace_once(
    text,
    "            textScale: textScaleOverride,\n            iconScale: iconScaleOverride\n        });\n",
    "            textScale: textScaleOverride,\n"
    "            iconScale: iconScaleOverride,\n"
    "            captureAllowed: captureAllowed\n"
    "        });\n",
    "Network loaded view capture",
)
text = replace_once(
    text,
    "            textScale: effectiveTextScale,\n            iconScale: effectiveIconScale\n        });\n",
    "            textScale: effectiveTextScale,\n"
    "            iconScale: effectiveIconScale,\n"
    "            captureAllowed: captureAllowed\n"
    "        });\n",
    "Network accepted view capture",
)
text = replace_once(
    text,
    "        iconScaleOverride = savedView.iconScale;\n        applyWindowSize(width, height);\n",
    "        iconScaleOverride = savedView.iconScale;\n"
    "        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;\n"
    "        applyWindowSize(width, height);\n",
    "Network discard capture",
)
text = replace_once(
    text,
    "            String(effectiveTextScale), String(effectiveIconScale), \"false\"\n",
    "            String(effectiveTextScale), String(effectiveIconScale),\n"
    "            captureAllowed ? \"true\" : \"false\"\n",
    "Network save capture",
)
text = replace_once(
    text,
    "        textScaleOverride = 100;\n        iconScaleOverride = 100;\n",
    "        const wasCaptureAllowed = captureAllowed;\n"
    "        textScaleOverride = 100;\n"
    "        iconScaleOverride = 100;\n"
    "        captureAllowedOverride = 0;\n",
    "Network reset capture",
)
text = replace_once(
    text,
    "            textScale: 100,\n            iconScale: 100\n        });\n"
    "        queueStateCommand([\"reset-flyout\", \"network\", activeMonitorName]);\n",
    "            textScale: 100,\n"
    "            iconScale: 100,\n"
    "            captureAllowed: false\n"
    "        });\n"
    "        privacyRemapPending = wasCaptureAllowed;\n"
    "        queueStateCommand([\"reset-flyout\", \"network\", activeMonitorName]);\n",
    "Network reset saved capture",
)
network_helpers = '''    function toggleCaptureAllowed() {
        if (vpnOpen || vpnPrivacyOpening)
            return;
        const next = !captureAllowed;
        captureAllowedOverride = next ? 1 : 0;
        savedView = Object.assign({}, savedView, { captureAllowed: next });
        privacyRemapPending = true;
        queueStateCommand(["set-capture", "network", next ? "true" : "false"]);
        settingsMessage = next
            ? "Network is visible in captures" : "Network capture protection enabled";
    }

    function startVpnUnlock() {
        if (vpnPrivacyProcess.running) {
            vpnPrivacyUnlockPending = true;
            return;
        }
        vpnPrivacyUnlockPending = false;
        vpnPrivacyAction = "unlock";
        vpnPrivacyProcess.exec([root.sensitiveCaptureScript, "network", "unlock"]);
    }

    function openVpnView() {
        if (vpnOpen || vpnPrivacyOpening)
            return;
        if (vpnPrivacyProcess.running) {
            actionMessage = "VPN privacy protection is still initializing";
            return;
        }
        settingsOpen = false;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
        cancelWifiPassword();
        vpnPrivacyUnlockPending = false;
        vpnPrivacyOpening = true;
        vpnPrivacyAction = "lock";
        vpnPrivacyProcess.exec([root.sensitiveCaptureScript, "network", "lock"]);
    }

    function closeVpnView() {
        const wasSensitive = vpnOpen || vpnPrivacyOpening;
        vpnOpen = false;
        vpnPrivacyOpening = false;
        if (wasSensitive)
            startVpnUnlock();
    }

'''
text = insert_before(text, "    function toggleSettings() {\n", network_helpers, "Network privacy helpers")
text = replace_function(text, "toggleSettings", '''    function toggleSettings() {
        if (vpnOpen || vpnPrivacyOpening)
            closeVpnView();
        settingsOpen = !settingsOpen;
        settingsPanel.resetCopySelection();
        settingsMessage = "";
    }
''')
text = replace_function(text, "toggleVpn", '''    function toggleVpn() {
        if (vpnOpen || vpnPrivacyOpening)
            closeVpnView();
        else
            openVpnView();
    }
''')
text = replace_once(
    text,
    "        settingsOpen = false;\n        vpnOpen = false;\n        settingsMessage = \"\";\n",
    "        settingsOpen = false;\n"
    "        if (vpnOpen || vpnPrivacyOpening)\n"
    "            closeVpnView();\n"
    "        settingsMessage = \"\";\n",
    "Network open sensitive cleanup",
)
text = replace_once(
    text,
    "        networkWindow.visible = false;\n        setWifiScanning(false);\n",
    "        networkWindow.visible = false;\n"
    "        if (vpnOpen || vpnPrivacyOpening)\n"
    "            closeVpnView();\n"
    "        setWifiScanning(false);\n",
    "Network close sensitive cleanup",
)
text = replace_once(
    text,
    "        settingsOpen = false;\n        vpnOpen = false;\n        settingsMessage = \"\";\n",
    "        settingsOpen = false;\n        settingsMessage = \"\";\n",
    "Network close VPN reset",
)
state_marker = '''    Process {
        id: stateWriter
        onExited: {
            BarState.refresh();
            Qt.callLater(() => root.runNextStateCommand());
        }
    }

    IpcHandler {
'''
network_processes = '''    Process {
        id: stateWriter
        onExited: {
            BarState.refresh();
            privacyRuleUpdater.exec([root.runtimeRulesScript]);
            Qt.callLater(() => root.runNextStateCommand());
        }
    }

    Process {
        id: privacyRuleUpdater
        onExited: {
            if (!root.privacyRemapPending)
                return;
            root.privacyRemapPending = false;
            if (!networkWindow.visible || root.vpnOpen || root.vpnPrivacyOpening)
                return;
            networkWindow.visible = false;
            Qt.callLater(() => {
                networkWindow.visible = true;
                root.positionWindow();
            });
        }
    }

    Process {
        id: vpnPrivacyProcess
        onExited: (exitCode, exitStatus) => {
            const completedAction = root.vpnPrivacyAction;
            root.vpnPrivacyAction = "";

            if (completedAction === "lock") {
                if (exitCode !== 0) {
                    root.vpnPrivacyOpening = false;
                    root.vpnOpen = false;
                    root.actionMessage = "VPN capture protection unavailable";
                    root.vpnPrivacyUnlockPending = false;
                    Qt.callLater(() => root.startVpnUnlock());
                    return;
                }
                if (root.vpnPrivacyUnlockPending) {
                    root.vpnPrivacyOpening = false;
                    root.vpnOpen = false;
                    root.vpnPrivacyUnlockPending = false;
                    Qt.callLater(() => root.startVpnUnlock());
                    return;
                }
                root.vpnPrivacyOpening = false;
                root.vpnOpen = true;
                return;
            }

            if (completedAction === "unlock")
                root.vpnPrivacyUnlockPending = false;
        }
    }

    Component.onCompleted: {
        root.vpnPrivacyAction = "unlock";
        vpnPrivacyProcess.exec([root.sensitiveCaptureScript, "network", "unlock"]);
    }

    IpcHandler {
'''
text = replace_once(text, state_marker, network_processes, "Network privacy processes")
vpn_button = '''                        SettingsButton {
                            label: "󰒃"
                            active: root.vpnOpen
'''
network_eye = '''                        CaptureEyeButton {
                            captureAllowed: root.captureAllowed && !root.vpnOpen && !root.vpnPrivacyOpening
                            locked: root.vpnOpen || root.vpnPrivacyOpening
                            textSize: root.scaledIcon(12)
                            onClicked: root.toggleCaptureAllowed()
                        }

'''
text = replace_once(
    text,
    vpn_button,
    network_eye + vpn_button.replace("active: root.vpnOpen", "active: root.vpnOpen || root.vpnPrivacyOpening"),
    "Network capture eye",
)
save(path, text)

# Bluetooth receives the same persisted capture behavior as the other ordinary flyouts.
path = QML / "BluetoothMenu.qml"
text = load(path)
text = replace_once(
    text,
    "    property int iconScaleOverride: -1\n",
    "    property int iconScaleOverride: -1\n"
    "    property int captureAllowedOverride: -1\n"
    "    property bool privacyRemapPending: false\n",
    "Bluetooth capture state",
)
text = replace_once(
    text,
    "        iconScale: 100\n    })\n",
    "        iconScale: 100,\n        captureAllowed: false\n    })\n",
    "Bluetooth saved capture default",
)
text = replace_once(
    text,
    '    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"\n',
    '    readonly property string stateScript: configHome + "/hypr/scripts/quickshell_application_state.sh"\n'
    '    readonly property string runtimeRulesScript: configHome + "/hypr/scripts/quickshell_runtime_rules.sh"\n',
    "Bluetooth runtime rules path",
)
text = replace_once(
    text,
    "    readonly property int effectiveIconScale: iconScaleOverride >= 0\n"
    "        ? iconScaleOverride : BarState.bluetoothViewFor(activeMonitorName).iconScale\n",
    "    readonly property int effectiveIconScale: iconScaleOverride >= 0\n"
    "        ? iconScaleOverride : BarState.bluetoothViewFor(activeMonitorName).iconScale\n"
    "    readonly property bool captureAllowed: captureAllowedOverride >= 0\n"
    "        ? captureAllowedOverride === 1 : BarState.captureAllowedFor(\"bluetooth\")\n",
    "Bluetooth effective capture state",
)
text = replace_once(
    text,
    "        || savedView.iconScale !== effectiveIconScale\n",
    "        || savedView.iconScale !== effectiveIconScale\n"
    "        || savedView.captureAllowed !== captureAllowed\n",
    "Bluetooth capture dirty state",
)
text = replace_once(
    text,
    "        iconScaleOverride = persisted.iconScale;\n        savedView = ({\n",
    "        iconScaleOverride = persisted.iconScale;\n"
    "        captureAllowedOverride = BarState.captureAllowedFor(\"bluetooth\") ? 1 : 0;\n"
    "        savedView = ({\n",
    "Bluetooth load capture",
)
text = replace_once(
    text,
    "            textScale: textScaleOverride,\n            iconScale: iconScaleOverride\n        });\n",
    "            textScale: textScaleOverride,\n"
    "            iconScale: iconScaleOverride,\n"
    "            captureAllowed: captureAllowed\n"
    "        });\n",
    "Bluetooth loaded view capture",
)
text = replace_once(
    text,
    "            textScale: effectiveTextScale,\n            iconScale: effectiveIconScale\n        });\n",
    "            textScale: effectiveTextScale,\n"
    "            iconScale: effectiveIconScale,\n"
    "            captureAllowed: captureAllowed\n"
    "        });\n",
    "Bluetooth accepted view capture",
)
text = replace_once(
    text,
    "        iconScaleOverride = savedView.iconScale;\n        applyWindowSize(width, height);\n",
    "        iconScaleOverride = savedView.iconScale;\n"
    "        captureAllowedOverride = savedView.captureAllowed ? 1 : 0;\n"
    "        applyWindowSize(width, height);\n",
    "Bluetooth discard capture",
)
text = replace_once(
    text,
    "            String(effectiveTextScale), String(effectiveIconScale), \"false\"\n",
    "            String(effectiveTextScale), String(effectiveIconScale),\n"
    "            captureAllowed ? \"true\" : \"false\"\n",
    "Bluetooth save capture",
)
text = replace_once(
    text,
    "        textScaleOverride = 100;\n        iconScaleOverride = 100;\n",
    "        const wasCaptureAllowed = captureAllowed;\n"
    "        textScaleOverride = 100;\n"
    "        iconScaleOverride = 100;\n"
    "        captureAllowedOverride = 0;\n",
    "Bluetooth reset capture",
)
text = replace_once(
    text,
    "            textScale: 100,\n            iconScale: 100\n        });\n"
    "        queueStateCommand([\"reset-flyout\", \"bluetooth\", activeMonitorName]);\n",
    "            textScale: 100,\n"
    "            iconScale: 100,\n"
    "            captureAllowed: false\n"
    "        });\n"
    "        privacyRemapPending = wasCaptureAllowed;\n"
    "        queueStateCommand([\"reset-flyout\", \"bluetooth\", activeMonitorName]);\n",
    "Bluetooth reset saved capture",
)
bluetooth_toggle = '''    function toggleCaptureAllowed() {
        const next = !captureAllowed;
        captureAllowedOverride = next ? 1 : 0;
        savedView = Object.assign({}, savedView, { captureAllowed: next });
        privacyRemapPending = true;
        queueStateCommand(["set-capture", "bluetooth", next ? "true" : "false"]);
        settingsMessage = next
            ? "Bluetooth is visible in captures" : "Bluetooth capture protection enabled";
    }

'''
text = insert_before(text, "    function toggleSettings() {\n", bluetooth_toggle, "Bluetooth capture toggle")
state_marker = '''    Process {
        id: stateWriter
        onExited: {
            BarState.refresh();
            Qt.callLater(() => root.runNextStateCommand());
        }
    }

    Timer {
'''
bluetooth_processes = '''    Process {
        id: stateWriter
        onExited: {
            BarState.refresh();
            privacyRuleUpdater.exec([root.runtimeRulesScript]);
            Qt.callLater(() => root.runNextStateCommand());
        }
    }

    Process {
        id: privacyRuleUpdater
        onExited: {
            if (!root.privacyRemapPending)
                return;
            root.privacyRemapPending = false;
            if (!bluetoothWindow.visible)
                return;
            bluetoothWindow.visible = false;
            Qt.callLater(() => {
                bluetoothWindow.visible = true;
                root.positionWindow();
            });
        }
    }

    Timer {
'''
text = replace_once(text, state_marker, bluetooth_processes, "Bluetooth privacy processes")
text = insert_before(text, gear_settings, eye_settings, "Bluetooth capture eye")
save(path, text)

# VPN diagnostics stay available, but browser handoff is explicitly outside the protected panel.
path = QML / "NetworkVpnSection.qml"
text = load(path)
text = replace_once(
    text,
    '    readonly property bool browserLinkAllowed: BarState.captureAllowedFor("network")\n',
    "",
    "Network VPN browser capture coupling",
)
text = replace_once(text, '                text: " WireGuard VPN"\n', '                text: "󰒃 WireGuard VPN"\n', "WireGuard icon")
text = sub_once(
    text,
    r'            SettingsButton \{\n                label: "WTFIsMyIP"\n                available: root\.browserLinkAllowed\n(.*?)\n            \}',
    '            SettingsButton {\n                label: "myip.wtf"\n\\1\n            }',
    "myip.wtf button",
    re.S,
)
text = sub_once(
    text,
    r'        Text \{\n            Layout\.fillWidth: true\n            visible: !root\.browserLinkAllowed\n            text: "WTFIsMyIP opens.*?"\n            color: Theme\.muted',
    '        Text {\n            Layout.fillWidth: true\n            text: "myip.wtf opens in your normal Firefox session outside this protected VPN panel. It can show your public IP, hostname, location, ISP, browser headers, and XML/YAML/JSON/plain-text output."\n            color: Theme.muted',
    "myip.wtf browser warning",
    re.S,
)
save(path, text)

# One Num Lock implementation. A bounded startup burst catches late input initialization.
path = QML / "NumlockSessionTweak.qml"
save(path, '''pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool stateLoaded: false
    property int startupAttemptsRemaining: 0
    readonly property bool enabled: numlockSettings.disableNumlockAtSessionStart

    function enforce() {
        if (!enabled || primeProcess.running || offProcess.running)
            return;

        primeProcess.exec([
            "hyprctl", "eval",
            "hl.config({ input = { numlock_by_default = true } })"
        ]);
    }

    function beginEnforcementBurst() {
        if (!enabled) {
            startupAttemptsRemaining = 0;
            return;
        }
        startupAttemptsRemaining = 4;
        enforce();
    }

    FileView {
        id: settingsFile
        path: Quickshell.statePath("quick-settings-tweaks.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.stateLoaded = true;
            if (numlockSettings.disableNumlockAtSessionStart)
                Qt.callLater(() => root.beginEnforcementBurst());
        }

        JsonAdapter {
            id: numlockSettings
            property bool disableNumlockAtSessionStart: false

            onDisableNumlockAtSessionStartChanged: {
                if (!root.stateLoaded)
                    return;
                if (disableNumlockAtSessionStart)
                    Qt.callLater(() => root.beginEnforcementBurst());
                else
                    root.startupAttemptsRemaining = 0;
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.enabled && root.startupAttemptsRemaining > 0
        onTriggered: {
            root.enforce();
            root.startupAttemptsRemaining--;
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: !root.stateLoaded
        onTriggered: settingsFile.reload()
    }

    Process {
        id: primeProcess
        onExited: {
            if (!root.enabled)
                return;
            offProcess.exec([
                "hyprctl", "eval",
                "hl.config({ input = { numlock_by_default = false } })"
            ]);
        }
    }

    Process {
        id: offProcess
    }
}
''')

# Construct the singleton at shell startup and reapply after later config reloads.
path = QML / "shell.qml"
text = load(path)
text = replace_once(
    text,
    "    readonly property bool quickSettingsReady: QuickSettings !== null\n",
    "    readonly property bool quickSettingsReady: QuickSettings !== null\n"
    "    readonly property bool numlockTweakReady: NumlockSessionTweak.enabled || !NumlockSessionTweak.enabled\n",
    "shell Num Lock singleton construction",
)
text = replace_once(
    text,
    "            if (event.name === \"configreloaded\") {\n"
    "                runtimeRules.exec([root.runtimeRulesScript]);\n"
    "                return;\n"
    "            }\n",
    "            if (event.name === \"configreloaded\") {\n"
    "                runtimeRules.exec([root.runtimeRulesScript]);\n"
    "                NumlockSessionTweak.enforce();\n"
    "                return;\n"
    "            }\n",
    "shell Num Lock config reload",
)
save(path, text)

# Runtime privacy rules honor the sensitive lock every time they are refreshed.
path = SCRIPTS / "quickshell_runtime_rules.sh"
text = load(path)
text = replace_once(
    text,
    'STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"\n',
    'STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"\n'
    'RUNTIME_ROOT="${XDG_RUNTIME_DIR:-${CACHE_HOME}/awtarchy-runtime}"\n'
    'NETWORK_SENSITIVE_LOCK="${RUNTIME_ROOT}/awtarchy/network-sensitive-capture.lock"\n',
    "runtime sensitive lock path",
)
text = replace_once(
    text,
    "bluetooth_protected=true\n",
    "bluetooth_protected=true\n"
    "network_sensitive_locked=false\n"
    '[[ -e "$NETWORK_SENSITIVE_LOCK" ]] && network_sensitive_locked=true\n',
    "runtime sensitive lock state",
)
text = replace_once(
    text,
    "capture_allowed bluetooth && bluetooth_protected=false\n",
    "capture_allowed bluetooth && bluetooth_protected=false\n"
    'if [[ "$network_sensitive_locked" == true ]]; then\n'
    "    network_protected=true\n"
    "fi\n",
    "runtime forced network protection",
)
text = replace_once(
    text,
    "awtarchy_vpn_editor_privacy_rule_v1:set_enabled(${network_protected})\n"
    "awtarchy_public_ip_privacy_rule_v1:set_enabled(${network_protected})\n",
    "awtarchy_vpn_editor_privacy_rule_v1:set_enabled(true)\n"
    "awtarchy_public_ip_privacy_rule_v1:set_enabled(true)\n",
    "runtime always-private VPN helpers",
)
save(path, text)

# Use the cleaner WTFIsMyIP alias for both browser and text lookup.
path = SCRIPTS / "quickshell_wireguard.sh"
text = load(path)
text = replace_once(text, 'WTFISMYIP_URL="https://wtfismyip.com/"\n', 'WTFISMYIP_URL="https://myip.wtf/"\n', "myip.wtf browser URL")
text = replace_once(text, 'WTFISMYIP_TEXT_URL="https://wtfismyip.com/text"\n', 'WTFISMYIP_TEXT_URL="https://myip.wtf/text"\n', "myip.wtf text URL")
save(path, text)

print("Applied Quickshell capture privacy and Num Lock changes.")
