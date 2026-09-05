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

# The shared laptop reconciler already runs on fresh installs and normal updates.
# It must own deployment/repair of the privileged write helper so those two paths
# cannot drift.
require_literal "$RECONCILER" 'POWER_PROFILE_HELPER_SOURCE="${REPO_ROOT}/local/libexec/awtarchy/power-profile-helper"' \
  'power reconciler does not use the fixed repository helper source'
require_absent "$RECONCILER" 'AWTARCHY_POWER_PROFILE_HELPER_SOURCE' \
  'power reconciler allows an environment override of privileged helper source'
require_literal "$RECONCILER" 'POWER_PROFILE_HELPER_DESTINATION="/usr/local/libexec/awtarchy/power-profile-helper"' \
  'power reconciler does not target the fixed root-owned helper path'
require_literal "$RECONCILER" 'install_power_profile_helper()' \
  'power reconciler has no helper install/repair function'
require_literal "$RECONCILER" "[[ \$(/usr/bin/head -n1 -- \"\$POWER_PROFILE_HELPER_SOURCE\") == '#!/usr/bin/bash' ]]" \
  'power reconciler does not validate the helper interpreter with a fixed command path'
require_literal "$RECONCILER" '/usr/bin/bash -n "$POWER_PROFILE_HELPER_SOURCE"' \
  'power reconciler does not syntax-check the helper source'
require_literal "$RECONCILER" 'dir_owner="$(/usr/bin/stat -c %u -- "$destination_dir" 2>/dev/null)"' \
  'power reconciler does not verify helper directory ownership'
require_literal "$RECONCILER" '(( (8#$dir_mode & 8#022) == 0 ))' \
  'power reconciler does not reject group/world-writable helper directories'
require_literal "$RECONCILER" 'install -m 0755 -o root -g root "$POWER_PROFILE_HELPER_SOURCE" "$temporary"' \
  'power reconciler does not root-own the staged helper'
require_literal "$RECONCILER" 'sha256sum "$POWER_PROFILE_HELPER_SOURCE"' \
  'power reconciler does not hash the helper source'
require_literal "$RECONCILER" 'sha256sum "$temporary"' \
  'power reconciler does not verify the staged helper hash'
require_literal "$RECONCILER" 'mv -Tf -- "$temporary" "$POWER_PROFILE_HELPER_DESTINATION"' \
  'power reconciler does not atomically activate the helper'
require_literal "$RECONCILER" 'install_power_profile_helper' \
  'power reconciler never invokes helper deployment'

# The write-capable helper must never become passwordless. TLP 1.10 marks
# `tlp-stat -b` as root-only, so Battery Care needs a separate, narrowly-scoped
# read-only helper for status discovery instead of weakening this boundary.
require_absent "$RECONCILER" 'NOPASSWD: /usr/local/libexec/awtarchy/power-profile-helper' \
  'power reconciler grants persistent passwordless write-helper access'
[[ -f "$STATUS_HELPER" ]] || fail 'read-only Battery Care status helper is missing'
require_literal "$STATUS_HELPER" '#!/usr/bin/bash' \
  'Battery Care status helper does not use the fixed Bash interpreter'
require_literal "$STATUS_HELPER" '[[ $# -eq 0 ]]' \
  'Battery Care status helper accepts an argument surface'
require_literal "$STATUS_HELPER" '(( EUID == 0 ))' \
  'Battery Care status helper does not require root'
require_literal "$STATUS_HELPER" '/usr/bin/env -i' \
  'Battery Care status helper does not clear the caller environment'
require_literal "$STATUS_HELPER" '/usr/bin/tlp-stat -b' \
  'Battery Care status helper does not pin the read-only TLP battery report'
require_absent "$STATUS_HELPER" '"$@"' \
  'Battery Care status helper forwards caller-controlled arguments'

require_literal "$RECONCILER" 'BATTERY_STATUS_HELPER_SOURCE="${REPO_ROOT}/local/libexec/awtarchy/battery-status-helper"' \
  'power reconciler does not use the fixed read-only status helper source'
require_literal "$RECONCILER" 'BATTERY_STATUS_HELPER_DESTINATION="/usr/local/libexec/awtarchy/battery-status-helper"' \
  'power reconciler does not target the fixed read-only status helper path'
require_literal "$RECONCILER" 'SUDOERS_DIR="/etc/sudoers.d"' \
  'power reconciler does not pin the sudoers policy directory'
require_literal "$RECONCILER" 'install_battery_status_helper()' \
  'power reconciler has no read-only status helper install/repair function'
require_literal "$RECONCILER" 'install_battery_status_policy()' \
  'power reconciler has no read-only status policy install/repair function'
require_literal "$RECONCILER" 'NOPASSWD: ${BATTERY_STATUS_HELPER_DESTINATION} ""' \
  'power reconciler does not restrict passwordless access to the no-argument read-only status helper'
require_literal "$RECONCILER" '/usr/sbin/visudo -cf' \
  'power reconciler does not validate the generated battery status sudoers rule'

# Exercise install and repair with a sandboxed copy. The real source keeps fixed
# system destinations; only this disposable test copy redirects them under /tmp.
command -v sudo >/dev/null 2>&1 || fail 'sudo is required for status-helper install regression'
sudo -n true >/dev/null 2>&1 || fail 'noninteractive sudo is required for status-helper install regression'
policy_user="$(id -un)"
[[ "$policy_user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail 'test username is incompatible with sudoers regression'
mkdir -p -- "$TMP/system/libexec" "$TMP/system/sudoers"
sudo -n /usr/bin/chown root:root "$TMP/system/libexec" "$TMP/system/sudoers"
sudo -n /usr/bin/chmod 0755 "$TMP/system/libexec" "$TMP/system/sudoers"
cp -- "$RECONCILER" "$TMP/reconciler-under-test"
python3 - "$TMP/reconciler-under-test" "$TMP/system/libexec/battery-status-helper" "$TMP/system/sudoers" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    'BATTERY_STATUS_HELPER_DESTINATION="/usr/local/libexec/awtarchy/battery-status-helper"':
        f'BATTERY_STATUS_HELPER_DESTINATION="{sys.argv[2]}"',
    'SUDOERS_DIR="/etc/sudoers.d"': f'SUDOERS_DIR="{sys.argv[3]}"',
    'main "$@"': ': # test copy: do not run reconciler main',
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f'expected exactly one reconciler anchor: {old}')
    text = text.replace(old, new)
path.write_text(text)
PY
cat >>"$TMP/reconciler-under-test" <<'EOF_TEST_CALLS'
install_battery_status_helper
install_battery_status_policy
EOF_TEST_CALLS

sudo -n /usr/bin/bash "$TMP/reconciler-under-test"
installed_status="$TMP/system/libexec/battery-status-helper"
policy_file="$TMP/system/sudoers/awtarchy-battery-status-${policy_user}"
[[ -f "$installed_status" && ! -L "$installed_status" && -x "$installed_status" ]] \
  || fail 'status helper was not installed as an executable regular file'
[[ $(stat -c %u -- "$installed_status") == 0 && $(stat -c %a -- "$installed_status") == 755 ]] \
  || fail 'status helper install ownership/mode is not root:0755'
cmp -s -- "$STATUS_HELPER" "$installed_status" \
  || fail 'installed status helper does not match trusted repository source'
[[ -f "$policy_file" && ! -L "$policy_file" ]] || fail 'battery status sudoers policy was not installed'
[[ $(stat -c %u -- "$policy_file") == 0 && $(stat -c %a -- "$policy_file") == 440 ]] \
  || fail 'battery status sudoers policy ownership/mode is not root:0440'
sudo -n /usr/sbin/visudo -cf "$policy_file" >/dev/null \
  || fail 'installed battery status sudoers policy is invalid'
grep -Fxq "${policy_user} ALL=(root) NOPASSWD: ${installed_status} \"\"" "$policy_file" \
  || fail 'installed sudoers policy does not restrict the helper to zero arguments'
! grep -Fq 'power-profile-helper' "$policy_file" \
  || fail 'read-only status policy accidentally grants write-helper access'

# Corrupt Awtarchy-owned installed state and prove a second reconciliation repairs
# both artifacts rather than accepting stale helper/policy content.
printf '%s\n' '# corrupted' | sudo -n /usr/bin/tee "$installed_status" >/dev/null
sudo -n /usr/bin/chmod 0755 "$installed_status"
sudo -n /usr/bin/sed -i 's/NOPASSWD:/PASSWD:/' "$policy_file"
sudo -n /usr/bin/bash "$TMP/reconciler-under-test"
cmp -s -- "$STATUS_HELPER" "$installed_status" \
  || fail 'status helper reconciliation did not repair changed installed content'
grep -Fxq "${policy_user} ALL=(root) NOPASSWD: ${installed_status} \"\"" "$policy_file" \
  || fail 'status policy reconciliation did not repair changed Awtarchy-owned content'

require_literal "$DETECTOR" 'BATTERY_STATUS_HELPER="${AWTARCHY_BATTERY_STATUS_HELPER:-/usr/local/libexec/awtarchy/battery-status-helper}"' \
  'Battery Care detector does not use the installed root-only status bridge'
require_literal "$DETECTOR" 'SUDO_BIN="${AWTARCHY_SUDO_BIN:-/usr/bin/sudo}"' \
  'Battery Care detector does not pin sudo for noninteractive status reads'
require_literal "$DETECTOR" '"$SUDO_BIN" -n -- "$BATTERY_STATUS_HELPER"' \
  'Battery Care detector does not use noninteractive sudo for the read-only status helper'

# Functional regression: direct tlp-stat is unavailable to the desktop user, as
# it is in current upstream TLP, but the no-password read-only bridge returns the
# authoritative plugin/capability report. The detector must still expose normal
# writable TLP controls without prompting just to open the flyout.
POWER_ROOT="$TMP/power"
mkdir -p -- "$POWER_ROOT/BAT0"
printf '%s\n' Battery >"$POWER_ROOT/BAT0/type"
printf '%s\n' Dell >"$POWER_ROOT/BAT0/manufacturer"
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
Plugin: dell
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
exec "$3"
EOF_SUDO
chmod 0755 "$TMP/sudo"

json="$(
  AWTARCHY_POWER_SUPPLY_ROOT="$POWER_ROOT" \
  AWTARCHY_TLP_STAT_BIN="$TMP/tlp-stat-root-only" \
  AWTARCHY_BATTERY_STATUS_HELPER="$TMP/battery-status-helper" \
  AWTARCHY_SUDO_BIN="$TMP/sudo" \
  AWTARCHY_TLP_CONFIG_DIR="$TMP/tlp.d" \
  AWTARCHY_TLP_USER_CONFIG="$TMP/tlp.conf" \
  AWTARCHY_SONY_BATTERY_CARE_PATH="$TMP/no-sony-limiter" \
    bash "$DETECTOR" --status-json
)"
jq -e '
  .backend == "tlp"
  and .plugin == "dell"
  and .supported == true
  and .writable == true
  and .compatibility == "validated"
  and .mode == "range"
  and .stop_min == 55
  and .stop_max == 100
  and .target == 80
' <<<"$json" >/dev/null \
  || fail "root-only TLP status bridge was not used: $json"

printf '%s\n' 'PASS: install/update power reconciliation keeps writes authenticated and exposes root-only TLP battery status through a narrow read-only bridge.'
