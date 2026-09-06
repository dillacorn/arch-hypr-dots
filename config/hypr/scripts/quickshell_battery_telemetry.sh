#!/usr/bin/env bash
# Read-only raw battery telemetry correction for Awtarchy Quickshell.
# UPower remains authoritative unless a multi-battery system contains a pack
# that is unambiguously electrically dead/phantom from raw sysfs evidence.

set -euo pipefail
export LC_ALL=C

POWER_SUPPLY_ROOT="${AWTARCHY_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"

usage() {
    printf 'usage: %s --status-json\n' "${0##*/}" >&2
    return 2
}

read_text() {
    local path="$1"
    [[ -r "$path" ]] || return 1
    tr -d '\r\n' <"$path"
}

read_nonnegative_integer() {
    local path="$1" value
    value="$(read_text "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$value"
}

read_signed_integer() {
    local path="$1" value
    value="$(read_text "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^-?[0-9]+$ ]] || return 1
    printf '%s\n' "$value"
}

abs_integer() {
    local value="$1"
    if [[ "$value" == -* ]]; then
        printf '%s\n' "${value#-}"
    else
        printf '%s\n' "$value"
    fi
}

json_array() {
    jq -cn --args '$ARGS.positional' "$@"
}

emit_fallback() {
    local reason="$1"
    local excluded_json included_json
    excluded_json="$(json_array)"
    included_json="$(json_array)"
    jq -cn \
        --arg reason "$reason" \
        --argjson excluded "$excluded_json" \
        --argjson included "$included_json" '
        {
            override:false,
            reason:$reason,
            percentage:null,
            energy_wh:null,
            energy_capacity_wh:null,
            change_rate_watts:null,
            time_to_empty_seconds:null,
            time_to_full_seconds:null,
            excluded:$excluded,
            included:$included
        }'
}

main() {
    [[ ${1:-} == --status-json && $# -eq 1 ]] || { usage; return 2; }
    command -v jq >/dev/null 2>&1 || return 127

    local present_count=0 unknown=false
    local battery_dir type name present voltage
    local energy_now energy_full charge_now charge_full stored_now stored_full storage_kind
    local power current power_abs current_abs pack_energy_now pack_energy_full pack_power value
    local total_now=0 total_full=0 total_power=0
    local percentage energy_wh energy_capacity_wh change_rate_watts
    local time_to_empty_seconds=0 time_to_full_seconds=0 excluded_json included_json
    local -a dead_names=()
    local -a included_names=()
    local -a included_energy_now=()
    local -a included_energy_full=()
    local -a included_power_now=()

    shopt -s nullglob
    for battery_dir in "$POWER_SUPPLY_ROOT"/*; do
        [[ -d "$battery_dir" ]] || continue
        type="$(read_text "$battery_dir/type" 2>/dev/null || true)"
        [[ "$type" == Battery ]] || continue

        name="${battery_dir##*/}"
        present="$(read_nonnegative_integer "$battery_dir/present" 2>/dev/null || true)"
        if [[ "$present" != 0 && "$present" != 1 ]]; then
            unknown=true
            continue
        fi
        [[ "$present" == 1 ]] || continue
        ((present_count += 1))

        voltage="$(read_nonnegative_integer "$battery_dir/voltage_now" 2>/dev/null || true)"
        if [[ -z "$voltage" ]]; then
            unknown=true
            continue
        fi

        energy_now="$(read_nonnegative_integer "$battery_dir/energy_now" 2>/dev/null || true)"
        energy_full="$(read_nonnegative_integer "$battery_dir/energy_full" 2>/dev/null || true)"
        charge_now="$(read_nonnegative_integer "$battery_dir/charge_now" 2>/dev/null || true)"
        charge_full="$(read_nonnegative_integer "$battery_dir/charge_full" 2>/dev/null || true)"

        stored_now=""
        stored_full=""
        storage_kind=""
        if [[ -n "$energy_now" && -n "$energy_full" && "$energy_full" -gt 0 ]]; then
            stored_now="$energy_now"
            stored_full="$energy_full"
            storage_kind="energy"
        elif [[ -n "$charge_now" && -n "$charge_full" && "$charge_full" -gt 0 ]]; then
            stored_now="$charge_now"
            stored_full="$charge_full"
            storage_kind="charge"
        else
            unknown=true
            continue
        fi

        power="$(read_signed_integer "$battery_dir/power_now" 2>/dev/null || true)"
        current="$(read_signed_integer "$battery_dir/current_now" 2>/dev/null || true)"
        if [[ -z "$power" && -z "$current" ]]; then
            unknown=true
            continue
        fi

        power_abs=""
        current_abs=""
        [[ -z "$power" ]] || power_abs="$(abs_integer "$power")"
        [[ -z "$current" ]] || current_abs="$(abs_integer "$current")"

        if [[ "$voltage" -eq 0 ]]; then
            # A dead/phantom classification requires a stale positive capacity
            # plus zero present charge/energy and zero observed electrical flow.
            # Any contradictory or missing signal fails closed to UPower.
            if [[ "$stored_now" -eq 0 \
                && ( -z "$power_abs" || "$power_abs" -eq 0 ) \
                && ( -z "$current_abs" || "$current_abs" -eq 0 ) ]]; then
                dead_names+=("$name")
                continue
            fi
            unknown=true
            continue
        fi

        # Nonzero voltage means an empty 0%-equivalent pack is still real
        # hardware. It stays included. Charge-domain telemetry is converted only
        # with observed voltage so all included packs share energy-domain units.
        if [[ "$storage_kind" == energy ]]; then
            pack_energy_now="$stored_now"
            pack_energy_full="$stored_full"
        else
            pack_energy_now="$(awk -v q="$stored_now" -v v="$voltage" 'BEGIN { printf "%.0f", (q * v) / 1000000 }')"
            pack_energy_full="$(awk -v q="$stored_full" -v v="$voltage" 'BEGIN { printf "%.0f", (q * v) / 1000000 }')"
        fi

        if [[ -n "$power_abs" ]]; then
            pack_power="$power_abs"
        else
            pack_power="$(awk -v i="$current_abs" -v v="$voltage" 'BEGIN { printf "%.0f", (i * v) / 1000000 }')"
        fi

        if [[ ! "$pack_energy_full" =~ ^[0-9]+$ || "$pack_energy_full" -le 0 \
            || ! "$pack_energy_now" =~ ^[0-9]+$ || ! "$pack_power" =~ ^[0-9]+$ ]]; then
            unknown=true
            continue
        fi

        included_names+=("$name")
        included_energy_now+=("$pack_energy_now")
        included_energy_full+=("$pack_energy_full")
        included_power_now+=("$pack_power")
    done

    if (( present_count < 2 )); then
        emit_fallback "single-battery"
        return 0
    fi

    if [[ "$unknown" == true ]]; then
        emit_fallback "insufficient-telemetry"
        return 0
    fi

    if (( ${#dead_names[@]} == 0 )); then
        emit_fallback "no-dead-pack"
        return 0
    fi

    if (( ${#included_names[@]} == 0 )); then
        emit_fallback "insufficient-telemetry"
        return 0
    fi

    for value in "${included_energy_now[@]}"; do
        total_now=$((total_now + value))
    done
    for value in "${included_energy_full[@]}"; do
        total_full=$((total_full + value))
    done
    for value in "${included_power_now[@]}"; do
        total_power=$((total_power + value))
    done

    if (( total_full <= 0 || total_now < 0 || total_now > total_full || total_power < 0 )); then
        emit_fallback "insufficient-telemetry"
        return 0
    fi

    percentage="$(awk -v now="$total_now" -v full="$total_full" 'BEGIN { printf "%d", ((now / full) * 100) + 0.5 }')"
    energy_wh="$(awk -v value="$total_now" 'BEGIN { printf "%.6f", value / 1000000 }')"
    energy_capacity_wh="$(awk -v value="$total_full" 'BEGIN { printf "%.6f", value / 1000000 }')"
    change_rate_watts="$(awk -v value="$total_power" 'BEGIN { printf "%.6f", value / 1000000 }')"
    if (( total_power > 0 )); then
        time_to_empty_seconds="$(awk -v now="$total_now" -v power="$total_power" 'BEGIN { printf "%.0f", (now / power) * 3600 }')"
        time_to_full_seconds="$(awk -v now="$total_now" -v full="$total_full" -v power="$total_power" 'BEGIN { printf "%.0f", ((full - now) / power) * 3600 }')"
    fi

    excluded_json="$(json_array "${dead_names[@]}")"
    included_json="$(json_array "${included_names[@]}")"

    jq -cn \
        --argjson percentage "$percentage" \
        --argjson energy_wh "$energy_wh" \
        --argjson energy_capacity_wh "$energy_capacity_wh" \
        --argjson change_rate_watts "$change_rate_watts" \
        --argjson time_to_empty_seconds "$time_to_empty_seconds" \
        --argjson time_to_full_seconds "$time_to_full_seconds" \
        --argjson excluded "$excluded_json" \
        --argjson included "$included_json" '
        {
            override:true,
            reason:"dead-or-phantom-pack",
            percentage:$percentage,
            energy_wh:$energy_wh,
            energy_capacity_wh:$energy_capacity_wh,
            change_rate_watts:$change_rate_watts,
            time_to_empty_seconds:$time_to_empty_seconds,
            time_to_full_seconds:$time_to_full_seconds,
            excluded:$excluded,
            included:$included
        }'
}

main "$@"
