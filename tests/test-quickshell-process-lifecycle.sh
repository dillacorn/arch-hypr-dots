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
chmod 0755 "${STOP_TEST_BIN}/qs" "${STOP_TEST_BIN}/hyprctl"

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
  local stat_file="$1" state="$2" start_time="$3" field
  printf '424242 (quickshell) %s' "$state" >"$stat_file"
  for field in {4..21}; do
    printf ' 0' >>"$stat_file"
  done
  printf ' %s\n' "$start_time" >>"$stat_file"
}

run_stop_fixture() {
  local name="$1" executable="$2" state="$3" mode="$4" expected="$5"
  local fixture="${TMPD}/${name}" rc=0
  mkdir -p -- "$fixture/home" "$fixture/proc/424242"
  write_stop_fixture_stat "$fixture/proc/424242/stat" "$state" 100
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

printf 'PASS: Quickshell process lifecycle regressions\n'
