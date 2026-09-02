from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


bashrc = Path("bashrc")
text = bashrc.read_text(encoding="utf-8")

text = replace_once(
    text,
    "_AUR_GUARD_AUR_SCAN_PACKAGE='aur-scanner'\n_AUR_GUARD_AUR_SCAN_SIGNING_KEY=",
    "_AUR_GUARD_AUR_SCAN_PACKAGE='aur-scanner'\n_AUR_GUARD_AUR_SCAN_PATH='/usr/bin/aur-scan'\n_AUR_GUARD_AUR_SCAN_SIGNING_KEY=",
    "aur-scan trusted path constant",
)

helper_anchor = "declare -a _AUR_GUARD_SCAN_REVIEW_FINDINGS=()\n"
helper = r'''_aur_guard_resolve_aur_scan() {
  local scanner="${_AUR_GUARD_AUR_SCAN_PATH:-/usr/bin/aur-scan}"
  local owner

  [[ -f "$scanner" && ! -L "$scanner" && -x "$scanner" ]] || return 1
  owner=$(command pacman --query --owns --quiet "$scanner" 2>/dev/null) || return 1

  case "$owner" in
    aur-scanner|ks-aur-scanner)
      printf '%s\n' "$scanner"
      ;;
    *)
      return 1
      ;;
  esac
}

'''
if "_aur_guard_resolve_aur_scan()" in text:
    raise SystemExit("trusted aur-scan resolver already exists")
text = replace_once(text, helper_anchor, helper + helper_anchor, "aur-scan resolver insertion")

text = replace_once(
    text,
    '''  scanner=$(type -P aur-scan 2>/dev/null) || {
    _aur_guard_fail "aur-scan is required before evaluating $pkg. Install $_AUR_GUARD_AUR_SCAN_PACKAGE with: aurinstall $_AUR_GUARD_AUR_SCAN_PACKAGE"
    return 127
  }
''',
    '''  scanner=$(_aur_guard_resolve_aur_scan) || {
    _aur_guard_fail "trusted package-owned aur-scan is required before evaluating $pkg. Install $_AUR_GUARD_AUR_SCAN_PACKAGE with: aurinstall $_AUR_GUARD_AUR_SCAN_PACKAGE"
    return 127
  }
''',
    "scanner resolution",
)

text = replace_once(
    text,
    "  type -P aur-scan >/dev/null 2>&1 && return 0\n",
    "  _aur_guard_resolve_aur_scan >/dev/null 2>&1 && return 0\n",
    "scanner ensure fast path",
)

text = replace_once(
    text,
    '''  type -P aur-scan >/dev/null 2>&1 || {
    _aur_guard_fail "$_AUR_GUARD_AUR_SCAN_PACKAGE installed without providing aur-scan"
    return 127
  }
''',
    '''  _aur_guard_resolve_aur_scan >/dev/null 2>&1 || {
    _aur_guard_fail "$_AUR_GUARD_AUR_SCAN_PACKAGE installed without providing a trusted package-owned aur-scan"
    return 127
  }
''',
    "scanner ensure post-bootstrap check",
)

bashrc.write_text(text, encoding="utf-8")

security = Path("tests/test-security-boundaries.sh")
text = security.read_text(encoding="utf-8")
text = replace_once(
    text,
    '''assert_contains "$BASHRC" "_AUR_GUARD_AUR_SCAN_PACKAGE='aur-scanner'"
assert_contains "$BASHRC" '_aur_guard_scan_checkout_with_aur_scan()'
''',
    '''assert_contains "$BASHRC" "_AUR_GUARD_AUR_SCAN_PACKAGE='aur-scanner'"
assert_contains "$BASHRC" "_AUR_GUARD_AUR_SCAN_PATH='/usr/bin/aur-scan'"
assert_contains "$BASHRC" '_aur_guard_resolve_aur_scan()'
assert_contains "$BASHRC" '_aur_guard_scan_checkout_with_aur_scan()'
''',
    "security static scanner assertions",
)
text = replace_once(
    text,
    '''cat >"$aur_scan_runner" <<'EOF_AUR_SCAN_RUNNER'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_AUR_GUARD_FIXTURE:?}"
_aur_guard_scan_checkout_with_aur_scan fixture "${AWTARCHY_TEST_AUR_SCAN_PKGDIR:?}"
EOF_AUR_SCAN_RUNNER
chmod 0755 "${aur_scan_fakebin}/aur-scan" "$aur_scan_runner"
''',
    '''cat >"${aur_scan_fakebin}/pacman" <<'EOF_AUR_SCAN_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *' --query --owns --quiet '*) printf '%s\\n' aur-scanner ;;
  *) exit 1 ;;
esac
EOF_AUR_SCAN_PACMAN
cat >"$aur_scan_runner" <<'EOF_AUR_SCAN_RUNNER'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_AUR_GUARD_FIXTURE:?}"
_AUR_GUARD_AUR_SCAN_PATH="${AWTARCHY_TEST_AUR_SCAN_PATH:?}"
_aur_guard_scan_checkout_with_aur_scan fixture "${AWTARCHY_TEST_AUR_SCAN_PKGDIR:?}"
EOF_AUR_SCAN_RUNNER
chmod 0755 "${aur_scan_fakebin}/aur-scan" "${aur_scan_fakebin}/pacman" "$aur_scan_runner"
''',
    "security scanner fixture",
)
text = replace_once(
    text,
    '''    AWTARCHY_TEST_AUR_SCAN_LOG="$aur_scan_log" \\
    AWTARCHY_TEST_AUR_GUARD_FIXTURE="$aur_guard_fixture" \\
''',
    '''    AWTARCHY_TEST_AUR_SCAN_LOG="$aur_scan_log" \\
    AWTARCHY_TEST_AUR_SCAN_PATH="${aur_scan_fakebin}/aur-scan" \\
    AWTARCHY_TEST_AUR_GUARD_FIXTURE="$aur_guard_fixture" \\
''',
    "clean scanner trusted path env",
)
text = replace_once(
    text,
    '''    AWTARCHY_TEST_AUR_SCAN_LOG="$aur_scan_log" \\
    AWTARCHY_TEST_AUR_SCAN_STATUS=42 \\
    AWTARCHY_TEST_AUR_GUARD_FIXTURE="$aur_guard_fixture" \\
''',
    '''    AWTARCHY_TEST_AUR_SCAN_LOG="$aur_scan_log" \\
    AWTARCHY_TEST_AUR_SCAN_STATUS=42 \\
    AWTARCHY_TEST_AUR_SCAN_PATH="${aur_scan_fakebin}/aur-scan" \\
    AWTARCHY_TEST_AUR_GUARD_FIXTURE="$aur_guard_fixture" \\
''',
    "failing scanner trusted path env",
)

text = replace_once(
    text,
    '''source "${AWTARCHY_TEST_AUR_GUARD_FIXTURE:?}"

aurinstall() {
''',
    '''source "${AWTARCHY_TEST_AUR_GUARD_FIXTURE:?}"
_AUR_GUARD_AUR_SCAN_PATH="${AWTARCHY_TEST_AUR_SCAN_BOOTSTRAP_FAKEBIN:?}/aur-scan"

aurinstall() {
''',
    "bootstrap trusted scanner path",
)
text = replace_once(
    text,
    '''_AUR_GUARD_AUR_SCAN_BOOTSTRAP=0
_aur_guard_ensure_aur_scan fixture
[[ ${_AUR_GUARD_AUR_SCAN_BOOTSTRAP:-0} == 0 ]]
type -P aur-scan >/dev/null 2>&1
EOF_AUR_SCAN_BOOTSTRAP_RUNNER
chmod 0755 "$aur_scan_bootstrap_runner"
''',
    '''_AUR_GUARD_AUR_SCAN_BOOTSTRAP=0
_aur_guard_ensure_aur_scan fixture
[[ ${_AUR_GUARD_AUR_SCAN_BOOTSTRAP:-0} == 0 ]]
_aur_guard_resolve_aur_scan >/dev/null
EOF_AUR_SCAN_BOOTSTRAP_RUNNER
cat >"${aur_scan_bootstrap_fakebin}/pacman" <<'EOF_AUR_SCAN_BOOTSTRAP_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *' --query --owns --quiet '*)
    [[ -x ${AWTARCHY_TEST_AUR_SCAN_BOOTSTRAP_FAKEBIN:?}/aur-scan ]] || exit 1
    printf '%s\\n' aur-scanner
    ;;
  *) exit 1 ;;
esac
EOF_AUR_SCAN_BOOTSTRAP_PACMAN
chmod 0755 "$aur_scan_bootstrap_runner" "${aur_scan_bootstrap_fakebin}/pacman"
''',
    "bootstrap ownership fixture",
)
security.write_text(text, encoding="utf-8")

review = Path("tests/test-aur-scan-review-policy.sh")
text = review.read_text(encoding="utf-8")
text = replace_once(
    text,
    '''EOF_AUR_SCAN
chmod 0755 "${fakebin}/aur-scan"
''',
    '''EOF_AUR_SCAN
cat >"${fakebin}/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *' --query --owns --quiet '*) printf '%s\\n' aur-scanner ;;
  *) exit 1 ;;
esac
EOF_PACMAN
chmod 0755 "${fakebin}/aur-scan" "${fakebin}/pacman"
''',
    "review policy pacman fixture",
)
text = replace_once(
    text,
    '''source "${AWTARCHY_TEST_FIXTURE:?}"

declare -F _aur_guard_has_scan_review >/dev/null \\
''',
    '''source "${AWTARCHY_TEST_FIXTURE:?}"
_AUR_GUARD_AUR_SCAN_PATH="${AWTARCHY_TEST_AUR_SCAN_PATH:?}"

declare -F _aur_guard_has_scan_review >/dev/null \\
''',
    "review policy trusted scanner path",
)
text = replace_once(
    text,
    '''    AWTARCHY_TEST_FIXTURE="$fixture" \\
    AWTARCHY_TEST_PKGDIR="$pkgdir" \\
''',
    '''    AWTARCHY_TEST_FIXTURE="$fixture" \\
    AWTARCHY_TEST_AUR_SCAN_PATH="${fakebin}/aur-scan" \\
    AWTARCHY_TEST_PKGDIR="$pkgdir" \\
''',
    "review policy env",
)
review.write_text(text, encoding="utf-8")
