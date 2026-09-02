#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASHRC="${ROOT}/bashrc"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "${file#"${ROOT}/"} is missing: ${needle}"
}

fingerprint='25631EAE3F43999050B7D7021132BF893C33FB51'
assert_contains "$BASHRC" "_AUR_GUARD_AUR_SCAN_SIGNING_KEY='${fingerprint}'"
assert_contains "$BASHRC" '_aur_guard_ensure_aur_scan_signing_key()'
# shellcheck disable=SC2016
assert_contains "$BASHRC" '_aur_guard_ensure_aur_scan "$pkg"'

python3 - "$BASHRC" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index('_aur_guard_ensure_aur_scan() {')
end = text.index('\naurverify() {', start)
body = text[start:end]
key = body.index('_aur_guard_ensure_aur_scan_signing_key')
install = body.index('aurinstall "$_AUR_GUARD_AUR_SCAN_PACKAGE"')
if not key < install:
    raise SystemExit('aur-scanner signing key is not prepared before bootstrap install')

verify_start = text.index('aurverify() {')
verify_end = text.index('\naurinstall() {', verify_start)
verify_body = text[verify_start:verify_end]
ensure = verify_body.index('_aur_guard_ensure_aur_scan "$pkg"')
verify = verify_body.index('_aur_guard_verify_tree "$pkg"')
if not ensure < verify:
    raise SystemExit('aurverify does not self-heal aur-scan before verification')
PY

fixture="${TMPD}/bashrc-fixture"
fakebin="${TMPD}/fakebin"
order_log="${TMPD}/order.log"
gpg_log="${TMPD}/gpg.log"
mkdir -p -- "$fakebin"
sed 's/^\[\[ \$- != \*i\* \]\] && return$/:/' "$BASHRC" >"$fixture"

cat >"${fakebin}/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
exit 1
EOF_PACMAN

cat >"${fakebin}/gpg" <<'EOF_GPG'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"${AWTARCHY_TEST_GPG_LOG:?}"
printf '\n' >>"${AWTARCHY_TEST_GPG_LOG:?}"
case " $* " in
  *' --list-keys '*) exit 1 ;;
  *' --recv-keys '*) exit 0 ;;
  *' --with-colons '*--fingerprint' '*)
    printf 'fpr:::::::::%s:\n' "${AWTARCHY_TEST_SIGNING_KEY:?}"
    exit 0
    ;;
esac
exit 0
EOF_GPG
chmod 0755 "${fakebin}/pacman" "${fakebin}/gpg"

runner="${TMPD}/runner"
cat >"$runner" <<'EOF_RUNNER'
#!/usr/bin/env bash
set -euo pipefail
export AUR_GUARD_TEST_MODE=1
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_AUR_GUARD_FIXTURE:?}"

_aur_guard_validate_package_name() { return 0; }
_aur_guard_ensure_aur_scan() {
  printf '%s\n' ensure >>"${AWTARCHY_TEST_ORDER_LOG:?}"
  return 0
}
_aur_guard_verify_tree() {
  printf '%s\n' verify >>"${AWTARCHY_TEST_ORDER_LOG:?}"
  return 0
}
_aur_guard_has_guarded_matches() { return 1; }
_aur_guard_cleanup_work() { return 0; }

: >"${AWTARCHY_TEST_ORDER_LOG:?}"
aurverify fixture >/dev/null
mapfile -t order <"${AWTARCHY_TEST_ORDER_LOG:?}"
[[ ${#order[@]} -eq 2 ]]
[[ ${order[0]} == ensure ]]
[[ ${order[1]} == verify ]]
EOF_RUNNER
chmod 0755 "$runner"

env \
  "PATH=${fakebin}:/usr/bin:/bin" \
  AWTARCHY_TEST_AUR_GUARD_FIXTURE="$fixture" \
  AWTARCHY_TEST_ORDER_LOG="$order_log" \
  "$runner" || fail 'aurverify did not self-heal aur-scan before verification'

key_runner="${TMPD}/key-runner"
cat >"$key_runner" <<'EOF_KEY_RUNNER'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_AUR_GUARD_FIXTURE:?}"
_aur_guard_ensure_aur_scan_signing_key
EOF_KEY_RUNNER
chmod 0755 "$key_runner"

env \
  "PATH=${fakebin}:/usr/bin:/bin" \
  AWTARCHY_TEST_AUR_GUARD_FIXTURE="$fixture" \
  AWTARCHY_TEST_GPG_LOG="$gpg_log" \
  AWTARCHY_TEST_SIGNING_KEY="$fingerprint" \
  "$key_runner" || fail 'AurGuard could not self-heal the aur-scanner signing key'

grep -Fq -- '--recv-keys' "$gpg_log" || fail 'AurGuard did not fetch the missing aur-scanner signing key'
grep -Fq -- "$fingerprint" "$gpg_log" || fail 'AurGuard did not pin the expected aur-scanner signing fingerprint'

printf '%s\n' 'PASS: aur-scan self-healing bootstrap boundary'
