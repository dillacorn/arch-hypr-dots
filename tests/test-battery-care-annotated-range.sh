#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
DETECTOR="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "$HELPER" ]] || fail 'power-profile-helper is missing'
[[ -f "$DETECTOR" ]] || fail 'battery care detector is missing'
command -v jq >/dev/null 2>&1 || fail 'jq is required'

TEST_HELPER="$TMP/power-profile-helper"
FAKE_TLP="$TMP/tlp"
FAKE_STAT="$TMP/tlp-stat"
CONF_DIR="$TMP/tlp.d"
USER_CONF="$TMP/tlp.conf"
STATE="$TMP/state"
mkdir -p -- "$CONF_DIR"
: >"$USER_CONF"
printf '%s\n' 'target=100' 'start=0' >"$STATE"
cp -- "$HELPER" "$TEST_HELPER"

python3 - "$TEST_HELPER" "$FAKE_TLP" "$FAKE_STAT" "$CONF_DIR" "$USER_CONF" "$(id -u)" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('TLP="/usr/bin/tlp"', f'TLP="{sys.argv[2]}"')
s = s.replace('TLP_STAT="/usr/bin/tlp-stat"', f'TLP_STAT="{sys.argv[3]}"')
s = s.replace('CONFIG_DIR="/etc/tlp.d"', f'CONFIG_DIR="{sys.argv[4]}"')
s = s.replace('USER_CONFIG="/etc/tlp.conf"', f'USER_CONFIG="{sys.argv[5]}"')
s = s.replace("(( EUID == 0 )) || fail 'must run as root'", ': # test copy: root check bypassed')
s = s.replace('[[ "$dir_owner" == 0 && "$dir_mode" =~ ^[0-7]{3,4}$ ]]',
              f'[[ "$dir_owner" == {sys.argv[6]} && "$dir_mode" =~ ^[0-7]{{3,4}}$ ]]')
p.write_text(s)
PY
chmod 0755 "$TEST_HELPER"

cat >"$FAKE_STAT" <<'FAKE_STAT_EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_STATE:?}"
cat <<EOF
+++ Battery Care
Plugin: arbitrary-range
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0/1: 0(off)..100(default)
/sys/class/power_supply/BAT0/charge_control_end_threshold = ${target} [%]
EOF
FAKE_STAT_EOF
chmod 0755 "$FAKE_STAT"

cat >"$FAKE_TLP" <<'FAKE_TLP_EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_STATE:?}"
config=${AWTARCHY_TEST_CONFIG:?}
case "${1:-}" in
  setcharge)
    target="$(awk -F= '/^STOP_CHARGE_THRESH_BAT0=/{print $2; exit}' "$config")"
    start="$(awk -F= '/^START_CHARGE_THRESH_BAT0=/{print $2; exit}' "$config")"
    ;;
  fullcharge)
    target=100
    start=0
    ;;
  *) exit 64 ;;
esac
printf 'target=%q\nstart=%q\n' "$target" "$start" >"${AWTARCHY_TEST_STATE}"
FAKE_TLP_EOF
chmod 0755 "$FAKE_TLP"

AWTARCHY_TEST_STATE="$STATE" \
AWTARCHY_TEST_CONFIG="$CONF_DIR/00-awtarchy-battery-care.conf" \
  "$TEST_HELPER" battery-set 80

grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$CONF_DIR/00-awtarchy-battery-care.conf" \
  || fail 'stop-only hardware did not use dummy start threshold'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$CONF_DIR/00-awtarchy-battery-care.conf" \
  || fail 'annotated range rejected an in-range 80% target'

POWER_ROOT="$TMP/power"
mkdir -p -- "$POWER_ROOT/BAT0"
printf '%s\n' Battery >"$POWER_ROOT/BAT0/type"
printf '%s\n' 80 >"$POWER_ROOT/BAT0/charge_control_end_threshold"

json="$(
  AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
  AWTARCHY_TLP_STAT_BIN="$FAKE_STAT" \
  AWTARCHY_TLP_CONFIG_DIR="$CONF_DIR" \
  AWTARCHY_TLP_USER_CONFIG="$USER_CONF" \
  AWTARCHY_TEST_STATE="$STATE" \
    bash "$DETECTOR" --status-json
)"
jq -e '.backend == "tlp" and .mode == "range" and .stop_min == 0 and .stop_max == 100' \
  <<<"$json" >/dev/null \
  || fail "detector did not classify annotated range correctly: $json"

# An annotated intermediate default must not truncate the full numeric span.
cat >"$FAKE_STAT" <<'FAKE_ANNOTATED_EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'EOF'
+++ Battery Care
Plugin: another-arbitrary-range
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 0(off)..96(default)..99
* STOP_CHARGE_THRESH_BAT0/1: 1..100(default)
/sys/class/power_supply/BAT0/charge_control_start_threshold = 75 [%]
/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]
EOF
FAKE_ANNOTATED_EOF
chmod 0755 "$FAKE_STAT"

json="$(
  AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
  AWTARCHY_TLP_STAT_BIN="$FAKE_STAT" \
  AWTARCHY_TLP_CONFIG_DIR="$TMP/empty-tlp.d" \
  AWTARCHY_TLP_USER_CONFIG="$USER_CONF" \
    bash "$DETECTOR" --status-json
)"
jq -e '.backend == "tlp" and .mode == "range" and .start_min == 0 and .start_max == 99 and .stop_min == 1 and .stop_max == 100' \
  <<<"$json" >/dev/null \
  || fail "detector truncated annotated range: $json"

printf '%s\n' 'PASS: annotated TLP battery ranges retain their full numeric endpoints.'
