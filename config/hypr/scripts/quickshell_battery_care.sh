#!/usr/bin/env bash
# Read-only Battery Care status adapter for Awtarchy Quickshell.
# TLP owns hardware/vendor compatibility; this script only normalizes TLP's
# generic advertised percentage interface for the UI.

set -euo pipefail
export LC_ALL=C

POWER_SUPPLY_ROOT="${AWTARCHY_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
TLP_STAT_BIN="${AWTARCHY_TLP_STAT_BIN:-/usr/bin/tlp-stat}"
BATTERY_STATUS_HELPER="${AWTARCHY_BATTERY_STATUS_HELPER:-/usr/local/libexec/awtarchy/battery-status-helper}"
SUDO_BIN="${AWTARCHY_SUDO_BIN:-/usr/bin/sudo}"
TLP_CONFIG_DIR="${AWTARCHY_TLP_CONFIG_DIR:-/etc/tlp.d}"
TLP_USER_CONFIG="${AWTARCHY_TLP_USER_CONFIG:-/etc/tlp.conf}"
MANAGED_CONFIG="${TLP_CONFIG_DIR}/00-awtarchy-battery-care.conf"

usage() {
    printf 'usage: %s --status-json\n' "${0##*/}" >&2
    return 2
}

[[ ${1:-} == --status-json && $# -eq 1 ]] || { usage; exit $?; }
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

parse_range() {
    local spec="$1" first last min max
    [[ "$spec" == *..* ]] || return 1

    first="${spec%%..*}"
    last="${spec##*..}"
    [[ "$first" =~ ([0-9]+) ]] || return 1
    min="${BASH_REMATCH[1]}"
    [[ "$last" =~ ([0-9]+) ]] || return 1
    max="${BASH_REMATCH[1]}"
    (( min <= max )) || return 1

    printf '%s\t%s\n' "$min" "$max"
}

parse_presets() {
    local spec="$1" numbers
    numbers="$(grep -oE '[0-9]+' <<<"$spec" | paste -sd, -)"
    [[ -n "$numbers" ]] || {
        printf '[]\n'
        return 0
    }
    printf '[%s]\n' "$numbers" | jq -c '[.[] | select(. >= 0 and . <= 100)] | unique'
}

range_is_percentage_control() {
    local min="$1" max="$2"
    (( min >= 0 && max <= 100 && max > 1 && min < 100 ))
}

presets_have_percentage_target() {
    local presets="$1"
    jq -e 'any(.[]; . >= 2 and . < 100)' <<<"$presets" >/dev/null
}

batteries='[]'
first_start=null
first_stop=null
mixed_stop_thresholds=false

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
        if value="$(read_percent "$battery_dir/charge_control_start_threshold" 2>/dev/null)"; then
            start_threshold="$value"
            [[ "$first_start" != null ]] || first_start="$value"
        fi
    fi

    if [[ -e "$battery_dir/charge_control_end_threshold" ]]; then
        stop_supported=true
        if value="$(read_percent "$battery_dir/charge_control_end_threshold" 2>/dev/null)"; then
            stop_threshold="$value"
            if [[ "$first_stop" == null ]]; then
                first_stop="$value"
            elif [[ "$first_stop" != "$value" ]]; then
                mixed_stop_thresholds=true
            fi
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

managed_config=false
managed_target=null
if [[ -f "$MANAGED_CONFIG" && ! -L "$MANAGED_CONFIG" ]]; then
    managed_config=true
    managed_target_text="$(sed -n -E 's/^#[[:space:]]*target=([0-9]+).*$/\1/p' "$MANAGED_CONFIG" | head -n1)"
    if [[ ! "$managed_target_text" =~ ^[0-9]+$ ]]; then
        managed_target_text="$(sed -n -E 's/^[[:space:]]*STOP_CHARGE_THRESH_BAT[0-9]+[[:space:]]*=[[:space:]]*([0-9]+).*$/\1/p' "$MANAGED_CONFIG" | head -n1)"
    fi
    if [[ "$managed_target_text" =~ ^[0-9]+$ ]] \
        && (( managed_target_text >= 2 && managed_target_text <= 100 )); then
        managed_target="$managed_target_text"
    fi
fi

conflict_sources='[]'
config_conflict=false
for config_file in "$TLP_CONFIG_DIR"/*.conf "$TLP_USER_CONFIG"; do
    [[ -f "$config_file" ]] || continue
    [[ "$config_file" == "$MANAGED_CONFIG" ]] && continue
    if grep -Eq '^[[:space:]]*(START|STOP)_CHARGE_THRESH_BAT[0-9]+[[:space:]]*=' "$config_file"; then
        config_conflict=true
        conflict_sources="$(jq -cn --argjson current "$conflict_sources" --arg file "$config_file" '$current + [$file]')"
    fi
done

read_tlp_battery_report() {
    local report=""

    if [[ -x "$BATTERY_STATUS_HELPER" && -x "$SUDO_BIN" ]]; then
        report="$("$SUDO_BIN" -n -- "$BATTERY_STATUS_HELPER" 2>/dev/null || true)"
        if [[ -n "$report" ]]; then
            printf '%s\n' "$report"
            return 0
        fi
    fi

    if [[ -x "$TLP_STAT_BIN" ]]; then
        report="$("$TLP_STAT_BIN" -b 2>/dev/null || true)"
        if [[ -n "$report" ]]; then
            printf '%s\n' "$report"
            return 0
        fi
    fi

    return 1
}

tlp_output="$(read_tlp_battery_report 2>/dev/null || true)"
tlp_available=false
[[ -n "$tlp_output" ]] && tlp_available=true

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

features_lower="${features,,}"
supported=false
writable=false
compatibility="unsupported"
backend="none"
mode="unsupported"
start_min=null
start_max=null
stop_min=null
stop_max=null
stop_presets='[]'

if [[ "$features_lower" == *"charge threshold"* || "$features_lower" == *"charge type"* ]]; then
    supported=true
    backend="tlp"
    compatibility="unvalidated"

    if [[ "$features_lower" != *"charge threshold"* ]]; then
        :
    elif range="$(parse_range "$stop_spec" 2>/dev/null)"; then
        IFS=$'\t' read -r candidate_stop_min candidate_stop_max <<<"$range"
        if range_is_percentage_control "$candidate_stop_min" "$candidate_stop_max"; then
            stop_min="$candidate_stop_min"
            stop_max="$candidate_stop_max"
            mode="range"
            writable=true
            compatibility="validated"

            if range="$(parse_range "$start_spec" 2>/dev/null)"; then
                IFS=$'\t' read -r candidate_start_min candidate_start_max <<<"$range"
                if (( candidate_start_min >= 0 && candidate_start_max <= 100 )); then
                    start_min="$candidate_start_min"
                    start_max="$candidate_start_max"
                fi
            fi
        fi
    else
        stop_presets="$(parse_presets "$stop_spec")"
        if presets_have_percentage_target "$stop_presets"; then
            mode="presets"
            writable=true
            compatibility="validated"
        else
            stop_presets='[]'
        fi
    fi
fi

observed_target=null
enabled=null
if [[ "$mode" == range || "$mode" == presets ]]; then
    if [[ "$mixed_stop_thresholds" == true ]]; then
        first_stop=null
    elif [[ "$first_stop" != null ]]; then
        observed_target="$first_stop"
    fi

    if [[ "$observed_target" != null ]]; then
        if (( observed_target < 100 )); then
            enabled=true
        else
            enabled=false
        fi
    elif [[ "$managed_target" != null ]]; then
        if (( managed_target < 100 )); then
            enabled=true
        else
            enabled=false
        fi
    fi
fi

summary="Charge limiting unavailable"
detail="TLP does not report a usable battery charge-limit interface."
if [[ "$supported" == true && "$writable" == true ]]; then
    case "$mode" in
        range)
            summary="Charge limiting available"
            detail="TLP supports a ${stop_min}-${stop_max}% stop threshold"
            ;;
        presets)
            summary="Charge limit presets available"
            detail="TLP reports specific percentage charge targets"
            ;;
    esac
elif [[ "$supported" == true ]]; then
    summary="Advanced Battery Care available"
    detail="TLP reports a non-percentage battery-care mode; configure it with TLPUI."
fi

jq -cn \
    --argjson supported "$supported" \
    --argjson writable "$writable" \
    --arg compatibility "$compatibility" \
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
    --argjson mixed_stop_thresholds "$mixed_stop_thresholds" \
    --argjson tlp_available "$tlp_available" \
    --argjson managed_config "$managed_config" \
    --argjson managed_target "$managed_target" \
    --argjson config_conflict "$config_conflict" \
    --argjson conflict_sources "$conflict_sources" \
    --argjson enabled "$enabled" \
    --argjson target "$observed_target" \
    --argjson batteries "$batteries" '
    {
        supported:$supported,
        writable:$writable,
        compatibility:$compatibility,
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
        mixed_stop_thresholds:$mixed_stop_thresholds,
        tlp_available:$tlp_available,
        managed_config:$managed_config,
        managed_target:$managed_target,
        config_conflict:$config_conflict,
        conflict_sources:$conflict_sources,
        enabled:$enabled,
        target:$target,
        batteries:$batteries
    }'
