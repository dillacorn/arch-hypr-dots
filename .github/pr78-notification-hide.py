from pathlib import Path
import hashlib

ROOT = Path.cwd()
NOTIFICATIONS = ROOT / "config/quickshell/awtarchy/Notifications.qml"
CARD = ROOT / "config/quickshell/awtarchy/NotificationCard.qml"
HELPER = ROOT / "config/hypr/scripts/quickshell_notification_dismiss.sh"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


helper = HELPER.read_text()
helper = replace_once(
    helper,
    "# Dismiss the first visible Awtarchy Quickshell notification.\n",
    "# Hide the first visible Awtarchy Quickshell popup without deleting its history entry.\n",
    "notification helper comment",
)
helper = replace_once(
    helper,
    "exec qs -c awtarchy ipc call notifications dismissFirst\n",
    "exec qs -c awtarchy ipc call notifications hideFirstPopup\n",
    "notification helper IPC action",
)
HELPER.write_text(helper)

card = CARD.read_text()
card = replace_once(
    card,
    "    property bool swipeDismissing: false\n",
    "    property bool swipeDismissing: false\n    property bool clearFading: false\n    property real clearOpacity: clearFading ? 0 : 1\n",
    "notification card clear properties",
)
card = replace_once(
    card,
    '''    opacity: Math.max(0.45, 1 - Math.min(0.55,\n        Math.abs(swipeOffset) / Math.max(1, width)))\n''',
    '''    opacity: root.clearOpacity * Math.max(0.45, 1 - Math.min(0.55,\n        Math.abs(swipeOffset) / Math.max(1, width)))\n''',
    "notification card opacity composition",
)
card = replace_once(
    card,
    '''    NumberAnimation {\n        id: swipeReset\n''',
    '''    Behavior on clearOpacity {\n        NumberAnimation {\n            duration: 110\n            easing.type: Easing.OutCubic\n        }\n    }\n\n    NumberAnimation {\n        id: swipeReset\n''',
    "notification card clear fade behavior",
)
CARD.write_text(card)

notifications = NOTIFICATIONS.read_text()
notifications = replace_once(
    notifications,
    '''    property var popupNotifications: []\n    property int historyRevision: 0\n''',
    '''    property var popupNotifications: []\n    property int historyRevision: 0\n    property bool clearInProgress: false\n    property var clearQueue: []\n    property var clearFadeNotifications: []\n    property int clearFadeIndex: 0\n    property int clearVisualCount: 0\n''',
    "notification clear state properties",
)
notifications = replace_once(
    notifications,
    '''    function hidePopup(notification) {\n        removePopup(notification);\n        if (isTransientNotification(notification) && notification.tracked)\n            notification.expire();\n    }\n\n    function hideAllPopups() {\n''',
    '''    function hidePopup(notification) {\n        removePopup(notification);\n        if (isTransientNotification(notification) && notification.tracked)\n            notification.expire();\n    }\n\n    function hideFirstPopup() {\n        if (popupNotifications.length === 0)\n            return;\n        hidePopup(popupNotifications[0]);\n    }\n\n    function hideAllPopups() {\n''',
    "popup-only hide function",
)
notifications = replace_once(
    notifications,
    '''    function dismissAll() {\n        popupNotifications = [];\n        const values = [...server.trackedNotifications.values];\n        for (let i = 0; i < values.length; ++i)\n            values[i].dismiss();\n        historyRevision++;\n    }\n\n    function loadSavedView(targetScreen) {\n''',
    '''    function dismissAll() {\n        popupNotifications = [];\n        const values = [...server.trackedNotifications.values];\n        for (let i = 0; i < values.length; ++i)\n            values[i].dismiss();\n        historyRevision++;\n    }\n\n    function beginClearAll() {\n        if (clearInProgress)\n            return;\n\n        const values = historyNotifications();\n        if (values.length === 0)\n            return;\n\n        const visualCount = Math.min(values.length, 10);\n        clearQueue = [...server.trackedNotifications.values];\n        clearFadeNotifications = [];\n        clearFadeIndex = 0;\n        clearVisualCount = visualCount;\n        clearInProgress = true;\n        hideAllPopups();\n        clearStaggerTimer.restart();\n    }\n\n    function finishClearAll() {\n        if (!clearInProgress)\n            return;\n\n        const values = clearQueue.slice();\n        for (let i = 0; i < values.length; ++i) {\n            if (values[i] && values[i].tracked)\n                values[i].dismiss();\n        }\n\n        clearQueue = [];\n        clearFadeNotifications = [];\n        clearFadeIndex = 0;\n        clearVisualCount = 0;\n        clearInProgress = false;\n        historyRevision++;\n    }\n\n    function loadSavedView(targetScreen) {\n''',
    "animated clear functions",
)
notifications = replace_once(
    notifications,
    '''    FileView {\n        id: muteFile\n''',
    '''    Timer {\n        id: clearStaggerTimer\n        interval: 32\n        repeat: true\n        triggeredOnStart: true\n        onTriggered: {\n            if (!root.clearInProgress || root.clearFadeIndex >= root.clearVisualCount) {\n                stop();\n                clearFinishTimer.restart();\n                return;\n            }\n\n            const notification = root.historyNotifications()[root.clearFadeIndex];\n            if (notification)\n                root.clearFadeNotifications = [...root.clearFadeNotifications, notification];\n            root.clearFadeIndex++;\n\n            if (root.clearFadeIndex >= root.clearVisualCount) {\n                stop();\n                clearFinishTimer.restart();\n            }\n        }\n    }\n\n    Timer {\n        id: clearFinishTimer\n        interval: 120\n        repeat: false\n        onTriggered: root.finishClearAll()\n    }\n\n    FileView {\n        id: muteFile\n''',
    "notification clear timers",
)
notifications = replace_once(
    notifications,
    '''        function disable(): void { root.setPopupMute(true); }\n        function dismissFirst(): void { root.dismissFirst(); }\n        function dismissAll(): void { root.dismissAll(); }\n''',
    '''        function disable(): void { root.setPopupMute(true); }\n        function hideFirstPopup(): void { root.hideFirstPopup(); }\n        function dismissFirst(): void { root.dismissFirst(); }\n        function dismissAll(): void { root.dismissAll(); }\n''',
    "notification hide IPC",
)
notifications = replace_once(
    notifications,
    '''                                enabled: root.historyCount > 0\n                                hoverEnabled: enabled\n                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor\n                                onClicked: root.dismissAll()\n''',
    '''                                enabled: root.historyCount > 0 && !root.clearInProgress\n                                hoverEnabled: enabled\n                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor\n                                onClicked: root.beginClearAll()\n''',
    "notification Clear button",
)
notifications = replace_once(
    notifications,
    '''                        bodyLineLimit: 8\n\n                        onActivated: root.activateOrDismiss(notification)\n''',
    '''                        bodyLineLimit: 8\n                        clearFading: root.clearFadeNotifications.indexOf(notification) >= 0\n\n                        onActivated: root.activateOrDismiss(notification)\n''',
    "notification history card fade binding",
)
NOTIFICATIONS.write_text(notifications)

marker = "# 2026-08-27 reversible notification popup hiding and staggered Clear."
history = HISTORY.read_text()
if marker in history:
    raise SystemExit("managed-history marker already exists")
installed = [
    ("config/hypr/scripts/quickshell_notification_dismiss.sh", ".config/hypr/scripts/quickshell_notification_dismiss.sh"),
    ("config/quickshell/awtarchy/NotificationCard.qml", ".config/quickshell/awtarchy/NotificationCard.qml"),
    ("config/quickshell/awtarchy/Notifications.qml", ".config/quickshell/awtarchy/Notifications.qml"),
]
lines = ["", marker]
for rel, managed in installed:
    digest = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
    lines.append(f"{digest}\t{managed}")
HISTORY.write_text(history.rstrip("\n") + "\n" + "\n".join(lines) + "\n")
