#!/usr/bin/env bash
# shellcheck disable=SC1090
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
DETECTOR="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
CARD="${ROOT}/config/quickshell/awtarchy/BatteryCareCard.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "$HELPER" ]] || fail 'power-profile-helper is missing'
[[ -f "$DETECTOR" ]] || fail 'battery-care detector is missing'
[[ -f "$CARD" ]] || fail 'BatteryCareCard.qml is missing'

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

# Divergent live limits must remain per-battery facts, never a fabricated global target.
POWER_ROOT="$TMP/power"
for battery in BAT0 BAT1; do
  mkdir -p -- "$POWER_ROOT/$battery"
  printf '%s\n' Battery >"$POWER_ROOT/$battery/type"
  printf '%s\n' TestVendor >"$POWER_ROOT/$battery/manufacturer"
  printf '%s\n' "$battery" >"$POWER_ROOT/$battery/model_name"
  printf '%s\n' 75 >"$POWER_ROOT/$battery/charge_control_start_threshold"
done
printf '%s\n' 80 >"$POWER_ROOT/BAT0/charge_control_end_threshold"
printf '%s\n' 100 >"$POWER_ROOT/BAT1/charge_control_end_threshold"

cat >"$FAKE_BIN/tlp-stat" <<'FAKE_MIXED_STAT'
#!/usr/bin/env bash
set -euo pipefail
cat <<'EOF'
+++ Battery Care
Plugin: dell
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 50..95(default)
* STOP_CHARGE_THRESH_BAT0/1: 55..100(default)
/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]
/sys/class/power_supply/BAT1/charge_control_end_threshold = 100 [%]
EOF
FAKE_MIXED_STAT
chmod 0755 "$FAKE_BIN/tlp-stat"

json="$(
  AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
  AWTARCHY_TLP_STAT_BIN="$FAKE_BIN/tlp-stat" \
  AWTARCHY_TLP_CONFIG_DIR="$CONF_DIR" \
  AWTARCHY_TLP_USER_CONFIG="$USER_CONF" \
  AWTARCHY_SONY_BATTERY_CARE_PATH="$TMP/no-sony-limiter" \
    bash "$DETECTOR" --status-json
)"

jq -e '
  .mixed_stop_thresholds == true
  and .current_stop == null
  and .target == null
  and .enabled == null
  and (.batteries | map(.stop_threshold)) == [80, 100]
' <<<"$json" >/dev/null \
  || fail "mixed BAT0/BAT1 stop thresholds were collapsed into one global state: $json"

# Current TLP Lenovo supports BAT0 and BAT1 charge_types independently. A mixed
# Long_Life/Standard state must not be collapsed to globally On just because the
# first matching line happens to be Long_Life.
rm -f -- \
  "$POWER_ROOT/BAT0/charge_control_start_threshold" \
  "$POWER_ROOT/BAT0/charge_control_end_threshold" \
  "$POWER_ROOT/BAT1/charge_control_start_threshold" \
  "$POWER_ROOT/BAT1/charge_control_end_threshold"

cat >"$FAKE_BIN/tlp-stat" <<'FAKE_LENOVO_MIXED'
#!/usr/bin/env bash
set -euo pipefail
cat <<'EOF'
+++ Battery Care
Plugin: lenovo
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0/1: 0(Standard)..1(Long_Life) -- charge_types
+++ Battery Status: BAT0
/sys/class/power_supply/BAT0/charge_types = Standard [Long_Life]
+++ Battery Status: BAT1
/sys/class/power_supply/BAT1/charge_types = [Standard] Long_Life
EOF
FAKE_LENOVO_MIXED
chmod 0755 "$FAKE_BIN/tlp-stat"

# The privileged verifier must reject a partial multi-battery transition too.
# Otherwise a successful BAT0 write could hide a failed BAT1 write or vice versa.
VERIFY_HELPER="$TMP/power-profile-helper-source"
sed '/^main "\$@"$/d' "$TEST_HELPER" >"$VERIFY_HELPER"
source "$VERIFY_HELPER"
if verify_enabled_state lenovo 1; then
  fail 'Lenovo enabled-state verification accepted mixed Long_Life/Standard batteries'
fi
if verify_disabled_state lenovo; then
  fail 'Lenovo disabled-state verification accepted mixed Long_Life/Standard batteries'
fi

json="$(
  AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
  AWTARCHY_TLP_STAT_BIN="$FAKE_BIN/tlp-stat" \
  AWTARCHY_TLP_CONFIG_DIR="$CONF_DIR" \
  AWTARCHY_TLP_USER_CONFIG="$USER_CONF" \
  AWTARCHY_SONY_BATTERY_CARE_PATH="$TMP/no-sony-limiter" \
    bash "$DETECTOR" --status-json
)"

jq -e '
  .plugin == "lenovo"
  and .mixed_stop_thresholds == true
  and .target == null
  and .enabled == null
' <<<"$json" >/dev/null \
  || fail "mixed Lenovo BAT0/BAT1 charge types were collapsed into one global state: $json"

grep -Fq 'readonly property bool mixedStopThresholds: Boolean(statusData.mixed_stop_thresholds)' "$CARD" \
  || fail 'Battery Care QML does not expose mixed stop-threshold state'
grep -Fq 'mixed_stop_thresholds: false' "$CARD" \
  || fail 'Battery Care empty status does not initialize mixed stop-threshold state'
grep -Fq 'mixedStopThresholds || statusData.enabled === true' "$CARD" \
  || fail 'mixed battery limits are not treated as an active limit for the OFF toggle'
grep -Fq 'if (!mixedStopThresholds && statusData.target !== null && statusData.target !== undefined)' "$CARD" \
  || fail 'Battery Care can still collapse mixed thresholds into a singular maximum-charge label'
grep -Fq 'if (mixedStopThresholds)' "$CARD" \
  || fail 'Battery Care has no explicit mixed-state control label'
grep -Fq 'return "Mixed";' "$CARD" \
  || fail 'Battery Care mixed-state control label is missing'

printf '%s\n' 'Battery multi-battery regression tests passed.'
