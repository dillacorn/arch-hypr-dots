#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/config/hypr/scripts/quickshell_floating_windows.sh"
HYPR_LUA="$ROOT/config/hypr/hyprland.lua"
BAR="$ROOT/config/quickshell/awtarchy/Bar.qml"
CARD="$ROOT/config/quickshell/awtarchy/FloatingWindowsCard.qml"
STATE_QML="$ROOT/config/quickshell/awtarchy/FloatingWindowsState.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

[[ -f "$STATE_QML" ]] || fail 'shared FloatingWindowsState singleton is missing'

contains "$HELPER" 'toggle)' \
    'Floating Windows helper has no global toggle action'
contains "$HELPER" 'AWTARCHY_FLOATING_STATE_FILE' \
    'Floating Windows helper does not publish shared runtime state'
contains "$HELPER" '--notify' \
    'Floating Windows helper has no notification-capable toggle path'

contains "$HYPR_LUA" 'local floating_windows_toggle = "~/.config/hypr/scripts/quickshell_floating_windows.sh toggle --notify"' \
    'hyprland.lua does not define the approved global floating-spawn toggle command'
bind_count="$(grep -Fc 'hl.bind("SUPER + ALT + F", hl.dsp.exec_cmd(floating_windows_toggle), {})' "$HYPR_LUA" || true)"
[[ "$bind_count" == 2 ]] \
    || fail 'SUPER+ALT+F must toggle global floating-spawn mode in default and noalt modes'
contains "$HYPR_LUA" '{ "SUPER + F", hl.dsp.window.float({ action = "toggle" }) },' \
    'existing SUPER+F focused-window float/tile bind changed or disappeared'

contains "$STATE_QML" 'pragma Singleton' \
    'FloatingWindowsState is not a singleton'
contains "$STATE_QML" 'readonly property bool enabled: state === "enabled"' \
    'FloatingWindowsState does not expose enabled state'
contains "$STATE_QML" 'function setEnabled(enabled)' \
    'FloatingWindowsState cannot set global floating-spawn mode'
contains "$STATE_QML" 'function toggle()' \
    'FloatingWindowsState cannot toggle global floating-spawn mode'
contains "$STATE_QML" 'watchChanges: true' \
    'FloatingWindowsState does not react to helper state publication'
if grep -Fq 'repeat: true' "$STATE_QML"; then
    fail 'FloatingWindowsState must not add repeating status polling'
fi

contains "$CARD" 'FloatingWindowsState.state' \
    'Quick Settings Floating Windows card does not consume shared state'
contains "$CARD" 'FloatingWindowsState.toggle()' \
    'Quick Settings Floating Windows card does not use the shared toggle path'
if grep -Fq 'interval: 3000' "$CARD"; then
    fail 'Quick Settings Floating Windows card still polls status every 3 seconds'
fi

indicator_count="$(grep -Fc 'label: "Floating"' "$BAR" || true)"
[[ "$indicator_count" == 2 ]] \
    || fail 'horizontal and vertical bars must both expose the Floating indicator'
visible_count="$(grep -Fc 'visible: FloatingWindowsState.enabled' "$BAR" || true)"
[[ "$visible_count" == 2 ]] \
    || fail 'Floating bar indicators must only appear while global floating-spawn mode is enabled'
disable_count="$(grep -Fc 'onClicked: FloatingWindowsState.setEnabled(false)' "$BAR" || true)"
[[ "$disable_count" == 2 ]] \
    || fail 'clicking either Floating indicator must restore normal tiling'

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
TEST_LUA="$TMP/hyprland.lua"
FAKE_HYPRCTL="$TMP/hyprctl"
FAKE_NOTIFY="$TMP/notify-send"
HYPRCTL_LOG="$TMP/hyprctl.log"
NOTIFY_LOG="$TMP/notify.log"
STATE_FILE="$TMP/floating-state"
CONFIGERROR_COUNT="$TMP/configerrors.count"
cp -- "$HYPR_LUA" "$TEST_LUA"
: >"$HYPRCTL_LOG"
: >"$NOTIFY_LOG"
printf '0\n' >"$CONFIGERROR_COUNT"

cat >"$FAKE_HYPRCTL" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${FAKE_HYPRCTL_LOG:?}"
case "${1:-}" in
    configerrors)
        count="$(cat "${FAKE_CONFIGERROR_COUNT:?}")"
        count=$((count + 1))
        printf '%s\n' "$count" >"${FAKE_CONFIGERROR_COUNT}"
        ;;
    reload)
        ;;
esac
FAKE
chmod +x "$FAKE_HYPRCTL"

cat >"$FAKE_NOTIFY" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${FAKE_NOTIFY_LOG:?}"
FAKE
chmod +x "$FAKE_NOTIFY"

run_helper() {
    HYPRLAND_LUA="$TEST_LUA" \
    HYPRCTL="$FAKE_HYPRCTL" \
    NOTIFY_SEND="$FAKE_NOTIFY" \
    AWTARCHY_FLOATING_STATE_FILE="$STATE_FILE" \
    FAKE_HYPRCTL_LOG="$HYPRCTL_LOG" \
    FAKE_CONFIGERROR_COUNT="$CONFIGERROR_COUNT" \
    FAKE_NOTIFY_LOG="$NOTIFY_LOG" \
    "$HELPER" "$@"
}

[[ "$(run_helper status)" == "disabled" ]] \
    || fail 'status did not report stock disabled state'
[[ "$(cat "$STATE_FILE")" == "disabled" ]] \
    || fail 'status did not publish disabled runtime state'

printf '0\n' >"$CONFIGERROR_COUNT"
[[ "$(run_helper toggle --notify)" == "enabled" ]] \
    || fail 'toggle --notify did not enable global floating-spawn mode'
[[ "$(cat "$STATE_FILE")" == "enabled" ]] \
    || fail 'toggle did not publish enabled runtime state'
contains "$TEST_LUA" 'local awtarchy_floating_windows = true -- AWTARCHY_FLOATING_WINDOWS' \
    'toggle did not persist the enabled marker'
contains "$NOTIFY_LOG" 'Floating windows enabled' \
    'keyboard notification did not report enabled state'

printf '0\n' >"$CONFIGERROR_COUNT"
[[ "$(run_helper toggle --notify)" == "disabled" ]] \
    || fail 'second toggle --notify did not restore normal tiling'
[[ "$(cat "$STATE_FILE")" == "disabled" ]] \
    || fail 'second toggle did not publish disabled runtime state'
contains "$TEST_LUA" 'local awtarchy_floating_windows = false -- AWTARCHY_FLOATING_WINDOWS' \
    'second toggle did not persist the disabled marker'
contains "$NOTIFY_LOG" 'Floating windows disabled' \
    'keyboard notification did not report disabled state'

printf '%s\n' 'PASS: global Floating Windows mode has one shared state, keyboard toggle, and clickable bar escape hatch.'
