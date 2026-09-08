#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SHELL_MANAGER="${REPO_ROOT}/config/hypr/scripts/quickshell.sh"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Package upgrades replace /usr/bin/quickshell while the old process is still
# running. Linux then exposes its executable as "quickshell (deleted)". Exercise
# that lifecycle behavior, plus the adjacent zombie/PID-reuse cases, instead of
# only checking that the manager contains a SIGTERM command.
STOP_TEST_BIN="${TMPD}/bin"
STOP_TEST_ENV="${TMPD}/bash-env"
mkdir -p -- "$STOP_TEST_BIN"

cat >"${STOP_TEST_BIN}/qs" <<'EOF_STOP_QS'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' list --json '* ]]; then
  printf '%s\n' '[{"pid":424242}]'
  exit 0
fi
exit 1
EOF_STOP_QS

cat >"${STOP_TEST_BIN}/hyprctl" <<'EOF_STOP_HYPRCTL'
#!/usr/bin/env bash
exit 0
EOF_STOP_HYPRCTL

cat >"${STOP_TEST_BIN}/python3" <<'EOF_STOP_PYTHON'
#!/usr/bin/env bash
set -euo pipefail

[[ ${1:-} == - && ${2:-} =~ ^[1-9][0-9]*$ && ${3:-} =~ ^[0-9]+$ ]] || exit 4
pid="$2"
expected_start_time="$3"
proc_root="${AWTARCHY_TEST_PROC_ROOT:?}"
mode="${AWTARCHY_TEST_STOP_MODE:?}"

write_stat() {
  local state="$1" start_time="$2" field
  printf '%s (quickshell) %s' "$pid" "$state" >"${proc_root}/${pid}/stat"
  for field in {4..21}; do
    printf ' 0' >>"${proc_root}/${pid}/stat"
  done
  printf ' %s\n' "$start_time" >>"${proc_root}/${pid}/stat"
}

case "$mode" in
  pre-signal-reused)
    write_stat S 200
    ;;
  pre-signal-mismatch)
    ln -sfn -- /usr/bin/not-quickshell "${proc_root}/${pid}/exe"
    ;;
esac

[[ -r ${proc_root}/${pid}/stat ]] || exit 3
IFS= read -r stat_line <"${proc_root}/${pid}/stat" || exit 4
[[ $stat_line == *') '* ]] || exit 4
stat_tail="${stat_line##*) }"
IFS=' ' read -r -a fields <<<"$stat_tail"
(( ${#fields[@]} >= 20 )) || exit 4
[[ ${fields[0]} != Z && ${fields[0]} != X && ${fields[0]} != x ]] || exit 3
[[ ${fields[19]} == "$expected_start_time" ]] || exit 3
executable="$(readlink "${proc_root}/${pid}/exe")" || exit 4
executable="${executable% (deleted)}"
[[ ${executable##*/} == quickshell ]] || exit 4

printf '%s\n' '-TERM -- 424242' >>"${AWTARCHY_TEST_SIGNAL_LOG:?}"
case "$mode" in
  terminates)
    rm -- "${proc_root}/${pid}/stat"
    ;;
  reused)
    write_stat S 200
    ;;
  stubborn)
    ;;
  *)
    exit 4
    ;;
esac
EOF_STOP_PYTHON
chmod 0755 "${STOP_TEST_BIN}/qs" "${STOP_TEST_BIN}/hyprctl" \
  "${STOP_TEST_BIN}/python3"

cat >"$STOP_TEST_ENV" <<'EOF_STOP_ENV'
write_stop_test_stat() {
  local pid="$1" state="$2" start_time="$3" field
  printf '%s (quickshell) %s' "$pid" "$state" \
    >"${AWTARCHY_TEST_PROC_ROOT:?}/${pid}/stat"
  for field in {4..21}; do
    printf ' 0' >>"${AWTARCHY_TEST_PROC_ROOT}/${pid}/stat"
  done
  printf ' %s\n' "$start_time" >>"${AWTARCHY_TEST_PROC_ROOT}/${pid}/stat"
}

kill() {
  local signal="${1:-}" pid="${3:-}"
  case "$signal" in
    -0)
      [[ ! -e ${AWTARCHY_TEST_TERMINATED_MARKER:?} ]]
      ;;
    -TERM)
      printf '%s\n' "$*" >>"${AWTARCHY_TEST_SIGNAL_LOG:?}"
      case "${AWTARCHY_TEST_STOP_MODE:?}" in
        terminates)
          : >"${AWTARCHY_TEST_TERMINATED_MARKER:?}"
          command rm -- "${AWTARCHY_TEST_PROC_ROOT:?}/${pid}/stat"
          ;;
        reused)
          write_stop_test_stat "$pid" S 200
          ;;
        pre-signal-reused)
          write_stop_test_stat "$pid" S 200
          ;;
        pre-signal-mismatch)
          ln -sfn -- /usr/bin/not-quickshell \
            "${AWTARCHY_TEST_PROC_ROOT:?}/${pid}/exe"
          ;;
        stubborn|zombie|mismatch)
          ;;
      esac
      ;;
    *)
      builtin kill "$@"
      ;;
  esac
}

sleep() {
  :
}
EOF_STOP_ENV

write_stop_fixture_stat() {
  local stat_file="$1" state="$2" start_time="$3"
  printf '424242 (quickshell) %s' "$state" >"$stat_file"
  for _ in {4..21}; do
    printf ' 0' >>"$stat_file"
  done
  printf ' %s\n' "$start_time" >>"$stat_file"
}

run_stop_fixture() {
  local name="$1" executable="$2" state="$3" mode="$4" expected="$5"
  local fixture="${TMPD}/${name}" rc=0
  mkdir -p -- "$fixture/home" "$fixture/proc/424242"
  if [[ $state == malformed ]]; then
    printf '%s\n' 'not a Linux process stat record' >"$fixture/proc/424242/stat"
  else
    write_stop_fixture_stat "$fixture/proc/424242/stat" "$state" 100
  fi
  ln -s -- "$executable" "$fixture/proc/424242/exe"
  : >"$fixture/signals.log"

  env \
    "HOME=$fixture/home" \
    "PATH=$STOP_TEST_BIN:$PATH" \
    "BASH_ENV=$STOP_TEST_ENV" \
    "AWTARCHY_TEST_MODE=1" \
    "AWTARCHY_TEST_PROC_ROOT=$fixture/proc" \
    "AWTARCHY_TEST_STOP_MODE=$mode" \
    "AWTARCHY_TEST_SIGNAL_LOG=$fixture/signals.log" \
    "AWTARCHY_TEST_TERMINATED_MARKER=$fixture/terminated" \
    bash "$SHELL_MANAGER" stop >"$fixture/stdout" 2>"$fixture/stderr" || rc=$?

  if [[ $expected == success && $rc -ne 0 ]]; then
    fail "Quickshell stop fixture ${name} failed: $(<"$fixture/stderr")"
  fi
  if [[ $expected == failure && $rc -eq 0 ]]; then
    fail "Quickshell stop fixture ${name} unexpectedly succeeded"
  fi
}

run_stop_fixture package-upgrade '/usr/bin/quickshell (deleted)' S terminates success
grep -Fq -- '-TERM -- 424242' "${TMPD}/package-upgrade/signals.log" \
  || fail 'Package-replaced Quickshell process did not receive SIGTERM'

run_stop_fixture zombie /usr/bin/quickshell Z zombie success
[[ ! -s ${TMPD}/zombie/signals.log ]] \
  || fail 'Zombie Quickshell process received an unnecessary SIGTERM'

run_stop_fixture pid-reuse /usr/bin/quickshell S reused success
grep -Fq -- '-TERM -- 424242' "${TMPD}/pid-reuse/signals.log" \
  || fail 'Original Quickshell process did not receive SIGTERM before PID reuse'

run_stop_fixture stubborn /usr/bin/quickshell S stubborn failure
grep -Fq 'did not finish after SIGTERM' "${TMPD}/stubborn/stderr" \
  || fail 'A genuinely stuck Quickshell process did not report a shutdown timeout'

run_stop_fixture identity-mismatch /usr/bin/not-quickshell S mismatch failure
grep -Fq 'refusing to signal' "${TMPD}/identity-mismatch/stderr" \
  || fail 'Quickshell PID identity mismatch did not fail safely and explicitly'

run_stop_fixture malformed-stat /usr/bin/quickshell malformed stubborn failure
grep -Fq 'could not verify' "${TMPD}/malformed-stat/stderr" \
  || fail 'Malformed process identity did not fail safely and explicitly'

run_stop_fixture pre-signal-reuse /usr/bin/quickshell S pre-signal-reused success
[[ ! -s ${TMPD}/pre-signal-reuse/signals.log ]] \
  || fail 'Manager signaled a PID reused after initial validation'

run_stop_fixture pre-signal-mismatch /usr/bin/quickshell S pre-signal-mismatch failure
[[ ! -s ${TMPD}/pre-signal-mismatch/signals.log ]] \
  || fail 'Manager signaled a process whose executable changed after initial validation'

# Every UI wrapper calls `quickshell.sh start` before IPC. If the shell is
# already healthy, that fast path must return before cursor reapply mutates the
# Hyprland config and triggers a compositor reload.
python3 - "$SHELL_MANAGER" <<'PY_START_ORDER'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start = text.index("start_shell() {")
end = text.index("\nstop_shell() {", start)
body = text[start:end]
running_check = body.index("if is_running; then")
cursor_reapply = body.index('if [[ -f "$CURSOR_THEME_SCRIPT" && ! -L "$CURSOR_THEME_SCRIPT" ]]; then')
if running_check > cursor_reapply:
    raise SystemExit("FAIL: healthy Quickshell start reapplies cursor state before the running fast path")
PY_START_ORDER

printf 'PASS: Quickshell process lifecycle regressions\n'
