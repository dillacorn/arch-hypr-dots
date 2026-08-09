#!/usr/bin/env bash
# Persist Quickshell application launcher settings.

set -euo pipefail

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
STATE_LOCK_FILE="${STATE_FILE}.lock"
QUICKSHELL_SCRIPT="${HYPR_QUICKSHELL_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh}"

MIN_WIDTH=1
MAX_WIDTH=16384
MIN_HEIGHT=1
MAX_HEIGHT=16384
MIN_TEXT_SCALE=50
MAX_TEXT_SCALE=200
MIN_ICON_SCALE=50
MAX_ICON_SCALE=200
TMP_FILE=""

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell_application_state.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

need jq
need flock

cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}

trap cleanup EXIT

bootstrap_state() {
    mkdir -p "$(dirname "$STATE_FILE")"

    if [[ ! -s "$STATE_FILE" ]] || ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
        if [[ -x "$QUICKSHELL_SCRIPT" ]]; then
            "$QUICKSHELL_SCRIPT" dump-state >/dev/null 2>&1 || true
        fi
    fi
}

ensure_state_locked() {
    if [[ ! -s "$STATE_FILE" ]] || ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
        printf '{"enabled":true,"monitors":{},"launcher_sizes":{}}\n' >"$STATE_FILE"
    fi
}

new_tmp() {
    TMP_FILE="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
}

commit_tmp() {
    mv -f -- "$TMP_FILE" "$STATE_FILE"
    TMP_FILE=""
}

validate_int_range() {
    local value="$1" min="$2" max="$3" label="$4"
    [[ $value =~ ^[0-9]+$ ]] || {
        printf '%s must be an integer\n' "$label" >&2
        exit 2
    }
    (( value >= min && value <= max )) || {
        printf '%s must be %d-%d\n' "$label" "$min" "$max" >&2
        exit 2
    }
}

lock_size() {
    local monitor="$1" width="$2" height="$3"
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    new_tmp
    jq \
        --arg monitor "$monitor" \
        --argjson width "$width" \
        --argjson height "$height" '
        .launcher_sizes = (if (.launcher_sizes | type) == "object" then .launcher_sizes else {} end)
        | .launcher_sizes[$monitor] = ((if (.launcher_sizes[$monitor] | type) == "object"
            then .launcher_sizes[$monitor] else {} end) + {
            width:$width,
            height:$height,
            locked:true
        })
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

unlock_size() {
    local monitor="$1"
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    new_tmp
    jq --arg monitor "$monitor" '
        .launcher_sizes = (if (.launcher_sizes | type) == "object" then .launcher_sizes else {} end)
        | .launcher_sizes[$monitor] = ((if (.launcher_sizes[$monitor] | type) == "object"
            then .launcher_sizes[$monitor] else {} end)
            | del(.width, .height, .locked))
        | if (.launcher_sizes[$monitor] | length) == 0
            then del(.launcher_sizes[$monitor])
            else .
          end
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_locks() {
    new_tmp
    jq '
        .launcher_sizes = ((if (.launcher_sizes | type) == "object" then .launcher_sizes else {} end)
            | with_entries(.value = (if (.value | type) == "object"
                then (.value | del(.width, .height, .locked)) else {} end))
            | with_entries(select((.value | length) > 0)))
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_scales() {
    local monitor="$1" text_scale="$2" icon_scale="$3"
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    validate_int_range "$text_scale" "$MIN_TEXT_SCALE" "$MAX_TEXT_SCALE" 'text scale'
    validate_int_range "$icon_scale" "$MIN_ICON_SCALE" "$MAX_ICON_SCALE" 'icon scale'
    new_tmp
    jq \
        --arg monitor "$monitor" \
        --argjson text_scale "$text_scale" \
        --argjson icon_scale "$icon_scale" '
        .launcher_sizes = (if (.launcher_sizes | type) == "object" then .launcher_sizes else {} end)
        | .launcher_sizes[$monitor] = ((if (.launcher_sizes[$monitor] | type) == "object"
            then .launcher_sizes[$monitor] else {} end) + {
            text_scale:$text_scale,
            icon_scale:$icon_scale
        })
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_monitor() {
    local monitor="$1"
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    new_tmp
    jq --arg monitor "$monitor" '
        .launcher_sizes = (if (.launcher_sizes | type) == "object" then .launcher_sizes else {} end)
        | del(.launcher_sizes[$monitor])
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

copy_view() {
    local width="$1" height="$2" text_scale="$3" icon_scale="$4"
    shift 4
    local -a targets=("$@")
    local targets_json

    (( ${#targets[@]} > 0 )) || {
        printf 'at least one target monitor is required\n' >&2
        exit 2
    }
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    validate_int_range "$text_scale" "$MIN_TEXT_SCALE" "$MAX_TEXT_SCALE" 'text scale'
    validate_int_range "$icon_scale" "$MIN_ICON_SCALE" "$MAX_ICON_SCALE" 'icon scale'
    targets_json="$(jq -cn --args '$ARGS.positional' -- "${targets[@]}")"

    new_tmp
    jq \
        --argjson targets "$targets_json" \
        --argjson width "$width" \
        --argjson height "$height" \
        --argjson text_scale "$text_scale" \
        --argjson icon_scale "$icon_scale" '
        .launcher_sizes = (if (.launcher_sizes | type) == "object" then .launcher_sizes else {} end)
        | .launcher_sizes = reduce $targets[] as $monitor
            (.launcher_sizes;
                .[$monitor] as $current
                | .[$monitor] = ((if ($current | type) == "object" then $current else {} end) + {
                    width:$width,
                    height:$height,
                    text_scale:$text_scale,
                    icon_scale:$icon_scale,
                    locked:(($current.locked // false) == true)
                }))
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_all() {
    new_tmp
    jq '
        .launcher_sizes = {}
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

# Legacy commands remain accepted so older local helpers do not fail during the
# testing branch transition. Launcher dimensions are no longer read globally.
set_field() {
    local field="$1" value="$2" min max label
    case "$field" in
        width) min=$MIN_WIDTH; max=$MAX_WIDTH; label='width' ;;
        height) min=$MIN_HEIGHT; max=$MAX_HEIGHT; label='height' ;;
        text_size) min=10; max=28; label='text size' ;;
        icon_size) min=12; max=48; label='icon size' ;;
        *) printf 'invalid field: %s\n' "$field" >&2; exit 2 ;;
    esac
    validate_int_range "$value" "$min" "$max" "$label"
    new_tmp
    jq --arg field "$field" --argjson value "$value" '
        .application_view = (.application_view // {})
        | .application_view[$field] = $value
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_size() {
    local width="$1" height="$2"
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    new_tmp
    jq --argjson width "$width" --argjson height "$height" '
        .application_view = (.application_view // {})
        | .application_view.width = $width
        | .application_view.height = $height
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_all() {
    local width="$1" height="$2" text_size="$3" icon_size="$4"
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    validate_int_range "$text_size" 10 28 'text size'
    validate_int_range "$icon_size" 12 48 'icon size'
    new_tmp
    jq \
        --argjson width "$width" \
        --argjson height "$height" \
        --argjson text_size "$text_size" \
        --argjson icon_size "$icon_size" '
        .application_view = {
            width:$width,
            height:$height,
            text_size:$text_size,
            icon_size:$icon_size
        }
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_defaults() {
    reset_all
}

bootstrap_state
exec 9>"$STATE_LOCK_FILE"
flock -x 9
ensure_state_locked

cmd="${1:-}"
case "$cmd" in
    lock-size)
        [[ -n ${2:-} && -n ${3:-} && -n ${4:-} ]] || exit 2
        lock_size "$2" "$3" "$4"
        ;;
    unlock-size)
        [[ -n ${2:-} ]] || exit 2
        unlock_size "$2"
        ;;
    reset-locks)
        reset_locks
        ;;
    set-scales)
        [[ -n ${2:-} && -n ${3:-} && -n ${4:-} ]] || exit 2
        set_scales "$2" "$3" "$4"
        ;;
    copy-view)
        [[ -n ${2:-} && -n ${3:-} && -n ${4:-} && -n ${5:-} && -n ${6:-} ]] || exit 2
        copy_view "$2" "$3" "$4" "$5" "${@:6}"
        ;;
    reset-monitor)
        [[ -n ${2:-} ]] || exit 2
        reset_monitor "$2"
        ;;
    reset-all)
        reset_all
        ;;
    set)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_field "$2" "$3"
        ;;
    set-size)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_size "$2" "$3"
        ;;
    set-all)
        [[ -n ${2:-} && -n ${3:-} && -n ${4:-} && -n ${5:-} ]] || exit 2
        set_all "$2" "$3" "$4" "$5"
        ;;
    reset)
        reset_defaults
        ;;
    *)
        printf 'usage: %s {lock-size <MON> <width> <height>|unlock-size <MON>|set-scales <MON> <text_percent> <icon_percent>|copy-view <width> <height> <text_percent> <icon_percent> <MON>...|reset-monitor <MON>|reset-all|reset-locks|set <field> <value>|set-size <width> <height>|set-all <width> <height> <text_size> <icon_size>|reset}\n' "${0##*/}" >&2
        exit 2
        ;;
esac
