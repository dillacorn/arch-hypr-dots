#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-power-profile.sh"
HELPER="${ROOT}/local/libexec/awtarchy/power-profile-helper"

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

[[ -f "$HELPER" ]] || fail 'trusted Power Mode helper source is missing'

# The shared laptop reconciler already runs on fresh installs and normal updates.
# It must own deployment/repair of the privileged helper so those two paths cannot drift.
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

require_absent "$RECONCILER" 'NOPASSWD: /usr/local/libexec/awtarchy/power-profile-helper' \
  'power reconciler grants persistent passwordless Power Mode helper access'

printf '%s\n' 'PASS: install/update power reconciliation deploys the trusted helper without passwordless sudo.'
