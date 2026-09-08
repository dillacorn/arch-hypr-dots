#!/usr/bin/env bash
# Manage Awtarchy Screen Share Guard session and persistent overrides.

set -euo pipefail

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
RUNTIME_ROOT="${XDG_RUNTIME_DIR:-${CACHE_HOME}/awtarchy-runtime}"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
STATE_LOCK_FILE="${STATE_FILE}.lock"
SESSION_FILE="${RUNTIME_ROOT}/awtarchy/screenshare-guard-session.json"
SESSION_LOCK_FILE="${SESSION_FILE}.lock"
HYPRCTL="${AWTARCHY_SCREENSHARE_HYPRCTL:-hyprctl}"
TMP_FILE=""

TARGETS=(
    security
    mullvad-browser
    localsend
    telegram
    matrix
    discord
    teams
    messages
    notifications
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

ACTIVE_DEFAULTS=(
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

OPTIONAL_DEFAULTS=(
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

declare -A LABELS=(
    [security]="Passwords & Security"
    [mullvad-browser]="Mullvad Browser"
    [localsend]="LocalSend"
    [telegram]="Telegram"
    [matrix]="Element / Matrix"
    [discord]="Discord / Vesktop / Fluxer"
    [teams]="Teams"
    [messages]="Messages"
    [notifications]="Notifications"
    [obs]="OBS"
    [steam]="Steam"
    [rustdesk]="RustDesk"
    [files]="Files"
    [wallpicker]="Wallpicker"
    [virt-manager]="Virtual Machine Manager"
    [alacritty]="Alacritty"
    [mpv]="mpv"
    [ags]="AGS"
    [logout-dialog]="Logout Dialog"
    [waybar]="Waybar"
)

declare -A DEFAULT_PROTECTED=()
for target in "${ACTIVE_DEFAULTS[@]}"; do
    DEFAULT_PROTECTED["$target"]=true
done
for target in "${OPTIONAL_DEFAULTS[@]}"; do
    DEFAULT_PROTECTED["$target"]=false
done

cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}
trap cleanup EXIT

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'screenshare_guard.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

need jq
need flock

valid_target() {
    local target="$1" candidate
    for candidate in "${TARGETS[@]}"; do
        [[ "$candidate" == "$target" ]] && return 0
    done
    return 1
}

require_target() {
    valid_target "$1" || {
        printf 'screenshare_guard.sh: unknown target: %s\n' "$1" >&2
        exit 2
    }
}

protected_value() {
    case "$1" in
        protected|true|1|on) printf 'true\n' ;;
        allowed|allow|false|0|off) printf 'false\n' ;;
        *)
            printf 'screenshare_guard.sh: expected protected or allowed\n' >&2
            exit 2
            ;;
    esac
}

ensure_files_locked() {
    mkdir -p -- "$(dirname -- "$STATE_FILE")" "$(dirname -- "$SESSION_FILE")"
    if [[ ! -s "$STATE_FILE" ]] || ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
        printf '{}\n' >"$STATE_FILE"
    fi
    if [[ ! -s "$SESSION_FILE" ]] || ! jq -e 'type == "object"' "$SESSION_FILE" >/dev/null 2>&1; then
        printf '{}\n' >"$SESSION_FILE"
    fi
}

with_locks() {
    mkdir -p -- "$(dirname -- "$STATE_LOCK_FILE")" "$(dirname -- "$SESSION_LOCK_FILE")"
    exec 9>"$STATE_LOCK_FILE"
    exec 8>"$SESSION_LOCK_FILE"
    flock 9
    flock 8
    ensure_files_locked
    local rc=0
    "$@" || rc=$?
    flock -u 8
    flock -u 9
    exec 8>&- 9>&-
    return "$rc"
}

persistent_value_locked() {
    local target="$1"
    jq -r --arg target "$target" '
        if ((.screenshare_guard? // {}) | type) == "object"
            and ((.screenshare_guard? // {}) | has($target))
            and (.screenshare_guard[$target] | type) == "boolean"
        then (.screenshare_guard[$target] | tostring)
        else "null"
        end
    ' "$STATE_FILE"
}

session_value_locked() {
    local target="$1"
    jq -r --arg target "$target" '
        if type == "object" and has($target) and (.[$target] | type) == "boolean"
        then (.[$target] | tostring)
        else "null"
        end
    ' "$SESSION_FILE"
}

desired_value_locked() {
    local target="$1" value
    value="$(session_value_locked "$target")"
    if [[ "$value" != null ]]; then
        printf '%s\n' "$value"
        return
    fi
    value="$(persistent_value_locked "$target")"
    if [[ "$value" != null ]]; then
        printf '%s\n' "$value"
        return
    fi
    printf '%s\n' "${DEFAULT_PROTECTED[$target]}"
}

is_locked_locked() {
    [[ "$(persistent_value_locked "$1")" != null ]]
}

write_state_locked() {
    local filter="$1" target="${2:-}" value="${3:-null}"
    TMP_FILE="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
    jq --arg target "$target" --argjson value "$value" "$filter" "$STATE_FILE" >"$TMP_FILE"
    mv -f -- "$TMP_FILE" "$STATE_FILE"
    TMP_FILE=""
}

write_session_locked() {
    local filter="$1" target="${2:-}" value="${3:-null}"
    TMP_FILE="$(mktemp "${SESSION_FILE}.tmp.XXXXXX")"
    jq --arg target "$target" --argjson value "$value" "$filter" "$SESSION_FILE" >"$TMP_FILE"
    mv -f -- "$TMP_FILE" "$SESSION_FILE"
    TMP_FILE=""
}

set_locked() {
    local target="$1" value="$2"
    if is_locked_locked "$target"; then
        write_state_locked '
            .screenshare_guard = (if (.screenshare_guard | type) == "object" then .screenshare_guard else {} end)
            | .screenshare_guard[$target] = $value
        ' "$target" "$value"
    else
        write_session_locked '.[$target] = $value' "$target" "$value"
    fi
}

lock_locked() {
    local target="$1" value
    value="$(desired_value_locked "$target")"
    write_state_locked '
        .screenshare_guard = (if (.screenshare_guard | type) == "object" then .screenshare_guard else {} end)
        | .screenshare_guard[$target] = $value
    ' "$target" "$value"
    write_session_locked 'del(.[$target])' "$target"
}

unlock_locked() {
    local target="$1" value
    value="$(desired_value_locked "$target")"
    write_state_locked '
        .screenshare_guard = (if (.screenshare_guard | type) == "object" then .screenshare_guard else {} end)
        | del(.screenshare_guard[$target])
        | if (.screenshare_guard | length) == 0 then del(.screenshare_guard) else . end
    ' "$target"
    write_session_locked '.[$target] = $value' "$target" "$value"
}

reset_locked() {
    write_state_locked 'del(.screenshare_guard)'
    printf '{}\n' >"$SESSION_FILE"
}

desired_json_locked() {
    local targets_json='{}' target desired persistent session locked default label section
    for target in "${TARGETS[@]}"; do
        desired="$(desired_value_locked "$target")"
        persistent="$(persistent_value_locked "$target")"
        session="$(session_value_locked "$target")"
        if [[ "$persistent" == null ]]; then locked=false; else locked=true; fi
        default="${DEFAULT_PROTECTED[$target]}"
        label="${LABELS[$target]}"
        section=optional
        [[ "$default" == true ]] && section=protected
        targets_json="$(jq -c \
            --arg id "$target" \
            --arg label "$label" \
            --arg section "$section" \
            --argjson default "$default" \
            --argjson desired "$desired" \
            --argjson locked "$locked" \
            --argjson session "$session" '
                . + {($id): {
                    id: $id,
                    label: $label,
                    section: $section,
                    default_protected: $default,
                    desired_protected: $desired,
                    locked: $locked,
                    session_override: $session
                }}
            ' <<<"$targets_json")"
    done
    jq -cn --argjson targets "$targets_json" '{targets:$targets}'
}

desired_json() {
    with_locks desired_json_locked
}

build_apply_lua_locked() {
    local target desired lua=''
    for target in "${TARGETS[@]}"; do
        desired="$(desired_value_locked "$target")"
        lua+="awtarchy_screenshare_guard_set_group_v1(\"${target}\", ${desired});"
    done
    lua+='hl.exec_scheduled_prop_refresh_immediately()'
    printf '%s\n' "$lua"
}

apply_guard() {
    local lua
    lua="$(with_locks build_apply_lua_locked)"
    "$HYPRCTL" eval "$lua" >/dev/null
}

runtime_status() {
    local raw
    if ! raw="$($HYPRCTL repl 'awtarchy_screenshare_guard_status_v1()' 2>/dev/null)"; then
        return 1
    fi
    printf '%s\n' "$raw"
}

status_json() {
    local desired actual='{}' raw line target value merged
    desired="$(desired_json)"
    if raw="$(runtime_status 2>/dev/null)"; then
        while IFS='=' read -r target value; do
            valid_target "$target" || continue
            case "$value" in
                true|false)
                    actual="$(jq -c --arg target "$target" --argjson value "$value" '. + {($target):$value}' <<<"$actual")"
                    ;;
            esac
        done <<<"$raw"
    fi
    merged="$(jq -c --argjson actual "$actual" '
        .targets |= with_entries(
            .value.effective_protected = ($actual[.key] // null)
            | .value.in_sync = (if ($actual[.key] | type) == "boolean"
                then ($actual[.key] == .value.desired_protected) else false end)
        )
    ' <<<"$desired")"
    printf '%s\n' "$merged"
}

set_target() {
    local target="$1" value="$2"
    require_target "$target"
    value="$(protected_value "$value")"
    with_locks set_locked "$target" "$value"
    apply_guard
}

lock_target() {
    require_target "$1"
    with_locks lock_locked "$1"
    apply_guard
}

unlock_target() {
    require_target "$1"
    with_locks unlock_locked "$1"
    apply_guard
}

reset_guard() {
    with_locks reset_locked
    apply_guard
}

case "${1:-}" in
    desired-json)
        desired_json
        ;;
    status-json)
        status_json
        ;;
    apply)
        apply_guard
        ;;
    set)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_target "$2" "$3"
        ;;
    lock)
        [[ -n ${2:-} ]] || exit 2
        lock_target "$2"
        ;;
    unlock)
        [[ -n ${2:-} ]] || exit 2
        unlock_target "$2"
        ;;
    reset)
        reset_guard
        ;;
    *)
        printf 'usage: %s {desired-json|status-json|apply|set <target> <protected|allowed>|lock <target>|unlock <target>|reset}\n' "${0##*/}" >&2
        exit 2
        ;;
esac
