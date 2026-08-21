#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML_DIR="${ROOT}/config/quickshell/awtarchy"
SCRIPT_DIR="${ROOT}/config/hypr/scripts"
HELPER="${QML_DIR}/FlyoutEdgeLayout.js"
APP_STATE="${SCRIPT_DIR}/quickshell_application_state.sh"
DEMO="${SCRIPT_DIR}/quickshell_notification_layout_demo.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: ${1#"$ROOT"/}"
}

require_source() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail "$description"
}

require_file "$HELPER"

node - "$HELPER" <<'NODE'
const helper = require(process.argv[2]);

function assertEqual(actual, expected, message) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

assertEqual(helper.edgeOf("bottom-center"), "bottom", "bottom-center edge normalization");
assertEqual(helper.edgeOf("left"), "left", "vertical edge normalization");
assertEqual(helper.isBottom("bottom"), true, "bottom placement detection");
assertEqual(helper.isBottom("top"), false, "top placement detection");
assertEqual(helper.sectionRow(true, 0, 4), 3, "bottom section reversal");
assertEqual(helper.sectionRow(false, 0, 4), 0, "top section order");
assertEqual(helper.resolveNotificationPosition("automatic", "bottom"), "bottom-right", "bottom automatic popup");
assertEqual(helper.resolveNotificationPosition("automatic", "top"), "top-right", "top automatic popup");
assertEqual(helper.resolveNotificationPosition("automatic", "left"), "top-left", "left automatic popup");
assertEqual(helper.resolveNotificationPosition("automatic", "right"), "top-right", "right automatic popup");
assertEqual(helper.resolveNotificationPosition("bottom-center", "top"), "bottom-center", "explicit popup override");
assertEqual(helper.resolveNotificationPosition("invalid", "bottom"), "bottom-right", "invalid popup fallback");
assertEqual(helper.notificationPositionOptions(), [
  "automatic",
  "top-left",
  "top-center",
  "top-right",
  "bottom-left",
  "bottom-center",
  "bottom-right"
], "notification popup choices");
NODE

flyouts=(
  Launcher.qml
  QuickSettings.qml
  NetworkMenu.qml
  BluetoothMenu.qml
  BatteryMenu.qml
  ClipboardMenu.qml
  Notifications.qml
)

for flyout in "${flyouts[@]}"; do
  file="${QML_DIR}/${flyout}"
  require_file "$file"
  require_source "$file" 'import "FlyoutEdgeLayout.js" as FlyoutEdgeLayout' \
    "${flyout} does not use the shared edge-layout policy"
  require_source "$file" 'readonly property bool bottomEdgeLayout:' \
    "${flyout} does not expose bottom-edge layout state"
  require_source "$file" 'Layout.row: root.bottomEdgeLayout ?' \
    "${flyout} does not move its controls beside a bottom bar"
done

require_source "${QML_DIR}/QuickSettings.qml" 'FlyoutEdgeLayout.sectionRow(root.bottomEdgeLayout' \
  'Quick Settings sections do not reverse beside a bottom bar'
require_source "${QML_DIR}/NetworkMenu.qml" 'FlyoutEdgeLayout.sectionRow(root.bottomEdgeLayout' \
  'Network sections do not reverse beside a bottom bar'
require_source "${QML_DIR}/BluetoothMenu.qml" 'FlyoutEdgeLayout.sectionRow(root.bottomEdgeLayout' \
  'Bluetooth sections do not reverse beside a bottom bar'
require_source "${QML_DIR}/BatteryMenu.qml" 'FlyoutEdgeLayout.sectionRow(root.bottomEdgeLayout' \
  'Battery sections do not reverse beside a bottom bar'
require_source "${QML_DIR}/ClipboardMenu.qml" 'ListView.BottomToTop' \
  'Clipboard history does not flow upward from a bottom bar'
require_source "${QML_DIR}/Notifications.qml" 'ListView.BottomToTop' \
  'Notification history does not flow upward from a bottom bar'
require_source "${QML_DIR}/Launcher.qml" 'GridView.BottomToTop' \
  'Launcher results do not flow upward from a bottom bar'

require_source "${QML_DIR}/BarState.qml" 'notification_popup_positions: {}' \
  'default application state has no per-display notification popup positions'
require_source "${QML_DIR}/BarState.qml" 'function notificationPopupPositionFor(name)' \
  'BarState cannot load a per-display notification popup position'
require_source "$APP_STATE" 'set-notification-popup-position)' \
  'application state helper cannot persist a notification popup position'
require_source "${QML_DIR}/Notifications.qml" 'popupPositionDraft' \
  'Notification settings do not expose a popup position draft'
require_source "${QML_DIR}/Notifications.qml" 'resolvedPopupPosition' \
  'notification popups do not resolve automatic and overridden positions'
require_source "${QML_DIR}/Notifications.qml" 'setPopupPreview(position)' \
  'Notification Center has no non-persistent popup preview IPC'
require_source "${QML_DIR}/Notifications.qml" 'clearPopupPreview()' \
  'Notification Center cannot clear its popup preview'

require_source "${QML_DIR}/Bar.qml" 'label: "󰍽"' \
  'mouse submap does not use the theme-tintable Nerd Font glyph'
mouse_glyph_count="$(grep -Fc -- 'label: "󰍽"' "${QML_DIR}/Bar.qml")"
[[ "$mouse_glyph_count" -eq 2 ]] \
  || fail "mouse submap glyph must be themed in both bar orientations, found ${mouse_glyph_count}"
if grep -Fq -- 'label: "🖱"' "${QML_DIR}/Bar.qml"; then
  fail 'mouse submap still uses an untintable emoji glyph'
fi

require_file "$DEMO"
[[ -x "$DEMO" ]] || fail 'notification layout demo is not executable'

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

state_cache="${tmp_dir}/cache"
state_file="${state_cache}/awtarchy/quickshell-state.json"
state_env=(
  XDG_CACHE_HOME="$state_cache"
  HOME="${tmp_dir}/home"
  HYPR_QUICKSHELL_SCRIPT=/bin/false
)

env "${state_env[@]}" "$APP_STATE" set-notification-popup-position DP-1 top-center
jq -e '.notification_popup_positions["DP-1"] == "top-center"' "$state_file" >/dev/null \
  || fail 'notification popup override was not stored for the selected display'

env "${state_env[@]}" "$APP_STATE" set-notification-popup-position DP-1 automatic
jq -e '(.notification_popup_positions["DP-1"] // "automatic") == "automatic"' "$state_file" >/dev/null \
  || fail 'Automatic did not remove the selected display override'

if env "${state_env[@]}" "$APP_STATE" set-notification-popup-position DP-1 middle >/dev/null 2>&1; then
  fail 'invalid notification popup positions are accepted'
fi

env "${state_env[@]}" "$APP_STATE" set-notification-popup-position DP-1 bottom-left
env "${state_env[@]}" "$APP_STATE" reset-flyout notifications DP-1
jq -e '(.notification_popup_positions["DP-1"] // "automatic") == "automatic"' "$state_file" >/dev/null \
  || fail 'resetting Notification settings did not restore Automatic for the display'

mkdir -p "${tmp_dir}/bin"
printf '%s\n' '#!/usr/bin/env bash' \
  "printf 'qs:%s\\n' \"\$*\" >>\"\${AWTARCHY_DEMO_LOG}\"" >"${tmp_dir}/bin/qs"
printf '%s\n' '#!/usr/bin/env bash' \
  "printf 'notify:%s\\n' \"\$*\" >>\"\${AWTARCHY_DEMO_LOG}\"" >"${tmp_dir}/bin/notify-send"
chmod 0755 "${tmp_dir}/bin/qs" "${tmp_dir}/bin/notify-send"

log_file="${tmp_dir}/demo.log"
AWTARCHY_DEMO_LOG="$log_file" AWTARCHY_NOTIFICATION_DEMO_DELAY=0 \
  PATH="${tmp_dir}/bin:${PATH}" "$DEMO"

for position in top-left top-center top-right bottom-left bottom-center bottom-right; do
  grep -Fq -- "qs:-c awtarchy ipc call notifications setPopupPreview ${position}" "$log_file" \
    || fail "notification demo does not preview ${position}"
  grep -Fq -- "Awtarchy notification layout · ${position}" "$log_file" \
    || fail "notification demo does not label ${position}"
done

grep -Fq -- 'qs:-c awtarchy ipc call notifications setPopupPreview automatic' "$log_file" \
  || fail 'notification demo does not preview Automatic behavior'
grep -Fq -- 'Awtarchy notification layout · automatic' "$log_file" \
  || fail 'notification demo does not label Automatic behavior'

grep -Fq -- 'qs:-c awtarchy ipc call notifications clearPopupPreview' "$log_file" \
  || fail 'notification demo does not restore the saved automatic/override behavior'

printf '%s\n' 'PASS: edge-aware flyouts, notification placement, demo, and mouse glyph are wired.'
