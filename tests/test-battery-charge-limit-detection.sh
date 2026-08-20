#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
CARE_CARD="${ROOT}/config/quickshell/awtarchy/BatteryCareCard.qml"
POWER_CARD="${ROOT}/config/quickshell/awtarchy/PowerModeCard.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

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

# Range-capable hardware: TLP is authoritative for vendor-specific writable ranges,
# while current values are read from the kernel power-supply attributes.
range_root="$TMP/range-power"
make_battery "$range_root" BAT0 75 80
cat >"$TMP/tlp-range" <<'EOF_TLP_RANGE'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: dell
Supported features: charge thresholds
Driver usage:
* natacpi (dell_laptop) = active (charge thresholds)
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
assert_json "$json" '.supported == true' 'range hardware was not detected as supported'
assert_json "$json" '.backend == "tlp"' 'TLP backend was not selected'
assert_json "$json" '.plugin == "dell"' 'TLP plugin was not parsed'
assert_json "$json" '.mode == "range"' 'range mode was not classified'
assert_json "$json" '.start_min == 50 and .start_max == 95' 'start threshold range was not parsed'
assert_json "$json" '.stop_min == 55 and .stop_max == 100' 'stop threshold range was not parsed'
assert_json "$json" '.batteries[0].name == "BAT0" and .batteries[0].start_threshold == 75 and .batteries[0].stop_threshold == 80' \
    'current BAT0 thresholds were not read'

# Fixed hardware with literal percentage presets can expose those presets safely.
fixed_root="$TMP/fixed-power"
make_battery "$fixed_root" BAT0 '' 80
cat >"$TMP/tlp-fixed" <<'EOF_TLP_FIXED'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: lg
Supported features: charge threshold
Driver usage:
* natacpi (lg_laptop) = active (charge threshold)
Parameter value range:
* STOP_CHARGE_THRESH_BAT0: 80(on), 100(off)
EOF_STATUS
EOF_TLP_FIXED
chmod +x "$TMP/tlp-fixed"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$fixed_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-fixed" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == true and .backend == "tlp" and .plugin == "lg"' \
    'fixed hardware TLP capability was not detected'
assert_json "$json" '.mode == "fixed"' 'fixed hardware was not classified as fixed'
assert_json "$json" '.stop_presets == [80,100]' 'fixed stop presets were not parsed'
assert_json "$json" '.batteries[0].stop_threshold == 80' 'fixed current stop threshold was not read'

# Lenovo conservation mode uses 0/1 mode selectors rather than percentages. Newer
# TLP reports this as "charge type". It is supported, but the actual fixed limit
# varies by model and must not be presented as 0%/1%.
lenovo_root="$TMP/lenovo-power"
make_battery "$lenovo_root" BAT0
cat >"$TMP/tlp-lenovo" <<'EOF_TLP_LENOVO'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: lenovo
Supported features: charge type
Driver usage:
* vendor (ideapad_laptop) = active (charge type)
Parameter value range:
* STOP_CHARGE_THRESH_BAT0/1: 0(Standard)..1(Long_Life) -- charge type
EOF_STATUS
EOF_TLP_LENOVO
chmod +x "$TMP/tlp-lenovo"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$lenovo_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-lenovo" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == true and .backend == "tlp" and .plugin == "lenovo" and .mode == "fixed"' \
    'Lenovo charge-type conservation mode was not detected'
assert_json "$json" '.stop_presets == [] and .stop_min == null and .stop_max == null' \
    'Lenovo 0/1 mode selectors were misreported as charge percentages'

# Samsung also uses 0/1 control values, but TLP documents the actual battery-life
# extender target as 80%, so Stage 3 may safely advertise 80%/100% choices.
samsung_root="$TMP/samsung-power"
make_battery "$samsung_root" BAT0
cat >"$TMP/tlp-samsung" <<'EOF_TLP_SAMSUNG'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: samsung
Supported features: charge threshold
Driver usage:
* vendor (samsung_laptop) = active (charge threshold)
Parameter value range:
* STOP_CHARGE_THRESH_BAT0: 0(off), 1(on) -- battery life extender
EOF_STATUS
EOF_TLP_SAMSUNG
chmod +x "$TMP/tlp-samsung"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$samsung_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-samsung" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == true and .backend == "tlp" and .plugin == "samsung" and .mode == "fixed"' \
    'Samsung battery-life extender was not detected'
assert_json "$json" '.stop_presets == [80,100]' \
    'Samsung 0/1 selectors were not translated to documented 80%/100% targets'

# If TLP is absent, standardized kernel threshold files still provide useful
# read-only capability/current-value reporting without guessing the writable range.
sysfs_root="$TMP/sysfs-power"
make_battery "$sysfs_root" BAT1 70 85
json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$sysfs_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/does-not-exist" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == true and .backend == "sysfs" and .mode == "sysfs"' \
    'standard sysfs fallback was not detected'
assert_json "$json" '.batteries[0].name == "BAT1" and .batteries[0].stop_threshold == 85' \
    'sysfs fallback did not report the current threshold'

# No exposed threshold interface means unsupported. Stage 3 must not claim a
# control exists merely because a battery exists.
unsupported_root="$TMP/unsupported-power"
make_battery "$unsupported_root" BAT0
json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$unsupported_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/does-not-exist" \
    bash "$SCRIPT" --status-json
)"
assert_json "$json" '.supported == false and .backend == "none" and .mode == "unsupported"' \
    'unsupported hardware was incorrectly advertised as charge-limit capable'

# Stage 3 remains read-only and the Battery flyout consumes the detector through
# a focused component hosted next to the existing Power Mode controls.
require_source "$SCRIPT" 'AWTARCHY_POWER_SUPPLY_ROOT'
require_source "$SCRIPT" 'AWTARCHY_TLP_STAT_BIN'
require_source "$CARE_CARD" 'quickshell_battery_care.sh'
require_source "$CARE_CARD" 'id: batteryCareReader'
require_source "$CARE_CARD" 'JSON.parse(text.trim() || "{}")'
require_source "$CARE_CARD" 'text: "Battery Health"'
require_source "$CARE_CARD" 'Read-only detection'
require_source "$POWER_CARD" 'BatteryCareCard {'

if grep -Eq '(^|[[:space:]])sudo([[:space:]]|$)|tlp[[:space:]]+setcharge|charge_control_(start|end)_threshold[^\n]*>' "$SCRIPT"; then
    fail 'Stage 3 detector contains a privileged or threshold-write path'
fi

printf '%s\n' 'Battery charge-limit capability detection regression tests passed.'
