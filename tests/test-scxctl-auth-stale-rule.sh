#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="${ROOT}/config/hypr/scripts/hypr_quicksettings_core.sh"
BACKEND="${ROOT}/config/hypr/scripts/hypr_quicksettings.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

function_body() {
  local file="$1" name="$2"
  awk -v start="^${name}\\(\\) \\{$" '
    $0 ~ start { active=1 }
    active { print }
    active && /^}$/ { exit }
  ' "$file"
}

! grep -Fq "sudo test -f \"\$sudoers_target\" && sudo_can_run_scxctl_noninteractive" "$CORE" \
  || fail 'authorization still trusts a cached sudo timestamp when a stale rule exists'

grep -Fq "local auth_mode=\"\${1:-tty}\" force_repair=\"\${2:-0}\"" "$CORE" \
  || fail 'authorization has no explicit forced-repair mode'
grep -Fq 'if (( force_repair == 0 )) && sudo_can_run_scxctl_noninteractive; then' "$CORE" \
  || fail 'explicit authorization cannot bypass a warm sudo timestamp'
grep -Fq 'stdin)' "$CORE" \
  || fail 'authorization has no stdin authentication mode'
grep -Fq "sudo -S -p '' -v" "$CORE" \
  || fail 'stdin authorization does not feed the password directly to sudo'
grep -Fq 'sudo -k' "$CORE" \
  || fail 'authorization does not invalidate cached sudo credentials'
grep -Fq "sudo -n \"\$SCXCTL_HELPER\" list >/dev/null 2>&1" "$CORE" \
  || fail 'authorization does not cold-test the restricted helper after installing the rule'
grep -Fq "printf '%s ALL=(root) NOPASSWD: %s\\n' \"\$user\" \"\$SCXCTL_HELPER\"" "$CORE" \
  || fail 'authorization does not install the fixed Awtarchy helper rule'
! grep -Fq 'NOPASSWD: /usr/bin/scxctl' "$CORE" \
  || fail 'authorization still grants passwordless access to the external scxctl CLI'

capture_body="$(function_body "$CORE" scxctl_run_capture)"
status_body="$(function_body "$BACKEND" machine_status)"
start_body="$(function_body "$BACKEND" machine_scheduler_start)"
stop_body="$(function_body "$BACKEND" machine_scheduler_stop)"

[[ "$capture_body" == *'get|list)'* ]] \
  || fail 'passive scxctl get/list reads are not separated from privileged operations'
# shellcheck disable=SC2016
[[ "$capture_body" == *'run_capture "$SCXCTL_HELPER" "$@"'* ]] \
  || fail 'passive scxctl reads do not call the trusted helper directly'
[[ "$status_body" == *'scxctl_auth_state_cached'* ]] \
  || fail 'Quick Settings passive status has no non-sudo authorization cache'
[[ "$status_body" != *'sudo_can_run_scxctl_noninteractive'* ]] \
  || fail 'Quick Settings passive status still probes sudo authorization'
[[ "$start_body" == *'sudo_can_run_scxctl_noninteractive'* ]] \
  || fail 'scheduler start no longer enforces the restricted sudo helper'
[[ "$stop_body" == *'sudo_can_run_scxctl_noninteractive'* ]] \
  || fail 'scheduler stop no longer enforces the restricted sudo helper'
grep -Fq 'scxctl_auth_state_cached()' "$CORE" \
  || fail 'cached scheduler authorization state helper is missing'
grep -Fq 'scxctl_auth_state_mark()' "$CORE" \
  || fail 'successful scheduler authorization is not persisted for passive status'
grep -Fq 'scxctl_auth_state_clear()' "$CORE" \
  || fail 'stale scheduler authorization state cannot be cleared'

printf '%s\n' 'PASS: sched-ext authorization stays restricted while passive status avoids sudo probes.'
