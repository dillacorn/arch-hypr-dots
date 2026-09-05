#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
DETECTOR="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
CARD="${ROOT}/config/quickshell/awtarchy/BatteryCareCard.qml"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
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
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

require_absent() {
  local file="$1" needle="$2" message="$3"
  ! grep -Fq -- "$needle" "$file" || fail "$message"
}

require_file "$HELPER"
require_file "$DETECTOR"
require_file "$CARD"
require_file "$RUNTIME"

require_source "$HELPER" 'TLP="/usr/bin/tlp"' 'helper does not pin the TLP executable'
require_source "$HELPER" 'TLP_STAT="/usr/bin/tlp-stat"' 'helper does not pin tlp-stat'
require_source "$HELPER" 'CONFIG_DIR="/etc/tlp.d"' 'helper does not pin TLP drop-in directory'
require_source "$HELPER" 'MANAGED_CONFIG="${CONFIG_DIR}/00-awtarchy-battery-care.conf"' 'helper managed config path changed unexpectedly'
require_source "$HELPER" '(( EUID == 0 )) || fail' 'helper does not require root'
require_source "$HELPER" 'Existing user-managed TLP charge thresholds' 'helper does not fail closed on external TLP thresholds'
require_source "$HELPER" 'rollback_apply()' 'helper does not roll back failed hardware application'
require_source "$HELPER" 'verify_enabled_state' 'helper does not read back enabled state'
require_source "$HELPER" 'verify_disabled_state' 'helper does not read back disabled state'
require_absent "$HELPER" 'charge_control_end_threshold" >' 'helper writes battery sysfs directly'
require_absent "$HELPER" 'charge_control_start_threshold" >' 'helper writes battery sysfs directly'

require_source "$CARD" 'batteryCareHelper: "/usr/local/libexec/awtarchy/power-profile-helper"' 'Battery Health UI does not use the installed Power Mode helper'
require_source "$CARD" '"/usr/bin/sudo", "-S", "-p", ""' 'Battery Health UI is missing explicit sudo authorization'
require_source "$CARD" 'property int targetDraft: 80' 'Battery Health UI default target is not 80%'
require_source "$CARD" 'root.pendingAction = "battery-disable"' 'Battery Health UI has no OFF path'
require_source "$CARD" 'root.pendingAction = "battery-enable-fixed"' 'Battery Health UI has no fixed conservation-mode path'
require_source "$CARD" 'root.pendingAction = "battery-set"' 'Battery Health UI has no target-setting path'
require_absent "$CARD" 'charge_control_end_threshold' 'QML writes battery threshold sysfs directly'
require_absent "$CARD" 'tlp setcharge' 'QML bypasses the privileged helper with tlp setcharge'

require_source "$DETECTOR" 'config_conflict' 'detector does not expose external TLP config conflicts'
require_source "$DETECTOR" 'managed_config' 'detector does not expose Awtarchy-managed persistence state'
require_source "$DETECTOR" 'enabled' 'detector does not expose observed charge-limit state'
require_source "$DETECTOR" 'target' 'detector does not expose observed target'

require_source "$RUNTIME" 'repair_v354_sony_battery_disable_repo()' 'runtime has no v3.5.4 Sony battery helper repair'
require_source "$RUNTIME" '[[ "$tag" == "v3.5.4" ]] || return 0' 'v3.5.4 Sony battery repair is not tag scoped'
require_source "$RUNTIME" 'repair_v354_sony_battery_disable_repo "$repo_dir" "$tag"' 'stable update path does not repair the v3.5.4 helper source'
repair_line="$(grep -nF 'repair_v354_sony_battery_disable_repo "$repo_dir" "$tag"' "$RUNTIME" | tail -n1 | cut -d: -f1)"
reconcile_line="$(grep -nF 'reconcile_power_profile_backend "$repo_dir"' "$RUNTIME" | tail -n1 | cut -d: -f1)"
[[ "$repair_line" =~ ^[0-9]+$ && "$reconcile_line" =~ ^[0-9]+$ && "$repair_line" -lt "$reconcile_line" ]] \
  || fail 'v3.5.4 Sony battery repair does not run before the release helper is reconciled'

TEST_HELPER="$TMP/power-profile-helper"
cp -- "$HELPER" "$TEST_HELPER"
chmod 0755 "$TEST_HELPER"
FAKE_BIN="$TMP/bin"
CONF_DIR="$TMP/tlp.d"
USER_CONF="$TMP/tlp.conf"
STATE="$TMP/state"
LOG="$TMP/tlp.log"
mkdir -p -- "$FAKE_BIN" "$CONF_DIR"
: >"$USER_CONF"
printf '%s\n' 'plugin=dell' 'target=100' 'enabled=0' 'start=95' >"$STATE"
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
path.write_text(text)
PY

cat >"$FAKE_BIN/tlp-stat" <<'FAKE_STAT'
#!/usr/bin/env bash
set -euo pipefail
state=${AWTARCHY_TEST_STATE:?}
# shellcheck disable=SC1090
source "$state"
case "$plugin" in
  dell)
    cat <<EOF
+++ Battery Care
Plugin: dell
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 50..95(default)
* STOP_CHARGE_THRESH_BAT0/1: 55..100(default)
/sys/class/power_supply/BAT0/charge_control_start_threshold = ${start} [%]
/sys/class/power_supply/BAT0/charge_control_end_threshold = ${target} [%]
EOF
    ;;
  sony)
    cat <<EOF
+++ Battery Care
Plugin: sony
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0: 50, 80, 100(off) -- battery care limiter
/sys/devices/platform/sony-laptop/battery_care_limiter = ${target} [%]
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
  samsung)
    cat <<EOF
+++ Battery Care
Plugin: samsung
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0: 0(off), 1(on) -- battery life extender
/sys/devices/platform/samsung/battery_life_extender = ${enabled} ($([[ $enabled == 1 ]] && printf '80%%' || printf '100%%'))
EOF
    ;;
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
    if [[ -f "$config" ]]; then
      stop="$(awk -F= '/^STOP_CHARGE_THRESH_BAT0=/{print $2; exit}' "$config")"
      start_value="$(awk -F= '/^START_CHARGE_THRESH_BAT0=/{print $2; exit}' "$config")"
      case "$plugin" in
        lenovo)
          enabled="$stop"
          ;;
        lg)
          target="$stop"
          enabled=$([[ "$target" -lt 100 ]] && printf 1 || printf 0)
          ;;
        samsung)
          enabled="$stop"
          target=$([[ "$stop" == 1 ]] && printf 80 || printf 100)
          ;;
        *)
          target="$stop"
          start="${start_value:-0}"
          enabled=$([[ "$target" -lt 100 ]] && printf 1 || printf 0)
          ;;
      esac
    fi
    ;;
  fullcharge)
    if [[ "$plugin" == sony ]]; then
      target=0
    else
      target=100
    fi
    enabled=0
    start=95
    ;;
  *) exit 64 ;;
esac
{
  printf 'plugin=%q\n' "$plugin"
  printf 'target=%q\n' "$target"
  printf 'enabled=%q\n' "$enabled"
  printf 'start=%q\n' "${start:-0}"
} >"$state"
FAKE_TLP
chmod 0755 "$FAKE_BIN/tlp"

run_helper() {
  AWTARCHY_TEST_STATE="$STATE" AWTARCHY_TEST_LOG="$LOG" \
  AWTARCHY_TEST_CONFIG="$CONF_DIR/00-awtarchy-battery-care.conf" \
    "$TEST_HELPER" "$@"
}

run_helper battery-set 80
MANAGED="$CONF_DIR/00-awtarchy-battery-care.conf"
grep -Fxq 'START_CHARGE_THRESH_BAT0=75' "$MANAGED" || fail 'Dell start threshold was not derived as target-5'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'Dell stop threshold was not persisted'
grep -Fxq 'START_CHARGE_THRESH_BAT1=75' "$MANAGED" || fail 'Dell BAT1 start threshold was not persisted'
grep -Fxq 'STOP_CHARGE_THRESH_BAT1=80' "$MANAGED" || fail 'Dell BAT1 stop threshold was not persisted'
grep -Fxq 'start' "$LOG" || fail 'TLP start was not used to apply persistent thresholds'

printf '%s\n' 'STOP_CHARGE_THRESH_BAT0=70' >"$CONF_DIR/10-user.conf"
if run_helper battery-set 85 >"$TMP/conflict.out" 2>"$TMP/conflict.err"; then fail 'external TLP thresholds were overwritten'; fi
grep -Fq 'Existing user-managed TLP charge thresholds' "$TMP/conflict.err" || fail 'config conflict was not explained'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'managed threshold changed despite external-config conflict'
rm -f -- "$CONF_DIR/10-user.conf"

if run_helper battery-set 40 >"$TMP/range.out" 2>"$TMP/range.err"; then fail 'out-of-range Dell target was accepted'; fi
grep -Fq 'outside supported stop range' "$TMP/range.err" || fail 'out-of-range error was not specific'

printf '%s\n' 'plugin=sony' 'target=100' 'enabled=0' 'start=0' >"$STATE"
rm -f -- "$MANAGED"
if run_helper battery-set 70 >"$TMP/preset.out" 2>"$TMP/preset.err"; then fail 'unsupported Sony preset was accepted'; fi
run_helper battery-set 80
grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$MANAGED" || fail 'stop-only hardware did not use dummy start threshold'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'Sony 80% preset was not persisted'
: >"$LOG"
run_helper battery-disable
[[ ! -e "$MANAGED" ]] || fail 'Sony disable left Awtarchy threshold persistence behind'
grep -Fxq 'fullcharge' "$LOG" || fail 'Sony disable did not restore the vendor full-charge state'
grep -Fq 'target=0' "$STATE" || fail 'Sony raw limiter 0 was not accepted as the disabled state'

printf '%s\n' 'plugin=tuxedo' 'target=100' 'enabled=0' 'start=95' >"$STATE"
rm -f -- "$MANAGED"
run_helper battery-set 80
grep -Fxq 'START_CHARGE_THRESH_BAT0=70' "$MANAGED" || fail 'Tuxedo supported start threshold was not selected'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'Tuxedo stop preset was not persisted'
grep -Fxq 'START_CHARGE_THRESH_BAT1=70' "$MANAGED" || fail 'Tuxedo BAT1 supported start threshold was not selected'
grep -Fxq 'STOP_CHARGE_THRESH_BAT1=80' "$MANAGED" || fail 'Tuxedo BAT1 stop preset was not persisted'

printf '%s\n' 'plugin=lenovo' 'target=100' 'enabled=0' 'start=0' >"$STATE"
rm -f -- "$MANAGED"
run_helper battery-enable-fixed
grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$MANAGED" || fail 'Lenovo dummy start threshold missing'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=1' "$MANAGED" || fail 'Lenovo Long_Life selector was not persisted'
grep -Fxq 'START_CHARGE_THRESH_BAT1=0' "$MANAGED" || fail 'Lenovo BAT1 dummy start threshold missing'
grep -Fxq 'STOP_CHARGE_THRESH_BAT1=1' "$MANAGED" || fail 'Lenovo BAT1 Long_Life selector was not persisted'
grep -Fq 'enabled=1' "$STATE" || fail 'Lenovo fixed mode was not read back as enabled'

printf '%s\n' 'plugin=lg' 'target=100' 'enabled=0' 'start=0' >"$STATE"
rm -f -- "$MANAGED"
run_helper battery-set 80
grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$MANAGED" || fail 'LG dummy start threshold missing'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'LG 80% target was not persisted literally'
grep -Fq 'target=80' "$STATE" || fail 'LG 80% state was not verified'

printf '%s\n' 'plugin=samsung' 'target=100' 'enabled=0' 'start=0' >"$STATE"
rm -f -- "$MANAGED"
run_helper battery-set 80
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=1' "$MANAGED" || fail 'Samsung 80% target was not translated to extender=1'
grep -Fq 'target=80' "$STATE" || fail 'Samsung 80% state was not verified'

run_helper battery-disable
[[ ! -e "$MANAGED" ]] || fail 'disable left Awtarchy threshold persistence behind'
grep -Fxq 'fullcharge' "$LOG" || fail 'disable did not restore vendor defaults with tlp fullcharge'
grep -Fq 'enabled=0' "$STATE" || fail 'disabled state was not read back'

printf '%s\n' 'plugin=dell' 'target=80' 'enabled=1' 'start=75' >"$STATE"
cat >"$MANAGED" <<'PREVIOUS'
# Managed by Awtarchy Battery flyout.
# target=80
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
START_CHARGE_THRESH_BAT1=75
STOP_CHARGE_THRESH_BAT1=80
PREVIOUS
cp -- "$FAKE_BIN/tlp" "$FAKE_BIN/tlp.good"
python3 - "$FAKE_BIN/tlp" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text().replace('target="$stop"\n          start=', 'target=77\n          start=')
p.write_text(s)
PY
if run_helper battery-set 85 >"$TMP/readback.out" 2>"$TMP/readback.err"; then fail 'helper reported success when hardware readback disagreed'; fi
grep -Fq 'hardware read-back verification failed' "$TMP/readback.err" || fail 'readback failure was not explained'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'previous managed config was not restored after readback failure'

V354_FIXTURE="$TMP/v354-power-profile-helper"
V354_REPO="$TMP/v354-repo"
V353_CONTROL_REPO="$TMP/v353-control-repo"
mkdir -p -- "$V354_REPO/local/libexec/awtarchy" "$V353_CONTROL_REPO/local/libexec/awtarchy"
git -c safe.directory="$ROOT" -C "$ROOT" show \
  v3.5.4:local/libexec/awtarchy/power-profile-helper >"$V354_FIXTURE"
cp -- "$V354_FIXTURE" "$V354_REPO/local/libexec/awtarchy/power-profile-helper"
cp -- "$V354_FIXTURE" "$V353_CONTROL_REPO/local/libexec/awtarchy/power-profile-helper"
repair_definition="$(sed -n '/^repair_v354_sony_battery_disable_repo() {/,/^}/p' "$RUNTIME")"
[[ -n "$repair_definition" ]] || fail 'could not extract v3.5.4 Sony battery repair function'
log() { :; }
die() { fail "$*"; }
eval "$repair_definition"
repair_v354_sony_battery_disable_repo "$V354_REPO" v3.5.4
V354_EXPECTED="$TMP/v354-expected-power-profile-helper"
cp -- "$V354_FIXTURE" "$V354_EXPECTED"
python3 - "$V354_EXPECTED" <<'PY_V354_EXPECTED'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """    huawei)
      /usr/bin/grep -Eq 'charge_control_thresholds[^=]*=[[:space:]]*[0-9]+[[:space:]]+100([^0-9]|$)' <<<"$report"
      ;;
    *)
"""
new = """    huawei)
      /usr/bin/grep -Eq 'charge_control_thresholds[^=]*=[[:space:]]*[0-9]+[[:space:]]+100([^0-9]|$)' <<<"$report"
      ;;
    sony)
      /usr/bin/grep -Eq 'battery_care_limiter[^=]*=[[:space:]]*0([^0-9]|$)' <<<"$report"
      ;;
    *)
"""
if text.count(old) != 1:
    raise SystemExit("v3.5.4 fixture did not contain the expected pre-repair helper source")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY_V354_EXPECTED
cmp -s -- "$V354_EXPECTED" "$V354_REPO/local/libexec/awtarchy/power-profile-helper" \
  || fail 'v3.5.4 post-release repair changed more than the Sony disable verifier'
bash -n "$V354_REPO/local/libexec/awtarchy/power-profile-helper" \
  || fail 'v3.5.4 repaired Sony helper failed Bash syntax validation'
repair_v354_sony_battery_disable_repo "$V353_CONTROL_REPO" v3.5.3
cmp -s -- "$V354_FIXTURE" "$V353_CONTROL_REPO/local/libexec/awtarchy/power-profile-helper" \
  || fail 'v3.5.4 Sony repair changed a non-v3.5.4 release target'

printf '%s\n' 'PASS: battery care controls validate, persist, verify, and roll back safely.'
