#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "$HELPER" ]] || fail 'power-profile-helper is missing'

TEST_HELPER="$TMP/power-profile-helper"
FAKE_TLP="$TMP/tlp"
FAKE_STAT="$TMP/tlp-stat"
CONF_DIR="$TMP/tlp.d"
USER_CONF="$TMP/tlp.conf"
STATE="$TMP/state"
mkdir -p -- "$CONF_DIR"
: >"$USER_CONF"
printf '%s\n' 'configured=100' 'observed=100' >"$STATE"
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
Plugin: thinkpad
Supported features: charge thresholds, recalibration
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 0(off)..96(default)..99
* STOP_CHARGE_THRESH_BAT0/1: 1..100(default)
/sys/class/power_supply/BAT0/charge_control_start_threshold = 75 [%]
/sys/class/power_supply/BAT0/charge_control_end_threshold = ${observed} [%]
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
  start)
    configured="$(awk -F= '/^STOP_CHARGE_THRESH_BAT0=/{print $2; exit}' "$config")"
    # TLP documents ThinkPad E/L/S/Yoga EC firmware that can report a
    # different value even though the configured threshold works correctly.
    observed=74
    ;;
  fullcharge)
    configured=100
    observed=100
    ;;
  *) exit 64 ;;
esac
printf 'configured=%q\nobserved=%q\n' "$configured" "$observed" >"${AWTARCHY_TEST_STATE}"
FAKE_TLP_EOF
chmod 0755 "$FAKE_TLP"

AWTARCHY_TEST_STATE="$STATE" \
AWTARCHY_TEST_CONFIG="$CONF_DIR/00-awtarchy-battery-care.conf" \
  "$TEST_HELPER" battery-set 80

grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$CONF_DIR/00-awtarchy-battery-care.conf" \
  || fail 'configured ThinkPad target was not persisted'
grep -Fxq 'configured=80' "$STATE" \
  || fail 'fake TLP did not receive the configured ThinkPad target'
grep -Fxq 'observed=74' "$STATE" \
  || fail 'fixture did not simulate the documented ThinkPad read-back mismatch'

printf '%s\n' 'PASS: ThinkPad firmware read-back mismatch does not falsely roll back an active configured limit.'
