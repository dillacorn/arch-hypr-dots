#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
NOTIFICATIONS="${ROOT}/config/quickshell/awtarchy/Notifications.qml"
CARD="${ROOT}/config/quickshell/awtarchy/NotificationCard.qml"
DISMISS_HELPER="${ROOT}/config/hypr/scripts/quickshell_notification_dismiss.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_source() {
    local file="$1" expected="$2" description="$3"
    grep -Fq -- "$expected" "$file" || fail "$description"
}

require_source "$DISMISS_HELPER" 'ipc call notifications hideFirstPopup' \
    'Space-family notification helper still permanently dismisses notification history'
if grep -Fq 'ipc call notifications dismissFirst' "$DISMISS_HELPER"; then
    fail 'notification keyboard helper still calls dismissFirst'
fi

require_source "$NOTIFICATIONS" 'function hideFirstPopup() {' \
    'notification store has no popup-only keyboard hide action'
require_source "$NOTIFICATIONS" 'hidePopup(popupNotifications[0]);' \
    'popup-only keyboard action does not use the history-preserving hide primitive'
require_source "$NOTIFICATIONS" 'function hideFirstPopup(): void { root.hideFirstPopup(); }' \
    'notification IPC does not expose the popup-only hide action'

python3 - "$NOTIFICATIONS" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
match = re.search(r"function hideFirstPopup\(\) \{(?P<body>.*?)\n    \}", text, re.S)
if not match:
    raise SystemExit("FAIL: could not isolate hideFirstPopup implementation")
body = match.group("body")
if "historyNotifications" in body or ".dismiss()" in body or "dismissNotification" in body:
    raise SystemExit("FAIL: popup-only keyboard hide still mutates notification history")
print("PASS: popup-only keyboard hide has no history fallback.")
PY

# Explicit card X/swipe remains a permanent history dismissal.
require_source "$NOTIFICATIONS" 'function dismissNotification(notification) {' \
    'explicit notification dismissal path is missing'
require_source "$NOTIFICATIONS" 'notification.dismiss();' \
    'explicit notification dismissal is no longer permanent'
require_source "$NOTIFICATIONS" 'onDismissRequested: root.dismissNotification(notification)' \
    'history card X/swipe no longer uses permanent dismissal'

# Clear is permanent but visually staggered and bounded.
require_source "$NOTIFICATIONS" 'property bool clearInProgress: false' \
    'notification Clear has no serialized animation state'
require_source "$NOTIFICATIONS" 'property var clearFadeNotifications: []' \
    'notification Clear has no bounded fade queue'
require_source "$NOTIFICATIONS" 'const visualCount = Math.min(values.length, 10);' \
    'notification Clear does not cap the animated staircase work'
require_source "$NOTIFICATIONS" 'id: clearStaggerTimer' \
    'notification Clear has no staircase timer'
require_source "$NOTIFICATIONS" 'interval: 32' \
    'notification Clear staircase cadence changed unexpectedly'
require_source "$NOTIFICATIONS" 'id: clearFinishTimer' \
    'notification Clear has no post-animation cleanup timer'
require_source "$NOTIFICATIONS" 'interval: 120' \
    'notification Clear cleanup does not allow the visible fade to finish'
require_source "$NOTIFICATIONS" 'onClicked: root.beginClearAll()' \
    'Clear button bypasses the animated clear path'
require_source "$NOTIFICATIONS" 'clearFading: root.clearFadeNotifications.indexOf(notification) >= 0' \
    'history cards are not wired to the staggered fade state'
require_source "$NOTIFICATIONS" 'values[i].dismiss();' \
    'animated Clear no longer permanently removes notification history'

require_source "$CARD" 'property bool clearFading: false' \
    'notification cards have no lightweight Clear fade state'
require_source "$CARD" 'opacity: root.clearFading ? 0 :' \
    'notification Clear state does not fade cards out'
require_source "$CARD" 'Behavior on opacity {' \
    'notification Clear fade is not animated'
require_source "$CARD" 'duration: 110' \
    'notification Clear fade duration changed unexpectedly'

printf '%s\n' 'Notification popup hiding and staggered Clear regression test passed.'
