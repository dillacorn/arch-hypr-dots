#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
DETECTOR="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
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
}

extract_writable_plugins() {
    local file="$1" body line
    body="$(sed -n '/^battery_plugin_writable() {/,/^}/p' "$file")"
    [[ -n "$body" ]] || fail "${file#"$ROOT"/} has no battery_plugin_writable policy"
    line="$(sed -n -E 's/^[[:space:]]*([a-z0-9|-]+)\)[[:space:]]+return 0.*$/\1/p' <<<"$body" | head -n1)"
    [[ -n "$line" ]] || fail "${file#"$ROOT"/} writable plugin policy could not be parsed"
    tr '|' '\n' <<<"$line" | sed '/^$/d' | LC_ALL=C sort
}

expected_plugins="$(cat <<'EOF_EXPECTED'
asus
cros-ec
dell
huawei
lenovo
lenovo-legacy
lg
macbook
msi
samsung
sony
system76
thinkpad
thinkpad-legacy
toshiba
tuxedo
wilco-ec
EOF_EXPECTED
)"

command -v jq >/dev/null 2>&1 || fail 'jq is required'
[[ -f "$DETECTOR" ]] || fail 'battery detector is missing'
[[ -f "$HELPER" ]] || fail 'battery helper is missing'

actual_detector="$(extract_writable_plugins "$DETECTOR")"
actual_helper="$(extract_writable_plugins "$HELPER")"
[[ "$actual_detector" == "$expected_plugins" ]] \
    || fail "detector writable plugin set differs from expected current TLP compatibility set"
[[ "$actual_helper" == "$expected_plugins" ]] \
    || fail "helper writable plugin set differs from expected current TLP compatibility set"
[[ "$actual_detector" == "$actual_helper" ]] \
    || fail 'detector/helper writable plugin sets disagree'
! grep -qx 'lg-legacy' <<<"$actual_detector" || fail 'obsolete lg-legacy plugin is still writable'
! grep -qx 'generic' <<<"$actual_detector" || fail 'generic plugin is writable'

power_root="$TMP/power"
make_battery "$power_root" BAT0 75 80

cat >"$TMP/tlp-dell" <<'EOF_TLP_DELL'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: dell
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 50..95(default)
* STOP_CHARGE_THRESH_BAT0/1: 55..100(default)
/sys/class/power_supply/BAT0/charge_control_start_threshold = 75 [%]
/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]
EOF_STATUS
EOF_TLP_DELL
chmod 0755 "$TMP/tlp-dell"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$power_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-dell" \
    bash "$DETECTOR" --status-json
)"
assert_json "$json" '.supported == true and .writable == true and .compatibility == "validated" and .plugin == "dell"' \
    'validated Dell backend was not marked writable'

cat >"$TMP/tlp-unknown" <<'EOF_TLP_UNKNOWN'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: future-vendor
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0: 50..100(default)
/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]
EOF_STATUS
EOF_TLP_UNKNOWN
chmod 0755 "$TMP/tlp-unknown"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$power_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-unknown" \
    bash "$DETECTOR" --status-json
)"
assert_json "$json" '.supported == true and .writable == false and .compatibility == "unvalidated" and .backend == "tlp" and .plugin == "future-vendor"' \
    'unknown TLP backend did not fail closed'

cat >"$TMP/tlp-generic" <<'EOF_TLP_GENERIC'
#!/usr/bin/env bash
cat <<'EOF_STATUS'
+++ Battery Care
Plugin: generic
Supported features: none available
EOF_STATUS
EOF_TLP_GENERIC
chmod 0755 "$TMP/tlp-generic"

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$power_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-generic" \
    bash "$DETECTOR" --status-json
)"
assert_json "$json" '.supported == false and .writable == false and .compatibility == "unsupported" and .plugin == "generic"' \
    'generic TLP backend was not kept unsupported/non-writable'

json="$(
    AWTARCHY_POWER_SUPPLY_ROOT="$power_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/does-not-exist" \
    bash "$DETECTOR" --status-json
)"
assert_json "$json" '.supported == true and .writable == false and .compatibility == "unvalidated" and .backend == "sysfs"' \
    'sysfs-only threshold reporting was not kept read-only/unvalidated'

printf '%s\n' 'PASS: TLP battery compatibility policy is explicit and fail-closed.'
