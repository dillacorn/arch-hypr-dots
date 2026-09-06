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
printf '%s\n' 75 >"$POWER_ROOT/BAT0/charge_control_start_threshold"
printf '%s\n' 80 >"$POWER_ROOT/BAT0/charge_control_end_threshold"

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
EOF_TLP_STAT
chmod 0755 "$TMP/tlp-stat"

run_profile() {
    local plugin="$1" features="$2" start_spec="$3" stop_spec="$4"
    TEST_PLUGIN="$plugin" \
    TEST_FEATURES="$features" \
    TEST_START_SPEC="$start_spec" \
    TEST_STOP_SPEC="$stop_spec" \
    AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-stat" \
        bash "$DETECTOR" --status-json
}

# Generic numeric ranges are writable regardless of plugin identity.
json="$(run_profile arbitrary-range 'charge thresholds' '0(off)..96(default)..99' '1..100(default)')"
assert_json "$json" \
    '.plugin == "arbitrary-range" and .supported == true and .writable == true and .mode == "range" and .start_min == 0 and .start_max == 99 and .stop_min == 1 and .stop_max == 100 and .target == 80 and .enabled == true' \
    'annotated numeric range was not normalized generically'

# Generic literal percentage presets remain writable without vendor knowledge.
json="$(run_profile arbitrary-presets 'charge threshold' '' '50, 80, 100(default)')"
assert_json "$json" \
    '.plugin == "arbitrary-presets" and .supported == true and .writable == true and .mode == "presets" and .stop_presets == [50,80,100] and .target == 80 and .enabled == true' \
    'numeric presets were not normalized generically'

# Raw selector/boolean controls are not percentages. They stay detected for
# diagnostics but are intentionally read-only in Awtarchy.
json="$(run_profile arbitrary-selector 'charge threshold' '' '0(Standard)..1(Long_Life) -- selector')"
assert_json "$json" \
    '.plugin == "arbitrary-selector" and .supported == true and .writable == false and .mode == "unsupported"' \
    'selector semantics leaked into the percentage UI'

# No advertised threshold capability remains unsupported.
json="$(run_profile generic 'none available' '' '')"
assert_json "$json" \
    '.supported == false and .writable == false and .mode == "unsupported"' \
    'missing TLP battery-care capability was exposed as writable'

# The detector may report the plugin name for diagnostics, but it must not own
# a compatibility matrix keyed by today's hardware vendors.
if grep -Eq '(^|[^[:alnum:]_-])(asus|dell|huawei|lenovo|lg|samsung|sony|thinkpad|tuxedo)([^[:alnum:]_-]|$)' "$DETECTOR"; then
    fail 'battery detector still contains vendor-specific compatibility policy'
fi

printf '%s\n' 'PASS: TLP battery capability profiles are normalized generically.'
