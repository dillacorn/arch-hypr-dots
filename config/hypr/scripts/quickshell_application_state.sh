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
LOCKSCREEN_ANIMATIONS_JSON='["random","swarm","edges","center","split","off"]'
LOCKSCREEN_BACKGROUNDS_JSON='["black","wallpaper","color"]'
LOCKSCREEN_LAYOUT_KEYS_JSON='["logo","time","date","username","weather","password"]'
LOCKSCREEN_LAYOUT_DEFAULT_JSON='{"logo":{"x":0.5,"y":0.34,"scale":1,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":1,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1,"color":"auto"}}'
CURSOR_VARIANTS_JSON='["ice","classic","amber","ice-sharp","classic-sharp","amber-sharp","ice-right","classic-right","amber-right","ice-sharp-right","classic-sharp-right","amber-sharp-right"]'
QUICK_SETTINGS_SECTIONS_JSON='["brightness","output-volume","bar","display-effects","submap","wallpaper","awtarchy","smtty","scheduler","numlock","title-bars"]'
WORKSPACE_STYLES_JSON='["awtarchy","numbers","icons","workflow","phases","custom-symbol"]'
WORKSPACE_ICON_STYLES_JSON='["off","awtarchy","workflow","phases","custom-symbol"]'
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

validate_lockscreen_animation() {
    local value="$1"
    if ! jq -e -n \
        --arg value "$value" \
        --argjson allowed "$LOCKSCREEN_ANIMATIONS_JSON" \
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid lockscreen animation: %s\n' "$value" >&2
        exit 2
    fi
}


validate_cursor_variant() {
    local value="$1"
    if ! jq -e -n \
        --arg value "$value" \
        --argjson allowed "$CURSOR_VARIANTS_JSON" \
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid cursor variant: %s\n' "$value" >&2
        exit 2
    fi
}

set_cursor_theme() {
    local value="$1"
    validate_cursor_variant "$value"
    new_tmp
    jq --arg value "$value" '.cursor_variant = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
validate_workspace_style() {
    local style="$1"
    if ! jq -e -n \
        --arg style "$style" \
        --argjson allowed "$WORKSPACE_STYLES_JSON" \
        '$allowed | index($style) != null' >/dev/null 2>&1; then
        printf 'invalid workspace style: %s\n' "$style" >&2
        exit 2
    fi
}

validate_identity_label() {
    local value="$1" label="$2"
    if ! jq -e -n --arg value "$value" '
        ($value | explode) as $points
        | ($points | length) >= 1
        and ($points | length) <= 8
        and ($value | test("\\S"))
        and ($value | contains("\n") | not)
        and ($value | contains("\r") | not)
        and ($points | all(. >= 32 and (. < 127 or . > 159)))
    ' >/dev/null 2>&1; then
        printf '%s must be 1-8 Unicode code points with visible content and no line breaks or control characters\n' "$label" >&2
        exit 2
    fi
}

validate_workspace_icon_style() {
    local style="$1"
    if ! jq -e -n \
        --arg style "$style" \
        --argjson allowed "$WORKSPACE_ICON_STYLES_JSON" \
        '$allowed | index($style) != null' >/dev/null 2>&1; then
        printf 'invalid workspace icon style: %s\n' "$style" >&2
        exit 2
    fi
}

set_lockscreen_animation() {
    local value="$1"
    validate_lockscreen_animation "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_animation = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_lockscreen_option() {
    local field="$1" value="$2" label="$3" enabled
    case "$field" in
        lockscreen_audio_reactive|lockscreen_mouse_interactive|lockscreen_show_logo|lockscreen_show_time|lockscreen_show_date|lockscreen_show_username|lockscreen_show_weather) ;;
        *)
            printf 'unsupported lockscreen option: %s\n' "$field" >&2
            exit 2
            ;;
    esac
    enabled="$(parse_bool "$value" "$label")"
    new_tmp
    jq --arg field "$field" --argjson enabled "$enabled" '.[$field] = $enabled' \
        "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

validate_lockscreen_background() {
    local value="$1"
    if ! jq -e -n \
        --arg value "$value" \
        --argjson allowed "$LOCKSCREEN_BACKGROUNDS_JSON" \
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid lockscreen background: %s\n' "$value" >&2
        exit 2
    fi
}

set_lockscreen_background() {
    local value="$1"
    validate_lockscreen_background "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_background = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

validate_lockscreen_hex_color() {
    local value="$1" label="$2"
    [[ "$value" =~ ^#[0-9A-Fa-f]{6}$ ]] || {
        printf '%s must be #RRGGBB\n' "$label" >&2
        exit 2
    }
}

set_lockscreen_background_color() {
    local value="${1,,}"
    validate_lockscreen_hex_color "$value" 'lockscreen background color'
    new_tmp
    jq --arg value "$value" '.lockscreen_background_color = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

normalize_lockscreen_wallpaper_path() {
    local value="$1" resolved
    [[ -n "$value" ]] || {
        printf '%s' ''
        return 0
    }
    [[ "$value" == /* && "$value" != *$'\n'* && "$value" != *$'\r'*         && -f "$value" && -r "$value" ]] || {
        printf 'lockscreen wallpaper must be a readable absolute local file\n' >&2
        exit 2
    }
    resolved="$(readlink -f -- "$value" 2>/dev/null || true)"
    [[ -n "$resolved" && "$resolved" == /* && -f "$resolved" && -r "$resolved" ]] || {
        printf 'lockscreen wallpaper could not be resolved\n' >&2
        exit 2
    }
    printf '%s' "$resolved"
}

set_lockscreen_wallpaper() {
    local path
    path="$(normalize_lockscreen_wallpaper_path "$1")"
    [[ -n "$path" ]] || {
        printf 'lockscreen wallpaper is required\n' >&2
        exit 2
    }
    new_tmp
    jq --arg path "$path" '
        .lockscreen_wallpaper_path = $path
        | .lockscreen_background = "wallpaper"
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

normalize_lockscreen_weather_location() {
    local value="$1" normalized
    normalized="$(jq -nr --arg value "$value" '$value | gsub("^\\s+|\\s+$"; "")')"
    if ! jq -e -n --arg value "$normalized" '
        ($value | explode) as $points
        | ($points | length) <= 96
        and ($points | all(. >= 32 and (. < 127 or . > 159)))
    ' >/dev/null 2>&1; then
        printf 'lockscreen weather location must be at most 96 Unicode code points with no control characters\n' >&2
        exit 2
    fi
    printf '%s' "$normalized"
}

set_lockscreen_weather_location() {
    local normalized
    normalized="$(normalize_lockscreen_weather_location "$1")"
    new_tmp
    jq --arg value "$normalized" '.lockscreen_weather_location = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

normalize_lockscreen_layout_json() {
    local value="$1"
    jq -ce -n \
        --argjson candidate "$value" \
        --argjson keys "$LOCKSCREEN_LAYOUT_KEYS_JSON" '
        if (
            ($candidate | type) == "object"
            and (($candidate | keys | sort) == ($keys | sort))
            and all($keys[];
                . as $key
                | ($candidate[$key] | type) == "object"
                and ((($candidate[$key] | keys | sort) == ["x", "y"])
                    or (($candidate[$key] | keys | sort) == ["scale", "x", "y"])
                    or (($candidate[$key] | keys | sort) == ["color", "x", "y"])
                    or (($candidate[$key] | keys | sort) == ["color", "scale", "x", "y"]))
                and ($candidate[$key].x | type) == "number"
                and ($candidate[$key].y | type) == "number"
                and (($candidate[$key] | has("scale") | not)
                    or ($candidate[$key].scale | type) == "number")
                and (($candidate[$key] | has("color") | not)
                    or (($candidate[$key].color | type) == "string"
                        and ($candidate[$key].color == "auto"
                            or ($candidate[$key].color | test("^#[0-9A-Fa-f]{6}$")))))
                and (($candidate[$key].scale // 1) >= 0.50)
                and (($candidate[$key].scale // 1) <= 2.00)
                and (if $key == "password" then
                    $candidate[$key].x >= 0.15 and $candidate[$key].x <= 0.85
                    and $candidate[$key].y >= 0.20 and $candidate[$key].y <= 0.86
                else
                    $candidate[$key].x >= 0.05 and $candidate[$key].x <= 0.95
                    and $candidate[$key].y >= 0.08 and $candidate[$key].y <= 0.92
                end)
            )
        ) then
            reduce $keys[] as $key ({};
                .[$key] = {
                    x: $candidate[$key].x,
                    y: $candidate[$key].y,
                    scale: ($candidate[$key].scale // 1),
                    color: ($candidate[$key].color // "auto")
                })
        else
            error("invalid lockscreen layout")
        end
    '
}

validate_lockscreen_layout() {
    local normalized
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\n' >&2
        exit 2
    fi
}

save_lockscreen_layout() {
    local normalized
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\n' >&2
        exit 2
    fi
    new_tmp
    jq --argjson value "$normalized" '.lockscreen_layout = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

validate_lockscreen_editor_visibility() {
    local value="$1"
    if ! jq -e -n \
        --argjson candidate "$value" \
        --argjson keys "$LOCKSCREEN_LAYOUT_KEYS_JSON" '
        ($candidate | type) == "object"
        and (($candidate | keys | sort) == ($keys | sort))
        and all($keys[]; . as $key | ($candidate[$key] | type) == "boolean")
        and $candidate.password == true
    ' >/dev/null 2>&1; then
        printf 'invalid lockscreen editor visibility\n' >&2
        exit 2
    fi
}

save_lockscreen_editor() {
    local normalized visibility="$2" background="$3" background_color="${4,,}" wallpaper="$5"
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\n' >&2
        exit 2
    fi
    validate_lockscreen_editor_visibility "$visibility"
    validate_lockscreen_background "$background"
    validate_lockscreen_hex_color "$background_color" 'lockscreen background color'
    wallpaper="$(normalize_lockscreen_wallpaper_path "$wallpaper")"
    if [[ "$background" == 'wallpaper' && -z "$wallpaper" ]]; then
        printf 'wallpaper background requires a selected local image\n' >&2
        exit 2
    fi
    new_tmp
    jq \
        --argjson layout "$normalized" \
        --argjson visibility "$visibility" \
        --arg background "$background" \
        --arg background_color "$background_color" \
        --arg wallpaper "$wallpaper" '
        .lockscreen_layout = $layout
        | .lockscreen_show_logo = $visibility.logo
        | .lockscreen_show_time = $visibility.time
        | .lockscreen_show_date = $visibility.date
        | .lockscreen_show_username = $visibility.username
        | .lockscreen_show_weather = $visibility.weather
        | .lockscreen_background = $background
        | .lockscreen_background_color = $background_color
        | .lockscreen_wallpaper_path = $wallpaper
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
reset_lockscreen_presentation() {
    new_tmp
    jq --argjson layout "$LOCKSCREEN_LAYOUT_DEFAULT_JSON" '
        .lockscreen_animation = "split"
        | .lockscreen_audio_reactive = true
        | .lockscreen_mouse_interactive = true
        | .lockscreen_show_logo = true
        | .lockscreen_show_time = false
        | .lockscreen_show_date = false
        | .lockscreen_show_username = false
        | .lockscreen_show_weather = false
        | .lockscreen_background = "black"
        | .lockscreen_background_color = "#000000"
        | .lockscreen_wallpaper_path = ""
        | .lockscreen_weather_location = ""
        | .lockscreen_layout = $layout
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_workspace_numbers() {
    local value="$1" enabled
    case "$value" in
        1|true|on) enabled=true ;;
        0|false|off) enabled=false ;;
        *)
            printf 'workspace numbers must be true or false\n' >&2
            exit 2
            ;;
    esac
    new_tmp
    jq --argjson enabled "$enabled" '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | .bar_appearance.workspace_numbers_enabled = $enabled
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_workspace_icon_style() {
    local style="$1"
    validate_workspace_icon_style "$style"
    new_tmp
    jq --arg style "$style" '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | .bar_appearance.workspace_icon_style = $style
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_workspace_style() {
    local style="$1"
    validate_workspace_style "$style"
    new_tmp
    jq --arg style "$style" '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | .bar_appearance.workspace_style = $style
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_workspace_custom_label() {
    local value="$1"
    validate_identity_label "$value" 'workspace custom label'
    new_tmp
    jq --arg value "$value" '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | .bar_appearance.workspace_custom_label = $value
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

clear_workspace_custom_label() {
    new_tmp
    jq '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | del(.bar_appearance.workspace_custom_label)
        | if (.bar_appearance | length) == 0 then del(.bar_appearance) else . end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_workspace_override() {
    local workspace="$1" value="$2"
    validate_int_range "$workspace" 1 10 'workspace'
    validate_identity_label "$value" 'workspace override'
    new_tmp
    jq \
        --arg workspace "$workspace" \
        --arg value "$value" '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | .bar_appearance.workspace_overrides = (if (.bar_appearance.workspace_overrides | type) == "object"
            then .bar_appearance.workspace_overrides else {} end)
        | .bar_appearance.workspace_overrides[$workspace] = $value
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

clear_workspace_override() {
    local workspace="$1"
    validate_int_range "$workspace" 1 10 'workspace'
    new_tmp
    jq --arg workspace "$workspace" '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | .bar_appearance.workspace_overrides = (if (.bar_appearance.workspace_overrides | type) == "object"
            then .bar_appearance.workspace_overrides else {} end)
        | del(.bar_appearance.workspace_overrides[$workspace])
        | if (.bar_appearance.workspace_overrides | length) == 0
            then del(.bar_appearance.workspace_overrides) else . end
        | if (.bar_appearance | length) == 0 then del(.bar_appearance) else . end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

clear_workspace_overrides() {
    new_tmp
    jq '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | del(.bar_appearance.workspace_overrides)
        | if (.bar_appearance | length) == 0 then del(.bar_appearance) else . end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_bar_workspace_visible() {
    local workspace="$1" value="$2" visible
    validate_int_range "$workspace" 1 10 'workspace'
    visible="$(parse_bool "$value" 'workspace bar visibility')"
    new_tmp
    jq \
        --argjson workspace "$workspace" \
        --argjson visible "$visible" '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | ((if (.bar_appearance.hidden_workspaces | type) == "array"
            then .bar_appearance.hidden_workspaces else [] end)
            | map(tonumber? // empty)
            | map(select(. >= 1 and . <= 10))
            | unique | sort) as $current
        | (if $visible
            then ($current | map(select(. != $workspace)))
            else (($current + [$workspace]) | unique | sort)
          end) as $next
        | if ($next | length) == 0
            then del(.bar_appearance.hidden_workspaces)
            else .bar_appearance.hidden_workspaces = $next
          end
        | if (.bar_appearance | length) == 0 then del(.bar_appearance) else . end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_launcher_icon() {
    local value="$1"
    validate_identity_label "$value" 'launcher icon'
    new_tmp
    jq --arg value "$value" '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | .bar_appearance.launcher_icon = $value
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_launcher_icon() {
    new_tmp
    jq '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | del(.bar_appearance.launcher_icon)
        | if (.bar_appearance | length) == 0 then del(.bar_appearance) else . end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_workspace_icons() {
    new_tmp
    jq '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | del(
            .bar_appearance.workspace_style,
            .bar_appearance.workspace_numbers_enabled,
            .bar_appearance.workspace_icon_style,
            .bar_appearance.workspace_custom_label,
            .bar_appearance.workspace_overrides
        )
        | if (.bar_appearance | length) == 0 then del(.bar_appearance) else . end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_bar_icons() {
    new_tmp
    jq '
        .bar_appearance = (if (.bar_appearance | type) == "object" then .bar_appearance else {} end)
        | del(
            .bar_appearance.workspace_style,
            .bar_appearance.workspace_numbers_enabled,
            .bar_appearance.workspace_icon_style,
            .bar_appearance.workspace_custom_label,
            .bar_appearance.workspace_overrides,
            .bar_appearance.launcher_icon
        )
        | if (.bar_appearance | length) == 0 then del(.bar_appearance) else . end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
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

set_clock_date() {
    local monitor="$1" value="$2" clock_date
    [[ -n "$monitor" ]] || { printf 'monitor is required\n' >&2; exit 2; }
    clock_date="$(parse_bool "$value" 'clock date')"
    new_tmp
    jq \
        --arg monitor "$monitor" \
        --argjson clock_date "$clock_date" '
        .monitors = (if (.monitors | type) == "object" then .monitors else {} end)
        | .monitors[$monitor] = ((if (.monitors[$monitor] | type) == "object"
            then .monitors[$monitor] else {} end) + {clock_date:$clock_date})
    ' "$STATE_FILE" >"$TMP_FILE"
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
    set-cursor-theme)
        [[ -n ${2:-} ]] || exit 2
        set_cursor_theme "$2"
        ;;
    set-lockscreen-animation)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_animation "$2"
        ;;
    set-lockscreen-audio-reactive)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_audio_reactive "$2" 'lockscreen audio reactive'
        ;;
    set-lockscreen-mouse-interactive)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_mouse_interactive "$2" 'lockscreen mouse interactive'
        ;;
    set-lockscreen-show-logo)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_show_logo "$2" 'lockscreen show logo'
        ;;
    set-lockscreen-show-time)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_show_time "$2" 'lockscreen show time'
        ;;
    set-lockscreen-show-date)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_show_date "$2" 'lockscreen show date'
        ;;
    set-lockscreen-show-username)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_show_username "$2" 'lockscreen show username'
        ;;
    set-lockscreen-show-weather)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_show_weather "$2" 'lockscreen show weather'
        ;;
    set-lockscreen-background)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_background "$2"
        ;;
    set-lockscreen-background-color)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_background_color "$2"
        ;;
    set-lockscreen-wallpaper)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_wallpaper "$2"
        ;;
    set-lockscreen-weather-location)
        [[ $# -eq 2 ]] || exit 2
        set_lockscreen_weather_location "$2"
        ;;
    save-lockscreen-layout)
        [[ -n ${2:-} ]] || exit 2
        save_lockscreen_layout "$2"
        ;;
    save-lockscreen-editor)
        [[ $# -eq 6 ]] || exit 2
        save_lockscreen_editor "$2" "$3" "$4" "$5" "$6"
        ;;
    reset-lockscreen-presentation)
        reset_lockscreen_presentation
        ;;
    set-workspace-numbers)
        [[ -n ${2:-} ]] || exit 2
        set_workspace_numbers "$2"
        ;;
    set-workspace-icon-style)
        [[ -n ${2:-} ]] || exit 2
        set_workspace_icon_style "$2"
        ;;
    set-workspace-style)
        [[ -n ${2:-} ]] || exit 2
        set_workspace_style "$2"
        ;;
    set-workspace-custom-label)
        [[ -n ${2:-} ]] || exit 2
        set_workspace_custom_label "$2"
        ;;
    clear-workspace-custom-label)
        clear_workspace_custom_label
        ;;
    set-bar-workspace-visible)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_bar_workspace_visible "$2" "$3"
        ;;
    set-workspace-override)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_workspace_override "$2" "$3"
        ;;
    clear-workspace-override)
        [[ -n ${2:-} ]] || exit 2
        clear_workspace_override "$2"
        ;;
    clear-workspace-overrides)
        clear_workspace_overrides
        ;;
    set-launcher-icon)
        [[ -n ${2:-} ]] || exit 2
        set_launcher_icon "$2"
        ;;
    reset-launcher-icon)
        reset_launcher_icon
        ;;
    reset-workspace-icons)
        reset_workspace_icons
        ;;
    reset-bar-icons)
        reset_bar_icons
        ;;
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
    set-clock-date)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_clock_date "$2" "$3"
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
        printf 'usage: %s {set-cursor-theme <ice|classic>|set-lockscreen-animation <random|swarm|edges|center|split|off>|set-lockscreen-audio-reactive <true|false>|set-lockscreen-mouse-interactive <true|false>|set-lockscreen-show-logo <true|false>|set-lockscreen-show-time <true|false>|set-lockscreen-show-date <true|false>|set-lockscreen-show-username <true|false>|set-lockscreen-show-weather <true|false>|set-lockscreen-background <black|wallpaper|color>|set-lockscreen-background-color <#RRGGBB>|set-lockscreen-wallpaper <absolute_path>|set-lockscreen-weather-location <location>|save-lockscreen-layout <json>|save-lockscreen-editor <layout_json> <visibility_json> <background> <background_color> <wallpaper_path>|reset-lockscreen-presentation|set-workspace-numbers <true|false>|set-bar-workspace-visible <1-10> <true|false>|set-workspace-icon-style <style>|set-workspace-style <legacy-style>|set-workspace-custom-label <label>|clear-workspace-custom-label|set-workspace-override <1-10> <label>|clear-workspace-override <1-10>|clear-workspace-overrides|set-launcher-icon <label>|reset-launcher-icon|reset-workspace-icons|reset-bar-icons|save-view <MON> <width> <height> <text_percent> <icon_percent> <centered> [capture_allowed]|save-flyout <TYPE> <MON> <width> <height> <text_percent> <icon_percent> <capture_allowed> [popup_limit]|set-update-notifications <true|false>|set-clock-date <MON> <true|false>|set-notification-popup-limit <1-20>|set-notification-popup-position <MON> <automatic|top-left|top-center|top-right|bottom-left|bottom-center|bottom-right>|copy-flyout <TYPE> <width> <height> <text_percent> <icon_percent> <MON>...|reset-flyout <TYPE> <MON>|set-capture <TYPE> <true|false>|save-quick-settings-layout <MON> <order_json> <hidden_json>|copy-quick-settings-layout <order_json> <hidden_json> <MON>...|reset-quick-settings-layout <MON>|lock-size <MON> <width> <height>|unlock-size <MON>|set-scales <MON> <text_percent> <icon_percent>|set-centered <MON> <true|false>|copy-view <width> <height> <text_percent> <icon_percent> <MON>...|reset-monitor <MON>|reset-all|reset-locks|set <field> <value>|set-size <width> <height>|set-all <width> <height> <text_size> <icon_size>|reset}\n' "${0##*/}" >&2
        exit 2
        ;;
esac
