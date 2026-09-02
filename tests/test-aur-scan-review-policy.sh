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

fixture="${TMPD}/bashrc-fixture"
fakebin="${TMPD}/fakebin"
pkgdir="${TMPD}/pkg"
scan_log="${TMPD}/scan.log"
mkdir -p -- "$fakebin" "$pkgdir"
printf '%s\n' 'pkgname=fixture' >"${pkgdir}/PKGBUILD"
sed 's/^\[\[ \$- != \*i\* \]\] && return$/:/' "$BASHRC" >"$fixture"

cat >"${fakebin}/aur-scan" <<'EOF_AUR_SCAN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"${AWTARCHY_TEST_SCAN_LOG:?}"
case "${AWTARCHY_TEST_SCAN_CASE:-clean}" in
  clean)
    cat <<'JSON'
{"package_name":"fixture","package_version":"1-1","findings":[],"scanned_files":["PKGBUILD"],"timestamp":"2026-09-02T00:00:00Z","scan_duration_ms":1}
JSON
    ;;
  low)
    cat <<'JSON'
{"package_name":"fixture","package_version":"1-1","findings":[{"id":"META-001","severity":"low","category":"suspicious_metadata","title":"Provides impersonation","description":"Package provides another package name","location":{"file":"PKGBUILD","line":11,"column":null,"snippet":"provides=('fixture')"},"recommendation":"Verify alternative package","cwe_id":null,"metadata":{}}],"scanned_files":["PKGBUILD"],"timestamp":"2026-09-02T00:00:00Z","scan_duration_ms":1}
JSON
    ;;
  medium)
    cat <<'JSON'
{"package_name":"fixture","package_version":"1-1","findings":[{"id":"SRC-001","severity":"medium","category":"network_security","title":"Insecure source transport","description":"Source uses HTTP","location":{"file":"PKGBUILD","line":20,"column":null,"snippet":"source=(http://example.invalid/file)"},"recommendation":"Use HTTPS","cwe_id":"CWE-319","metadata":{}}],"scanned_files":["PKGBUILD"],"timestamp":"2026-09-02T00:00:00Z","scan_duration_ms":1}
JSON
    ;;
  high)
    cat <<'JSON'
{"package_name":"fixture","package_version":"1-1","findings":[{"id":"PERSIST-003","severity":"high","category":"persistence","title":"Cron job creation","description":"Creating cron jobs for persistence","location":{"file":"PKGBUILD","line":72,"column":null,"snippet":"rm -r \"$pkgdir\"/etc/cron.daily/"},"recommendation":"Review cron behavior","cwe_id":null,"metadata":{}}],"scanned_files":["PKGBUILD"],"timestamp":"2026-09-02T00:00:00Z","scan_duration_ms":1}
JSON
    ;;
  critical)
    cat <<'JSON'
{"package_name":"fixture","package_version":"1-1","findings":[{"id":"PRIV-002","severity":"critical","category":"privilege_escalation","title":"SUID bit in package()","description":"Function package sets SUID bits","location":{"file":"PKGBUILD","line":34,"column":null,"snippet":"chmod 4755 chrome-sandbox"},"recommendation":"Review sandbox requirement","cwe_id":"CWE-732","metadata":{}}],"scanned_files":["PKGBUILD"],"timestamp":"2026-09-02T00:00:00Z","scan_duration_ms":1}
JSON
    ;;
  malformed)
    printf '%s\n' '{not-json'
    ;;
  operational-failure)
    exit 42
    ;;
  *) exit 99 ;;
esac
EOF_AUR_SCAN
cat >"${fakebin}/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *' --query --owns --quiet '*) printf '%s\n' aur-scanner ;;
  *) exit 1 ;;
esac
EOF_PACMAN
chmod 0755 "${fakebin}/aur-scan" "${fakebin}/pacman"

runner="${TMPD}/runner"
cat >"$runner" <<'EOF_RUNNER'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_FIXTURE:?}"
_AUR_GUARD_AUR_SCAN_PATH="${AWTARCHY_TEST_AUR_SCAN_PATH:?}"

declare -F _aur_guard_has_scan_review >/dev/null \
  || { printf '%s\n' 'missing _aur_guard_has_scan_review' >&2; exit 70; }
declare -F _aur_guard_print_scan_review >/dev/null \
  || { printf '%s\n' 'missing _aur_guard_print_scan_review' >&2; exit 71; }

run_case() {
  local name="$1" expect_review="$2"
  _AUR_GUARD_SCAN_REVIEW_FINDINGS=()
  AWTARCHY_TEST_SCAN_CASE="$name" \
    _aur_guard_scan_checkout_with_aur_scan fixture "${AWTARCHY_TEST_PKGDIR:?}" >/dev/null
  if [[ "$expect_review" == yes ]]; then
    _aur_guard_has_scan_review
  else
    ! _aur_guard_has_scan_review
  fi
}

run_case clean no
run_case low no
run_case medium no
run_case high yes
high_review="$(_aur_guard_print_scan_review)"
grep -Fq -- 'PERSIST-003' <<<"$high_review"
grep -Fq -- 'HIGH' <<<"$high_review"
grep -Fq -- 'Cron job creation' <<<"$high_review"
grep -Fq -- 'cron.daily' <<<"$high_review"

run_case critical yes
critical_review="$(_aur_guard_print_scan_review)"
grep -Fq -- 'PRIV-002' <<<"$critical_review"
grep -Fq -- 'CRITICAL' <<<"$critical_review"
grep -Fq -- 'SUID bit in package()' <<<"$critical_review"
grep -Fq -- 'chrome-sandbox' <<<"$critical_review"

_AUR_GUARD_SCAN_REVIEW_FINDINGS=()
if AWTARCHY_TEST_SCAN_CASE=malformed \
    _aur_guard_scan_checkout_with_aur_scan fixture "${AWTARCHY_TEST_PKGDIR:?}" >/dev/null 2>&1; then
  printf '%s\n' 'malformed scanner JSON was accepted' >&2
  exit 72
fi

_AUR_GUARD_SCAN_REVIEW_FINDINGS=()
if AWTARCHY_TEST_SCAN_CASE=operational-failure \
    _aur_guard_scan_checkout_with_aur_scan fixture "${AWTARCHY_TEST_PKGDIR:?}" >/dev/null 2>&1; then
  printf '%s\n' 'scanner operational failure was accepted' >&2
  exit 73
fi
EOF_RUNNER
chmod 0755 "$runner"

if ! env \
    "PATH=${fakebin}:/usr/bin:/bin" \
    AWTARCHY_TEST_FIXTURE="$fixture" \
    AWTARCHY_TEST_AUR_SCAN_PATH="${fakebin}/aur-scan" \
    AWTARCHY_TEST_PKGDIR="$pkgdir" \
    AWTARCHY_TEST_SCAN_LOG="$scan_log" \
    "$runner"; then
  fail 'structured aur-scan review policy regression failed'
fi

mapfile -t scan_args <"$scan_log"
[[ ${#scan_args[@]} -eq 4 ]] || fail 'aur-scan received an unexpected argument count'
[[ ${scan_args[0]} == scan ]] || fail 'aur-scan did not use scan mode'
[[ ${scan_args[1]} == "$pkgdir" ]] || fail 'aur-scan did not receive the exact checkout path'
[[ ${scan_args[2]} == --format && ${scan_args[3]} == json ]] \
  || fail 'AurGuard must use structured aur-scan JSON without a severity fail gate'

grep -Fq -- '--fail-on' "$scan_log" \
  && fail 'AurGuard still delegates its security verdict to aur-scan --fail-on'

printf '%s\n' 'PASS: aur-scan findings are structured review evidence while operational failures still fail closed.'
