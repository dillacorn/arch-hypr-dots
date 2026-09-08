#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/config/hypr/scripts/screenshare_guard.sh"
HYPR="$ROOT/config/hypr/hyprland.lua"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
BAR_STATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
LAYOUT_EDITOR="$ROOT/config/quickshell/awtarchy/QuickSettingsLayoutEditor.qml"
FLYOUT_SETTINGS="$ROOT/config/quickshell/awtarchy/FlyoutSettings.qml"
RUNTIME_RULES="$ROOT/config/hypr/scripts/quickshell_runtime_rules.sh"
APP_STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_source() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

[[ -x "$HELPER" ]] || fail 'Screen Share Guard helper is missing or not executable'

# Stock policy must preserve the existing active protections while leaving the
# previously-commented optional targets opt-in.
active_targets=(
    security
    mullvad-browser
    localsend
    telegram
    matrix
    discord
    teams
    messages
    notifications
)
optional_targets=(
    obs
    steam
    rustdesk
    files
    wallpicker
    virt-manager
    alacritty
    mpv
    ags
    logout-dialog
    waybar
)

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/cache" "$TMP/runtime" "$TMP/bin"

cat >"$TMP/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_HYPRCTL_LOG:?}"
case "${1:-}" in
    eval)
        printf 'ok\n'
        ;;
    repl)
        # Unit tests validate desired/session/persistent state separately. A
        # live Hyprland session is responsible for final effective-state proof.
        printf 'true\n'
        ;;
esac
STUB
chmod 0755 "$TMP/bin/hyprctl"

export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_RUNTIME_DIR="$TMP/runtime"
export XDG_CONFIG_HOME="$TMP/home/.config"
export AWTARCHY_SCREENSHARE_HYPRCTL="$TMP/bin/hyprctl"
export AWTARCHY_TEST_HYPRCTL_LOG="$TMP/hyprctl.log"
STATE_FILE="$XDG_CACHE_HOME/awtarchy/quickshell-state.json"
SESSION_FILE="$XDG_RUNTIME_DIR/awtarchy/screenshare-guard-session.json"
mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$SESSION_FILE")"
printf '{}\n' >"$STATE_FILE"

policy_json="$($HELPER desired-json)" || fail 'desired-json failed'
for target in "${active_targets[@]}"; do
    jq -e --arg target "$target" '.targets[$target].default_protected == true and .targets[$target].desired_protected == true' \
        <<<"$policy_json" >/dev/null || fail "active target does not default protected: $target"
done
for target in "${optional_targets[@]}"; do
    jq -e --arg target "$target" '.targets[$target].default_protected == false and .targets[$target].desired_protected == false' \
        <<<"$policy_json" >/dev/null || fail "optional target does not default capture-allowed: $target"
done

# Unlocked toggles are session-only.
$HELPER set discord allowed >/dev/null
jq -e '.discord == false' "$SESSION_FILE" >/dev/null \
    || fail 'unlocked Discord toggle was not stored as a session override'
if jq -e '.screenshare_guard.discord? != null' "$STATE_FILE" >/dev/null; then
    fail 'unlocked Discord toggle leaked into persistent state'
fi

# Locking remembers the current effective choice and clears its session entry.
$HELPER lock discord >/dev/null
jq -e '.screenshare_guard.discord == false' "$STATE_FILE" >/dev/null \
    || fail 'locking Discord did not persist its capture-allowed state'
if [[ -s "$SESSION_FILE" ]] && jq -e '.discord? != null' "$SESSION_FILE" >/dev/null; then
    fail 'locking Discord left a duplicate session override'
fi

# A toggle on a locked row updates the remembered choice.
$HELPER set discord protected >/dev/null
jq -e '.screenshare_guard.discord == true' "$STATE_FILE" >/dev/null \
    || fail 'locked Discord toggle did not update persistent state'

# Unlocking must not visibly flip the row: preserve its current choice for the
# remainder of the session while removing durable persistence.
$HELPER unlock discord >/dev/null
if jq -e '.screenshare_guard.discord? != null' "$STATE_FILE" >/dev/null; then
    fail 'unlocking Discord left a persistent Screen Share Guard override'
fi
jq -e '.discord == true' "$SESSION_FILE" >/dev/null \
    || fail 'unlocking Discord did not preserve its current state for this session'

# Reset clears both override layers and restores the stock policy.
$HELPER set obs protected >/dev/null
$HELPER lock obs >/dev/null
$HELPER reset >/dev/null
if jq -e '.screenshare_guard? != null' "$STATE_FILE" >/dev/null; then
    fail 'Restore Defaults left persistent Screen Share Guard state behind'
fi
if [[ -s "$SESSION_FILE" ]] && jq -e 'length > 0' "$SESSION_FILE" >/dev/null; then
    fail 'Restore Defaults left session Screen Share Guard overrides behind'
fi
policy_json="$($HELPER desired-json)" || fail 'desired-json failed after reset'
jq -e '.targets.discord.desired_protected == true and .targets.obs.desired_protected == false' \
    <<<"$policy_json" >/dev/null || fail 'Restore Defaults did not restore stock policy'

if $HELPER set definitely-not-a-target protected >/dev/null 2>&1; then
    fail 'unknown Screen Share Guard target was accepted'
fi

# Runtime application is through named Lua rule handles, never source editing.
: >"$AWTARCHY_TEST_HYPRCTL_LOG"
$HELPER set discord allowed >/dev/null
$HELPER apply >/dev/null
require_source "$AWTARCHY_TEST_HYPRCTL_LOG" 'awtarchy_screenshare_guard_set_group_v1("discord", false)' \
    'runtime apply did not disable the Discord named rule group'
require_source "$AWTARCHY_TEST_HYPRCTL_LOG" 'hl.exec_scheduled_prop_refresh_immediately()' \
    'runtime apply does not force immediate dynamic-property refresh'
if grep -Eq 'sed|hyprland\.lua|comment' "$AWTARCHY_TEST_HYPRCTL_LOG"; then
    fail 'runtime Screen Share Guard attempted source/config rewriting'
fi

# The Hyprland config owns fail-closed named rule handles and exposes runtime
# query/toggle helpers so UI state can be verified against the compositor.
require_source "$HYPR" 'awtarchy_screenshare_guard_rules_v1' \
    'Hyprland config does not expose named Screen Share Guard rule handles'
require_source "$HYPR" 'awtarchy_screenshare_guard_set_group_v1' \
    'Hyprland config does not expose runtime Screen Share Guard toggling'
require_source "$HYPR" 'awtarchy_screenshare_guard_group_enabled_v1' \
    'Hyprland config does not expose effective Screen Share Guard state'
require_source "$HYPR" ':is_enabled()' \
    'Hyprland Screen Share Guard effective-state query does not inspect rule handles'
require_source "$HYPR" 'screenshare_guard.sh apply' \
    'Hyprland does not reapply Screen Share Guard state after startup/reload'

# Existing runtime-rule startup paths must also reapply the guard state.
require_source "$RUNTIME_RULES" 'screenshare_guard.sh' \
    'Quickshell runtime rule setup does not reapply Screen Share Guard state'

# Screen Share Guard is a first-class Quick Settings cell and participates in
# the existing layout visibility/order system.
require_source "$BAR_STATE" '"screen-share-guard"' \
    'BarState stock Quick Settings order is missing Screen Share Guard'
require_source "$APP_STATE" '"screen-share-guard"' \
    'Quick Settings persisted-layout normalization is missing Screen Share Guard'
require_source "$QUICK_SETTINGS" 'quickSettingsSectionRow("screen-share-guard")' \
    'Quick Settings does not place Screen Share Guard as its own cell'
require_source "$QUICK_SETTINGS" 'ScreenShareGuardCard' \
    'Quick Settings does not use the Screen Share Guard card'
require_source "$LAYOUT_EDITOR" '"screen-share-guard": "Screen Share Guard"' \
    'Quick Settings layout editor is missing the Screen Share Guard label'
require_source "$FLYOUT_SETTINGS" '"screen-share-guard": "Screen Share Guard"' \
    'Quick Settings visibility controls are missing the Screen Share Guard label'

printf 'Screen Share Guard controls tests passed.\n'
