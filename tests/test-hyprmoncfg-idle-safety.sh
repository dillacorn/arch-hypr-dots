#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$ROOT/config/hypr/hyprland.lua"
HYPRIDLE_CONF="$ROOT/config/hypr/hypridle.conf"
HYPRIDLE_ACTION="$ROOT/config/hypr/scripts/hypridle_action.sh"
PROTECTED_IDLE_SAFETY="$ROOT/config/hypr/scripts/protected_idle_safety.sh"
INHIBITOR="$ROOT/config/hypr/scripts/idle_inhibitor_global.sh"
LAUNCH_HANDLER="$ROOT/config/hypr/scripts/launch_handler.sh"
SYSTEM_STATE="$ROOT/config/quickshell/awtarchy/SystemState.qml"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
BAR="$ROOT/config/quickshell/awtarchy/Bar.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_file_text() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

require_hypr_count() {
    local needle="$1" expected="$2" message="$3" count
    count="$(grep -Fc -- "$needle" "$HYPR" || true)"
    [[ "$count" == "$expected" ]] || fail "$message (expected $expected, found $count)"
}

# Hyprmoncfg is a large floating terminal utility. The same shortcut must work
# in normal and noalt modes without displacing the existing maccel shortcut.
require_file_text "$HYPR" \
    'local hyprmoncfg = "APP_NO_LAUNCH_IF_TILED=1 ~/.config/hypr/scripts/launch_handler.sh hyprmoncfg \"~/.config/hypr/scripts/default_terminal.sh --class hyprmoncfg -- hyprmoncfg\""' \
    'hyprmoncfg launcher does not use the shared terminal/toggle helpers with tiled-instance suppression'
require_hypr_count \
    'hl.bind("SUPER + CTRL + M", hl.dsp.exec_cmd(hyprmoncfg), {})' \
    2 \
    'SUPER+CTRL+M is not consistently bound to hyprmoncfg in normal and noalt modes'
require_hypr_count \
    '{ "SUPER + SHIFT + M", maccel },' \
    2 \
    'existing SUPER+SHIFT+M maccel binding was displaced'
require_file_text "$HYPR" \
    'hl.window_rule({ match = { class = "^(hyprmoncfg)$" }, float = true })' \
    'hyprmoncfg is not forced floating on launch'
require_file_text "$HYPR" \
    'hl.window_rule({ match = { class = "^(hyprmoncfg)$" }, size = { "(monitor_w*0.85)", "(monitor_h*0.90)" } })' \
    'hyprmoncfg does not use the approved monitor-relative 85%x90% size'
require_file_text "$HYPR" \
    'hl.window_rule({ match = { class = "^(hyprmoncfg)$" }, center = true })' \
    'hyprmoncfg is not centered'

# A matching tiled instance belongs to the user. The shortcut must not close it
# and must not spawn a second floating copy.
TMP="$(mktemp -d)"
cleanup() {
    rm -rf -- "$TMP"
}
trap cleanup EXIT

stub_bin="$TMP/bin"
mkdir -p -- "$stub_bin"
launch_marker="$TMP/launched"

cat >"$stub_bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
    activeworkspace)
        printf '%s\n' '{"id":1}'
        ;;
    clients)
        printf '%s\n' '[{"mapped":true,"hidden":false,"floating":false,"workspace":{"id":1},"pid":4242,"address":"0xabc","class":"hyprmoncfg","initialClass":"hyprmoncfg","title":"hyprmoncfg"}]'
        ;;
    dispatch)
        printf '%s\n' "$*" >>"${HYPRCTL_LOG:?}"
        ;;
    *)
        printf '%s\n' "unexpected hyprctl invocation: $*" >&2
        exit 2
        ;;
esac
EOF
chmod 0755 "$stub_bin/hyprctl"

export HYPRCTL_LOG="$TMP/hyprctl.log"
export LAUNCH_MARKER="$launch_marker"
PATH="$stub_bin:$PATH" \
APP_NO_LAUNCH_IF_TILED=1 \
    "$LAUNCH_HANDLER" hyprmoncfg \
    "sh -c 'printf launched > \"\$LAUNCH_MARKER\"'"
sleep 0.15
[[ ! -e "$launch_marker" ]] || fail 'tiled hyprmoncfg instance allowed a duplicate floating launch'

# Four hours of genuine inactivity gets one safety listener. It must lock and
# power off displays for protected sessions without allowing suspend.
require_file_text "$HYPRIDLE_CONF" 'timeout = 14400 # 4 hours' \
    'hypridle lacks the four-hour protected-session safety timer'
require_file_text "$HYPRIDLE_CONF" \
    'on-timeout = ~/.config/hypr/scripts/protected_idle_safety.sh' \
    'four-hour safety timer does not use the protected-session safety coordinator'

require_file_text "$PROTECTED_IDLE_SAFETY" \
    'hypridle_action.sh' \
    'protected-session safety does not reuse the authoritative hypridle probes'
require_file_text "$INHIBITOR" 'set-mode)' \
    'idle inhibitor backend lacks explicit mode selection'
require_file_text "$INHIBITOR" 'always-awake' \
    'idle inhibitor backend lacks an Always Awake mode'
require_file_text "$SYSTEM_STATE" 'property string idleMode: "off"' \
    'Quickshell SystemState does not track the authoritative idle mode'
require_file_text "$SYSTEM_STATE" 'function setIdleMode(mode)' \
    'Quickshell SystemState cannot explicitly select an idle mode'
require_file_text "$QUICK_SETTINGS" 'text: "Always Awake"' \
    'Quick Settings lacks the explicit Always Awake control'
require_file_text "$QUICK_SETTINGS" 'SystemState.setIdleMode(' \
    'Quick Settings Always Awake control does not use shared SystemState idle mode'
require_file_text "$BAR" 'SystemState.idleMode === "always-awake"' \
    'bar idle indicator does not distinguish Always Awake mode'
count="$(grep -Fc -- 'normalBackground: SystemState.idleMode === "always-awake" ? Theme.subtleActive : "transparent"' "$BAR" || true)"
[[ "$count" == 2 ]] || fail "Always Awake background must exist on both bar orientations (expected 2, found $count)"

MANAGED_HISTORY="$ROOT/local/share/awtarchy/quickshell-managed-history.sha256"
for managed_file in "$BAR" "$QUICK_SETTINGS" "$SYSTEM_STATE"; do
    repo_rel="${managed_file#$ROOT/}"
    current_entry="$(sha256sum "$managed_file" | awk '{print $1}')"$'\t'".${repo_rel}"
    grep -Fqx -- "$current_entry" "$MANAGED_HISTORY" \
        || fail "managed history is missing current stock hash for $repo_rel"
done

# Exercise the long-idle action with controlled backends. Keep Awake must allow
# lock+DPMS, while Always Awake must block that safety action too.
mode_file="$TMP/mode"
action_log="$TMP/action.log"
printf '%s\n' keep-awake >"$mode_file"

cat >"$stub_bin/idle-inhibitor" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
mode="$(cat "${IDLE_MODE_FILE:?}")"
case "${1:-status}" in
    is-active)
        [[ "$mode" != off ]]
        ;;
    mode)
        printf '%s\n' "$mode"
        ;;
    is-always-awake)
        [[ "$mode" == always-awake ]]
        ;;
    off)
        printf '%s\n' off >"${IDLE_MODE_FILE:?}"
        ;;
    *)
        printf '%s\n' "unexpected inhibitor invocation: ${1:-}" >&2
        exit 2
        ;;
esac
EOF
chmod 0755 "$stub_bin/idle-inhibitor"

cat >"$stub_bin/loginctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'loginctl %s\n' "$*" >>"${ACTION_LOG:?}"
EOF
chmod 0755 "$stub_bin/loginctl"

cat >"$stub_bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
    clients)
        printf '%s\n' '[]'
        ;;
    monitors)
        printf '%s\n' '[]'
        ;;
    activeworkspace)
        printf '%s\n' '{"id":1}'
        ;;
    dispatch)
        printf 'hyprctl %s\n' "$*" >>"${ACTION_LOG:?}"
        ;;
    *)
        printf '%s\n' "unexpected hyprctl invocation: $*" >&2
        exit 2
        ;;
esac
EOF
chmod 0755 "$stub_bin/hyprctl"

: >"$action_log"
PATH="$stub_bin:$PATH" \
INHIBITOR_SH="$stub_bin/idle-inhibitor" \
IDLE_MODE_FILE="$mode_file" \
ACTION_LOG="$action_log" \
HYPRCTL_BIN="$stub_bin/hyprctl" \
LOGINCTL_BIN="$stub_bin/loginctl" \
HYPRIDLE_ACTION_SCRIPT="$HYPRIDLE_ACTION" \
    "$PROTECTED_IDLE_SAFETY"

require_file_text "$action_log" 'loginctl lock-session' \
    'Keep Awake did not permit the four-hour safety lock'
require_file_text "$action_log" \
    'hyprctl dispatch hl.dsp.dpms({ action = "disable" })' \
    'Keep Awake did not permit the four-hour safety DPMS-off action'

printf '%s\n' always-awake >"$mode_file"
: >"$action_log"
PATH="$stub_bin:$PATH" \
INHIBITOR_SH="$stub_bin/idle-inhibitor" \
IDLE_MODE_FILE="$mode_file" \
ACTION_LOG="$action_log" \
HYPRCTL_BIN="$stub_bin/hyprctl" \
LOGINCTL_BIN="$stub_bin/loginctl" \
HYPRIDLE_ACTION_SCRIPT="$HYPRIDLE_ACTION" \
    "$PROTECTED_IDLE_SAFETY"

[[ ! -s "$action_log" ]] || fail 'Always Awake did not suppress the four-hour lock+DPMS safety action'

printf '%s\n' 'PASS: hyprmoncfg toggle geometry and protected-session idle safety are consistent.'
