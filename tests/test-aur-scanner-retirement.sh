#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASHRC="${ROOT}/bashrc"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
VALIDATE="${ROOT}/.github/workflows/validate-awtarchy.yml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" text="$2"
  grep -Fq -- "$text" "$file" \
    || fail "${file#"$ROOT"/} is missing final aur-scanner contract: $text"
}

obsolete_paths=(
  .github/workflows/apply-aur-scan-integration.yml
  tests/test-aur-scan-self-heal.sh
  tests/test-aur-scan-checkout-delegation.sh
)
for rel in "${obsolete_paths[@]}"; do
  [[ ! -e "${ROOT}/${rel}" && ! -L "${ROOT}/${rel}" ]] \
    || fail "obsolete AurGuard integration artifact remains: $rel"
done

bash -n "$BASHRC"
bash -n "$RUNTIME"
bash -n "$RECONCILER"

if grep -Fq '_AUR_GUARD_' "$BASHRC" || grep -Fq '_aur_guard_' "$BASHRC"; then
  fail 'shipping bashrc still contains AurGuard implementation state/helpers'
fi
for retired in aurguard aurguardtest aurverify aurinstall aurup aurunsafe aurcheck aurremove auruninstall; do
  if grep -Eq "^${retired}[[:space:]]*\\(\\)" "$BASHRC"; then
    fail "shipping bashrc still defines retired AurGuard command: $retired"
  fi
done

assert_contains "$BASHRC" 'aur-scan install <package>'
assert_contains "$BASHRC" 'command aur-scan -h'
# shellcheck disable=SC2016
assert_contains "$RUNTIME" 'run_as_target /usr/bin/aur-scan install "$@" --noconfirm'
assert_contains "$RUNTIME" 'target_uses_direct_aur_scanner()'
assert_contains "$RUNTIME" 'ensure_update_aur_scanner()'
# shellcheck disable=SC2016
assert_contains "$RECONCILER" '"$AUR_SCAN_BIN" install "$pkg" --noconfirm'

required_tests=(
  tests/test-installer-aur-scanner-delegation.sh
  tests/test-aur-scanner-updater-migration.sh
  tests/test-aur-helper-policy.sh
  tests/test-aur-scanner-docs.sh
  tests/test-aur-scanner-retirement.sh
)

assert_contains "$VALIDATE" 'bash -n bashrc'
assert_contains "$VALIDATE" '            bashrc \'
for test_path in "${required_tests[@]}"; do
  [[ -f "${ROOT}/${test_path}" ]] || fail "missing replacement scanner regression: $test_path"
  assert_contains "$VALIDATE" "bash -n ${test_path}"
  assert_contains "$VALIDATE" "bash ${test_path}"
done

printf '%s\n' 'PASS: AurGuard implementation artifacts are retired and repository-wide CI owns the replacement aur-scanner contracts.'
