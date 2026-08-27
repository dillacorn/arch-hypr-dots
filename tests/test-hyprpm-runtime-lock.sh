#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AUTO_RELOAD="${ROOT}/config/hypr/scripts/hyprpm-auto-reload.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

fakebin="${TMP}/bin"
runtime="${TMP}/runtime"
home="${TMP}/home"
hyprpm_log="${TMP}/hyprpm.log"
mkdir -p -- "$fakebin" "$runtime/awtarchy" "$home"
: >"$hyprpm_log"

cat >"$fakebin/hyprpm" <<'EOF_HYPRPM'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_HYPRPM_LOG:?}"
if [[ ${TEST_HYPRPM_FAIL_RELOAD:-0} == 1 && ${1:-} == reload ]]; then
  exit 1
fi
EOF_HYPRPM
chmod 0755 "$fakebin/hyprpm"

# A recent per-user runtime lock must suppress an explicit live reconcile.
date +%s >"$runtime/awtarchy/hyprpm-auto-reload.lock"

env -u HYPRLAND_INSTANCE_SIGNATURE \
  PATH="$fakebin:$PATH" \
  HOME="$home" \
  USER=tester \
  XDG_RUNTIME_DIR="$runtime" \
  XDG_CACHE_HOME="$home/.cache" \
  XDG_STATE_HOME="$home/.local/state" \
  HYPRPM_AUTO_LIVE_RELOAD=1 \
  TEST_HYPRPM_LOG="$hyprpm_log" \
  bash "$AUTO_RELOAD"

[[ ! -s "$hyprpm_log" ]] \
  || fail 'per-user runtime lock did not suppress live hyprpm reconciliation'

# The explicit repair path must also be able to create the per-user lock when
# the session directory does not already exist.
rm -rf -- "$runtime/awtarchy"
: >"$hyprpm_log"

env -u HYPRLAND_INSTANCE_SIGNATURE \
  PATH="$fakebin:$PATH" \
  HOME="$home" \
  USER=tester \
  XDG_RUNTIME_DIR="$runtime" \
  XDG_CACHE_HOME="$home/.cache" \
  XDG_STATE_HOME="$home/.local/state" \
  HYPRPM_AUTO_LIVE_RELOAD=1 \
  TEST_HYPRPM_FAIL_RELOAD=1 \
  TEST_HYPRPM_LOG="$hyprpm_log" \
  bash "$AUTO_RELOAD"

[[ -f "$runtime/awtarchy/hyprpm-auto-reload.lock" ]] \
  || fail 'explicit live reconcile could not create its per-user runtime lock'
[[ "$(cat "$runtime/awtarchy/hyprpm-auto-reload.lock")" =~ ^[0-9]+$ ]] \
  || fail 'per-user runtime lock did not contain a timestamp'

! grep -Fq '/tmp/hyprpm-auto-reload.lock' "$AUTO_RELOAD" \
  || fail 'hyprpm live-reconcile lock still defaults to shared /tmp state'
grep -Fq 'LOCK_FILE="${HYPRPM_AUTO_LOCK_FILE:-${SESSION_DIR}/hyprpm-auto-reload.lock}"' "$AUTO_RELOAD" \
  || fail 'hyprpm live-reconcile lock is not scoped to the per-user session directory'

printf 'PASS: hyprpm live-reconcile lock is per-user runtime state\n'
