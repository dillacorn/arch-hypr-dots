#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="${ROOT}/config/hypr/scripts/hypr_quicksettings_core.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

! grep -Fq 'sudo test -f "$sudoers_target" && sudo_can_run_scxctl_noninteractive' "$CORE" \
  || fail 'authorization still trusts a cached sudo timestamp when a stale rule exists'

grep -Fq 'sudo -k' "$CORE" \
  || fail 'authorization does not invalidate cached sudo before final NOPASSWD verification'
grep -Fq 'sudo -n "$SCXCTL_HELPER" list >/dev/null 2>&1' "$CORE" \
  || fail 'authorization does not cold-test the restricted helper after installing the rule'

printf '%s\n' 'PASS: stale scxctl rules are replaced and verified without cached sudo credentials.'
