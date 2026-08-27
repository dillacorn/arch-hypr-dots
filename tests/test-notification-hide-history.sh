#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Runtime contract: body clicks preserve history; Clear visibly slides cards out.
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

# Clicking a notification body may invoke its default action, but Awtarchy must
# never permanently remove that notification from history. The explicit X/swipe
# path below owns permanent per-notification deletion.
require_source "$NOTIFICATIONS" 'function activateNotification(notification) {' \
    'notification body click still uses the old activate-or-dismiss behavior'
require_source "$NOTIFICATIONS" 'hidePopup(notification);' \
    'notification body activation does not hide the live popup'
require_source "$NOTIFICATIONS" 'onActivated: root.activateNotification(notification)' \
    'notification cards are not wired to the history-preserving activation path'

python3 - "$NOTIFICATIONS" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
match = re.search(r"function activateNotification\(notification\) \{(?P<body>.*?)\n    \}", text, re.S)
if not match:
    raise SystemExit("FAIL: could not isolate activateNotification implementation")
body = match.group("body")
if ".dismiss()" in body or "dismissNotification" in body:
    raise SystemExit("FAIL: notification body activation can still permanently delete history")
if 'identifier === "default"' not in body or ".invoke()" not in body:
    raise SystemExit("FAIL: notification body activation no longer supports default actions")
if "hidePopup(notification);" not in body:
    raise SystemExit("FAIL: notification popup is not hidden after body activation")
print("PASS: body activation preserves history and keeps default actions.")
PY

# Explicit card X/swipe remains a permanent history dismissal.
require_source "$NOTIFICATIONS" 'function dismissNotification(notification) {' \
    'explicit notification dismissal path is missing'
require_source "$NOTIFICATIONS" 'notification.dismiss();' \
    'explicit notification dismissal is no longer permanent'
require_source "$NOTIFICATIONS" 'onDismissRequested: root.dismissNotification(notification)' \
    'history card X/swipe no longer uses permanent dismissal'

# Clear is permanent, visually staggered, snapshot-based, and bounded.
require_source "$NOTIFICATIONS" 'property bool clearInProgress: false' \
    'notification Clear has no serialized animation state'
require_source "$NOTIFICATIONS" 'property var clearVisualQueue: []' \
    'notification Clear does not capture a stable visual snapshot'
require_source "$NOTIFICATIONS" 'property var clearSlideNotifications: []' \
    'notification Clear has no bounded slide queue'
require_source "$NOTIFICATIONS" 'const visualCount = Math.min(values.length, 10);' \
    'notification Clear does not cap the animated staircase work'
require_source "$NOTIFICATIONS" 'clearVisualQueue = values.slice();' \
    'notification Clear does not freeze the visible history at click time'
require_source "$NOTIFICATIONS" 'const notification = root.clearVisualQueue[root.clearSlideIndex];' \
    'notification Clear rereads live history during the staircase animation'
require_source "$NOTIFICATIONS" 'id: clearStaggerTimer' \
    'notification Clear has no staircase timer'
require_source "$NOTIFICATIONS" 'interval: 32' \
    'notification Clear staircase cadence changed unexpectedly'
require_source "$NOTIFICATIONS" 'id: clearFinishTimer' \
    'notification Clear has no post-animation cleanup timer'
require_source "$NOTIFICATIONS" 'interval: 120' \
    'notification Clear cleanup does not allow the visible slide to finish'
require_source "$NOTIFICATIONS" 'onClicked: root.beginClearAll()' \
    'Clear button bypasses the animated clear path'
require_source "$NOTIFICATIONS" 'clearSliding: root.clearSlideNotifications.indexOf(notification) >= 0' \
    'history cards are not wired to the staggered slide state'
require_source "$NOTIFICATIONS" 'values[i].dismiss();' \
    'animated Clear no longer permanently removes notification history'

# Clear translation is isolated from manual swipe translation. Motion must be the
# dominant Clear effect rather than a fade-only disappearance.
require_source "$CARD" 'property bool clearSliding: false' \
    'notification cards have no dedicated Clear slide state'
require_source "$CARD" 'property real clearOffset: clearSliding ? Math.max(1, width) : 0' \
    'notification Clear does not translate the card fully out of view'
require_source "$CARD" 'x: root.swipeOffset + root.clearOffset' \
    'notification Clear slide is not composed separately with manual swipe state'
require_source "$CARD" 'Behavior on clearOffset {' \
    'notification Clear has no horizontal slide animation'
require_source "$CARD" 'duration: 110' \
    'notification Clear slide duration changed unexpectedly'
if grep -Fq 'property real clearOpacity: clearFading ? 0 : 1' "$CARD"; then
    fail 'notification Clear is still implemented as a fade-to-zero effect'
fi
if grep -Fq 'Behavior on opacity {' "$CARD"; then
    fail 'notification Clear animation adds latency to normal swipe opacity changes'
fi

# Final contract: keyboard/body hiding is reversible, explicit dismissal is
# permanent, and Clear slides the click-time snapshot out before deletion.
printf '%s\n' 'Notification body preservation and slide-out Clear regression test passed.'
