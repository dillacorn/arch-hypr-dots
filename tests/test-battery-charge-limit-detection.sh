#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
CARE_CARD="${ROOT}/config/quickshell/awtarchy/BatteryCareCard.qml"
POWER_CARD="${ROOT}/config/quickshell/awtarchy/PowerModeCard.qml"
TMP="$(mktemp -d)"
cleanup() {
    chmod -R u+w -- "$TMP" 2>/dev/null || true
    rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "missing file: ${1#"$ROOT"/}"
}

require_source() {
    local file="$1" needle="$2"
    grep -Fq -- "$needle" "$file" || fail "${file#"$ROOT"/} missing: $needle"
}

assert_json() {
    local json="$1" filter="$2" description="$3"
    jq -e "$filter" <<<"$json" >/dev/null || fail "$description: $json"
}

make_battery() {
    local root="$1" name="$2" start="${3:-}" stop="${4:-}"
    mkdir -p -- "$root/$name"
    printf '%s\n' Battery >"$root/$name/type"
    printf '%s\n' TestVendor >"$root/$name/manufacturer"
    printf '%s\n' TestModel >"$root/$name/model_name"
    [[ -z "$start" ]] || printf '%s\n' "$start" >"$root/$name/charge_control_start_threshold"
    [[ -z "$stop" ]] || printf '%s\n' "$stop" >"$root/$name/charge_control_end_threshold"
    chmod -R a-w -- "$root/$name"
}

require_file "$SCRIPT"
require_file "$CARE_CARD"
require_file "$POWER_CARD"
command -v jq >/dev/null 2>&1 || fail 'jq is required'

# Numeric threshold ranges are a generic TLP contract. Plugin identity is only
# diagnostic text and must not govern whether Quickshell can expose the control.
range_root="$TMP/range-power"
make_battery "$range_root" BAT0 75 80
cat >"$TMP/tlp-range" <<'EOF_TLP_RANGE'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: future-vendor
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 50..95(default)
* STOP_CHARGE_THRESH_BAT0/1: 55..100(default)
EOF_STATUS
EOF_TLP_RANGE
chmod +x "$TMP/tlp-range"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$range_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-range" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == true and .writable == true and .backend == "tlp"' \
    'numeric TLP range was not detected as writable'
assert_json "$json" '.plugin == "future-vendor" and .mode == "range"' \
    'generic TLP range was classified using plugin policy'
assert_json "$json" '.start_min == 50 and .start_max == 95 and .stop_min == 55 and .stop_max == 100' \
    'generic threshold ranges were not parsed'
assert_json "$json" '.batteries[0].name == "BAT0" and .batteries[0].start_threshold == 75 and .batteries[0].stop_threshold == 80' \
    'current standard kernel threshold telemetry was not retained'

# Literal percentage presets are generic too. No LG-specific mode is needed.
preset_root="$TMP/preset-power"
make_battery "$preset_root" BAT0 '' 80
cat >"$TMP/tlp-presets" <<'EOF_TLP_PRESETS'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: another-future-vendor
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0: 80, 100(default)
EOF_STATUS
EOF_TLP_PRESETS
chmod +x "$TMP/tlp-presets"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$preset_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-presets" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == true and .writable == true and .mode == "presets"' \
    'numeric TLP presets were not exposed generically'
assert_json "$json" '.stop_presets == [80,100]' 'generic stop presets were not parsed'

# 0/1 charge-type selectors are not percentages. Awtarchy deliberately does not
# translate those vendor semantics; TLPUI remains the advanced configuration UI.
selector_root="$TMP/selector-power"
make_battery "$selector_root" BAT0
cat >"$TMP/tlp-selector" <<'EOF_TLP_SELECTOR'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: selector-vendor
Supported features: charge type
Parameter value range:
* STOP_CHARGE_THRESH_BAT0/1: 0(Standard)..1(Long_Life) -- charge type
EOF_STATUS
EOF_TLP_SELECTOR
chmod +x "$TMP/tlp-selector"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$selector_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-selector" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == true and .writable == false and .backend == "tlp" and .mode == "unsupported"' \
    '0/1 selector mode was misrepresented as a percentage control'
assert_json "$json" '.stop_presets == [] and .stop_min == null and .stop_max == null' \
    'selector values leaked into percentage controls'

# A battery exposing sysfs thresholds is useful telemetry, but Awtarchy no longer
# declares hardware writable without TLP's authoritative capability report.
sysfs_root="$TMP/sysfs-power"
make_battery "$sysfs_root" BAT1 70 85
json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$sysfs_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/does-not-exist" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == false and .writable == false and .backend == "none" and .mode == "unsupported"' \
    'sysfs presence bypassed TLP authority'
assert_json "$json" '.batteries[0].name == "BAT1" and .batteries[0].stop_threshold == 85' \
    'read-only kernel threshold telemetry disappeared'

unsupported_root="$TMP/unsupported-power"
make_battery "$unsupported_root" BAT0
cat >"$TMP/tlp-unsupported" <<'EOF_TLP_UNSUPPORTED'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: generic
Supported features: none available
EOF_STATUS
EOF_TLP_UNSUPPORTED
chmod +x "$TMP/tlp-unsupported"
json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$unsupported_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-unsupported" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == false and .writable == false and .backend == "none" and .mode == "unsupported"' \
    'TLP without battery-care capability was incorrectly exposed'

# Capability detection remains unprivileged and read-only. QML consumes the
# normalized status while mutations remain behind the root-owned helper.
require_source "$SCRIPT" 'AWTARCHY_POWER_SUPPLY_ROOT'
require_source "$SCRIPT" 'AWTARCHY_TLP_STAT_BIN'
require_source "$CARE_CARD" 'quickshell_battery_care.sh'
require_source "$CARE_CARD" 'id: batteryCareReader'
require_source "$CARE_CARD" 'JSON.parse(text.trim() || "{}")'
require_source "$CARE_CARD" 'text: "Battery Health"'
require_source "$CARE_CARD" 'text: "Battery Care"'
require_source "$POWER_CARD" 'BatteryCareCard {'

if grep -Eq '(^|[[:space:]])(pkexec)([[:space:]]|$)' "$SCRIPT" \
    || grep -Fq 'tlp setcharge' "$SCRIPT" \
    || grep -Eq '>[[:space:]]*"?[^"[:space:]]*/charge_control_(start|end)_threshold' "$SCRIPT"; then
    fail 'battery capability detector contains a privileged/direct charge-write path'
fi

printf '%s\n' 'Battery charge-limit capability detection regression tests passed.'
