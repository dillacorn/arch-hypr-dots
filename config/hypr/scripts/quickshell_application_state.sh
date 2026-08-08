#!/usr/bin/env bash
# Persist Quickshell application launcher settings.

set -euo pipefail

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
QUICKSHELL_SCRIPT="${HYPR_QUICKSHELL_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh}"

DEFAULT_WIDTH=420
DEFAULT_HEIGHT=582
DEFAULT_TEXT_SIZE=14
DEFAULT_ICON_SIZE=18
MIN_WIDTH=420
MAX_WIDTH=3840
MIN_HEIGHT=360
MAX_HEIGHT=2160
MIN_TEXT_SIZE=10
MAX_TEXT_SIZE=28
MIN_ICON_SIZE=12
MAX_ICON_SIZE=48

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell_application_state.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

need jq

ensure_state() {
    mkdir -p "$(dirname "$STATE_FILE")"

    if [[ ! -s "$STATE_FILE" ]] || ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
        if [[ -x "$QUICKSHELL_SCRIPT" ]]; then
            "$QUICKSHELL_SCRIPT" dump-state >/dev/null 2>&1 || true
        fi
    fi

    if [[ ! -s "$STATE_FILE" ]] || ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
        printf '{"enabled":true,"monitors":{}}\n' >"$STATE_FILE"
    fi
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
    local monitor="$1" width="$2" height="$3" tmp
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq \
        --arg monitor "$monitor" \
        --argjson width "$width" \
        --argjson height "$height" '
        .monitors = (.monitors // {})
        | .monitors[$monitor] = (.monitors[$monitor] // {})
        | .monitors[$monitor].application_view = {
            width:$width,
            height:$height,
            locked:true
        }
        | del(.application_view)
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

unlock_size() {
    local monitor="$1" tmp
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg monitor "$monitor" '
        .monitors = (.monitors // {})
        | if .monitors[$monitor] then del(.monitors[$monitor].application_view) else . end
        | del(.application_view)
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

reset_locks() {
    local tmp
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq '
        .monitors = (.monitors // {})
        | .monitors |= with_entries(.value |= del(.application_view))
        | del(.application_view)
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

# Legacy commands remain accepted so older local helpers do not fail during the
# testing branch transition. Launcher dimensions are no longer read globally.
set_field() {
    local field="$1" value="$2" min max label tmp
    case "$field" in
        width) min=$MIN_WIDTH; max=$MAX_WIDTH; label='width' ;;
        height) min=$MIN_HEIGHT; max=$MAX_HEIGHT; label='height' ;;
        text_size) min=$MIN_TEXT_SIZE; max=$MAX_TEXT_SIZE; label='text size' ;;
        icon_size) min=$MIN_ICON_SIZE; max=$MAX_ICON_SIZE; label='icon size' ;;
        *) printf 'invalid field: %s\n' "$field" >&2; exit 2 ;;
    esac
    validate_int_range "$value" "$min" "$max" "$label"
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg field "$field" --argjson value "$value" '
        .application_view = (.application_view // {})
        | .application_view[$field] = $value
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

set_size() {
    local width="$1" height="$2"
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    ensure_state
    local tmp="${STATE_FILE}.tmp.$$"
    jq --argjson width "$width" --argjson height "$height" '
        .application_view = (.application_view // {})
        | .application_view.width = $width
        | .application_view.height = $height
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

set_all() {
    local width="$1" height="$2" text_size="$3" icon_size="$4"
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    validate_int_range "$text_size" "$MIN_TEXT_SIZE" "$MAX_TEXT_SIZE" 'text size'
    validate_int_range "$icon_size" "$MIN_ICON_SIZE" "$MAX_ICON_SIZE" 'icon size'
    ensure_state
    local tmp="${STATE_FILE}.tmp.$$"
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
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

reset_defaults() {
    reset_locks
}

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
        printf 'usage: %s {lock-size <MON> <width> <height>|unlock-size <MON>|reset-locks|set <field> <value>|set-size <width> <height>|set-all <width> <height> <text_size> <icon_size>|reset}\n' "${0##*/}" >&2
        exit 2
        ;;
esac
