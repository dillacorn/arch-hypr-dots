#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/config/hypr/scripts/screenshare_guard.sh"
HYPR="$ROOT/config/hypr/hyprland.lua"
SCREENSHARE_LUA="$ROOT/config/hypr/screenshare_guard.lua"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
SCREENSHARE_CARD="$ROOT/config/quickshell/awtarchy/ScreenShareGuardCard.qml"
MANAGED_HISTORY="$ROOT/local/share/awtarchy/quickshell-managed-history.sha256"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_source() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

[[ -x "$HELPER" ]] || fail 'Screen Share Guard helper is missing or not executable'
[[ -r "$SCREENSHARE_LUA" ]] || fail 'Screen Share Guard Lua module is missing'
[[ -r "$SCREENSHARE_CARD" ]] || fail 'Screen Share Guard QML card is missing'

# Stock policy keeps the privacy-focused application groups and current Awtarchy
# integrations. Retired shell surfaces and Quickshell notification privacy are
# not duplicated here.
active_targets=(
    security
    mullvad-browser
    localsend
    telegram
    matrix
    discord
    teams
    messages
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
)

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/cache" "$TMP/runtime" "$TMP/bin"

cat >"$TMP/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_HYPRCTL_LOG:?}"
if [[ ${1:-} == -r ]]; then
    shift
fi
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
jq -e '(.targets | keys | length) == 16' <<<"$policy_json" >/dev/null \
    || fail 'Screen Share Guard exposes stale or unexpected target groups'
for retired in notifications ags logout-dialog waybar; do
    if jq -e --arg target "$retired" '.targets[$target]? != null' <<<"$policy_json" >/dev/null; then
        fail "retired/duplicate Screen Share Guard target is still exposed: $retired"
    fi
done

# Current Awtarchy Firefox web-app classes must be covered by the relevant groups.
require_source "$SCREENSHARE_LUA" '|telegram|Telegram)$' \
    'Telegram protection does not include the current Awtarchy Firefox web-app class'
require_source "$SCREENSHARE_LUA" '^(messages|Messages)$' \
    'Messages protection does not include the current Awtarchy Firefox web-app class'
require_source "$SCREENSHARE_LUA" 'steam-chat|SteamChat' \
    'optional Steam protection does not include the current Awtarchy Steam Chat web app'
if grep -Eq 'swaync|namespace = "\^\(ags\)\$"|logout_dialog|namespace = "\^\(waybar\)\$"' "$SCREENSHARE_LUA"; then
    fail 'Screen Share Guard Lua still contains retired shell/notification layer rules'
fi

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

# A toggle on a locked row updates the remembered choice and stays free of
# duplicate session state.
printf '{"discord":false}\n' >"$SESSION_FILE"
$HELPER set discord protected >/dev/null
jq -e '.screenshare_guard.discord == true' "$STATE_FILE" >/dev/null \
    || fail 'locked Discord toggle did not update persistent state'
if jq -e '.discord? != null' "$SESSION_FILE" >/dev/null; then
    fail 'locked Discord toggle left a stale session override'
fi

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
require_source "$AWTARCHY_TEST_HYPRCTL_LOG" '-r eval ' \
    'runtime apply does not request a Hyprland state refresh after rule changes'
if grep -Fq 'hl.exec_scheduled_prop_refresh_immediately()' "$AWTARCHY_TEST_HYPRCTL_LOG"; then
    fail 'runtime apply still requires the Hyprland 0.56-only immediate-refresh Lua API'
fi
if grep -Eq 'sed|hyprland\.lua|comment' "$AWTARCHY_TEST_HYPRCTL_LOG"; then
    fail 'runtime Screen Share Guard attempted source/config rewriting'
fi

# The Hyprland config loads the dedicated module and exposes only the two runtime
# entry points the helper actually calls.
require_source "$HYPR" 'screenshare_guard.lua' \
    'Hyprland config does not load the Screen Share Guard module'
require_source "$HYPR" 'local awtarchy_screenshare_guard_v1' \
    'Hyprland config does not keep the Screen Share Guard module local'
require_source "$HYPR" 'awtarchy_screenshare_guard_set_group_v1' \
    'Hyprland config does not expose runtime Screen Share Guard toggling'
require_source "$HYPR" 'awtarchy_screenshare_guard_status_v1' \
    'Hyprland config does not expose Screen Share Guard runtime status'
if grep -Fq 'awtarchy_screenshare_guard_rules_v1' "$HYPR"; then
    fail 'Hyprland config still exposes Screen Share Guard rule internals'
fi
if grep -Fq 'awtarchy_screenshare_guard_group_enabled_v1' "$HYPR"; then
    fail 'Hyprland config still exposes the unused per-group status wrapper'
fi
require_source "$SCREENSHARE_LUA" ':is_enabled()' \
    'Screen Share Guard effective-state query does not inspect rule handles'
require_source "$SCREENSHARE_LUA" 'hl.on("hyprland.start"' \
    'Screen Share Guard does not restore saved state at Hyprland startup'
require_source "$SCREENSHARE_LUA" 'hl.on("config.reloaded"' \
    'Screen Share Guard does not restore saved state after config reload'
require_source "$SCREENSHARE_LUA" 'screenshare_guard.sh' \
    'Screen Share Guard module does not reapply saved state'

# The guard is an independent always-available Quick Settings cell. It stays
# compact by default and expands only when the user opens it.
require_source "$QUICK_SETTINGS" 'Layout.row: root.visibleQuickSettingsSectionOrder().length' \
    'Quick Settings does not reserve the first free row for Screen Share Guard'
require_source "$QUICK_SETTINGS" 'ScreenShareGuardCard' \
    'Quick Settings does not use the Screen Share Guard card'
require_source "$SCREENSHARE_CARD" 'property bool expanded: false' \
    'Screen Share Guard does not default to a collapsed compact card'
require_source "$SCREENSHARE_CARD" 'model: root.expanded ? root.targetModel("protected") : []' \
    'protected Screen Share Guard rows are rendered while the card is collapsed'
require_source "$SCREENSHARE_CARD" 'onClicked: root.expanded = !root.expanded' \
    'Screen Share Guard header does not toggle expanded state'

# All managed Screen Share Guard stock files must be recognizable by the updater
# on the next revision, including this first version of newly-added files.
managed_history_missing=0
for entry in \
    "$QUICK_SETTINGS|.config/quickshell/awtarchy/QuickSettings.qml" \
    "$SCREENSHARE_CARD|.config/quickshell/awtarchy/ScreenShareGuardCard.qml" \
    "$HELPER|.config/hypr/scripts/screenshare_guard.sh" \
    "$SCREENSHARE_LUA|.config/hypr/screenshare_guard.lua"
do
    source_file="${entry%%|*}"
    rel="${entry#*|}"
    digest="$(sha256sum "$source_file" | awk '{print $1}')"
    if ! grep -Fqx -- "$digest"$'\t'"$rel" "$MANAGED_HISTORY"; then
        printf 'MISSING_MANAGED_HASH %s\t%s\n' "$digest" "$rel" >&2
        managed_history_missing=1
    fi
done
(( managed_history_missing == 0 )) \
    || fail 'managed history is missing current Screen Share Guard stock hashes'

printf 'Screen Share Guard controls tests passed.\n'
