#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
DETECTOR="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_json() {
    local json="$1" filter="$2" message="$3"
    jq -e "$filter" <<<"$json" >/dev/null || fail "$message: $json"
}

POWER_ROOT="$TMP/power"
mkdir -p -- "$POWER_ROOT/BAT0"
printf '%s\n' Battery >"$POWER_ROOT/BAT0/type"
printf '%s\n' TestVendor >"$POWER_ROOT/BAT0/manufacturer"
printf '%s\n' TestModel >"$POWER_ROOT/BAT0/model_name"

cat >"$TMP/tlp-stat" <<'EOF_TLP_STAT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '+++ Battery Care'
printf 'Plugin: %s\n' "${TEST_PLUGIN:?}"
printf 'Supported features: %s\n' "${TEST_FEATURES:?}"
if [[ -n ${TEST_START_SPEC:-} ]]; then
    printf '* START_CHARGE_THRESH_BAT0/1: %s\n' "$TEST_START_SPEC"
fi
if [[ -n ${TEST_STOP_SPEC:-} ]]; then
    printf '* STOP_CHARGE_THRESH_BAT0/1: %s\n' "$TEST_STOP_SPEC"
fi
if [[ -n ${TEST_STATE_LINES:-} ]]; then
    printf '%s\n' "$TEST_STATE_LINES"
fi
EOF_TLP_STAT
chmod 0755 "$TMP/tlp-stat"

run_profile() {
    local plugin="$1" features="$2" start_spec="$3" stop_spec="$4" state_lines="$5"
    TEST_PLUGIN="$plugin" \
    TEST_FEATURES="$features" \
    TEST_START_SPEC="$start_spec" \
    TEST_STOP_SPEC="$stop_spec" \
    TEST_STATE_LINES="$state_lines" \
    AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-stat" \
    AWTARCHY_SONY_BATTERY_CARE_PATH="$TMP/no-sony-limiter" \
        bash "$DETECTOR" --status-json
}

assert_validated_range() {
    local plugin="$1" start_spec="$2" stop_spec="$3" start_min="$4" start_max="$5" stop_min="$6" stop_max="$7"
    local json state_lines
    state_lines=$'/sys/class/power_supply/BAT0/charge_control_start_threshold = 75 [%]\n/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]'
    json="$(run_profile "$plugin" 'charge thresholds' "$start_spec" "$stop_spec" "$state_lines")"
    assert_json "$json" ".plugin == \"$plugin\" and .supported == true and .writable == true and .compatibility == \"validated\" and .backend == \"tlp\" and .mode == \"range\" and .start_min == $start_min and .start_max == $start_max and .stop_min == $stop_min and .stop_max == $stop_max" \
        "$plugin range profile was not normalized as expected"
}

assert_validated_stop_range() {
    local plugin="$1" start_spec="$2" stop_spec="$3" stop_min="$4" stop_max="$5"
    local json
    json="$(run_profile "$plugin" 'charge threshold' "$start_spec" "$stop_spec" '/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]')"
    assert_json "$json" ".plugin == \"$plugin\" and .supported == true and .writable == true and .compatibility == \"validated\" and .backend == \"tlp\" and .mode == \"range\" and .stop_min == $stop_min and .stop_max == $stop_max" \
        "$plugin stop-range profile was not normalized as expected"
}

# Ordinary/range-style TLP plugins.
assert_validated_stop_range asus '' '1..100(default)' 1 100
assert_validated_range cros-ec '0..99' '1..100(default)' 0 99 1 100
assert_validated_range dell '50..95(default)' '55..100(default)' 50 95 55 100

json="$(run_profile huawei 'charge thresholds' '0(default)..99' '1..100(default)' '/sys/devices/platform/huawei-wmi/charge_control_thresholds = 75 80')"
assert_json "$json" '.supported == true and .writable == true and .compatibility == "validated" and .mode == "range" and .start_min == 0 and .start_max == 99 and .stop_min == 1 and .stop_max == 100 and .target == 80 and .enabled == true' \
    'Huawei threshold pair was not normalized correctly'

assert_validated_stop_range msi "don't care (hardware enforces stop - 10)" '10..100(default)' 10 100
assert_validated_range system76 '0(off)..99' '1..100(default)' 0 99 1 100
assert_validated_range thinkpad '0(off)..99' '1..100(default)' 0 99 1 100
assert_validated_range thinkpad-legacy '2..96(default)' '6..100(default)' 2 96 6 100
assert_validated_range wilco-ec '50..95(default)' '55..100(default)' 50 95 55 100

# Preset and fixed-percentage plugins.
json="$(run_profile macbook 'charge threshold' "don't care (hardware enforces 75, 100)" '80, 100(default)' '/sys/class/power_supply/macsmc-battery/charge_control_end_threshold = 80 [%]')"
assert_json "$json" '.supported == true and .writable == true and .compatibility == "validated" and .mode == "presets" and (.stop_presets | index(80)) != null and (.stop_presets | index(100)) != null and .target == 80' \
    'MacBook preset semantics were not normalized correctly'

json="$(run_profile sony 'charge threshold' '' '50, 80, 100(off) -- battery care limiter' '/sys/devices/platform/sony-laptop/battery_care_limiter = 0 (100) [%]')"
assert_json "$json" '.supported == true and .writable == true and .compatibility == "validated" and .mode == "presets" and .target == 100 and .enabled == false and (.stop_presets | index(50)) != null and (.stop_presets | index(80)) != null and (.stop_presets | index(100)) != null' \
    'Sony raw zero was not normalized to logical 100/off'

json="$(run_profile tuxedo 'charge thresholds' '40/50/60/70/80/95(default)' '60/70/80/90/100(default)' $'/sys/class/power_supply/BAT0/charge_control_start_threshold = 70 [%]\n/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]')"
assert_json "$json" '.supported == true and .writable == true and .compatibility == "validated" and .mode == "presets" and (.stop_presets | index(60)) != null and (.stop_presets | index(80)) != null and (.stop_presets | index(100)) != null and .target == 80' \
    'Tuxedo discrete threshold profile was not normalized correctly'

for plugin in lg toshiba; do
    json="$(run_profile "$plugin" 'charge threshold' '' '80(on), 100(off)' '/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]')"
    assert_json "$json" ".plugin == \"$plugin\" and .supported == true and .writable == true and .compatibility == \"validated\" and .mode == \"fixed\" and (.stop_presets | index(80)) != null and (.stop_presets | index(100)) != null and .target == 80" \
        "$plugin fixed 80/100 profile was not normalized correctly"
done

# Selector/boolean plugins are normalized to user-facing on/off state.
json="$(run_profile lenovo 'charge threshold' '' '0(Standard)..1(Long_Life) -- charge_types' '/sys/class/power_supply/BAT0/charge_types = Standard [Long_Life]')"
assert_json "$json" '.supported == true and .writable == true and .compatibility == "validated" and .mode == "fixed" and .enabled == true and .target == null' \
    'Lenovo Long_Life state was not normalized correctly'

json="$(run_profile lenovo-legacy 'charge threshold' '' '0(off), 1(on) -- conservation_mode' '/sys/devices/platform/ideapad/conservation_mode = 0')"
assert_json "$json" '.supported == true and .writable == true and .compatibility == "validated" and .mode == "fixed" and .enabled == false and .target == 100' \
    'Lenovo legacy conservation OFF state was not normalized correctly'

json="$(run_profile samsung 'charge threshold' '' '0(off), 1(on) -- battery life extender' '/sys/devices/platform/samsung/battery_life_extender = 1 (80%)')"
assert_json "$json" '.supported == true and .writable == true and .compatibility == "validated" and .mode == "fixed" and .enabled == true and .target == 80 and .stop_presets == [80,100]' \
    'Samsung battery life extender state was not normalized correctly'

# Obsolete, unknown, and generic backends must never become writable by accident.
json="$(run_profile lg-legacy 'charge threshold' '' '80(on), 100(off)' '/sys/devices/platform/lg/charge_control_end_threshold = 80 [%]')"
assert_json "$json" '.supported == true and .writable == false and .compatibility == "unvalidated" and .backend == "tlp"' \
    'obsolete lg-legacy backend did not fail closed'

json="$(run_profile future-vendor 'charge threshold' '' '50..100(default)' '/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]')"
assert_json "$json" '.supported == true and .writable == false and .compatibility == "unvalidated" and .backend == "tlp" and .summary == "Battery Care detected but not validated by Awtarchy"' \
    'future TLP plugin did not remain detected but non-writable'

json="$(run_profile generic 'none available' '' '' '')"
assert_json "$json" '.supported == false and .writable == false and .compatibility == "unsupported" and .backend == "none"' \
    'TLP generic backend was not kept unsupported'

# QML filters logical 100/off out of selectable target buttons.
grep -Fq 'value >= 1 && value < 100' "$ROOT/config/quickshell/awtarchy/BatteryCareCard.qml" \
    || fail 'Battery Care QML no longer excludes logical 100/off from numeric target buttons'

printf '%s\n' 'PASS: current TLP battery detector vendor profiles are classified and normalized.'
