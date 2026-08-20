#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
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

command -v jq >/dev/null 2>&1 || fail 'jq is required'
[[ -f "$SCRIPT" ]] || fail 'battery care detector is missing'

power_root="$TMP/power"
sony_path="$TMP/sony-laptop/battery_care_limiter"
mkdir -p "$power_root/BAT0" "$(dirname "$sony_path")"
printf '%s\n' Battery >"$power_root/BAT0/type"
printf '%s\n' 'Sony Corp.' >"$power_root/BAT0/manufacturer"
printf '%s\n' VAIO >"$power_root/BAT0/model_name"

cat >"$TMP/tlp-stat" <<'EOF_TLP'
#!/usr/bin/env bash
# Real TLP 1.10 documents `tlp-stat -b` as a root command. Simulate the
# unprivileged Quickshell reader receiving no battery-care report.
exit 1
EOF_TLP
chmod 0755 "$TMP/tlp-stat"

run_detector() {
    AWTARCHY_POWER_SUPPLY_ROOT="$power_root" \
    AWTARCHY_TLP_STAT_BIN="$TMP/tlp-stat" \
    AWTARCHY_SONY_BATTERY_CARE_PATH="$sony_path" \
        bash "$SCRIPT" --status-json
}

# sony_laptop reports 0 when the limiter is disabled, which means full 100%
# charging is allowed. Supported targets are fixed at 50, 80 and 100(off).
printf '%s\n' 0 >"$sony_path"
json="$(run_detector)"
assert_json "$json" '.supported == true and .backend == "tlp" and .plugin == "sony"' \
    'Sony capability disappeared when tlp-stat required root'
assert_json "$json" '.mode == "presets" and .stop_presets == [50,80,100]' \
    'Sony fixed presets were not exposed correctly'
assert_json "$json" '.target == 100 and .enabled == false' \
    'Sony disabled limiter was not translated to full charging'

printf '%s\n' 80 >"$sony_path"
json="$(run_detector)"
assert_json "$json" '.target == 80 and .enabled == true' \
    'Sony active 80 percent limiter was not read back'

printf '%s\n' 'Sony unprivileged battery-care detection regression test passed.'
