#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
DETECTOR="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

assert_json() {
    local json="$1" filter="$2" description="$3"
    jq -e "$filter" <<<"$json" >/dev/null || fail "$description: $json"
}

command -v jq >/dev/null 2>&1 || fail 'jq is required'
[[ -f "$DETECTOR" ]] || fail 'battery detector is missing'
[[ -f "$HELPER" ]] || fail 'battery helper is missing'

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
    printf '* START_CHARGE_THRESH_BAT0: %s\n' "$TEST_START_SPEC"
fi
if [[ -n ${TEST_STOP_SPEC:-} ]]; then
    printf '* STOP_CHARGE_THRESH_BAT0: %s\n' "$TEST_STOP_SPEC"
fi
if [[ -n ${TEST_STATE_LINES:-} ]]; then
    printf '%s\n' "$TEST_STATE_LINES"
fi
EOF_TLP_STAT
chmod 0755 "$TMP/tlp-stat"

run_detector() {
    local plugin="$1" features="$2" start_spec="$3" stop_spec="$4" state_lines="$5"
    TEST_PLUGIN="$plugin" \
    TEST_FEATURES="$features" \
    TEST_START_SPEC="$start_spec" \
    TEST_STOP_SPEC="$stop_spec" \
    TEST_STATE_LINES="$state_lines" \
    AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-stat" \
        bash "$DETECTOR" --status-json
}

# Awtarchy must consume TLP's advertised generic interface, not recognize a
# hard-coded list of today's plugins. A new plugin with ordinary numeric ranges
# must therefore work without any Awtarchy code change.
json="$(run_detector \
    future-vendor \
    'charge thresholds' \
    '50..95(default)' \
    '55..100(default)' \
    $'/sys/class/power_supply/BAT0/charge_control_start_threshold = 75 [%]\n/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]')"
assert_json "$json" \
    '.supported == true and .writable == true and .backend == "tlp" and .mode == "range" and .plugin == "future-vendor" and .start_min == 50 and .start_max == 95 and .stop_min == 55 and .stop_max == 100' \
    'future TLP plugin with a normal numeric range was not accepted generically'

json="$(run_detector \
    another-future-vendor \
    'charge threshold' \
    '' \
    '50, 80, 100(default)' \
    '/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]')"
assert_json "$json" \
    '.supported == true and .writable == true and .backend == "tlp" and .mode == "presets" and (.stop_presets | index(50)) != null and (.stop_presets | index(80)) != null and (.stop_presets | index(100)) != null' \
    'future TLP plugin with numeric presets was not accepted generically'

# Vendor selector/boolean semantics are intentionally not reimplemented. A
# 0/1 selector is not a meaningful percentage control, so Quickshell must defer
# that advanced mode to TLP/TLPUI rather than presenting a 1% charge target.
json="$(run_detector \
    selector-vendor \
    'charge threshold' \
    '' \
    '0(off), 1(on) -- vendor selector' \
    '/sys/devices/platform/example/selector = 1')"
assert_json "$json" \
    '.supported == true and .writable == false and .backend == "tlp" and .mode == "unsupported"' \
    'selector-only TLP mode was exposed as a numeric Awtarchy control'

json="$(run_detector generic 'none available' '' '' '')"
assert_json "$json" \
    '.supported == false and .writable == false and .mode == "unsupported"' \
    'TLP without battery-care capability was exposed as writable'

# The production boundary itself must stay generic. Plugin names may remain in
# status text for diagnostics, but there must be no plugin allowlist governing
# write eligibility on either side of the privilege boundary.
! grep -Fq 'battery_plugin_writable()' "$DETECTOR" \
    || fail 'detector still owns a TLP battery-plugin allowlist'
! grep -Fq 'battery_plugin_writable()' "$HELPER" \
    || fail 'privileged helper still owns a TLP battery-plugin allowlist'

printf '%s\n' 'PASS: Battery Care consumes generic TLP capability instead of an Awtarchy vendor matrix.'
