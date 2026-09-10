#!/usr/bin/env bash
# Refresh the lockscreen's display-only weather cache while the desktop is unlocked.

set -euo pipefail

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_DIR="${CACHE_HOME}/awtarchy"
CACHE_FILE="${CACHE_DIR}/lockscreen-weather.json"
TMP_FILE=""

cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}
trap cleanup EXIT

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell_lockscreen_weather.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

validate_location() {
    local value="$1"
    if ! jq -e -n --arg value "$value" '
        ($value | explode) as $points
        | ($points | length) <= 96
        and ($points | all(. >= 32 and (. < 127 or . > 159)))
    ' >/dev/null 2>&1; then
        printf 'weather location must be at most 96 Unicode code points with no control characters\n' >&2
        exit 2
    fi
}

weather_description() {
    case "$1" in
        0) printf '%s' 'Clear' ;;
        1) printf '%s' 'Mostly clear' ;;
        2) printf '%s' 'Partly cloudy' ;;
        3) printf '%s' 'Cloudy' ;;
        45|48) printf '%s' 'Fog' ;;
        51|53|55|56|57) printf '%s' 'Drizzle' ;;
        61|63|65|66|67) printf '%s' 'Rain' ;;
        71|73|75|77) printf '%s' 'Snow' ;;
        80|81|82) printf '%s' 'Rain showers' ;;
        85|86) printf '%s' 'Snow showers' ;;
        95|96|99) printf '%s' 'Thunderstorms' ;;
        *) printf '%s' 'Weather' ;;
    esac
}

resolve_location() {
    local requested="$1"
    local location_json latitude longitude resolved_name admin1

    if [[ -n "$requested" ]]; then
        location_json="$(curl --fail --silent --show-error \
            --connect-timeout 4 --max-time 8 \
            --get 'https://geocoding-api.open-meteo.com/v1/search' \
            --data-urlencode "name=$requested" \
            --data 'count=1' \
            --data 'language=en' \
            --data 'format=json')"

        latitude="$(jq -er '.results[0].latitude | select(type == "number")' <<<"$location_json")"
        longitude="$(jq -er '.results[0].longitude | select(type == "number")' <<<"$location_json")"
        resolved_name="$(jq -er '.results[0].name | select(type == "string" and length > 0)' <<<"$location_json")"
        admin1="$(jq -r '.results[0].admin1 // "" | select(type == "string")' <<<"$location_json")"
    else
        location_json="$(curl --fail --silent --show-error \
            --connect-timeout 4 --max-time 8 'https://ipwho.is/')"

        jq -e '.success == true' <<<"$location_json" >/dev/null
        latitude="$(jq -er '.latitude | select(type == "number")' <<<"$location_json")"
        longitude="$(jq -er '.longitude | select(type == "number")' <<<"$location_json")"
        resolved_name="$(jq -er '.city | select(type == "string" and length > 0)' <<<"$location_json")"
        admin1="$(jq -r '.region // "" | select(type == "string")' <<<"$location_json")"
    fi

    if [[ -n "$admin1" ]]; then
        printf '%s\t%s\t%s, %s\n' "$latitude" "$longitude" "$resolved_name" "$admin1"
    else
        printf '%s\t%s\t%s\n' "$latitude" "$longitude" "$resolved_name"
    fi
}

refresh_weather() {
    local location="$1"
    local resolved latitude longitude display_location forecast_json
    local temperature unit code description summary fetched_at expires_at

    need curl
    need jq
    validate_location "$location"

    resolved="$(resolve_location "$location")"
    IFS=$'\t' read -r latitude longitude display_location <<<"$resolved"
    [[ -n "$latitude" && -n "$longitude" && -n "$display_location" ]] || {
        printf 'weather location could not be resolved\n' >&2
        exit 1
    }

    forecast_json="$(curl --fail --silent --show-error \
        --connect-timeout 4 --max-time 8 \
        --get 'https://api.open-meteo.com/v1/forecast' \
        --data-urlencode "latitude=$latitude" \
        --data-urlencode "longitude=$longitude" \
        --data 'current=temperature_2m,weather_code' \
        --data 'temperature_unit=fahrenheit' \
        --data 'timezone=auto')"

    temperature="$(jq -er '.current.temperature_2m | select(type == "number")' <<<"$forecast_json")"
    unit="$(jq -er '.current_units.temperature_2m | select(type == "string" and length > 0)' <<<"$forecast_json")"
    code="$(jq -er '.current.weather_code | select(type == "number") | floor' <<<"$forecast_json")"
    description="$(weather_description "$code")"
    printf -v temperature '%.0f' "$temperature"
    summary="${temperature}${unit} · ${description}"

    fetched_at="$(date +%s)"
    expires_at=$((fetched_at + 1800))
    mkdir -p "$CACHE_DIR"
    TMP_FILE="$(mktemp "${CACHE_FILE}.tmp.XXXXXX")"

    jq -n \
        --arg summary "$summary" \
        --arg location "$display_location" \
        --argjson fetched_at "$fetched_at" \
        --argjson expires_at "$expires_at" \
        '{
            summary: $summary,
            location: $location,
            fetched_at: $fetched_at,
            expires_at: $expires_at,
            provider: "open-meteo"
        }' >"$TMP_FILE"

    jq -e '
        .provider == "open-meteo"
        and (.summary | type) == "string"
        and (.summary | length) >= 1
        and (.summary | length) <= 96
        and (.location | type) == "string"
        and (.fetched_at | type) == "number"
        and (.expires_at | type) == "number"
        and .expires_at > .fetched_at
    ' "$TMP_FILE" >/dev/null

    mv -f -- "$TMP_FILE" "$CACHE_FILE"
    TMP_FILE=""
}

case "${1:-}" in
    refresh)
        [[ $# -eq 2 ]] || {
            printf 'usage: %s refresh [location]\n' "${0##*/}" >&2
            exit 2
        }
        refresh_weather "$2"
        ;;
    *)
        printf 'usage: %s refresh [location]\n' "${0##*/}" >&2
        exit 2
        ;;
esac
