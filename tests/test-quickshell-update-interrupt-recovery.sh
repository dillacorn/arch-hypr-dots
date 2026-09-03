#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

extract_function() {
  local name="$1" out="$2"
  awk -v fn="$name" '
    $0 ~ "^" fn "\\(\\) \\{" { capture=1 }
    capture { print }
    capture && /^}/ { found=1; exit }
    END { if (!found) exit 3 }
  ' "$RUNTIME" >"$out"
}

HARNESS="${TMPD}/runtime-functions.sh"
: >"$HARNESS"
extract_function restore_quickshell_update_shell_on_exit "$TMPD/restore.fn" \
  || fail 'runtime is missing Quickshell interrupted-update recovery'
extract_function recover_interrupted_quickshell_update "$TMPD/recover.fn" \
  || fail 'runtime is missing durable previous-update Quickshell recovery'
extract_function cleanup_update "$TMPD/cleanup.fn" \
  || fail 'runtime cleanup function is unavailable'
cat "$TMPD/restore.fn" "$TMPD/recover.fn" "$TMPD/cleanup.fn" >"$HARNESS"

prepare_fixture() {
  local fixture="$1" initial_state="$2" start_rc="$3" marker_present="$4"

  mkdir -p -- "$fixture/home/.config/hypr/scripts" "$fixture/state"
  : >"$fixture/manager.log"
  if [[ $initial_state == running ]]; then
    : >"$fixture/running"
  fi
  if [[ $marker_present == 1 ]]; then
    : >"$fixture/state/quickshell-update-stopped"
  fi

  cat >"$fixture/home/.config/hypr/scripts/quickshell.sh" <<'EOF_MANAGER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${1:-}" >>"${AWTARCHY_TEST_MANAGER_LOG:?}"
case "${1:-}" in
  status)
    if [[ -e ${AWTARCHY_TEST_RUNNING_FILE:?} ]]; then
      printf '%s\n' running
    else
      printf '%s\n' stopped
    fi
    ;;
  start)
    if [[ ${AWTARCHY_TEST_START_RC:?} -ne 0 ]]; then
      exit "${AWTARCHY_TEST_START_RC}"
    fi
    : >"${AWTARCHY_TEST_RUNNING_FILE:?}"
    ;;
  *)
    exit 2
    ;;
esac
EOF_MANAGER
  chmod 0755 "$fixture/home/.config/hypr/scripts/quickshell.sh"
}

run_case() {
  local name="$1" restore_flag="$2" initial_state="$3" start_rc="$4" expected_start_count="$5" marker_present="${6:-0}"
  local fixture child rc=0 start_count=0
  fixture="${TMPD}/${name}"
  child="$fixture/child.sh"

  prepare_fixture "$fixture" "$initial_state" "$start_rc" "$marker_present"

  cat >"$child" <<EOF_CHILD
#!/usr/bin/env bash
set -euo pipefail
HOME_DIR='$fixture/home'
MOUSE_ENABLED=0
TMPD=''
QUICKSHELL_UPDATE_RESTORE_ON_EXIT=$restore_flag
QUICKSHELL_UPDATE_RECOVERY_MARKER='$fixture/state/quickshell-update-stopped'
run_target() { "\$@"; }
log() { printf '%s\n' "\$*"; }
warn() { printf 'WARN: %s\n' "\$*" >&2; }
source '$HARNESS'
trap cleanup_update EXIT
trap 'exit 130' INT
kill -INT \$\$
EOF_CHILD
  chmod 0755 "$child"

  AWTARCHY_TEST_MANAGER_LOG="$fixture/manager.log" \
  AWTARCHY_TEST_RUNNING_FILE="$fixture/running" \
  AWTARCHY_TEST_START_RC="$start_rc" \
    bash "$child" >"$fixture/stdout" 2>"$fixture/stderr" || rc=$?

  [[ $rc -eq 130 ]] || fail "${name}: interrupted updater exited ${rc}, expected 130"
  start_count="$(grep -Fxc start "$fixture/manager.log" || true)"
  [[ $start_count -eq $expected_start_count ]] \
    || fail "${name}: Quickshell start count ${start_count}, expected ${expected_start_count}"
}

run_recover_case() {
  local name="$1" initial_state="$2" start_rc="$3" expected_start_count="$4"
  local fixture child rc=0 start_count=0
  fixture="${TMPD}/${name}"
  child="$fixture/recover.sh"

  prepare_fixture "$fixture" "$initial_state" "$start_rc" 1

  cat >"$child" <<EOF_CHILD
#!/usr/bin/env bash
set -euo pipefail
HOME_DIR='$fixture/home'
MOUSE_ENABLED=0
TMPD=''
QUICKSHELL_UPDATE_RESTORE_ON_EXIT=0
QUICKSHELL_UPDATE_RECOVERY_MARKER='$fixture/state/quickshell-update-stopped'
run_target() { "\$@"; }
log() { printf '%s\n' "\$*"; }
warn() { printf 'WARN: %s\n' "\$*" >&2; }
source '$HARNESS'
recover_interrupted_quickshell_update
EOF_CHILD
  chmod 0755 "$child"

  AWTARCHY_TEST_MANAGER_LOG="$fixture/manager.log" \
  AWTARCHY_TEST_RUNNING_FILE="$fixture/running" \
  AWTARCHY_TEST_START_RC="$start_rc" \
    bash "$child" >"$fixture/stdout" 2>"$fixture/stderr" || rc=$?

  [[ $rc -eq 0 ]] || fail "${name}: durable recovery exited ${rc}, expected 0"
  start_count="$(grep -Fxc start "$fixture/manager.log" || true)"
  [[ $start_count -eq $expected_start_count ]] \
    || fail "${name}: Quickshell start count ${start_count}, expected ${expected_start_count}"
}

run_case interrupted-running 1 stopped 0 1
[[ -e ${TMPD}/interrupted-running/running ]] \
  || fail 'interrupted updater did not restore Quickshell'
grep -Fq 'Update interrupted; restoring Quickshell' "${TMPD}/interrupted-running/stdout" \
  || fail 'interrupted updater did not report Quickshell recovery'

run_case initially-stopped 0 stopped 0 0
[[ ! -e ${TMPD}/initially-stopped/running ]] \
  || fail 'updater started Quickshell even though it did not stop it'

run_case already-restored 1 running 0 0
[[ -e ${TMPD}/already-restored/running ]] \
  || fail 'already-running Quickshell fixture disappeared'

run_case restore-fails 1 stopped 7 1
grep -Fq 'Could not restore Quickshell after interrupted update' "${TMPD}/restore-fails/stderr" \
  || fail 'restore failure did not warn the user'

# The durable marker must recover even if the original process lost its
# in-memory flag before EXIT cleanup ran.
run_case durable-marker-cleanup 0 stopped 0 1 1
[[ -e ${TMPD}/durable-marker-cleanup/running ]] \
  || fail 'durable interrupted-update marker did not restore Quickshell'
[[ ! -e ${TMPD}/durable-marker-cleanup/state/quickshell-update-stopped ]] \
  || fail 'successful cleanup recovery did not clear the durable marker'

# A later updater invocation must consume the durable marker before attempting
# another stop/mutation cycle.
run_recover_case next-invocation-recovery stopped 0 1
[[ -e ${TMPD}/next-invocation-recovery/running ]] \
  || fail 'next updater invocation did not recover Quickshell from durable marker'
[[ ! -e ${TMPD}/next-invocation-recovery/state/quickshell-update-stopped ]] \
  || fail 'next-invocation recovery did not clear the durable marker'

# The updater must only arm cleanup recovery after it successfully stops at
# least one real Awtarchy Quickshell instance.
grep -Fq 'QUICKSHELL_UPDATE_RESTORE_ON_EXIT=1' "$RUNTIME" \
  || fail 'Quickshell shutdown path does not arm interrupted-update recovery'

# Once the live shell has been stopped, handled failures must use the
# Quickshell-aware rollback path so sudo/polkit failures restore the shell
# synchronously instead of relying only on EXIT cleanup.
python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.find('  stop_quickshell_update_shell \\\n')
if start < 0:
    raise SystemExit('FAIL: could not locate live Quickshell stop stage')
end = text.find('  if ! start_quickshell_update_shell; then', start)
if end < 0:
    raise SystemExit('FAIL: could not locate normal Quickshell restart stage')
segment = text[start:end]
if '\n    rollback_changes\n' in segment:
    raise SystemExit('FAIL: handled post-stop failure still uses plain rollback_changes')
PY

printf 'PASS: Quickshell interrupted-update recovery regressions\n'
