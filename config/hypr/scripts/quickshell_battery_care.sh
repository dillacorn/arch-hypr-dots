#!/usr/bin/env bash
# Read-only battery charge-limit capability detection for Awtarchy Quickshell.

set -euo pipefail
export LC_ALL=C

POWER_SUPPLY_ROOT="${AWTARCHY_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
TLP_STAT_BIN="${AWTARCHY_TLP_STAT_BIN:-/usr/bin/tlp-stat}"

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

read_percent() {
    local path="$1" value
    value="$(read_text "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    (( value >= 0 && value <= 100 )) || return 1
    printf '%s\n' "$value"
}

batteries='[]'
sysfs_supported=false
first_start=null
first_stop=null

shopt -s nullglob
for battery_dir in "$POWER_SUPPLY_ROOT"/*; do
    [[ -d "$battery_dir" ]] || continue
    type="$(read_text "$battery_dir/type" 2>/dev/null || true)"
    [[ "$type" == Battery ]] || continue

    name="${battery_dir##*/}"
    manufacturer="$(read_text "$battery_dir/manufacturer" 2>/dev/null || true)"
    model="$(read_text "$battery_dir/model_name" 2>/dev/null || true)"

    start_supported=false
    stop_supported=false
    start_threshold=null
    stop_threshold=null

    if [[ -e "$battery_dir/charge_control_start_threshold" ]]; then
        start_supported=true
        sysfs_supported=true
        if value="$(read_percent "$battery_dir/charge_control_start_threshold" 2>/dev/null)"; then
            start_threshold="$value"
            [[ "$first_start" != null ]] || first_start="$value"
        fi
    fi

    if [[ -e "$battery_dir/charge_control_end_threshold" ]]; then
        stop_supported=true
        sysfs_supported=true
        if value="$(read_percent "$battery_dir/charge_control_end_threshold" 2>/dev/null)"; then
            stop_threshold="$value"
            [[ "$first_stop" != null ]] || first_stop="$value"
        fi
    fi

    batteries="$(
        jq -cn \
            --argjson current "$batteries" \
            --arg name "$name" \
            --arg manufacturer "$manufacturer" \
            --arg model "$model" \
            --argjson start_supported "$start_supported" \
            --argjson stop_supported "$stop_supported" \
            --argjson start_threshold "$start_threshold" \
            --argjson stop_threshold "$stop_threshold" '
            $current + [{
                name:$name,
                manufacturer:$manufacturer,
                model:$model,
                start_supported:$start_supported,
                stop_supported:$stop_supported,
                start_threshold:$start_threshold,
                stop_threshold:$stop_threshold
            }]'
    )"
done

plugin=""
features=""
start_spec=""
stop_spec=""
tlp_output=""
tlp_available=false

if [[ -x "$TLP_STAT_BIN" ]]; then
    tlp_available=true
    tlp_output="$("$TLP_STAT_BIN" -b 2>/dev/null || true)"
    plugin="$(
        awk -F: '/^Plugin:[[:space:]]*/ {
            sub(/^[[:space:]]+/, "", $2); sub(/[[:space:]]+$/, "", $2); print $2; exit
        }' <<<"$tlp_output"
    )"
    features="$(
        awk -F: '/^Supported features:[[:space:]]*/ {
            sub(/^[[:space:]]+/, "", $2); sub(/[[:space:]]+$/, "", $2); print $2; exit
        }' <<<"$tlp_output"
    )"
    start_spec="$(
        sed -n -E 's/^\*[[:space:]]+START_CHARGE_THRESH_[^:]+:[[:space:]]*(.*)$/\1/p' \
            <<<"$tlp_output" | head -n1
    )"
    stop_spec="$(
        sed -n -E 's/^\*[[:space:]]+STOP_CHARGE_THRESH_[^:]+:[[:space:]]*(.*)$/\1/p' \
            <<<"$tlp_output" | head -n1
    )"
fi

plugin_lower="${plugin,,}"
features_lower="${features,,}"
tlp_supported=false
if [[ "$features_lower" == *"charge threshold"* ]]; then
    tlp_supported=true
elif [[ "$features_lower" == *"charge type"* && -n "$stop_spec" ]]; then
    # Some fixed conservation modes are represented as charging profiles rather
    # than literal percentage thresholds. TLP still exposes them through the
    # START/STOP_CHARGE_THRESH configuration abstraction.
    tlp_supported=true
fi

mode="unsupported"
backend="none"
supported=false
start_min=null
start_max=null
stop_min=null
stop_max=null
stop_presets='[]'

parse_range() {
    local spec="$1"
    if [[ "$spec" =~ ([0-9]+)[[:space:]]*\.\.[[:space:]]*([0-9]+) ]]; then
        printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

parse_presets() {
    local spec="$1" numbers
    numbers="$(grep -oE '[0-9]+' <<<"$spec" | paste -sd, -)"
    [[ -n "$numbers" ]] || {
        printf '[]\n'
        return 0
    }
    printf '[%s]\n' "$numbers" | jq -c 'unique'
}

if [[ "$tlp_supported" == true ]]; then
    supported=true
    backend="tlp"

    case "$plugin_lower" in
        lenovo|lenovo-legacy)
            # ideapad_laptop exposes a vendor conservation mode. Its 0/1 values
            # select Standard/Long_Life, not 0%/1%, and Linux cannot report the
            # model-specific fixed target (commonly 60% or 80%).
            mode="fixed"
            ;;
        samsung)
            # samsung_laptop also exposes 0/1, but TLP documents the actual
            # battery-life extender target as 80%, with 100% meaning disabled.
            mode="fixed"
            stop_presets='[80,100]'
            ;;
        *)
            if range="$(parse_range "$start_spec" 2>/dev/null)"; then
                IFS=$'\t' read -r start_min start_max <<<"$range"
            fi
            if range="$(parse_range "$stop_spec" 2>/dev/null)"; then
                IFS=$'\t' read -r stop_min stop_max <<<"$range"
            fi

            if [[ "$features_lower" == *"charge type"* ]]; then
                mode="fixed"
            elif [[ "$stop_min" != null && "$stop_max" != null ]]; then
                mode="range"
            elif [[ -n "$stop_spec" ]]; then
                stop_presets="$(parse_presets "$stop_spec")"
                if [[ "${stop_spec,,}" == *"(on)"* && "${stop_spec,,}" == *"(off)"* ]]; then
                    mode="fixed"
                elif (( $(jq 'length' <<<"$stop_presets") >= 2 )); then
                    mode="presets"
                else
                    mode="tlp"
                fi
            else
                mode="tlp"
            fi
            ;;
    esac
elif [[ "$sysfs_supported" == true ]]; then
    supported=true
    backend="sysfs"
    mode="sysfs"
fi

summary="Charge limiting unavailable"
detail="This laptop does not expose a supported charge-threshold interface."

if [[ "$supported" == true ]]; then
    case "$mode" in
        range)
            summary="Charge limiting available"
            if [[ "$stop_min" != null && "$stop_max" != null ]]; then
                detail="Custom stop threshold ${stop_min}-${stop_max}%"
            else
                detail="Custom charge thresholds supported"
            fi
            ;;
        fixed)
            summary="Battery health limit available"
            if [[ "$plugin_lower" == lenovo || "$plugin_lower" == lenovo-legacy ]]; then
                detail="Hardware-defined conservation mode; the exact fixed target is not exposed by Linux"
            else
                detail="Hardware-defined charge limit presets"
            fi
            ;;
        presets)
            summary="Charge limit presets available"
            detail="Hardware accepts specific charge targets"
            ;;
        tlp)
            summary="Charge limiting available"
            detail="TLP reports charge-threshold support"
            ;;
        sysfs)
            summary="Charge limiting available"
            detail="Kernel exposes standard charge-threshold controls; writable range not yet validated"
            ;;
    esac
fi

jq -cn \
    --argjson supported "$supported" \
    --arg backend "$backend" \
    --arg plugin "$plugin" \
    --arg mode "$mode" \
    --arg summary "$summary" \
    --arg detail "$detail" \
    --arg start_spec "$start_spec" \
    --arg stop_spec "$stop_spec" \
    --argjson start_min "$start_min" \
    --argjson start_max "$start_max" \
    --argjson stop_min "$stop_min" \
    --argjson stop_max "$stop_max" \
    --argjson stop_presets "$stop_presets" \
    --argjson current_start "$first_start" \
    --argjson current_stop "$first_stop" \
    --argjson tlp_available "$tlp_available" \
    --argjson batteries "$batteries" '
    {
        supported:$supported,
        backend:$backend,
        plugin:$plugin,
        mode:$mode,
        summary:$summary,
        detail:$detail,
        start_spec:$start_spec,
        stop_spec:$stop_spec,
        start_min:$start_min,
        start_max:$start_max,
        stop_min:$stop_min,
        stop_max:$stop_max,
        stop_presets:$stop_presets,
        current_start:$current_start,
        current_stop:$current_stop,
        tlp_available:$tlp_available,
        batteries:$batteries
    }'
