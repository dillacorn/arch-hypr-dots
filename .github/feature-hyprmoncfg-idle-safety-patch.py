#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one guarded match, found {count}")
    write(path, text.replace(old, new, 1))


def replace_count(path: str, old: str, new: str, expected: int) -> None:
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise SystemExit(
            f"{path}: expected exactly {expected} guarded matches, found {count}"
        )
    write(path, text.replace(old, new))


def sha256(path: str) -> str:
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


# Preserve the current managed Quick Settings / Bar states before changing them.
history_path = "local/share/awtarchy/quickshell-managed-history.sha256"
history = read(history_path)
managed_entries: list[str] = []
for source, installed in (
    ("config/quickshell/awtarchy/QuickSettings.qml", ".config/quickshell/awtarchy/QuickSettings.qml"),
    ("config/quickshell/awtarchy/Bar.qml", ".config/quickshell/awtarchy/Bar.qml"),
):
    line = f"{sha256(source)}\t{installed}"
    if line not in history:
        managed_entries.append(line)

system_state_baseline = (
    "e813a7a6c197df3df5cf57c0141c6912b89636a788d81057d45827b0e90765ce"
    "\t.config/quickshell/awtarchy/SystemState.qml"
)
if system_state_baseline not in history:
    raise SystemExit("managed history is missing the pre-feature SystemState.qml baseline")

if managed_entries:
    history = history.rstrip("\n") + (
        "\n\n# 2026-09-03 Always Awake Quick Settings and bar idle-mode status.\n"
        + "\n".join(managed_entries)
        + "\n"
    )
    write(history_path, history)


# Repair two unrelated artifacts from the earlier contents-API full-file write.
replace_once(
    "config/hypr/hyprland.lua",
    '    { leaf = "fadeOut", enabled = 1, speed = 1.3, bezier = "linear", style = "popin 87%" },',
    '    { leaf = "fadeOut", enabled = 1, speed = 1.3, bezier = "softFade" },',
)
replace_once(
    "config/hypr/hyprland.lua",
    '    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = direction }), {})\nend\n-- Send current workspace to monitor',
    '    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = direction }), {})\nend\n\n-- Send current workspace to monitor',
)
hypr_path = ROOT / "config/hypr/hyprland.lua"
hypr_path.write_text(
    hypr_path.read_text(encoding="utf-8").rstrip("\n") + "\n",
    encoding="utf-8",
)


# Add the stronger session-only mode to the existing Awtarchy card rather than
# creating another reorderable Quick Settings section.
quick_old = '''                                Text {
                                    Layout.fillWidth: true
                                    text: "Built-in manual for keybinds, Quickshell, display, gaming, packages, maintenance, networking, troubleshooting, and Extra Notes."
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }
'''
quick_new = quick_old + '''
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: Theme.active
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Always Awake"
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(10)
                                            font.bold: true
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Blocks lock, display-off, and suspend until disabled. Session only."
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            wrapMode: Text.Wrap
                                        }
                                    }

                                    SettingsButton {
                                        label: SystemState.idleMode === "always-awake" ? "On" : "Off"
                                        active: SystemState.idleMode === "always-awake"
                                        textSize: root.scaledText(9)
                                        onClicked: SystemState.setIdleMode(
                                            SystemState.idleMode === "always-awake"
                                                ? "off" : "always-awake")
                                    }
                                }
'''
replace_once("config/quickshell/awtarchy/QuickSettings.qml", quick_old, quick_new)


# Keep both horizontal and vertical bar eyes as the quick Keep Awake toggle,
# while making the stronger mode textually distinguishable in either layout.
replace_count(
    "config/quickshell/awtarchy/Bar.qml",
    '                tooltip: SystemState.idleInhibited ? "Idle inhibitor: activated\\nClick to deactivate" : "Idle inhibitor: deactivated\\nClick to activate"',
    '''                tooltip: SystemState.idleMode === "always-awake"
                    ? "Always Awake: activated\\nAll idle actions are blocked\\nClick to deactivate"
                    : (SystemState.idleInhibited
                        ? "Keep Awake: activated\\nLocks and turns displays off after 4 hours idle\\nClick to deactivate"
                        : "Idle inhibitor: deactivated\\nClick to activate Keep Awake")''',
    2,
)


# Document the new monitor-config shortcut in the built-in manual.
replace_once(
    "config/hypr/scripts/awtarchy-tips-tui.sh",
    "  SUPER+SHIFT+E                Yazi\n  SUPER+P                      Power menu",
    "  SUPER+SHIFT+E                Yazi\n  SUPER+CTRL+M                 Monitor configuration\n  SUPER+P                      Power menu",
)


# v3.4.7's post-release repair must stay historical. It should continue to
# repair instant bar feedback without being expected to reproduce future idle
# mode features added to current SystemState.qml.
replace_once(
    "tests/test-bar-control-actions.sh",
    '''repair_v347_idle_inhibitor_feedback_target "$v347_target_home" v3.4.7
cmp -s "${v347_target_home}/${v347_rel}" "$SYSTEM_STATE" \\
  || fail "v3.4.7 post-release repair does not produce the current fixed SystemState.qml"
''',
    '''repair_v347_idle_inhibitor_feedback_target "$v347_target_home" v3.4.7
grep -Fq 'property bool idleReconcilePending: false' "${v347_target_home}/${v347_rel}" \\
  || fail "v3.4.7 post-release repair does not add pending backend reconciliation"
grep -Fq 'root.idleInhibited = !root.idleInhibited;' "${v347_target_home}/${v347_rel}" \\
  || fail "v3.4.7 post-release repair does not add immediate visual feedback"
grep -Fq 'idleToggleProcess.exec([idleScript, "toggle"]);' "${v347_target_home}/${v347_rel}" \\
  || fail "v3.4.7 post-release repair does not use the managed toggle process"
! grep -Fq 'property string idleMode:' "${v347_target_home}/${v347_rel}" \\
  || fail "v3.4.7 post-release repair unexpectedly backports later idle-mode behavior"
''',
)

print("Scoped hyprmoncfg / idle-safety patch applied.")
