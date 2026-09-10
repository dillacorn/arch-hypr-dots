#!/usr/bin/env python3
from pathlib import Path

path = Path("config/hypr/scripts/quickshell_application_state.sh")
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    "LOCKSCREEN_BACKGROUNDS_JSON='[\"black\",\"wallpaper\"]'",
    "LOCKSCREEN_BACKGROUNDS_JSON='[\"black\",\"wallpaper\",\"color\"]'",
    "background allowlist",
)

replace_once(
    '''set_lockscreen_background() {
    local value="$1"
    validate_lockscreen_background "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_background = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

normalize_lockscreen_weather_location() {''',
    '''set_lockscreen_background() {
    local value="$1"
    validate_lockscreen_background "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_background = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

validate_lockscreen_hex_color() {
    local value="$1" label="$2"
    [[ "$value" =~ ^#[0-9A-Fa-f]{6}$ ]] || {
        printf '%s must be #RRGGBB\\n' "$label" >&2
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
    [[ "$value" == /* && "$value" != *$'\\n'* && "$value" != *$'\\r'* \
        && -f "$value" && -r "$value" ]] || {
        printf 'lockscreen wallpaper must be a readable absolute local file\\n' >&2
        exit 2
    }
    resolved="$(readlink -f -- "$value" 2>/dev/null || true)"
    [[ -n "$resolved" && "$resolved" == /* && -f "$resolved" && -r "$resolved" ]] || {
        printf 'lockscreen wallpaper could not be resolved\\n' >&2
        exit 2
    }
    printf '%s' "$resolved"
}

set_lockscreen_wallpaper() {
    local path
    path="$(normalize_lockscreen_wallpaper_path "$1")"
    [[ -n "$path" ]] || {
        printf 'lockscreen wallpaper is required\\n' >&2
        exit 2
    }
    new_tmp
    jq --arg path "$path" '
        .lockscreen_wallpaper_path = $path
        | .lockscreen_background = "wallpaper"
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

normalize_lockscreen_weather_location() {''',
    "background color and wallpaper state",
)

replace_once(
    '''save_lockscreen_editor() {
    local normalized visibility="$2"
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\\n' >&2
        exit 2
    fi
    validate_lockscreen_editor_visibility "$visibility"
    new_tmp
    jq \\
        --argjson layout "$normalized" \\
        --argjson visibility "$visibility" '
        .lockscreen_layout = $layout
        | .lockscreen_show_logo = $visibility.logo
        | .lockscreen_show_time = $visibility.time
        | .lockscreen_show_date = $visibility.date
        | .lockscreen_show_username = $visibility.username
        | .lockscreen_show_weather = $visibility.weather
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}''',
    '''save_lockscreen_editor() {
    local normalized visibility="$2" background="$3" background_color="${4,,}" wallpaper="$5"
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\\n' >&2
        exit 2
    fi
    validate_lockscreen_editor_visibility "$visibility"
    validate_lockscreen_background "$background"
    validate_lockscreen_hex_color "$background_color" 'lockscreen background color'
    wallpaper="$(normalize_lockscreen_wallpaper_path "$wallpaper")"
    if [[ "$background" == 'wallpaper' && -z "$wallpaper" ]]; then
        printf 'wallpaper background requires a selected local image\\n' >&2
        exit 2
    fi
    new_tmp
    jq \\
        --argjson layout "$normalized" \\
        --argjson visibility "$visibility" \\
        --arg background "$background" \\
        --arg background_color "$background_color" \\
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
}''',
    "atomic editor appearance save",
)

replace_once(
    '''        | .lockscreen_show_weather = false
        | .lockscreen_background = "black"
        | .lockscreen_weather_location = ""
        | .lockscreen_layout = $layout''',
    '''        | .lockscreen_show_weather = false
        | .lockscreen_background = "black"
        | .lockscreen_background_color = "#000000"
        | .lockscreen_wallpaper_path = ""
        | .lockscreen_weather_location = ""
        | .lockscreen_layout = $layout''',
    "reset appearance state",
)

replace_once(
    '''    set-lockscreen-background)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_background "$2"
        ;;
    set-lockscreen-weather-location)''',
    '''    set-lockscreen-background)
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
    set-lockscreen-weather-location)''',
    "new state commands",
)

replace_once(
    '''    save-lockscreen-editor)
        [[ $# -eq 3 ]] || exit 2
        save_lockscreen_editor "$2" "$3"
        ;;''',
    '''    save-lockscreen-editor)
        [[ $# -eq 6 ]] || exit 2
        save_lockscreen_editor "$2" "$3" "$4" "$5" "$6"
        ;;''',
    "expanded editor save dispatch",
)

text = text.replace(
    'set-lockscreen-background <black|wallpaper>|set-lockscreen-weather-location <location>|save-lockscreen-layout <json>|save-lockscreen-editor <layout_json> <visibility_json>',
    'set-lockscreen-background <black|wallpaper|color>|set-lockscreen-background-color <#RRGGBB>|set-lockscreen-wallpaper <absolute_path>|set-lockscreen-weather-location <location>|save-lockscreen-layout <json>|save-lockscreen-editor <layout_json> <visibility_json> <background> <background_color> <wallpaper_path>',
    1,
)

path.write_text(text)
