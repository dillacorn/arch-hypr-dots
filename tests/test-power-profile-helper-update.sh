#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-power-profile.sh"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"
STATUS_HELPER="${ROOT}/local/libexec/awtarchy/battery-status-helper"
DETECTOR="${ROOT}/config/hypr/scripts/quickshell_battery_care.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_literal() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

require_absent() {
  local file="$1" needle="$2" message="$3"
  ! grep -Fq -- "$needle" "$file" || fail "$message"
}

bash "$ROOT/tests/test-battery-status-helper.sh"

[[ -f "$HELPER" ]] || fail 'trusted Power Mode helper source is missing'
[[ -f "$STATUS_HELPER" ]] || fail 'read-only Battery Care status helper is missing'

# Install/update reconciliation owns deployment of the privileged helpers. Keep
# those sources, destinations, validation, and ownership boundaries fixed.
require_literal "$RECONCILER" 'POWER_PROFILE_HELPER_SOURCE="${REPO_ROOT}/local/libexec/awtarchy/power-profile-helper"' \
  'power reconciler does not use the fixed repository write-helper source'
require_literal "$RECONCILER" 'POWER_PROFILE_HELPER_DESTINATION="/usr/local/libexec/awtarchy/power-profile-helper"' \
  'power reconciler does not target the fixed root-owned write-helper path'
require_absent "$RECONCILER" 'AWTARCHY_POWER_PROFILE_HELPER_SOURCE' \
  'power reconciler allows an environment override of privileged helper source'
require_literal "$RECONCILER" '/usr/bin/bash -n "$POWER_PROFILE_HELPER_SOURCE"' \
  'power reconciler does not syntax-check the write helper'
require_literal "$RECONCILER" 'install -m 0755 -o root -g root "$POWER_PROFILE_HELPER_SOURCE" "$temporary"' \
  'power reconciler does not root-own the staged write helper'
require_literal "$RECONCILER" 'sha256sum "$POWER_PROFILE_HELPER_SOURCE"' \
  'power reconciler does not hash the write-helper source'
require_literal "$RECONCILER" 'sha256sum "$temporary"' \
  'power reconciler does not verify the staged write-helper hash'
require_literal "$RECONCILER" 'mv -Tf -- "$temporary" "$POWER_PROFILE_HELPER_DESTINATION"' \
  'power reconciler does not atomically activate the write helper'
require_absent "$RECONCILER" 'NOPASSWD: /usr/local/libexec/awtarchy/power-profile-helper' \
  'power reconciler grants passwordless write-helper access'

# Current TLP battery reports may require root. Keep that read path narrow and
# separate from the authenticated write helper.
require_literal "$STATUS_HELPER" '#!/usr/bin/bash' \
  'Battery Care status helper does not use the fixed Bash interpreter'
require_literal "$STATUS_HELPER" '[[ $# -eq 0 ]]' \
  'Battery Care status helper accepts an argument surface'
require_literal "$STATUS_HELPER" '(( EUID == 0 ))' \
  'Battery Care status helper does not require root'
require_literal "$STATUS_HELPER" '/usr/bin/env -i' \
  'Battery Care status helper does not clear the caller environment'
require_literal "$STATUS_HELPER" '/usr/bin/tlp-stat -b' \
  'Battery Care status helper does not pin the read-only TLP report'
require_absent "$STATUS_HELPER" '"$@"' \
  'Battery Care status helper forwards caller-controlled arguments'

require_literal "$RECONCILER" 'BATTERY_STATUS_HELPER_SOURCE="${REPO_ROOT}/local/libexec/awtarchy/battery-status-helper"' \
  'power reconciler does not use the fixed status-helper source'
require_literal "$RECONCILER" 'BATTERY_STATUS_HELPER_DESTINATION="/usr/local/libexec/awtarchy/battery-status-helper"' \
  'power reconciler does not target the fixed status-helper path'
require_literal "$RECONCILER" 'SUDOERS_DIR="/etc/sudoers.d"' \
  'power reconciler does not pin the sudoers policy directory'
require_literal "$RECONCILER" 'install_battery_status_helper()' \
  'power reconciler has no status-helper install/repair function'
require_literal "$RECONCILER" 'install_battery_status_policy()' \
  'power reconciler has no status-policy install/repair function'
require_literal "$RECONCILER" 'NOPASSWD: ${BATTERY_STATUS_HELPER_DESTINATION} \"\"' \
  'status policy is not restricted to the zero-argument read-only helper'
require_literal "$RECONCILER" '/usr/sbin/visudo -cf' \
  'power reconciler does not validate the generated status sudoers rule'

require_literal "$DETECTOR" 'BATTERY_STATUS_HELPER="${AWTARCHY_BATTERY_STATUS_HELPER:-/usr/local/libexec/awtarchy/battery-status-helper}"' \
  'Battery Care detector does not use the installed root-only status bridge'
require_literal "$DETECTOR" 'SUDO_BIN="${AWTARCHY_SUDO_BIN:-/usr/bin/sudo}"' \
  'Battery Care detector does not pin sudo for noninteractive status reads'
require_literal "$DETECTOR" '"$SUDO_BIN" -n -- "$BATTERY_STATUS_HELPER"' \
  'Battery Care detector does not use noninteractive sudo for the read-only status helper'

# Functional regression: direct tlp-stat is unavailable to the desktop user,
# while the narrow read-only bridge supplies a completely unknown future plugin
# with ordinary percentage ranges. Capability must work without a vendor matrix.
# Because this fixture exposes no kernel threshold files, current hardware state
# must remain unknown instead of being reconstructed from vendor-formatted TLP
# status lines.
POWER_ROOT="$TMP/power"
mkdir -p -- "$POWER_ROOT/BAT0"
printf '%s\n' Battery >"$POWER_ROOT/BAT0/type"
printf '%s\n' TestVendor >"$POWER_ROOT/BAT0/manufacturer"
printf '%s\n' TestModel >"$POWER_ROOT/BAT0/model_name"

cat >"$TMP/tlp-stat-root-only" <<'EOF_TLP_DIRECT'
#!/usr/bin/env bash
printf '%s\n' 'Error: root privileges required.' >&2
exit 1
EOF_TLP_DIRECT
chmod 0755 "$TMP/tlp-stat-root-only"

cat >"$TMP/battery-status-helper" <<'EOF_STATUS'
#!/usr/bin/env bash
cat <<'EOF'
+++ Battery Care
Plugin: future-vendor
Supported features: charge thresholds
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 50..95(default)
* STOP_CHARGE_THRESH_BAT0/1: 55..100(default)
+++ Battery Status: BAT0
/sys/class/power_supply/BAT0/charge_control_start_threshold = 75 [%]
/sys/class/power_supply/BAT0/charge_control_end_threshold = 80 [%]
EOF
EOF_STATUS
chmod 0755 "$TMP/battery-status-helper"

cat >"$TMP/sudo" <<'EOF_SUDO'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -n && ${2:-} == -- && $# -eq 3 ]] || exit 64
"$3"
EOF_SUDO
chmod 0755 "$TMP/sudo"

json="$(
  AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
  AWTARCHY_TLP_STAT_BIN="$TMP/tlp-stat-root-only" \
  AWTARCHY_BATTERY_STATUS_HELPER="$TMP/battery-status-helper" \
  AWTARCHY_SUDO_BIN="$TMP/sudo" \
  AWTARCHY_TLP_CONFIG_DIR="$TMP/tlp.d" \
  AWTARCHY_TLP_USER_CONFIG="$TMP/tlp.conf" \
    bash "$DETECTOR" --status-json
)"
jq -e '
  .backend == "tlp"
  and .plugin == "future-vendor"
  and .supported == true
  and .writable == true
  and .compatibility == "validated"
  and .mode == "range"
  and .stop_min == 55
  and .stop_max == 100
  and .target == null
  and .enabled == null
' <<<"$json" >/dev/null \
  || fail "root-only TLP capability bridge was not normalized generically: $json"

# A stale installed bridge by itself must never prove TLP battery capability.
cat >"$TMP/stale-battery-status-helper" <<'EOF_STALE_STATUS'
#!/usr/bin/env bash
exit 127
EOF_STALE_STATUS
chmod 0755 "$TMP/stale-battery-status-helper"

json="$(
  AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
  AWTARCHY_TLP_STAT_BIN="$TMP/missing-tlp-stat" \
  AWTARCHY_BATTERY_STATUS_HELPER="$TMP/stale-battery-status-helper" \
  AWTARCHY_SUDO_BIN="$TMP/sudo" \
  AWTARCHY_TLP_CONFIG_DIR="$TMP/tlp.d" \
  AWTARCHY_TLP_USER_CONFIG="$TMP/tlp.conf" \
    bash "$DETECTOR" --status-json
)"
jq -e '
  .tlp_available == false
  and .supported == false
  and .writable == false
  and .compatibility == "unsupported"
  and .backend == "none"
' <<<"$json" >/dev/null \
  || fail "stale Battery Care status bridge did not fail closed without TLP: $json"

printf '%s\n' 'PASS: update reconciliation keeps writes authenticated and root-only TLP capability reads narrow and generic.'
