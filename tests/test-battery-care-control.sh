#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
CARD="${ROOT}/config/quickshell/awtarchy/BatteryCareCard.qml"
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
require_file "$CARD"
require_source "$HELPER" 'TLP="/usr/bin/tlp"' 'helper does not pin the TLP executable'
require_source "$HELPER" 'TLP_STAT="/usr/bin/tlp-stat"' 'helper does not pin tlp-stat'
require_source "$HELPER" 'CONFIG_DIR="/etc/tlp.d"' 'helper does not pin TLP drop-in directory'
require_source "$HELPER" 'MANAGED_CONFIG="${CONFIG_DIR}/00-awtarchy-battery-care.conf"' 'helper managed config path changed unexpectedly'
require_source "$HELPER" '(( EUID == 0 )) || fail' 'helper does not require root'
require_source "$HELPER" 'Existing user-managed TLP charge thresholds' 'helper does not fail closed on external TLP thresholds'
require_absent "$HELPER" 'charge_control_end_threshold" >' 'helper writes battery sysfs directly'
require_absent "$HELPER" 'charge_control_start_threshold" >' 'helper writes battery sysfs directly'

TEST_HELPER="$TMP/power-profile-helper"
cp -- "$HELPER" "$TEST_HELPER"
chmod 0755 "$TEST_HELPER"
FAKE_BIN="$TMP/bin"
CONF_DIR="$TMP/tlp.d"
USER_CONF="$TMP/tlp.conf"
REPORT="$TMP/tlp-report"
LOG="$TMP/tlp.log"
FAIL_NEXT="$TMP/fail-next"
mkdir -p -- "$FAKE_BIN" "$CONF_DIR"
: >"$USER_CONF"
: >"$LOG"

python3 - "$TEST_HELPER" "$FAKE_BIN/tlp" "$FAKE_BIN/tlp-stat" "$CONF_DIR" "$USER_CONF" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace('TLP="/usr/bin/tlp"', f'TLP="{sys.argv[2]}"')
text = text.replace('TLP_STAT="/usr/bin/tlp-stat"', f'TLP_STAT="{sys.argv[3]}"')
text = text.replace('CONFIG_DIR="/etc/tlp.d"', f'CONFIG_DIR="{sys.argv[4]}"')
text = text.replace('USER_CONFIG="/etc/tlp.conf"', f'USER_CONFIG="{sys.argv[5]}"')
text = text.replace("(( EUID == 0 )) || fail 'must run as root'", ': # test copy: root check bypassed')
path.write_text(text, encoding="utf-8")
PY

cat >"$FAKE_BIN/tlp-stat" <<'EOF_STAT'
#!/usr/bin/env bash
set -euo pipefail
cat -- "${AWTARCHY_TEST_REPORT:?}"
EOF_STAT
chmod 0755 "$FAKE_BIN/tlp-stat"

cat >"$FAKE_BIN/tlp" <<'EOF_TLP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_LOG:?}"
if [[ ${1:-} == setcharge && -e ${AWTARCHY_TEST_FAIL_NEXT:?} ]]; then
  rm -f -- "$AWTARCHY_TEST_FAIL_NEXT"
  exit 1
fi
case "${1:-}" in
  setcharge|fullcharge) exit 0 ;;
  *) exit 64 ;;
esac
EOF_TLP
chmod 0755 "$FAKE_BIN/tlp"

MANAGED="$CONF_DIR/00-awtarchy-battery-care.conf"
run_helper() {
  AWTARCHY_TEST_REPORT="$REPORT" \
  AWTARCHY_TEST_LOG="$LOG" \
  AWTARCHY_TEST_FAIL_NEXT="$FAIL_NEXT" \
    "$TEST_HELPER" "$@"
}

write_range_report() {
  cat >"$REPORT" <<'EOF_REPORT'
+++ Battery Care
Plugin: future-vendor
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 50..95(default)
* STOP_CHARGE_THRESH_BAT0/1: 55..100(default)
+++ Battery Status: BAT0
/sys/class/power_supply/BAT0/charge_control_end_threshold = 74 [%]
+++ Battery Status: BAT1
/sys/class/power_supply/BAT1/charge_control_end_threshold = 74 [%]
EOF_REPORT
}

# A future TLP plugin using the ordinary percentage contract must work without
# being added to an Awtarchy allowlist. TLP's advertised BAT0/1 config parameter
# determines which standard TLP keys Awtarchy persists.
write_range_report
run_helper battery-set 80
grep -Fxq 'START_CHARGE_THRESH_BAT0=75' "$MANAGED" || fail 'generic BAT0 start threshold was not derived from TLP range'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'generic BAT0 stop threshold was not persisted'
grep -Fxq 'START_CHARGE_THRESH_BAT1=75' "$MANAGED" || fail 'TLP-advertised BAT1 start threshold was not persisted'
grep -Fxq 'STOP_CHARGE_THRESH_BAT1=80' "$MANAGED" || fail 'TLP-advertised BAT1 stop threshold was not persisted'
grep -Fxq 'setcharge' "$LOG" || fail 'configured thresholds were not applied through tlp setcharge'

# A stop-only TLP interface uses the documented dummy start value 0. Physical
# battery names must not cause extra config keys when TLP advertises only BAT0.
cat >"$REPORT" <<'EOF_REPORT'
+++ Battery Care
Plugin: stop-only-future-vendor
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0: 50, 80, 100(default)
+++ Battery Status: CMB0
+++ Battery Status: CMB1
EOF_REPORT
: >"$LOG"
run_helper battery-set 80
grep -Fxq 'START_CHARGE_THRESH_BAT0=0' "$MANAGED" || fail 'stop-only interface did not use dummy START=0'
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=80' "$MANAGED" || fail 'stop-only target was not persisted'
if grep -Fq 'BAT1=' "$MANAGED"; then
  fail 'physical battery names were incorrectly converted into TLP config qualifiers'
fi
grep -Fxq 'setcharge' "$LOG" || fail 'stop-only config was not applied through tlp setcharge'

# Selector semantics are deliberately outside Awtarchy. A 0/1 TLP control must
# not be treated as a 1% percentage range or translated using vendor knowledge.
cat >"$REPORT" <<'EOF_REPORT'
+++ Battery Care
Plugin: selector-vendor
Supported features: charge type
Parameter value range:
* STOP_CHARGE_THRESH_BAT0/1: 0(Standard)..1(Long_Life) -- charge type
+++ Battery Status: BAT0
EOF_REPORT
cp -- "$MANAGED" "$TMP/before-selector.conf"
if run_helper battery-set 80 >"$TMP/selector.out" 2>"$TMP/selector.err"; then
  fail 'selector-only TLP mode accepted a percentage target'
fi
cmp -s -- "$TMP/before-selector.conf" "$MANAGED" || fail 'selector rejection changed managed TLP config'

# User/TLPUI-owned threshold policy remains authoritative. Awtarchy may not
# silently override it.
write_range_report
printf '%s\n' 'STOP_CHARGE_THRESH_BAT0=70' >"$CONF_DIR/10-user.conf"
cp -- "$MANAGED" "$TMP/before-conflict.conf"
if run_helper battery-set 85 >"$TMP/conflict.out" 2>"$TMP/conflict.err"; then
  fail 'external TLP thresholds were overwritten'
fi
grep -Fq 'Existing user-managed TLP charge thresholds' "$TMP/conflict.err" || fail 'external-config conflict was not explained'
cmp -s -- "$TMP/before-conflict.conf" "$MANAGED" || fail 'managed config changed despite external-config conflict'
rm -f -- "$CONF_DIR/10-user.conf"

# TLP rejection is authoritative. Restore the exact prior Awtarchy drop-in and
# re-apply it; do not attempt a vendor-specific hardware verifier.
cat >"$MANAGED" <<'EOF_OLD'
# Managed by Awtarchy Battery flyout.
# target=80
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
START_CHARGE_THRESH_BAT1=75
STOP_CHARGE_THRESH_BAT1=80
EOF_OLD
cp -- "$MANAGED" "$TMP/expected-rollback.conf"
touch "$FAIL_NEXT"
if run_helper battery-set 85 >"$TMP/apply-fail.out" 2>"$TMP/apply-fail.err"; then
  fail 'TLP apply failure was reported as success'
fi
cmp -s -- "$TMP/expected-rollback.conf" "$MANAGED" || fail 'TLP apply failure did not restore previous managed config exactly'
[[ "$(grep -Fxc 'setcharge' "$LOG")" -ge 2 ]] || fail 'rollback did not ask TLP to re-apply restored configuration'

# Successful TLP application is sufficient even when firmware reports a
# transformed value. This fixture intentionally keeps read-back at 74%.
: >"$LOG"
run_helper battery-set 90
grep -Fxq 'STOP_CHARGE_THRESH_BAT0=90' "$MANAGED" || fail 'successful TLP application was rejected because read-back differed'
grep -Fxq 'setcharge' "$LOG" || fail 'successful target was not applied through TLP'

# Disabling removes only Awtarchy's owned policy and asks TLP to full-charge each
# physical battery TLP reports. No vendor OFF encoding is maintained here.
write_range_report
: >"$LOG"
run_helper battery-disable
[[ ! -e "$MANAGED" ]] || fail 'battery-disable left Awtarchy threshold persistence behind'
grep -Fxq 'fullcharge BAT0' "$LOG" || fail 'battery-disable did not ask TLP to full-charge BAT0'
grep -Fxq 'fullcharge BAT1' "$LOG" || fail 'battery-disable did not ask TLP to full-charge BAT1'

# The source boundary itself must stay generic after implementation.
require_absent "$HELPER" 'battery_plugin_writable()' 'helper still owns a TLP plugin allowlist'
require_absent "$HELPER" 'battery_dual_config_plugin()' 'helper still maps config keys by plugin identity'
require_absent "$HELPER" 'verify_enabled_state()' 'helper still owns vendor-specific enabled read-back rules'
require_absent "$HELPER" 'verify_disabled_state()' 'helper still owns vendor-specific disabled read-back rules'
require_absent "$HELPER" 'battery-enable-fixed' 'helper still exposes Awtarchy-owned fixed vendor semantics'

require_source "$CARD" 'batteryCareHelper: "/usr/local/libexec/awtarchy/power-profile-helper"' 'Battery Care UI does not use the installed helper'
require_source "$CARD" 'root.pendingAction = "battery-disable"' 'Battery Care UI has no OFF path'
require_source "$CARD" 'root.pendingAction = "battery-set"' 'Battery Care UI has no generic target-setting path'
require_absent "$CARD" 'charge_control_end_threshold' 'QML writes battery threshold sysfs directly'
require_absent "$CARD" 'tlp setcharge' 'QML bypasses the privileged helper with tlp setcharge'

printf '%s\n' 'PASS: Battery Care helper delegates generic threshold semantics and hardware application to TLP.'
