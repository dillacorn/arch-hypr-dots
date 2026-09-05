#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/local/libexec/awtarchy/battery-status-helper"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

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

if "$HELPER" unexpected >"$TMP/arg.out" 2>"$TMP/arg.err"; then
  fail 'helper accepted an argument'
fi
grep -Fq 'no arguments are accepted' "$TMP/arg.err" \
  || fail 'argument rejection did not fail for the intended reason'

if (( EUID != 0 )); then
  if "$HELPER" >"$TMP/root.out" 2>"$TMP/root.err"; then
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
chmod 0755 "$TMP/helper-under-test"

command -v sudo >/dev/null 2>&1 || fail 'sudo is required for the root helper behavior test'
sudo -n true >/dev/null 2>&1 || fail 'passwordless/noninteractive sudo is required for the root helper behavior test'

set +e
sudo -n /usr/bin/env ATTACK=present "$TMP/helper-under-test" >"$TMP/report.out" 2>"$TMP/report.err"
rc=$?
set -e
[[ $rc -eq 23 ]] || fail "helper did not preserve tlp-stat exit status (got $rc)"
grep -Fxq 'fixed-report' "$TMP/report.out" || fail 'helper did not preserve tlp-stat stdout'
grep -Fxq 'attack=unset' "$TMP/report.out" || fail 'helper leaked caller environment into tlp-stat'
[[ ! -s "$TMP/report.err" ]] || fail 'helper added unexpected stderr around tlp-stat output'

printf '%s\n' 'PASS: battery status helper is root-only, zero-argument, environment-sanitized, and read-only.'
