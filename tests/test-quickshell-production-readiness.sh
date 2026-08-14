#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_absent() {
  local rel="$1"
  [[ ! -e "${REPO_ROOT}/${rel}" ]] || fail "temporary conversion artifact still ships: ${rel}"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "${file#"${REPO_ROOT}/"} still contains temporary marker: ${needle}"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "${file#"${REPO_ROOT}/"} is missing required production behavior: ${needle}"
}

for rel in \
  local/bin/awtarchy-quickshell \
  QUICKSHELL_CONVERSION.md \
  config/quickshell/awtarchy/quickshell_flyout_handoff_test.py \
  config/quickshell/awtarchy/quickshell_flyout_warp_guard_test.py \
  tests/test-awtarchy-quickshell-isolation.sh
do
  assert_absent "$rel"
done

INSTALLER="${REPO_ROOT}/awtarchy-install.sh"
WORKFLOW="${REPO_ROOT}/.github/workflows/validate-awtarchy.yml"
LAUNCHER="${REPO_ROOT}/local/bin/awtarchy"
RUNTIME="${REPO_ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
WIREGUARD="${REPO_ROOT}/config/hypr/scripts/quickshell_wireguard.sh"
SHELL_MANAGER="${REPO_ROOT}/config/hypr/scripts/quickshell.sh"
APP_STATE="${REPO_ROOT}/config/hypr/scripts/quickshell_application_state.sh"

assert_not_contains "$INSTALLER" '--quickshell-command'
assert_not_contains "$INSTALLER" 'awtarchy-quickshell'
assert_not_contains "$WORKFLOW" 'quickshell-conversion-testing'
assert_not_contains "$WORKFLOW" 'local/bin/awtarchy-quickshell'

# Help and version are read-only inspection commands. They must not create ~/vpn.
HOME_DIR="${TMPD}/home"
FAKE_BIN="${TMPD}/bin"
mkdir -p -- "$HOME_DIR" "$FAKE_BIN"
cat >"${FAKE_BIN}/curl" <<'EOF_CURL'
#!/usr/bin/env bash
exit 22
EOF_CURL
chmod 0755 "${FAKE_BIN}/curl"

COMMON_ENV=(
  "HOME=${HOME_DIR}"
  "USER=$(id -un)"
  "LOGNAME=$(id -un)"
  "PATH=${FAKE_BIN}:${PATH}"
  "AWTARCHY_SKIP_UPDATE_CHECK=1"
)

env "${COMMON_ENV[@]}" bash "$LAUNCHER" help >/dev/null
[[ ! -e "${HOME_DIR}/vpn" ]] || fail 'awtarchy help created ~/vpn'

env "${COMMON_ENV[@]}" bash "$LAUNCHER" version >/dev/null
[[ ! -e "${HOME_DIR}/vpn" ]] || fail 'awtarchy version created ~/vpn'

# User-provided WireGuard profiles must not inject root command hooks, and the
# elevated executable must be the trusted Arch wireguard-tools path.
assert_contains "$WIREGUARD" 'WG_QUICK="/usr/bin/wg-quick"'
assert_not_contains "$WIREGUARD" 'command -v wg-quick'

VPN_DIR="${TMPD}/vpn"
mkdir -p -- "$VPN_DIR"
cat >"${VPN_DIR}/unsafe.conf" <<'EOF_PROFILE'
[Interface]
PrivateKey = test
Address = 10.0.0.2/32
PostUp = /bin/sh -c 'touch /tmp/awtarchy-wireguard-hook-ran'

[Peer]
PublicKey = test
AllowedIPs = 0.0.0.0/0
EOF_PROFILE

if AWTARCHY_VPN_DIR="$VPN_DIR" HOME="$HOME_DIR" bash "$WIREGUARD" up unsafe >"${TMPD}/wg.out" 2>"${TMPD}/wg.err"; then
  fail 'WireGuard profile containing a privileged hook was accepted'
fi
grep -Eqi 'hook|PreUp|PostUp|PreDown|PostDown' "${TMPD}/wg.err" \
  || fail 'WireGuard hook rejection did not explain the unsafe profile'

# Both writers of quickshell-state.json must serialize through the same lock.
assert_contains "$SHELL_MANAGER" 'STATE_LOCK_FILE="${STATE_FILE}.lock"'
assert_contains "$SHELL_MANAGER" 'flock -x'
assert_contains "$APP_STATE" 'STATE_LOCK_FILE="${STATE_FILE}.lock"'
assert_contains "$APP_STATE" 'flock -x'

# A production updater can self-refresh before a matching Quickshell release is
# published. It must detect a pre-Quickshell release before invoking migration
# normalization or retiring Waybar/Fuzzel-era files.
assert_contains "$RUNTIME" 'quickshell_update_target_ready'
python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
main_start = text.index('main() {', text.index('update_reset_backup_main()'))
main_end = text.index('\nmain "$@"', main_start)
main = text[main_start:main_end]

gate = main.find('quickshell_update_target_ready')
build = main.find('build_target_home "$repo_dir" "$target_home"')
prepare = main.find('prepare_quickshell_update_target "$target_home"')
if gate < 0 or build < 0 or prepare < 0:
    raise SystemExit('FAIL: updater production-readiness gate or migration calls are missing')
if not (gate < build and gate < prepare):
    raise SystemExit('FAIL: updater checks Quickshell release readiness too late')
PY

printf 'PASS: Quickshell production readiness regressions\n'
