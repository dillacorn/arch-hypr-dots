#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

TEST_HELPER="$TMP/power-profile-helper"
FAKE_BIN="$TMP/bin"
CONF_DIR="$TMP/tlp.d"
USER_CONF="$TMP/tlp.conf"
STATE="$TMP/state"
LOG="$TMP/tlp.log"
mkdir -p -- "$FAKE_BIN" "$CONF_DIR"
cp -- "$HELPER" "$TEST_HELPER"
chmod 0755 "$TEST_HELPER"
: >"$USER_CONF"
: >"$LOG"

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
text = text.replace(
    '  battery_require_config_path_safe\n\n  temporary=',
    '  : # test copy: config path safety bypassed\n\n  temporary='
)
path.write_text(text)
PY

cat >"$FAKE_BIN/tlp-stat" <<'FAKE_STAT'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_STATE:?}"
case "$plugin" in
  lg)
    cat <<EOF
+++ Battery Care
Plugin: lg
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0: 80(on), 100(off)
/sys/class/power_supply/BAT0/charge_control_end_threshold = ${target} [%]
EOF
    ;;
  lenovo)
    cat <<EOF
+++ Battery Care
Plugin: lenovo
Supported features: charge type
Parameter value range:
* STOP_CHARGE_THRESH_BAT0/1: 0(Standard)..1(Long_Life) -- charge type
/sys/class/power_supply/BAT0/charge_types = $([[ $enabled == 1 ]] && printf 'Standard [Long_Life]' || printf '[Standard] Long_Life')
EOF
    ;;
  tuxedo)
    cat <<EOF
+++ Battery Care
Plugin: tuxedo
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 40/50/60/70/80/95(default)
* STOP_CHARGE_THRESH_BAT0/1: 60/70/80/90/100(default)
/sys/class/power_supply/BAT0/charge_control_start_threshold = ${start} [%]
/sys/class/power_supply/BAT0/charge_control_end_threshold = ${target} [%]
EOF
    ;;
  *) exit 64 ;;
esac
FAKE_STAT
chmod 0755 "$FAKE_BIN/tlp-stat"

cat >"$FAKE_BIN/tlp" <<'FAKE_TLP'
#!/usr/bin/env bash
set -euo pipefail
state=${AWTARCHY_TEST_STATE:?}
log=${AWTARCHY_TEST_LOG:?}
config=${AWTARCHY_TEST_CONFIG:?}
printf '%s\n' "$*" >>"$log"
# shellcheck disable=SC1090
source "$state"
case "${1:-}" in
  start)
    [[ -f "$config" ]] || exit 1
    stop="$(awk -F= '/^STOP_CHARGE_THRESH_BAT0=/{print $2; exit}' "$config")"
    start_value="$(awk -F= '/^START_CHARGE_THRESH_BAT0=/{print $2; exit}' "$config")"
    case "$plugin" in
      lg)
        [[ "$stop" == 80 || "$stop" == 100 ]] || exit 2
        target="$stop"
        enabled=$([[ "$target" -lt 100 ]] && printf 1 || printf 0)
        start=0
        ;;
      lenovo)
        [[ "$stop" == 0 || "$stop" == 1 ]] || exit 2
        enabled="$stop"
        target=100
        start=0
        ;;
      tuxedo)
        case "$stop" in 60|70|80|90|100) ;; *) exit 2 ;; esac
        case "$start_value" in 40|50|60|70|80|95) ;; *) exit 2 ;; esac
        (( start_value < stop )) || exit 3
        target="$stop"
        start="$start_value"
        enabled=$([[ "$target" -lt 100 ]] && printf 1 || printf 0)
        ;;
    esac
    ;;
  fullcharge)
    target=100
    enabled=0
    start=95
    ;;
  *) exit 64 ;;
esac
{
  printf 'plugin=%q\n' "$plugin"
  printf 'target=%q\n' "$target"
  printf 'enabled=%q\n' "$enabled"
  printf 'start=%q\n' "$start"
} >"$state"
FAKE_TLP
chmod 0755 "$FAKE_BIN/tlp"

run_helper() {
    AWTARCHY_TEST_STATE="$STATE" \
    AWTARCHY_TEST_LOG="$LOG" \
    AWTARCHY_TEST_CONFIG="$CONF_DIR/00-awtarchy-battery-care.conf" \
        "$TEST_HELPER" "$@"
}

MANAGED="$CONF_DIR/00-awtarchy-battery-care.conf"

printf '%s\n' 'plugin=lg' 'target=100' 'enabled=0' 'start=0' >"$STATE"
if ! run_helper battery-set 80 >"$TMP/lg.out" 2>"$TMP/lg.err"; then
    cat "$TMP/lg.err" >&2
    fail 'current TLP LG 80% semantics were rejected'
fi
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" \
    || fail 'LG 80% target was not persisted as literal 80'

printf '%s\n' 'plugin=lenovo' 'target=100' 'enabled=0' 'start=0' >"$STATE"
rm -f -- "$MANAGED"
run_helper battery-enable-fixed
grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$MANAGED" || fail 'Lenovo BAT0 start selector missing'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=1' "$MANAGED" || fail 'Lenovo BAT0 Long_Life selector missing'
grep -Fxq 'START_CHARGE_THRESH_BAT1=0' "$MANAGED" || fail 'Lenovo BAT1 start selector missing'
grep -Fxq 'STOP_CHARGE_THRESH_BAT1=1' "$MANAGED" || fail 'Lenovo BAT1 Long_Life selector missing'

printf '%s\n' 'plugin=tuxedo' 'target=100' 'enabled=0' 'start=95' >"$STATE"
rm -f -- "$MANAGED"
run_helper battery-set 80
grep -Fxq 'START_CHARGE_THRESH_BAT0=70' "$MANAGED" || fail 'Tuxedo BAT0 supported start target missing'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'Tuxedo BAT0 stop target missing'
grep -Fxq 'START_CHARGE_THRESH_BAT1=70' "$MANAGED" || fail 'Tuxedo BAT1 supported start target missing'
grep -Fxq 'STOP_CHARGE_THRESH_BAT1=80' "$MANAGED" || fail 'Tuxedo BAT1 stop target missing'

printf '%s\n' 'PASS: current TLP vendor write semantics are preserved.'
