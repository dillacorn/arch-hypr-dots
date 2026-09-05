#!/usr/bin/env bash
# shellcheck disable=SC1090
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

FAKE_BIN="$TMP/bin"
CONF_DIR="$TMP/tlp.d"
USER_CONF="$TMP/tlp.conf"
STATE="$TMP/state"
BACKUP="$TMP/previous.conf"
mkdir -p -- "$FAKE_BIN" "$CONF_DIR"
: >"$USER_CONF"
printf '%s\n' 77 >"$STATE"

TEST_HELPER="$TMP/power-profile-helper"
sed '/^main "\$@"$/d' "$HELPER" >"$TEST_HELPER"
python3 - "$TEST_HELPER" "$FAKE_BIN/tlp" "$FAKE_BIN/tlp-stat" "$CONF_DIR" "$USER_CONF" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace('TLP="/usr/bin/tlp"', f'TLP="{sys.argv[2]}"')
text = text.replace('TLP_STAT="/usr/bin/tlp-stat"', f'TLP_STAT="{sys.argv[3]}"')
text = text.replace('CONFIG_DIR="/etc/tlp.d"', f'CONFIG_DIR="{sys.argv[4]}"')
text = text.replace('USER_CONFIG="/etc/tlp.conf"', f'USER_CONFIG="{sys.argv[5]}"')
path.write_text(text)
PY
source "$TEST_HELPER"

cat >"$FAKE_BIN/tlp-stat" <<'EOF_STAT'
#!/usr/bin/env bash
set -euo pipefail
target="$(cat "${AWTARCHY_TEST_STATE:?}")"
cat <<EOF
+++ Battery Care
Plugin: dell
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 50..95(default)
* STOP_CHARGE_THRESH_BAT0/1: 55..100(default)
+++ Battery Status: BAT0
/sys/class/power_supply/BAT0/charge_control_end_threshold = ${target} [%]
EOF
EOF_STAT
chmod 0755 "$FAKE_BIN/tlp-stat"

cat >"$FAKE_BIN/tlp" <<'EOF_TLP'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  start)
    if [[ ${AWTARCHY_STALE_ROLLBACK:-0} != 1 ]]; then
      target="$(sed -n -E 's/^# target=([0-9]+)$/\1/p' "${AWTARCHY_TEST_CONFIG:?}" | head -n1)"
      [[ -n "$target" ]] && printf '%s\n' "$target" >"${AWTARCHY_TEST_STATE:?}"
    fi
    ;;
  fullcharge)
    if [[ ${AWTARCHY_STALE_ROLLBACK:-0} != 1 ]]; then
      printf '%s\n' 100 >"${AWTARCHY_TEST_STATE:?}"
    fi
    ;;
  *) exit 64 ;;
esac
EOF_TLP
chmod 0755 "$FAKE_BIN/tlp"

cat >"$BACKUP" <<'EOF_BACKUP'
# Managed by Awtarchy Battery flyout.
# target=80
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
START_CHARGE_THRESH_BAT1=75
STOP_CHARGE_THRESH_BAT1=80
EOF_BACKUP

export AWTARCHY_TEST_STATE="$STATE"
export AWTARCHY_TEST_CONFIG="$CONF_DIR/00-awtarchy-battery-care.conf"

# A successful command return is insufficient: TLP vendor apply loops may return
# success even when hardware did not reach the restored threshold. Rollback must
# verify the actual state before claiming success.
printf '%s\n' 77 >"$STATE"
if AWTARCHY_STALE_ROLLBACK=1 rollback_apply present "$BACKUP" dell; then
  fail 'rollback accepted a stale 77% hardware state after restoring an 80% config'
fi
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$CONF_DIR/00-awtarchy-battery-care.conf" \
  || fail 'rollback did not restore the previous managed configuration before verification'

# The same rule applies when the prior state was no managed limit: fullcharge may
# return success while hardware remains limited.
rm -f -- "$CONF_DIR/00-awtarchy-battery-care.conf"
printf '%s\n' 80 >"$STATE"
if AWTARCHY_STALE_ROLLBACK=1 rollback_apply absent "$TMP/no-backup" dell; then
  fail 'rollback accepted a stale 80% hardware state after full-charge recovery'
fi

# Positive controls: when readback agrees, both restoration paths must succeed.
printf '%s\n' 77 >"$STATE"
rollback_apply present "$BACKUP" dell \
  || fail 'verified restoration of the previous 80% limit was rejected'
grep -Fxq '80' "$STATE" || fail 'previous 80% hardware state was not restored'

rm -f -- "$CONF_DIR/00-awtarchy-battery-care.conf"
printf '%s\n' 80 >"$STATE"
rollback_apply absent "$TMP/no-backup" dell \
  || fail 'verified restoration to full charge was rejected'
grep -Fxq '100' "$STATE" || fail 'full-charge hardware state was not restored'

printf '%s\n' 'PASS: battery rollback claims require hardware read-back verification.'
