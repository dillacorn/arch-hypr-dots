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

capture_body="$(function_body "$CORE" scxctl_run_capture)"
status_body="$(function_body "$BACKEND" machine_status)"
start_body="$(function_body "$BACKEND" machine_scheduler_start)"
stop_body="$(function_body "$BACKEND" machine_scheduler_stop)"

[[ "$capture_body" == *'get|list)'* ]] \
  || fail 'passive scxctl get/list reads are not explicitly separated from privileged operations'
[[ "$capture_body" == *'run_capture "$SCXCTL_HELPER" "$@"'* ]] \
  || fail 'passive scxctl reads do not call the trusted helper directly'

[[ "$status_body" == *'scxctl_auth_state_cached'* ]] \
  || fail 'Quick Settings status still has no non-sudo cached authorization state'
[[ "$status_body" != *'sudo_can_run_scxctl_noninteractive'* ]] \
  || fail 'Quick Settings passive status still probes sudo authorization'

[[ "$start_body" == *'sudo_can_run_scxctl_noninteractive'* ]] \
  || fail 'scheduler start no longer enforces the restricted sudo helper'
[[ "$stop_body" == *'sudo_can_run_scxctl_noninteractive'* ]] \
  || fail 'scheduler stop no longer enforces the restricted sudo helper'

grep -Fq 'scxctl_auth_state_cached()' "$CORE" \
  || fail 'cached scheduler authorization state helper is missing'
grep -Fq 'scxctl_auth_state_mark()' "$CORE" \
  || fail 'successful scheduler authorization is not persisted for passive UI status'
grep -Fq 'scxctl_auth_state_clear()' "$CORE" \
  || fail 'stale scheduler authorization state cannot be cleared'

printf '%s\n' 'PASS: passive sched-ext status avoids sudo while privileged scheduler actions remain enforced.'
