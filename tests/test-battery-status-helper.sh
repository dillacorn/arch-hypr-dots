#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/battery-status-helper"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-power-profile.sh"
TMP="$(mktemp -d)"
trap 'sudo -n rm -rf -- "$TMP/protected-sudoers" 2>/dev/null || true; rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "$HELPER" ]] || fail 'battery status helper is missing'
grep -Fq '#!/usr/bin/bash' "$HELPER" || fail 'helper interpreter is not fixed'
grep -Fq '[[ $# -eq 0 ]]' "$HELPER" || fail 'helper does not reject arguments'
grep -Fq '(( EUID == 0 ))' "$HELPER" || fail 'helper is not root-only'
grep -Fq '/usr/bin/env -i' "$HELPER" || fail 'helper does not sanitize its environment'
grep -Fq '/usr/bin/tlp-stat -b' "$HELPER" || fail 'helper does not execute the fixed battery report'
! grep -Fq '"$@"' "$HELPER" || fail 'helper forwards caller-controlled arguments'
! grep -Eq '/usr/bin/tlp([[:space:]]|$)' "$HELPER" || fail 'helper contains a battery write command'

# The sudoers principal must come from the actual invoking UID, not a caller-
# controlled USER environment variable. A malicious/stale USER value must not
# redirect the passwordless read-only helper rule to another account.
cp -- "$RECONCILER" "$TMP/reconciler-policy-user"
python3 - "$TMP/reconciler-policy-user" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = 'main "$@"'
if text.count(old) != 1:
    raise SystemExit('expected exactly one reconciler main invocation')
path.write_text(text.replace(old, ': # test copy: do not run reconciler main'))
PY
chmod 0755 "$TMP"
chmod 0644 "$TMP/reconciler-policy-user"

if (( EUID == 0 )); then
  policy_test_user="${SUDO_USER:-}"
  [[ -n "$policy_test_user" && "$policy_test_user" != root ]] \
    || fail 'root-run policy-user regression requires a non-root SUDO_USER'
  expected_user="$policy_test_user"
  if ! policy_user="$(
    /usr/bin/sudo -u "$policy_test_user" /usr/bin/env USER=root \
      /usr/bin/bash -c 'source "$1"; battery_status_policy_user' _ "$TMP/reconciler-policy-user" \
      2>"$TMP/policy-user.err"
  )"; then
    fail "Battery Care status policy trusted spoofed USER instead of the invoking UID: $(cat "$TMP/policy-user.err")"
  fi
else
  expected_user="$(/usr/bin/id -un)"
  if ! policy_user="$(
    USER=root /usr/bin/bash -c 'source "$1"; battery_status_policy_user' _ "$TMP/reconciler-policy-user" \
      2>"$TMP/policy-user.err"
  )"; then
    fail "Battery Care status policy trusted spoofed USER instead of the invoking UID: $(cat "$TMP/policy-user.err")"
  fi
fi
[[ "$policy_user" == "$expected_user" ]] \
  || fail "Battery Care status policy resolved '$policy_user' instead of invoking user '$expected_user'"

# Privileged helper sources are regular repository files and are installed as
# executable root-owned copies by the reconciler. Exercise the source through
# its fixed interpreter rather than depending on repository file mode.
if /usr/bin/bash "$HELPER" unexpected >"$TMP/arg.out" 2>"$TMP/arg.err"; then
  fail 'helper accepted an argument'
fi
grep -Fq 'no arguments are accepted' "$TMP/arg.err" \
  || fail 'argument rejection did not fail for the intended reason'

if (( EUID != 0 )); then
  if /usr/bin/bash "$HELPER" >"$TMP/root.out" 2>"$TMP/root.err"; then
    fail 'helper executed without root privileges'
  fi
  grep -Fq 'root privileges are required' "$TMP/root.err" \
    || fail 'unprivileged execution did not fail for the intended reason'
fi

cat >"$TMP/fake-tlp-stat" <<'EOF_TLP'
#!/usr/bin/env bash
printf 'fixed-report\n'
printf 'attack=%s\n' "${ATTACK-unset}"
exit 23
EOF_TLP
chmod 0755 "$TMP/fake-tlp-stat"

cp -- "$HELPER" "$TMP/helper-under-test"
python3 - "$TMP/helper-under-test" "$TMP/fake-tlp-stat" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = '/usr/bin/tlp-stat -b'
new = f'{sys.argv[2]} -b'
if text.count(old) != 1:
    raise SystemExit('expected exactly one fixed tlp-stat invocation')
path.write_text(text.replace(old, new))
PY

command -v sudo >/dev/null 2>&1 || fail 'sudo is required for the root helper behavior test'
sudo -n true >/dev/null 2>&1 || fail 'passwordless/noninteractive sudo is required for the root helper behavior test'

# /etc/sudoers.d is commonly root-owned 0750. The reconciler must inspect
# policy entries through root rather than relying on the desktop user being able
# to traverse the directory. This reproduces the real Arch failure where the
# installed policy was valid but the unprivileged post-install verifier could
# not see it.
if (( EUID != 0 )); then
  protected_sudoers="$TMP/protected-sudoers"
  reconciler_protected="$TMP/reconciler-protected-sudoers"
  sudo install -d -m 0750 -o root -g root "$protected_sudoers"
  cp -- "$RECONCILER" "$reconciler_protected"
  python3 - "$reconciler_protected" "$protected_sudoers" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
sudoers_dir = sys.argv[2]
text = path.read_text()
old_dir = 'SUDOERS_DIR="/etc/sudoers.d"'
old_main = 'main "$@"'
if text.count(old_dir) != 1:
    raise SystemExit('expected exactly one sudoers directory assignment')
if text.count(old_main) != 1:
    raise SystemExit('expected exactly one reconciler main invocation')
text = text.replace(old_dir, f'SUDOERS_DIR="{sudoers_dir}"', 1)
text = text.replace(old_main, ': # test copy: do not run reconciler main', 1)
path.write_text(text)
PY

  if ! /usr/bin/bash -c 'source "$1"; install_battery_status_policy' _ "$reconciler_protected" \
      >"$TMP/protected-install.out" 2>"$TMP/protected-install.err"; then
    fail "Battery Care policy could not verify inside root-only sudoers directory: $(cat "$TMP/protected-install.err")"
  fi

  protected_policy="${protected_sudoers}/awtarchy-battery-status-${expected_user}"
  sudo stat -c '%F %u %a' -- "$protected_policy" | grep -Fxq 'regular file 0 440' \
    || fail 'protected sudoers policy was not installed root-owned mode 0440'

  printf '%s\n' '# Foreign policy: must not be overwritten.' \
    | sudo tee -- "$protected_policy" >/dev/null
  sudo chmod 0440 "$protected_policy"
  sudo chown root:root "$protected_policy"

  set +e
  /usr/bin/bash -c 'source "$1"; install_battery_status_policy' _ "$reconciler_protected" \
    >"$TMP/protected-foreign.out" 2>"$TMP/protected-foreign.err"
  protected_rc=$?
  set -e
  (( protected_rc != 0 )) \
    || fail 'reconciler overwrote a non-Awtarchy policy hidden behind root-only sudoers permissions'
  sudo cat -- "$protected_policy" | grep -Fxq '# Foreign policy: must not be overwritten.' \
    || fail 'non-Awtarchy protected sudoers policy content was modified'
fi

set +e
# The redirects intentionally belong to this unprivileged test shell. Only the
# helper process needs elevation; the captured files stay user-owned under TMP.
# shellcheck disable=SC2024
sudo -n /usr/bin/env ATTACK=present /usr/bin/bash "$TMP/helper-under-test" >"$TMP/report.out" 2>"$TMP/report.err"
rc=$?
set -e
[[ $rc -eq 23 ]] || fail "helper did not preserve tlp-stat exit status (got $rc)"
grep -Fxq 'fixed-report' "$TMP/report.out" || fail 'helper did not preserve tlp-stat stdout'
grep -Fxq 'attack=unset' "$TMP/report.out" || fail 'helper leaked caller environment into tlp-stat'
[[ ! -s "$TMP/report.err" ]] || fail 'helper added unexpected stderr around tlp-stat output'

printf '%s\n' 'PASS: battery status helper and protected sudoers policy handling remain narrow, root-safe, and read-only.'