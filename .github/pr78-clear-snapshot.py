from pathlib import Path
import hashlib
import re

ROOT = Path.cwd()
QML = ROOT / "config/quickshell/awtarchy/Notifications.qml"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


text = QML.read_text()
text = replace_once(
    text,
    "    property var clearQueue: []\n    property var clearFadeNotifications: []\n",
    "    property var clearQueue: []\n    property var clearVisualQueue: []\n    property var clearFadeNotifications: []\n",
    "clear visual queue property",
)
text = replace_once(
    text,
    "        clearQueue = [...server.trackedNotifications.values];\n        clearFadeNotifications = [];\n",
    "        clearQueue = [...server.trackedNotifications.values];\n        clearVisualQueue = values.slice();\n        clearFadeNotifications = [];\n",
    "clear visual queue capture",
)
text = replace_once(
    text,
    "        clearQueue = [];\n        clearFadeNotifications = [];\n",
    "        clearQueue = [];\n        clearVisualQueue = [];\n        clearFadeNotifications = [];\n",
    "clear visual queue reset",
)
text = replace_once(
    text,
    "            const notification = root.historyNotifications()[root.clearFadeIndex];\n",
    "            const notification = root.clearVisualQueue[root.clearFadeIndex];\n",
    "clear timer snapshot lookup",
)
QML.write_text(text)

marker = "# 2026-08-27 reversible notification popup hiding and staggered Clear."
history = HISTORY.read_text()
marker_pos = history.rfind(marker)
if marker_pos < 0:
    raise SystemExit("notification managed-history marker is missing")
prefix = history[:marker_pos]
suffix = history[marker_pos:]
digest = hashlib.sha256(QML.read_bytes()).hexdigest()
pattern = r"(?m)^[0-9a-f]{64}\t\.config/quickshell/awtarchy/Notifications\.qml$"
suffix, count = re.subn(pattern, f"{digest}\t.config/quickshell/awtarchy/Notifications.qml", suffix, count=1)
if count != 1:
    raise SystemExit(f"expected one Notifications managed-history hash after marker, found {count}")
HISTORY.write_text(prefix + suffix)
