#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT}/awtarchy-install.sh"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

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

require_literal "$INSTALLER" 'POWER_PROFILE_HELPER_SOURCE="${SCRIPT_DIR}/local/libexec/awtarchy/power-profile-helper"' \
  'installer has no trusted Power Mode helper source'
require_literal "$INSTALLER" 'power_profile_destination="${SYSTEM_LIBEXEC_DIR}/power-profile-helper"' \
  'installer does not stage the Power Mode helper into root-owned libexec'
require_literal "$INSTALLER" "[[ \$(head -n1 -- \"\$POWER_PROFILE_HELPER_SOURCE\") == '#!/usr/bin/bash' ]]" \
  'installer does not validate the Power Mode helper interpreter'
require_literal "$INSTALLER" 'bash -n "$POWER_PROFILE_HELPER_SOURCE"' \
  'installer does not syntax-check the Power Mode helper'
require_literal "$INSTALLER" 'install -m 0755 -o root -g root "$POWER_PROFILE_HELPER_SOURCE" "$temporary"' \
  'installer does not root-own the staged Power Mode helper'

require_literal "$RUNTIME" 'power_profile_update_helper_is_current()' \
  'updater has no Power Mode helper current-state verification'
require_literal "$RUNTIME" 'repair_power_profile_update_helper()' \
  'updater has no Power Mode helper repair function'
require_literal "$RUNTIME" 'local source="${repo_dir}/local/libexec/awtarchy/power-profile-helper"' \
  'updater does not use the release Power Mode helper as source'
require_literal "$RUNTIME" 'local destination="/usr/local/libexec/awtarchy/power-profile-helper"' \
  'updater does not target the fixed root-owned Power Mode helper path'
require_literal "$RUNTIME" 'source_hash="$(/usr/bin/sha256sum "$source" | /usr/bin/awk' \
  'updater does not hash the Power Mode helper source'
require_literal "$RUNTIME" 'installed_hash="$(sudo /usr/bin/sha256sum "$temporary" | /usr/bin/awk' \
  'updater does not hash the staged Power Mode helper'
require_literal "$RUNTIME" 'sudo /usr/bin/install -m 0755 -o root -g root "$source" "$temporary"' \
  'updater does not root-own the staged Power Mode helper'
require_literal "$RUNTIME" 'sudo /usr/bin/mv -Tf -- "$temporary" "$destination"' \
  'updater does not atomically activate the Power Mode helper'
require_literal "$RUNTIME" 'repair_power_profile_update_helper "$repo_dir"' \
  'normal updater does not repair the trusted Power Mode helper'

require_absent "$INSTALLER" 'NOPASSWD: /usr/local/libexec/awtarchy/power-profile-helper' \
  'installer grants persistent passwordless Power Mode helper access'
require_absent "$RUNTIME" 'NOPASSWD: /usr/local/libexec/awtarchy/power-profile-helper' \
  'updater grants persistent passwordless Power Mode helper access'

printf '%s\n' 'PASS: installer/updater provision the trusted Power Mode helper without broad passwordless sudo.'
