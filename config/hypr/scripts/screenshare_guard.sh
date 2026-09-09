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

FALLBACK_TARGETS=(
    security
    mullvad-browser
    localsend
    telegram
    matrix
    discord
    teams
    messages
    obs
    steam
    rustdesk
    files
    wallpicker
    virt-manager
    alacritty
    mpv
)

declare -A FALLBACK_LABELS=(
    [security]="Passwords & Security"
    [mullvad-browser]="Mullvad Browser"
    [localsend]="LocalSend"
    [telegram]="Telegram"
    [matrix]="Element / Matrix"
    [discord]="Discord / Vesktop / Fluxer"
    [teams]="Teams"
    [messages]="Messages"
    [obs]="OBS"
    [steam]="Steam"
    [rustdesk]="RustDesk"
    [files]="Files"
    [wallpicker]="Wallpicker"
    [virt-manager]="Virtual Machine Manager"
    [alacritty]="Alacritty"
    [mpv]="mpv"
)

declare -A FALLBACK_SECTIONS=(
    [security]=protected
    [mullvad-browser]=protected
    [localsend]=protected
    [telegram]=protected
    [matrix]=protected
    [discord]=protected
    [teams]=protected
    [messages]=protected
    [obs]=optional
    [steam]=optional
    [rustdesk]=optional
    [files]=optional
    [wallpicker]=optional
    [virt-manager]=optional
    [alacritty]=optional
    [mpv]=optional
)

declare -A FALLBACK_DEFAULTS=(
    [security]=true
    [mullvad-browser]=true
    [localsend]=true
    [telegram]=true
    [matrix]=true
    [discord]=true
    [teams]=true
    [messages]=true
    [obs]=false
    [steam]=false
    [rustdesk]=false
    [files]=false
    [wallpicker]=false
    [virt-manager]=false
    [alacritty]=false
    [mpv]=false
)

TARGETS=()
RULE_ROWS=()
declare -A LABELS=()
declare -A SECTIONS=()
declare -A DEFAULT_PROTECTED=()

load_fallback_registry() {
    local target
    TARGETS=("${FALLBACK_TARGETS[@]}")
    RULE_ROWS=()
    LABELS=()
    SECTIONS=()
    DEFAULT_PROTECTED=()
    for target in "${TARGETS[@]}"; do
        LABELS["$target"]="${FALLBACK_LABELS[$target]}"
        SECTIONS["$target"]="${FALLBACK_SECTIONS[$target]}"
        DEFAULT_PROTECTED["$target"]="${FALLBACK_DEFAULTS[$target]}"
    done
}

load_runtime_registry() {
    local raw line id label section default class_regex title_regex target
    local -a parsed_targets=() parsed_rows=()
    local -A seen=() parsed_labels=() parsed_sections=() parsed_defaults=()

    if ! raw="$("$HYPRCTL" repl 'awtarchy_screenshare_guard_registry_v1()' 2>/dev/null)"; then
        return 1
    fi
    [[ -n "$raw" ]] || return 1

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r id label section default class_regex title_regex <<<"$line"
        [[ "$id" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || return 1
        [[ -n "$label" && "$label" != *$'\t'* ]] || return 1
        [[ "$section" == protected || "$section" == optional ]] || return 1
        [[ "$default" == true || "$default" == false ]] || return 1
        [[ -n "$class_regex" ]] || return 1

        if [[ -z ${seen[$id]+x} ]]; then
            seen["$id"]=1
            parsed_targets+=("$id")
            parsed_labels["$id"]="$label"
            parsed_sections["$id"]="$section"
            parsed_defaults["$id"]="$default"
        elif [[ "${parsed_labels[$id]}" != "$label" \
            || "${parsed_sections[$id]}" != "$section" \
            || "${parsed_defaults[$id]}" != "$default" ]]; then
            return 1
        fi

        parsed_rows+=("${id}"$'\t'"${label}"$'\t'"${section}"$'\t'"${default}"$'\t'"${class_regex}"$'\t'"${title_regex}")
    done <<<"$raw"

    (( ${#parsed_targets[@]} > 0 )) || return 1

    TARGETS=("${parsed_targets[@]}")
    RULE_ROWS=("${parsed_rows[@]}")
    LABELS=()
    SECTIONS=()
    DEFAULT_PROTECTED=()
    for target in "${TARGETS[@]}"; do
        LABELS["$target"]="${parsed_labels[$target]}"
        SECTIONS["$target"]="${parsed_sections[$target]}"
        DEFAULT_PROTECTED["$target"]="${parsed_defaults[$target]}"
    done
}

load_registry() {
    load_runtime_registry || load_fallback_registry
}

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
load_registry

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
        # jq variables are jq bindings, not Bash interpolation.
        # shellcheck disable=SC2016
        write_state_locked '
            .screenshare_guard = (if (.screenshare_guard | type) == "object" then .screenshare_guard else {} end)
            | .screenshare_guard[$target] = $value
        ' "$target" "$value"
        # shellcheck disable=SC2016
        write_session_locked 'del(.[$target])' "$target"
    else
        # shellcheck disable=SC2016
        write_session_locked '.[$target] = $value' "$target" "$value"
    fi
}

lock_locked() {
    local target="$1" value
    value="$(desired_value_locked "$target")"
    # jq variables are jq bindings, not Bash interpolation.
    # shellcheck disable=SC2016
    write_state_locked '
        .screenshare_guard = (if (.screenshare_guard | type) == "object" then .screenshare_guard else {} end)
        | .screenshare_guard[$target] = $value
    ' "$target" "$value"
    # shellcheck disable=SC2016
    write_session_locked 'del(.[$target])' "$target"
}

unlock_locked() {
    local target="$1" value
    value="$(desired_value_locked "$target")"
    # jq variables are jq bindings, not Bash interpolation.
    # shellcheck disable=SC2016
    write_state_locked '
        .screenshare_guard = (if (.screenshare_guard | type) == "object" then .screenshare_guard else {} end)
        | del(.screenshare_guard[$target])
        | if (.screenshare_guard | length) == 0 then del(.screenshare_guard) else . end
    ' "$target"
    # shellcheck disable=SC2016
    write_session_locked '.[$target] = $value' "$target" "$value"
}

reset_locked() {
    write_state_locked 'del(.screenshare_guard)'
    printf '{}\n' >"$SESSION_FILE"
}

desired_json_locked() {
    local targets_json='{}' target desired persistent session locked default label section order=0
    for target in "${TARGETS[@]}"; do
        desired="$(desired_value_locked "$target")"
        persistent="$(persistent_value_locked "$target")"
        session="$(session_value_locked "$target")"
        if [[ "$persistent" == null ]]; then locked=false; else locked=true; fi
        default="${DEFAULT_PROTECTED[$target]}"
        label="${LABELS[$target]}"
        section="${SECTIONS[$target]}"
        # jq variables are jq bindings, not Bash interpolation.
        # shellcheck disable=SC2016
        targets_json="$(jq -c \
            --arg id "$target" \
            --arg label "$label" \
            --arg section "$section" \
            --argjson order "$order" \
            --argjson default "$default" \
            --argjson desired "$desired" \
            --argjson locked "$locked" \
            --argjson session "$session" '
                . + {($id): {
                    id: $id,
                    label: $label,
                    section: $section,
                    order: $order,
                    default_protected: $default,
                    desired_protected: $desired,
                    locked: $locked,
                    session_override: $session
                }}
            ' <<<"$targets_json")"
        order=$((order + 1))
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
    printf '%s\n' "$lua"
}

apply_lua() {
    local lua="$1"
    "$HYPRCTL" -r eval "$lua" >/dev/null
}

sync_open_windows_locked() {
    local clients row target _label _section _default class_regex title_regex desired addresses address
    (( ${#RULE_ROWS[@]} > 0 )) || return 0

    clients="$("$HYPRCTL" -j clients)" || return 1
    jq -e 'type == "array"' <<<"$clients" >/dev/null || return 1

    for row in "${RULE_ROWS[@]}"; do
        IFS=$'\t' read -r target _label _section _default class_regex title_regex <<<"$row"
        desired="$(desired_value_locked "$target")"
        addresses="$(jq -r \
            --arg class "$class_regex" \
            --arg title "$title_regex" '
                def matches($value; $regex): try (($value // "") | test($regex)) catch false;
                .[]
                | select(
                    (matches(.class; $class) or matches(.initialClass; $class))
                    and
                    ($title == "" or matches(.title; $title) or matches(.initialTitle; $title))
                )
                | (.address // empty)
            ' <<<"$clients")" || return 1

        while IFS= read -r address; do
            [[ -n "$address" ]] || continue
            [[ "$address" =~ ^0x[0-9A-Fa-f]+$ ]] || return 1
            "$HYPRCTL" dispatch \
                "hl.dsp.window.set_prop({ prop = \"no_screen_share\", value = \"${desired}\", window = \"address:${address}\" })" \
                >/dev/null || return 1
        done <<<"$addresses"
    done
}

apply_guard_locked() {
    local lua
    lua="$(build_apply_lua_locked)"
    if ! apply_lua "$lua"; then
        return 1
    fi
    sync_open_windows_locked
}

apply_guard() {
    with_locks apply_guard_locked
}

restore_file_locked() {
    local file="$1" content="$2" tmp
    tmp="$(mktemp "${file}.rollback.XXXXXX")"
    printf '%s\n' "$content" >"$tmp"
    mv -f -- "$tmp" "$file"
}

mutate_and_apply_locked() {
    local mutation="$1"
    shift
    local state_before session_before rc=0

    state_before="$(<"$STATE_FILE")"
    session_before="$(<"$SESSION_FILE")"

    "$mutation" "$@" || rc=$?
    if (( rc == 0 )); then
        apply_guard_locked || rc=$?
    fi
    (( rc == 0 )) && return 0

    restore_file_locked "$STATE_FILE" "$state_before" || true
    restore_file_locked "$SESSION_FILE" "$session_before" || true
    apply_guard_locked >/dev/null 2>&1 || true
    return "$rc"
}

runtime_status() {
    local raw
    if ! raw="$("$HYPRCTL" repl 'awtarchy_screenshare_guard_status_v1()' 2>/dev/null)"; then
        return 1
    fi
    printf '%s\n' "$raw"
}

status_json() {
    local desired actual='{}' raw target value merged
    desired="$(desired_json)"
    if raw="$(runtime_status 2>/dev/null)"; then
        while IFS='=' read -r target value; do
            valid_target "$target" || continue
            case "$value" in
                true|false)
                    # jq variables are jq bindings, not Bash interpolation.
                    # shellcheck disable=SC2016
                    actual="$(jq -c --arg target "$target" --argjson value "$value" '. + {($target):$value}' <<<"$actual")"
                    ;;
            esac
        done <<<"$raw"
    fi
    # jq variables are jq bindings, not Bash interpolation.
    # shellcheck disable=SC2016
    merged="$(jq -c --argjson actual "$actual" '
        .targets |= with_entries(
            .key as $target
            | .value.effective_protected = (if ($actual | has($target)) then $actual[$target] else null end)
            | .value.in_sync = (if ($actual[$target] | type) == "boolean"
                then ($actual[$target] == .value.desired_protected) else false end)
        )
    ' <<<"$desired")"
    printf '%s\n' "$merged"
}

set_target() {
    local target="$1" value="$2"
    require_target "$target"
    value="$(protected_value "$value")"
    with_locks mutate_and_apply_locked set_locked "$target" "$value"
}

lock_target() {
    require_target "$1"
    with_locks mutate_and_apply_locked lock_locked "$1"
}

unlock_target() {
    require_target "$1"
    with_locks mutate_and_apply_locked unlock_locked "$1"
}

reset_guard() {
    with_locks mutate_and_apply_locked reset_locked
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
