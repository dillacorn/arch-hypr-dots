#!/usr/bin/env python3
from pathlib import Path
import hashlib
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one {label}, found {text.count(old)}")
    return text.replace(old, new, 1)


helper = Path("config/hypr/scripts/screenshare_guard.sh")
text = helper.read_text()
retired = {"notifications", "ags", "logout-dialog", "waybar"}
kept = []
for line in text.splitlines(keepends=True):
    if line.strip() in retired:
        continue
    if any(line.lstrip().startswith(f"[{name}]=") for name in retired):
        continue
    kept.append(line)
helper.write_text("".join(kept))

lua = Path("config/hypr/screenshare_guard.lua")
text = lua.read_text()
for target, pattern in [
    ("notifications", r"    notifications = \{\n.*?\n    \},\n"),
    ("ags", r"    ags = \{\n.*?\n    \},\n"),
    ("logout-dialog", r"    \[\"logout-dialog\"\] = \{\n.*?\n    \},\n"),
    ("waybar", r"    waybar = \{\n.*?\n    \},\n"),
]:
    text, count = re.subn(pattern, "", text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"expected exactly one Lua rule block for {target}, found {count}")

text = replace_once(
    text,
    'class = "^(org\\\\.telegram\\\\.desktop|TelegramDesktop|telegram-desktop|Telegram)$"',
    'class = "^(org\\\\.telegram\\\\.desktop|TelegramDesktop|telegram-desktop|telegram|Telegram)$"',
    "Telegram matcher",
)
text = replace_once(
    text,
    'class = "^(Messages)$"',
    'class = "^(messages|Messages)$"',
    "Messages matcher",
)
text = replace_once(
    text,
    'class = "^(steam|com\\\\.valvesoftware\\\\.Steam)$"',
    'class = "^(steam|com\\\\.valvesoftware\\\\.Steam|steam-chat|SteamChat)$"',
    "Steam matcher",
)

for target in ["notifications", "ags", '["logout-dialog"]', "waybar"]:
    pattern = rf"^    {re.escape(target)} = (?:true|false),\n"
    text, count = re.subn(pattern, "", text, count=1, flags=re.M)
    if count != 1:
        raise SystemExit(f"expected exactly one stock entry for {target}, found {count}")

old_order = '''guard.order = {
    "security", "mullvad-browser", "localsend", "telegram", "matrix",
    "discord", "teams", "messages", "notifications", "obs", "steam",
    "rustdesk", "files", "wallpicker", "virt-manager", "alacritty", "mpv",
    "ags", "logout-dialog", "waybar",
}
'''
new_order = '''guard.order = {
    "security", "mullvad-browser", "localsend", "telegram", "matrix",
    "discord", "teams", "messages", "obs", "steam", "rustdesk", "files",
    "wallpicker", "virt-manager", "alacritty", "mpv",
}
'''
text = replace_once(text, old_order, new_order, "guard order block")
lua.write_text(text)

hypr = Path("config/hypr/hyprland.lua")
text = hypr.read_text()
old = '''awtarchy_screenshare_guard_v1 = dofile(awtarchy_config_home .. "/hypr/screenshare_guard.lua")
awtarchy_screenshare_guard_rules_v1 = awtarchy_screenshare_guard_v1.rules

function awtarchy_screenshare_guard_set_group_v1(target, enabled)
    return awtarchy_screenshare_guard_v1.set_group(target, enabled)
end

function awtarchy_screenshare_guard_group_enabled_v1(target)
    return awtarchy_screenshare_guard_v1.group_enabled(target)
end

function awtarchy_screenshare_guard_status_v1()
    return awtarchy_screenshare_guard_v1.status()
end
'''
new = '''local awtarchy_screenshare_guard_v1 = dofile(awtarchy_config_home .. "/hypr/screenshare_guard.lua")

function awtarchy_screenshare_guard_set_group_v1(target, enabled)
    return awtarchy_screenshare_guard_v1.set_group(target, enabled)
end

function awtarchy_screenshare_guard_status_v1()
    return awtarchy_screenshare_guard_v1.status()
end
'''
text = replace_once(text, old, new, "Hyprland Screen Share Guard wrapper block")
hypr.write_text(text)

card = Path("config/quickshell/awtarchy/ScreenShareGuardCard.qml")
text = card.read_text()
text = replace_once(
    text,
    "    property int iconScale: 100\n    property bool optionalExpanded: false\n",
    "    property int iconScale: 100\n    property bool expanded: false\n    property bool optionalExpanded: false\n",
    "card expanded property insertion point",
)
for line in [
    '        "notifications"\n',
    '        "ags",\n',
    '        "logout-dialog",\n',
    '        "waybar"\n',
]:
    text = replace_once(text, line, "", f"card target {line.strip()}")
text = replace_once(text, '        "messages",\n    ]', '        "messages"\n    ]', "protected list trailing comma")
text = replace_once(text, '        "mpv",\n    ]', '        "mpv"\n    ]', "optional list trailing comma")

active_block = '''    onActiveChanged: {
        if (active)
            Qt.callLater(() => refresh());
    }
'''
text = replace_once(
    text,
    active_block,
    active_block + '''
    onExpandedChanged: {
        if (!expanded)
            optionalExpanded = false;
    }
''',
    "card active-state block",
)

old_header_tail = '''            Text {
                text: root.busy ? "Applying…" : "Privacy"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
            }
        }
'''
new_header_tail = '''            Text {
                text: root.busy ? "Applying…" : (root.actionError.length > 0 ? "Error" : "Privacy")
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
            }

            SettingsButton {
                label: root.expanded ? "Hide" : "Show"
                active: root.expanded
                textSize: root.scaledText(8)
                onClicked: root.expanded = !root.expanded
            }
        }
'''
text = replace_once(text, old_header_tail, new_header_tail, "card header")

description = '''        Text {
            Layout.fillWidth: true
            text: "Block sensitive windows from screenshots and screen sharing. Unlocked changes last for this session; lock a row to remember it."
'''
text = replace_once(text, description, description + "            visible: root.expanded\n", "card description")
text = replace_once(
    text,
    "            model: root.targetModel(root.protectedTargetIds)\n",
    "            model: root.expanded ? root.targetModel(root.protectedTargetIds) : []\n",
    "protected target model",
)
separator = '''        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.active
        }
'''
text = replace_once(
    text,
    separator,
    '''        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: root.expanded
            color: Theme.active
        }
''',
    "card separator",
)
optional_row = '''        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: "Optional protections"
'''
text = replace_once(
    text,
    optional_row,
    '''        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: "Optional protections"
''',
    "optional protections row",
)
text = replace_once(
    text,
    '                label: root.optionalExpanded ? "Hide" : "Show 11"\n',
    '                label: root.optionalExpanded ? "Hide" : "Show 8"\n',
    "optional target count",
)
text = replace_once(
    text,
    "            model: root.optionalExpanded ? root.targetModel(root.optionalTargetIds) : []\n",
    "            model: root.expanded && root.optionalExpanded ? root.targetModel(root.optionalTargetIds) : []\n",
    "optional target model",
)
footer = '''        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: root.actionError.length > 0 ? root.actionError : root.actionMessage
'''
text = replace_once(
    text,
    footer,
    '''        RowLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: root.actionError.length > 0 ? root.actionError : root.actionMessage
''',
    "card footer",
)
card.write_text(text)

history = Path("local/share/awtarchy/quickshell-managed-history.sha256")
current = history.read_text()
new_lines = []
for source, target in [
    ("config/quickshell/awtarchy/ScreenShareGuardCard.qml", ".config/quickshell/awtarchy/ScreenShareGuardCard.qml"),
    ("config/hypr/scripts/screenshare_guard.sh", ".config/hypr/scripts/screenshare_guard.sh"),
    ("config/hypr/screenshare_guard.lua", ".config/hypr/screenshare_guard.lua"),
]:
    digest = hashlib.sha256(Path(source).read_bytes()).hexdigest()
    entry = f"{digest}\t{target}\n"
    if entry not in current:
        new_lines.append(entry)
if new_lines:
    history.write_text(current + "\n# 2026-09-08 compact Screen Share Guard cleanup.\n" + "".join(new_lines))
