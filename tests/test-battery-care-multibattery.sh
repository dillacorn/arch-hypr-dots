#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "$HELPER" ]] || fail 'power-profile-helper is missing'

TEST_HELPER="$TMP/power-profile-helper"
FAKE_BIN="$TMP/bin"
CONF_DIR="$TMP/tlp.d"
USER_CONF="$TMP/tlp.conf"
LOG="$TMP/tlp.log"
mkdir -p -- "$FAKE_BIN" "$CONF_DIR"
: >"$USER_CONF"
: >"$LOG"
cp -- "$HELPER" "$TEST_HELPER"
chmod 0755 "$TEST_HELPER"

python3 - "$TEST_HELPER" "$FAKE_BIN/tlp" "$FAKE_BIN/tlp-stat" "$CONF_DIR" "$USER_CONF" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace('TLP="/usr/bin/tlp"', f'TLP="{sys.argv[2]}"')
text = text.replace('TLP_STAT="/usr/bin/tlp-stat"', f'TLP_STAT="{sys.argv[3]}"')
text = text.replace('CONFIG_DIR="/etc/tlp.d"', f'CONFIG_DIR="{sys.argv[4]}"')
text = text.replace('USER_CONFIG="/etc/tlp.conf"', f'USER_CONFIG="{sys.argv[5]}"')
text = text.replace("(( EUID == 0 )) || fail 'must run as root'", ': # test copy: root check bypassed')
path.write_text(text)
PY

cat >"$FAKE_BIN/tlp-stat" <<'FAKE_STAT'
#!/usr/bin/env bash
set -euo pipefail
cat <<'EOF'
+++ Battery Care
Plugin: dell
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 50..95(default)
* STOP_CHARGE_THRESH_BAT0/1: 55..100(default)
+++ ThinkPad Battery Status: BAT0
/sys/class/power_supply/BAT0/charge_control_end_threshold = 100 [%]
+++ ThinkPad Battery Status: BAT1
/sys/class/power_supply/BAT1/charge_control_end_threshold = 100 [%]
EOF
FAKE_STAT
chmod 0755 "$FAKE_BIN/tlp-stat"

cat >"$FAKE_BIN/tlp" <<'FAKE_TLP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_LOG:?}"
[[ ${1:-} == fullcharge ]] || exit 64
FAKE_TLP
chmod 0755 "$FAKE_BIN/tlp"

AWTARCHY_TEST_LOG="$LOG" "$TEST_HELPER" battery-disable

grep -Fxq 'fullcharge BAT0' "$LOG" || fail 'battery-disable did not restore BAT0 full charge'
grep -Fxq 'fullcharge BAT1' "$LOG" || fail 'battery-disable did not restore BAT1 full charge'
[[ "$(grep -Fc 'fullcharge' "$LOG")" -eq 2 ]] \
  || fail 'battery-disable issued an unexpected number of fullcharge operations'

printf '%s\n' 'Battery multi-battery full-charge regression test passed.'
