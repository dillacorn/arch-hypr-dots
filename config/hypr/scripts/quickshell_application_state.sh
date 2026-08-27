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
SAVE_VERSION=2
QUICK_SETTINGS_LAYOUT_SAVE_VERSION=1
QUICK_SETTINGS_SECTIONS_JSON='["brightness","output-volume","bar","display-effects","submap","wallpaper","awtarchy","smtty","scheduler","numlock","title-bars"]'
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
        printf '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}\n' >"$STATE_FILE"
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
            locked:true,
            saved:true
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

set_centered() {
    local monitor="$1" value="$2" centered
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }

    case "$value" in
        1|true|on) centered=true ;;
        0|false|off) centered=false ;;
        *)
            printf 'centered must be true or false\n' >&2
            exit 2
            ;;
    esac

    new_tmp
    jq \
        --arg monitor "$monitor" \
        --argjson centered "$centered" '
        .launcher_sizes = (if (.launcher_sizes | type) == "object" then .launcher_sizes else {} end)
        | .launcher_sizes[$monitor] = ((if (.launcher_sizes[$monitor] | type) == "object"
            then .launcher_sizes[$monitor] else {} end) + {
            centered:$centered
        })
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

save_view() {
    local monitor="$1" width="$2" height="$3" text_scale="$4" icon_scale="$5" value="$6" capture_value="${7:-}" centered capture
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    validate_int_range "$text_scale" "$MIN_TEXT_SCALE" "$MAX_TEXT_SCALE" 'text scale'
    validate_int_range "$icon_scale" "$MIN_ICON_SCALE" "$MAX_ICON_SCALE" 'icon scale'

    case "$value" in
        1|true|on) centered=true ;;
        0|false|off) centered=false ;;
        *)
            printf 'centered must be true or false\n' >&2
            exit 2
            ;;
    esac

    case "$capture_value" in
        "") capture=null ;;
        1|true|on) capture=true ;;
        0|false|off) capture=false ;;
        *)
            printf 'capture allowed must be true or false\n' >&2
            exit 2
            ;;
    esac

    new_tmp
    jq \
        --arg monitor "$monitor" \
        --argjson width "$width" \
        --argjson height "$height" \
        --argjson text_scale "$text_scale" \
        --argjson icon_scale "$icon_scale" \
        --argjson centered "$centered" \
        --argjson capture "$capture" \
        --argjson save_version "$SAVE_VERSION" '
        .launcher_sizes = (if (.launcher_sizes | type) == "object" then .launcher_sizes else {} end)
        | .launcher_sizes[$monitor] = (((if (.launcher_sizes[$monitor] | type) == "object"
            then .launcher_sizes[$monitor] else {} end) + {
            width:$width,
            height:$height,
            text_scale:$text_scale,
            icon_scale:$icon_scale,
            centered:$centered,
            saved:true,
            save_version:$save_version
        }) | del(.locked))
        | if $capture == null then . else
            .capture_allowed = (if (.capture_allowed | type) == "object" then .capture_allowed else {} end)
            | .capture_allowed.launcher = $capture
          end
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

flyout_key() {
    case "$1" in
        clipboard) printf 'clipboard_views\n' ;;
        notifications) printf 'notification_views\n' ;;
        quick-settings) printf 'quick_settings_views\n' ;;
        network) printf 'network_views\n' ;;
        bluetooth) printf 'bluetooth_views\n' ;;
        battery) printf 'battery_views\n' ;;
        *) printf 'invalid flyout: %s\n' "$1" >&2; exit 2 ;;
    esac
}

capture_key() {
    case "$1" in
        clipboard|notifications|launcher|network|bluetooth|battery) printf '%s\n' "$1" ;;
        quick-settings) printf 'quick_settings\n' ;;
        *) printf 'invalid capture surface: %s\n' "$1" >&2; exit 2 ;;
    esac
}

parse_bool() {
    case "$1" in
        1|true|on) printf 'true\n' ;;
        0|false|off) printf 'false\n' ;;
        *) printf '%s must be true or false\n' "$2" >&2; exit 2 ;;
    esac
}

set_update_notifications() {
    local enabled
    enabled="$(parse_bool "$1" 'update notifications')"
    new_tmp
    jq --argjson enabled "$enabled" \
        '.update_notifications_enabled = $enabled' \
        "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_capture() {
    local surface="$1" value="$2" surface_key capture
    surface_key="$(capture_key "$surface")"
    capture="$(parse_bool "$value" 'capture allowed')"
    new_tmp
    jq \
        --arg surface_key "$surface_key" \
        --argjson capture "$capture" '
        .capture_allowed = (if (.capture_allowed | type) == "object" then .capture_allowed else {} end)
        | .capture_allowed[$surface_key] = $capture
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

save_flyout() {
    local flyout="$1" monitor="$2" width="$3" height="$4" text_scale="$5" icon_scale="$6" capture_value="$7" popup_limit="${8:-}"
    local view_key surface_key capture popup_limit_json=null
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    view_key="$(flyout_key "$flyout")"
    surface_key="$(capture_key "$flyout")"
    capture="$(parse_bool "$capture_value" 'capture allowed')"
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    validate_int_range "$text_scale" "$MIN_TEXT_SCALE" "$MAX_TEXT_SCALE" 'text scale'
    validate_int_range "$icon_scale" "$MIN_ICON_SCALE" "$MAX_ICON_SCALE" 'icon scale'
    if [[ "$flyout" == notifications && -n "$popup_limit" ]]; then
        validate_int_range "$popup_limit" 1 20 'notification popup limit'
        popup_limit_json="$popup_limit"
    elif [[ -n "$popup_limit" ]]; then
        printf 'popup limit is only valid for notifications\n' >&2
        exit 2
    fi

    new_tmp
    jq \
        --arg view_key "$view_key" \
        --arg surface_key "$surface_key" \
        --arg monitor "$monitor" \
        --argjson width "$width" \
        --argjson height "$height" \
        --argjson text_scale "$text_scale" \
        --argjson icon_scale "$icon_scale" \
        --argjson capture "$capture" \
        --argjson popup_limit "$popup_limit_json" \
        --argjson save_version "$SAVE_VERSION" '
        .[$view_key] = (if (.[$view_key] | type) == "object" then .[$view_key] else {} end)
        | .[$view_key][$monitor] = {
            width:$width,
            height:$height,
            text_scale:$text_scale,
            icon_scale:$icon_scale,
            saved:true,
            save_version:$save_version
        }
        | .capture_allowed = (if (.capture_allowed | type) == "object" then .capture_allowed else {} end)
        | .capture_allowed[$surface_key] = $capture
        | if $popup_limit == null then . else
            .notification_popup_limit = $popup_limit
            | .notification_popup_limit_save_version = $save_version
            | .notification_views = ((if (.notification_views | type) == "object"
                then .notification_views else {} end)
                | with_entries(.value = (if (.value | type) == "object"
                    then (.value | del(.popup_limit)) else .value end)))
          end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_notification_popup_limit() {
    local popup_limit="$1"
    validate_int_range "$popup_limit" 1 20 'notification popup limit'
    new_tmp
    jq \
        --argjson popup_limit "$popup_limit" \
        --argjson save_version "$SAVE_VERSION" '
        .notification_popup_limit = $popup_limit
        | .notification_popup_limit_save_version = $save_version
        | .notification_views = ((if (.notification_views | type) == "object" then .notification_views else {} end)
            | with_entries(.value = (if (.value | type) == "object"
                then (.value | del(.popup_limit)) else .value end)))
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_notification_popup_position() {
    local monitor="$1" position="$2"
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    case "$position" in
        automatic|top-left|top-center|top-right|bottom-left|bottom-center|bottom-right) ;;
        *)
            printf 'invalid notification popup position: %s\n' "$position" >&2
            exit 2
            ;;
    esac

    new_tmp
    jq \
        --arg monitor "$monitor" \
        --arg position "$position" '
        .notification_popup_positions = (if (.notification_popup_positions | type) == "object"
            then .notification_popup_positions else {} end)
        | if $position == "automatic" then del(.notification_popup_positions[$monitor])
          else .notification_popup_positions[$monitor] = $position
          end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

copy_flyout() {
    local flyout="$1" width="$2" height="$3" text_scale="$4" icon_scale="$5"
    shift 5
    local -a targets=("$@")
    local view_key targets_json
    (( ${#targets[@]} > 0 )) || { printf 'at least one target monitor is required\n' >&2; exit 2; }
    view_key="$(flyout_key "$flyout")"
    validate_int_range "$width" "$MIN_WIDTH" "$MAX_WIDTH" 'width'
    validate_int_range "$height" "$MIN_HEIGHT" "$MAX_HEIGHT" 'height'
    validate_int_range "$text_scale" "$MIN_TEXT_SCALE" "$MAX_TEXT_SCALE" 'text scale'
    validate_int_range "$icon_scale" "$MIN_ICON_SCALE" "$MAX_ICON_SCALE" 'icon scale'
    targets_json="$(jq -cn --args '$ARGS.positional' -- "${targets[@]}")"

    new_tmp
    jq \
        --arg view_key "$view_key" \
        --argjson targets "$targets_json" \
        --argjson width "$width" \
        --argjson height "$height" \
        --argjson text_scale "$text_scale" \
        --argjson icon_scale "$icon_scale" \
        --argjson save_version "$SAVE_VERSION" '
        .[$view_key] = (if (.[$view_key] | type) == "object" then .[$view_key] else {} end)
        | .[$view_key] = reduce $targets[] as $monitor
            (.[$view_key]; .[$monitor] = {
                width:$width,
                height:$height,
                text_scale:$text_scale,
                icon_scale:$icon_scale,
                saved:true,
                save_version:$save_version
            })
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_flyout() {
    local flyout="$1" monitor="$2" view_key surface_key
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    view_key="$(flyout_key "$flyout")"
    surface_key="$(capture_key "$flyout")"

    new_tmp
    jq \
        --arg view_key "$view_key" \
        --arg surface_key "$surface_key" \
        --arg monitor "$monitor" '
        .[$view_key] = (if (.[$view_key] | type) == "object" then .[$view_key] else {} end)
        | del(.[$view_key][$monitor])
        | .capture_allowed = (if (.capture_allowed | type) == "object" then .capture_allowed else {} end)
        | .capture_allowed[$surface_key] = false
        | if $view_key == "notification_views" then
            del(.notification_popup_limit, .notification_popup_limit_save_version)
            | .notification_views = (.notification_views
                | with_entries(.value = (if (.value | type) == "object"
                    then (.value | del(.popup_limit)) else .value end)))
            | .notification_popup_positions = (if (.notification_popup_positions | type) == "object"
                then .notification_popup_positions else {} end)
            | del(.notification_popup_positions[$monitor])
          else . end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

validate_quick_settings_layout() {
    local order_json="$1" hidden_json="$2"

    if ! jq -e -n \
        --argjson allowed "$QUICK_SETTINGS_SECTIONS_JSON" \
        --argjson order "$order_json" \
        --argjson hidden "$hidden_json" '
        ($order | type) == "array"
        and ($hidden | type) == "array"
        and ($order | length) == ($allowed | length)
        and ($order | unique | length) == ($allowed | length)
        and (($order - $allowed) | length) == 0
        and (($allowed - $order) | length) == 0
        and ($hidden | unique | length) == ($hidden | length)
        and (($hidden - $allowed) | length) == 0
        and ($hidden | length) < ($allowed | length)
    ' >/dev/null 2>&1; then
        printf 'invalid Quick Settings layout\n' >&2
        exit 2
    fi
}

save_quick_settings_layout() {
    local monitor="$1" order_json="$2" hidden_json="$3"
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    validate_quick_settings_layout "$order_json" "$hidden_json"

    new_tmp
    jq \
        --arg monitor "$monitor" \
        --argjson order "$order_json" \
        --argjson hidden "$hidden_json" \
        --argjson save_version "$QUICK_SETTINGS_LAYOUT_SAVE_VERSION" '
        .quick_settings_layouts = (if (.quick_settings_layouts | type) == "object"
            then .quick_settings_layouts else {} end)
        | .quick_settings_layouts[$monitor] = {
            order:$order,
            hidden:$hidden,
            save_version:$save_version
        }
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

copy_quick_settings_layout() {
    local order_json="$1" hidden_json="$2"
    shift 2
    local -a targets=("$@")
    local targets_json

    (( ${#targets[@]} > 0 )) || {
        printf 'at least one target monitor is required\n' >&2
        exit 2
    }
    validate_quick_settings_layout "$order_json" "$hidden_json"
    targets_json="$(jq -cn --args '$ARGS.positional' -- "${targets[@]}")"

    new_tmp
    jq \
        --argjson targets "$targets_json" \
        --argjson order "$order_json" \
        --argjson hidden "$hidden_json" \
        --argjson save_version "$QUICK_SETTINGS_LAYOUT_SAVE_VERSION" '
        .quick_settings_layouts = (if (.quick_settings_layouts | type) == "object"
            then .quick_settings_layouts else {} end)
        | .quick_settings_layouts = reduce $targets[] as $monitor
            (.quick_settings_layouts;
                .[$monitor] = {
                    order:$order,
                    hidden:$hidden,
                    save_version:$save_version
                })
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_quick_settings_layout() {
    local monitor="$1"
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }

    new_tmp
    jq --arg monitor "$monitor" '
        .quick_settings_layouts = (if (.quick_settings_layouts | type) == "object"
            then .quick_settings_layouts else {} end)
        | del(.quick_settings_layouts[$monitor])
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
        | .capture_allowed = (if (.capture_allowed | type) == "object" then .capture_allowed else {} end)
        | .capture_allowed.launcher = false
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
        --argjson icon_scale "$icon_scale" \
        --argjson save_version "$SAVE_VERSION" '
        .launcher_sizes = (if (.launcher_sizes | type) == "object" then .launcher_sizes else {} end)
        | .launcher_sizes = reduce $targets[] as $monitor
            (.launcher_sizes;
                .[$monitor] as $current
                | .[$monitor] = (((if ($current | type) == "object" then $current else {} end) + {
                    width:$width,
                    height:$height,
                    text_scale:$text_scale,
                    icon_scale:$icon_scale,
                    saved:true,
                    save_version:$save_version
                }) | del(.locked)))
        | del(.application_view)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_all() {
    new_tmp
    jq '
        .launcher_sizes = {}
        | .capture_allowed = (if (.capture_allowed | type) == "object" then .capture_allowed else {} end)
        | .capture_allowed.launcher = false
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
    set-centered)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_centered "$2" "$3"
        ;;
    save-view)
        [[ -n ${2:-} && -n ${3:-} && -n ${4:-} && -n ${5:-} && -n ${6:-} && -n ${7:-} ]] || exit 2
        save_view "$2" "$3" "$4" "$5" "$6" "$7" "${8:-}"
        ;;
    save-flyout)
        [[ -n ${2:-} && -n ${3:-} && -n ${4:-} && -n ${5:-} && -n ${6:-} && -n ${7:-} && -n ${8:-} ]] || exit 2
        save_flyout "$2" "$3" "$4" "$5" "$6" "$7" "$8" "${9:-}"
        ;;
    set-update-notifications)
        [[ -n ${2:-} ]] || exit 2
        set_update_notifications "$2"
        ;;
    set-notification-popup-limit)
        [[ -n ${2:-} ]] || exit 2
        set_notification_popup_limit "$2"
        ;;
    set-notification-popup-position)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_notification_popup_position "$2" "$3"
        ;;
    copy-flyout)
        [[ -n ${2:-} && -n ${3:-} && -n ${4:-} && -n ${5:-} && -n ${6:-} && -n ${7:-} ]] || exit 2
        copy_flyout "$2" "$3" "$4" "$5" "$6" "${@:7}"
        ;;
    reset-flyout)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        reset_flyout "$2" "$3"
        ;;
    set-capture)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_capture "$2" "$3"
        ;;
    save-quick-settings-layout)
        [[ -n ${2:-} && -n ${3:-} && -n ${4:-} ]] || exit 2
        save_quick_settings_layout "$2" "$3" "$4"
        ;;
    copy-quick-settings-layout)
        [[ -n ${2:-} && -n ${3:-} && -n ${4:-} ]] || exit 2
        copy_quick_settings_layout "$2" "$3" "${@:4}"
        ;;
    reset-quick-settings-layout)
        [[ -n ${2:-} ]] || exit 2
        reset_quick_settings_layout "$2"
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
        printf 'usage: %s {save-view <MON> <width> <height> <text_percent> <icon_percent> <centered> [capture_allowed]|save-flyout <TYPE> <MON> <width> <height> <text_percent> <icon_percent> <capture_allowed> [popup_limit]|set-update-notifications <true|false>|set-clock-date <MON> <true|false>|set-notification-popup-limit <1-20>|set-notification-popup-position <MON> <automatic|top-left|top-center|top-right|bottom-left|bottom-center|bottom-right>|copy-flyout <TYPE> <width> <height> <text_percent> <icon_percent> <MON>...|reset-flyout <TYPE> <MON>|set-capture <TYPE> <true|false>|save-quick-settings-layout <MON> <order_json> <hidden_json>|copy-quick-settings-layout <order_json> <hidden_json> <MON>...|reset-quick-settings-layout <MON>|lock-size <MON> <width> <height>|unlock-size <MON>|set-scales <MON> <text_percent> <icon_percent>|set-centered <MON> <true|false>|copy-view <width> <height> <text_percent> <icon_percent> <MON>...|reset-monitor <MON>|reset-all|reset-locks|set <field> <value>|set-size <width> <height>|set-all <width> <height> <text_size> <icon_size>|reset}\n' "${0##*/}" >&2
        exit 2
        ;;
esac
