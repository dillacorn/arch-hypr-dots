#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="${ROOT}/config/hypr/scripts/hypr_quicksettings_core.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
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

printf '%s\n' 'PASS: explicit sched-ext authorization repairs stale rules without trusting cached sudo credentials.'
