#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NOTIFICATIONS = ROOT / "config/quickshell/awtarchy/Notifications.qml"
CARD = ROOT / "config/quickshell/awtarchy/NotificationCard.qml"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_exact(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


notifications = NOTIFICATIONS.read_text()

notifications = replace_exact(
    notifications,
    "    property var clearFadeNotifications: []\n    property int clearFadeIndex: 0\n",
    "    property var clearSlideNotifications: []\n    property int clearSlideIndex: 0\n",
    "Clear state properties",
)

notifications = replace_exact(
    notifications,
    '''    function activateOrDismiss(notification) {\n        if (!notification)\n            return;\n        const actions = notification.actions || [];\n        for (let i = 0; i < actions.length; ++i) {\n            if (actions[i].identifier === "default") {\n                actions[i].invoke();\n                return;\n            }\n        }\n        notification.dismiss();\n    }\n''',
    '''    function activateNotification(notification) {\n        if (!notification)\n            return;\n        const actions = notification.actions || [];\n        for (let i = 0; i < actions.length; ++i) {\n            if (actions[i].identifier === "default") {\n                actions[i].invoke();\n                break;\n            }\n        }\n        hidePopup(notification);\n    }\n''',
    "notification activation function",
)

old_activation = "onActivated: root.activateOrDismiss(notification)"
activation_count = notifications.count(old_activation)
if activation_count < 2:
    raise SystemExit(
        f"notification activation wiring: expected at least two matches, found {activation_count}"
    )
notifications = notifications.replace(
    old_activation, "onActivated: root.activateNotification(notification)"
)

# The two property declarations above are already renamed. Rename every remaining
# use of the old Clear queue/index names together so partial replacements cannot
# invalidate a later exact-match guard.
notifications = notifications.replace("clearFadeNotifications", "clearSlideNotifications")
notifications = notifications.replace("clearFadeIndex", "clearSlideIndex")

old_clear_binding = "clearFading: root.clearSlideNotifications.indexOf(notification) >= 0"
clear_binding_count = notifications.count(old_clear_binding)
if clear_binding_count != 1:
    raise SystemExit(
        f"history Clear binding: expected exactly one match, found {clear_binding_count}"
    )
notifications = notifications.replace(
    old_clear_binding,
    "clearSliding: root.clearSlideNotifications.indexOf(notification) >= 0",
    1,
)

if "clearFade" in notifications or "clearFading" in notifications:
    raise SystemExit("stale fade-only Clear state remains in Notifications.qml")
if "activateOrDismiss" in notifications:
    raise SystemExit("stale activateOrDismiss path remains in Notifications.qml")

NOTIFICATIONS.write_text(notifications)

card = CARD.read_text()
card = replace_exact(
    card,
    '''    property bool clearFading: false\n    property real clearOpacity: clearFading ? 0 : 1\n''',
    '''    property bool clearSliding: false\n    property real clearOffset: clearSliding ? Math.max(1, width) : 0\n    property real clearOpacity: clearSliding ? 0.88 : 1\n''',
    "NotificationCard Clear properties",
)
card = replace_exact(
    card,
    '''    transform: Translate {\n        x: root.swipeOffset\n    }\n''',
    '''    transform: Translate {\n        x: root.swipeOffset + root.clearOffset\n    }\n''',
    "NotificationCard translation",
)
card = replace_exact(
    card,
    '''    Behavior on clearOpacity {\n        NumberAnimation {\n            duration: 110\n            easing.type: Easing.OutCubic\n        }\n    }\n''',
    '''    Behavior on clearOffset {\n        NumberAnimation {\n            duration: 110\n            easing.type: Easing.OutCubic\n        }\n    }\n\n    Behavior on clearOpacity {\n        NumberAnimation {\n            duration: 110\n            easing.type: Easing.OutCubic\n        }\n    }\n''',
    "NotificationCard Clear animation",
)
if "clearFading" in card:
    raise SystemExit("stale clearFading state remains in NotificationCard.qml")
CARD.write_text(card)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

history = HISTORY.read_text()
section = (
    "\n# 2026-08-27 notification body preservation and Clear slide refinement.\n"
    f"{sha256(CARD)}\t.config/quickshell/awtarchy/NotificationCard.qml\n"
    f"{sha256(NOTIFICATIONS)}\t.config/quickshell/awtarchy/Notifications.qml\n"
)
if "# 2026-08-27 notification body preservation and Clear slide refinement." in history:
    raise SystemExit("managed-history refinement section already exists")
HISTORY.write_text(history.rstrip("\n") + "\n" + section.lstrip("\n"))

print("Applied PR #78 body-click preservation and slide-out Clear refinement.")
print(f"NotificationCard sha256={sha256(CARD)}")
print(f"Notifications sha256={sha256(NOTIFICATIONS)}")
