#!/usr/bin/env bash
# Read-only battery charge-limit capability detection for Awtarchy Quickshell.

set -euo pipefail
export LC_ALL=C

POWER_SUPPLY_ROOT="${AWTARCHY_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
TLP_STAT_BIN="${AWTARCHY_TLP_STAT_BIN:-/usr/bin/tlp-stat}"
BATTERY_STATUS_HELPER="${AWTARCHY_BATTERY_STATUS_HELPER:-/usr/local/libexec/awtarchy/battery-status-helper}"
SUDO_BIN="${AWTARCHY_SUDO_BIN:-/usr/bin/sudo}"
TLP_CONFIG_DIR="${AWTARCHY_TLP_CONFIG_DIR:-/etc/tlp.d}"
TLP_USER_CONFIG="${AWTARCHY_TLP_USER_CONFIG:-/etc/tlp.conf}"
MANAGED_CONFIG="${TLP_CONFIG_DIR}/00-awtarchy-battery-care.conf"
SONY_BATTERY_CARE_PATH="${AWTARCHY_SONY_BATTERY_CARE_PATH:-/sys/devices/platform/sony-laptop/battery_care_limiter}"

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
    if [[ "$managed_target_text" =~ ^[0-9]+$ ]] && (( managed_target_text >= 1 && managed_target_text <= 100 )); then
        managed_target="$managed_target_text"
    fi
fi

conflict_sources='[]'
config_conflict=false
for config_file in "$TLP_CONFIG_DIR"/*.conf "$TLP_USER_CONFIG"; do
    [[ -f "$config_file" ]] || continue
    [[ "$config_file" == "$MANAGED_CONFIG" ]] && continue
    if grep -Eq '^[[:space:]]*(START|STOP)_CHARGE_THRESH_BAT[01][[:space:]]*=' "$config_file"; then
        config_conflict=true
        conflict_sources="$(jq -cn --argjson current "$conflict_sources" --arg file "$config_file" '$current + [$file]')"
    fi
done

plugin=""
features=""
start_spec=""
stop_spec=""
tlp_output=""
tlp_available=false

battery_plugin_writable() {
    case "$1" in
        asus|cros-ec|dell|huawei|thinkpad|thinkpad-legacy|lenovo|lenovo-legacy|lg|macbook|msi|samsung|sony|system76|toshiba|tuxedo|wilco-ec) return 0 ;;
        *) return 1 ;;
    esac
}

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

if [[ -x "$BATTERY_STATUS_HELPER" || -x "$TLP_STAT_BIN" ]]; then
    tlp_available=true
    tlp_output="$(read_tlp_battery_report 2>/dev/null || true)"
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

# `tlp-stat -b` is documented by TLP as a root command, while this detector is
# intentionally unprivileged. sony_laptop exposes its actual limiter through a
# read-only sysfs attribute, so use the kernel interface to recover capability
# and current state when the authoritative TLP report is temporarily unavailable.
# Writes still go only through the root-owned TLP helper.
sony_limit=null
if value="$(read_percent "$SONY_BATTERY_CARE_PATH" 2>/dev/null)"; then
    case "$value" in
        0) sony_limit=100 ;;
        50|80|100) sony_limit="$value" ;;
    esac
fi
if [[ "$sony_limit" != null && "$tlp_available" == true ]]; then
    features_lower_probe="${features,,}"
    if [[ -z "$plugin" || "$features_lower_probe" != *"charge threshold"* || -z "$stop_spec" ]]; then
        plugin="sony"
        features="charge threshold"
        stop_spec="50, 80, 100(off) -- battery care limiter"
    fi
fi

plugin_lower="${plugin,,}"
features_lower="${features,,}"
tlp_supported=false
if [[ "$features_lower" == *"charge threshold"* ]]; then
    tlp_supported=true
elif [[ "$features_lower" == *"charge type"* && -n "$stop_spec" ]]; then
    tlp_supported=true
fi

mode="unsupported"
backend="none"
supported=false
writable=false
compatibility="unsupported"
start_min=null
start_max=null
stop_min=null
stop_max=null
stop_presets='[]'

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
    printf '[%s]\n' "$numbers" | jq -c 'unique'
}

if [[ "$tlp_supported" == true ]]; then
    supported=true
    backend="tlp"
    if battery_plugin_writable "$plugin_lower"; then
        writable=true
        compatibility="validated"
    else
        compatibility="unvalidated"
    fi

    case "$plugin_lower" in
        lenovo|lenovo-legacy)
            mode="fixed"
            ;;
        samsung)
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
elif [[ "$sysfs_supported" == true && "$plugin_lower" != "generic" ]]; then
    supported=true
    writable=false
    compatibility="unvalidated"
    backend="sysfs"
    mode="sysfs"
fi

observed_target=null
enabled=null

if [[ "$backend" == tlp ]]; then
    case "$plugin_lower" in
        lenovo)
            lenovo_long_life=false
            lenovo_standard=false
            if grep -Eq 'charge_types[^=]*=.*\[Long_Life\]' <<<"$tlp_output"; then
                lenovo_long_life=true
            fi
            if grep -Eq 'charge_types[^=]*=.*\[Standard\]' <<<"$tlp_output"; then
                lenovo_standard=true
            fi

            if [[ "$lenovo_long_life" == true && "$lenovo_standard" == true ]]; then
                mixed_stop_thresholds=true
            elif [[ "$lenovo_long_life" == true ]]; then
                enabled=true
            elif [[ "$lenovo_standard" == true ]]; then
                enabled=false
                observed_target=100
            fi
            ;;
        lenovo-legacy)
            if grep -Eq 'conservation_mode[^=]*=[[:space:]]*1([^0-9]|$)' <<<"$tlp_output"; then
                enabled=true
            elif grep -Eq 'conservation_mode[^=]*=[[:space:]]*0([^0-9]|$)' <<<"$tlp_output"; then
                enabled=false
                observed_target=100
            fi
            ;;
        samsung)
            if grep -Eq 'battery_life_extender[^=]*=[[:space:]]*1([^0-9]|$)' <<<"$tlp_output"; then
                enabled=true
                observed_target=80
            elif grep -Eq 'battery_life_extender[^=]*=[[:space:]]*0([^0-9]|$)' <<<"$tlp_output"; then
                enabled=false
                observed_target=100
            fi
            ;;
        sony)
            if [[ "$sony_limit" != null ]]; then
                observed_target="$sony_limit"
            else
                observed="$(awk '
                    /battery_care_limiter[^=]*=/ {
                        value=$0
                        sub(/^.*=[[:space:]]*/, "", value)
                        if (match(value, /^[0-9]+/)) { print substr(value, RSTART, RLENGTH); exit }
                    }
                ' <<<"$tlp_output")"
                if [[ "$observed" =~ ^[0-9]+$ ]]; then
                    if (( observed == 0 )); then
                        observed_target=100
                    else
                        observed_target="$observed"
                    fi
                fi
            fi
            ;;
        huawei)
            observed="$(sed -n -E 's/^.*charge_control_thresholds[^=]*=[[:space:]]*[0-9]+[[:space:]]+([0-9]+).*$/\1/p' <<<"$tlp_output" | head -n1)"
            if [[ "$observed" =~ ^[0-9]+$ ]]; then
                observed_target="$observed"
            fi
            ;;
        *)
            observed="$(awk '
                /(charge_control_end_threshold|stop_charge_thresh|battery_care_limit|battery_care_limiter)[^=]*=/ {
                    value=$0
                    sub(/^.*=[[:space:]]*/, "", value)
                    if (match(value, /^[0-9]+/)) { print substr(value, RSTART, RLENGTH); exit }
                }
            ' <<<"$tlp_output")"
            if [[ "$observed" =~ ^[0-9]+$ ]]; then
                observed_target="$observed"
            fi
            ;;
    esac
fi

if [[ "$mixed_stop_thresholds" == true ]]; then
    observed_target=null
    enabled=null
    first_stop=null
elif [[ "$observed_target" == null && "$first_stop" != null ]]; then
    observed_target="$first_stop"
fi
if [[ "$enabled" == null && "$observed_target" != null ]]; then
    if (( observed_target < 100 )); then
        enabled=true
    else
        enabled=false
    fi
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

if [[ "$compatibility" == "unvalidated" && "$backend" == "tlp" ]]; then
    summary="Battery Care detected but not validated by Awtarchy"
    detail="Write controls are disabled for this backend."
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
