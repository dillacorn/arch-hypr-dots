#!/usr/bin/env bash
# Read-only physical battery capacity-health telemetry for Awtarchy Quickshell.

set -euo pipefail
export LC_ALL=C

POWER_SUPPLY_ROOT="${AWTARCHY_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"

usage() {
    printf 'usage: %s --status-json\n' "${0##*/}" >&2
    exit 2
}

[[ ${1:-} == --status-json && $# -eq 1 ]] || usage
command -v jq >/dev/null 2>&1 || exit 127

read_text() {
    local path="$1"
    [[ -r "$path" ]] || return 1
    tr -d '\r\n' <"$path"
}

read_positive_integer() {
    local path="$1" value
    value="$(read_text "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    (( value > 0 )) || return 1
    printf '%s\n' "$value"
}

scaled_capacity() {
    local value="$1"
    awk -v value="$value" 'BEGIN { printf "%.2f", value / 1000000 }'
}

health_percentage() {
    local full="$1" design="$2"
    awk -v full="$full" -v design="$design" '
        BEGIN {
            if (design <= 0) exit 1
            value = (full / design) * 100
            if (value < 0) value = 0
            printf "%d", int(value + 0.5)
        }
    '
}

batteries='[]'
supported_count=0
aggregate_source=""
aggregate_compatible=true
aggregate_full=0
aggregate_design=0

shopt -s nullglob
for battery_dir in "$POWER_SUPPLY_ROOT"/*; do
    [[ -d "$battery_dir" ]] || continue
    type="$(read_text "$battery_dir/type" 2>/dev/null || true)"
    [[ "$type" == Battery ]] || continue

    name="${battery_dir##*/}"
    manufacturer="$(read_text "$battery_dir/manufacturer" 2>/dev/null || true)"
    model="$(read_text "$battery_dir/model_name" 2>/dev/null || true)"

    source=""
    full_raw=""
    design_raw=""
    full_wh=null
    design_wh=null
    full_ah=null
    design_ah=null
    percentage=null

    if full_raw="$(read_positive_integer "$battery_dir/energy_full" 2>/dev/null)" \
        && design_raw="$(read_positive_integer "$battery_dir/energy_full_design" 2>/dev/null)";
    then
        source="sysfs-energy"
        full_wh="$(scaled_capacity "$full_raw")"
        design_wh="$(scaled_capacity "$design_raw")"
    elif full_raw="$(read_positive_integer "$battery_dir/charge_full" 2>/dev/null)" \
        && design_raw="$(read_positive_integer "$battery_dir/charge_full_design" 2>/dev/null)";
    then
        source="sysfs-charge"
        full_ah="$(scaled_capacity "$full_raw")"
        design_ah="$(scaled_capacity "$design_raw")"
    fi

    if [[ -n "$source" ]]; then
        percentage="$(health_percentage "$full_raw" "$design_raw")"
        ((supported_count += 1))

        if [[ -z "$aggregate_source" ]]; then
            aggregate_source="$source"
        elif [[ "$aggregate_source" != "$source" ]]; then
            aggregate_compatible=false
        fi
        ((aggregate_full += full_raw))
        ((aggregate_design += design_raw))
    fi

    batteries="$(
        jq -cn \
            --argjson current "$batteries" \
            --arg name "$name" \
            --arg manufacturer "$manufacturer" \
            --arg model "$model" \
            --arg source "$source" \
            --argjson percentage "$percentage" \
            --argjson full_wh "$full_wh" \
            --argjson design_wh "$design_wh" \
            --argjson full_ah "$full_ah" \
            --argjson design_ah "$design_ah" '
            $current + [{
                name:$name,
                manufacturer:$manufacturer,
                model:$model,
                supported:($source != ""),
                source:$source,
                percentage:$percentage,
                full_wh:$full_wh,
                design_wh:$design_wh,
                full_ah:$full_ah,
                design_ah:$design_ah
            }]'
    )"
done

supported=false
source=""
percentage=null
full_wh=null
design_wh=null
full_ah=null
design_ah=null

if (( supported_count > 0 )); then
    supported=true
    source="$aggregate_source"

    if [[ "$aggregate_compatible" == true ]]; then
        percentage="$(health_percentage "$aggregate_full" "$aggregate_design")"
        case "$aggregate_source" in
            sysfs-energy)
                full_wh="$(scaled_capacity "$aggregate_full")"
                design_wh="$(scaled_capacity "$aggregate_design")"
                ;;
            sysfs-charge)
                full_ah="$(scaled_capacity "$aggregate_full")"
                design_ah="$(scaled_capacity "$aggregate_design")"
                ;;
        esac
    else
        source="mixed"
    fi
fi

jq -cn \
    --argjson supported "$supported" \
    --arg source "$source" \
    --argjson percentage "$percentage" \
    --argjson full_wh "$full_wh" \
    --argjson design_wh "$design_wh" \
    --argjson full_ah "$full_ah" \
    --argjson design_ah "$design_ah" \
    --argjson batteries "$batteries" '
    {
        supported:$supported,
        source:$source,
        percentage:$percentage,
        full_wh:$full_wh,
        design_wh:$design_wh,
        full_ah:$full_ah,
        design_ah:$design_ah,
        batteries:$batteries
    }'
