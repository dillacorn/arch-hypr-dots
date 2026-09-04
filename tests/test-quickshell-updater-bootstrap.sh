#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMPD="$(mktemp -d)"
SYSTEM_PATH="$PATH"
REAL_CHILD_PIDS=()

cleanup() {
  local pid
  for pid in "${REAL_CHILD_PIDS[@]}"; do
    builtin kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf -- "$TMPD"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Load the production update/restart functions without dispatching the full
# updater. This specifically models a fresh main runtime operating on an older
# release manager that cannot recognize "quickshell (deleted)".
awk '
  /^reload_quickshell_update_hyprland\(\) \{/ { capture=1 }
  /^rollback_quickshell_update\(\) \{/ { capture=0 }
  capture { print }
' "$RUNTIME" >"${TMPD}/runtime-functions.sh"
# shellcheck source=/dev/null
source "${TMPD}/runtime-functions.sh"

FAKE_BIN="${TMPD}/bin"
mkdir -p -- "$FAKE_BIN"

cat >"${FAKE_BIN}/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
exit 0
EOF_HYPRCTL

cat >"${FAKE_BIN}/qs" <<'EOF_QS'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' list --json '* ]]; then
  if [[ -r ${AWTARCHY_TEST_PROC_ROOT:?}/424242/stat ]]; then
    printf '%s\n' '[{"pid":424242}]'
  elif [[ ${AWTARCHY_TEST_QS_EMPTY_ERROR:-0} == 1 ]]; then
    exit 1
  else
    printf '%s\n' '[]'
  fi
  exit 0
fi
exit 1
EOF_QS

cat >"${FAKE_BIN}/pgrep" <<'EOF_PGREP'
#!/usr/bin/env bash
set -euo pipefail
[[ -r ${AWTARCHY_TEST_PROC_ROOT:?}/424242/stat ]]
EOF_PGREP

cat >"${FAKE_BIN}/python3" <<'EOF_PYTHON'
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
EOF_PYTHON
chmod 0755 "${FAKE_BIN}/hyprctl" "${FAKE_BIN}/qs" "${FAKE_BIN}/pgrep"
chmod 0755 "${FAKE_BIN}/python3"

write_proc_stat() {
  local stat_file="$1" state="$2" start_time="$3"
  printf '424242 (quickshell) %s' "$state" >"$stat_file"
  for _ in {4..21}; do
    printf ' 0' >>"$stat_file"
  done
  printf ' %s\n' "$start_time" >>"$stat_file"
}

# shellcheck disable=SC2317,SC2329
run_target() {
  "$@"
}

# shellcheck disable=SC2317,SC2329
warn() {
  :
}

# shellcheck disable=SC2317,SC2329
sleep() {
  :
}

# shellcheck disable=SC2317,SC2329
kill() {
  local signal="${1:-}" pid="${3:-}"
  local IFS=' '
  [[ $signal == -TERM && $pid == 424242 ]] || return 2
  printf '%s\n' "$*" >>"${AWTARCHY_TEST_SIGNAL_LOG:?}"
  case "${AWTARCHY_TEST_STOP_MODE:?}" in
    terminates)
      command rm -- "${AWTARCHY_TEST_PROC_ROOT:?}/${pid}/stat"
      ;;
    reused)
      write_proc_stat "${AWTARCHY_TEST_PROC_ROOT:?}/${pid}/stat" S 200
      ;;
    pre-signal-reused)
      write_proc_stat "${AWTARCHY_TEST_PROC_ROOT:?}/${pid}/stat" S 200
      ;;
    pre-signal-mismatch)
      ln -sfn -- /usr/bin/not-quickshell \
        "${AWTARCHY_TEST_PROC_ROOT:?}/${pid}/exe"
      ;;
    stubborn|mismatch)
      ;;
  esac
}

run_absent_case() {
  local fixture="${TMPD}/absent" rc=0
  mkdir -p -- "$fixture/home/.config/hypr/scripts" "$fixture/proc"
  HOME_DIR="$fixture/home" \
  TARGET_USER="$(id -un)" \
  HYPRLAND_INSTANCE_SIGNATURE=awtarchy-test \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_TEST_PROC_ROOT="$fixture/proc" \
  AWTARCHY_TEST_QS_EMPTY_ERROR=1 \
  PATH="$FAKE_BIN:$PATH" \
    stop_quickshell_update_shell || rc=$?
  [[ $rc -eq 0 ]] \
    || fail 'Updater treated an absent Quickshell instance as an unsafe enumeration failure'
}

# Some Quickshell builds return nonzero from `qs ... list --json` when no
# matching instance exists. If there is also no Quickshell process for the
# target user, there is nothing to stop and the updater must continue safely.
run_absent_case

run_bootstrap_case() {
  local name="$1" executable="$2" state="$3" mode="$4" expected="$5"
  local fixture="${TMPD}/${name}" manager rc=0

  mkdir -p -- "$fixture/home/.config/hypr/scripts" "$fixture/proc/424242"
  manager="$fixture/home/.config/hypr/scripts/quickshell.sh"
  if [[ $state == malformed ]]; then
    printf '%s\n' 'not a Linux process stat record' >"$fixture/proc/424242/stat"
  else
    write_proc_stat "$fixture/proc/424242/stat" "$state" 100
  fi
  ln -s -- "$executable" "$fixture/proc/424242/exe"
  : >"$fixture/manager.log"
  : >"$fixture/signals.log"

  cat >"$manager" <<'EOF_MANAGER'
#!/usr/bin/env bash
set -euo pipefail
action="${1:-}"
printf '%s\n' "$action" >>"${AWTARCHY_TEST_MANAGER_LOG:?}"
case "$action" in
  restart)
    exit 1
    ;;
  start)
    : >"${AWTARCHY_TEST_SHELL_RUNNING:?}"
    ;;
  status)
    [[ -e ${AWTARCHY_TEST_SHELL_RUNNING:?} ]] && printf '%s\n' running || printf '%s\n' stopped
    ;;
  *)
    exit 2
    ;;
esac
EOF_MANAGER
  chmod 0755 "$manager"

  HOME_DIR="$fixture/home" \
  TARGET_USER="$(id -un)" \
  HYPRLAND_INSTANCE_SIGNATURE=awtarchy-test \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_TEST_PROC_ROOT="$fixture/proc" \
  AWTARCHY_TEST_STOP_MODE="$mode" \
  AWTARCHY_TEST_SIGNAL_LOG="$fixture/signals.log" \
  AWTARCHY_TEST_MANAGER_LOG="$fixture/manager.log" \
  AWTARCHY_TEST_SHELL_RUNNING="$fixture/shell-running" \
  PATH="$FAKE_BIN:$PATH" \
    start_quickshell_update_shell || rc=$?

  if [[ $expected == success && $rc -ne 0 ]]; then
    fail "Updater bootstrap fixture ${name} failed"
  fi
  if [[ $expected == failure && $rc -eq 0 ]]; then
    fail "Updater bootstrap fixture ${name} unexpectedly succeeded"
  fi
}

run_bootstrap_case package-upgrade '/usr/bin/quickshell (deleted)' S terminates success
grep -Fxq restart "${TMPD}/package-upgrade/manager.log" \
  || fail 'Bootstrap did not first use the release manager restart'
grep -Fxq start "${TMPD}/package-upgrade/manager.log" \
  || fail 'Bootstrap did not start Quickshell after updater-managed shutdown'
grep -Fq -- '-TERM -- 424242' "${TMPD}/package-upgrade/signals.log" \
  || fail 'Bootstrap did not terminate package-replaced Quickshell'

run_bootstrap_case pid-reuse /usr/bin/quickshell S reused success
grep -Fxq start "${TMPD}/pid-reuse/manager.log" \
  || fail 'Bootstrap treated a reused PID as the old Quickshell process'

run_bootstrap_case zombie /usr/bin/quickshell Z stubborn success
[[ ! -s ${TMPD}/zombie/signals.log ]] \
  || fail 'Bootstrap signaled a zombie Quickshell process'

run_bootstrap_case stubborn /usr/bin/quickshell S stubborn failure
! grep -Fxq start "${TMPD}/stubborn/manager.log" \
  || fail 'Bootstrap started a second shell while the old process was still running'

run_bootstrap_case mismatch /usr/bin/not-quickshell S mismatch failure
[[ ! -s ${TMPD}/mismatch/signals.log ]] \
  || fail 'Bootstrap signaled a PID that was not Quickshell'

run_bootstrap_case malformed-stat /usr/bin/quickshell malformed stubborn failure
! grep -Fxq start "${TMPD}/malformed-stat/manager.log" \
  || fail 'Bootstrap started a second shell after failing to verify an existing PID'

run_bootstrap_case pre-signal-reuse /usr/bin/quickshell S pre-signal-reused success
[[ ! -s ${TMPD}/pre-signal-reuse/signals.log ]] \
  || fail 'Bootstrap signaled a PID reused after initial validation'

run_bootstrap_case pre-signal-mismatch /usr/bin/quickshell S pre-signal-mismatch failure
[[ ! -s ${TMPD}/pre-signal-mismatch/signals.log ]] \
  || fail 'Bootstrap signaled a process whose executable changed after initial validation'

runtime_process_start_time() {
  local pid="$1" stat_line stat_tail
  local -a fields=()

  IFS= read -r stat_line <"/proc/${pid}/stat"
  stat_tail="${stat_line##*) }"
  IFS=' ' read -r -a fields <<<"$stat_tail"
  printf '%s\n' "${fields[19]}"
}

spawn_real_process() {
  local executable="$1"

  "$executable" 60 &
  SPAWNED_PID=$!
  REAL_CHILD_PIDS+=("$SPAWNED_PID")
  for _ in {1..100}; do
    [[ -r /proc/${SPAWNED_PID}/stat ]] && return 0
    /usr/bin/sleep 0.01
  done
  return 1
}

# pidfd_send_signal is the primary production path, not only a unit-test mock.
# Exercise it against real Linux processes to prove that the runtime terminates
# an expected identity while refusing a mismatched executable.
if [[ -x /usr/bin/sleep && -x /usr/bin/tail ]]; then
  real_fixture="${TMPD}/real"
  mkdir -p -- "$real_fixture/proc"
  : >"$real_fixture/signals.log"

  spawn_real_process /usr/bin/sleep \
    || fail 'Could not spawn real-process termination fixture'
  real_sleep_pid="$SPAWNED_PID"
  real_sleep_start="$(runtime_process_start_time "$real_sleep_pid")"
  if quickshell_update_signal_identity "$real_sleep_pid" "$real_sleep_start"; then
    fail 'Production pidfd helper signaled a real process whose executable was not Quickshell'
  else
    rc=$?
  fi
  [[ $rc -eq 4 ]] \
    || fail "Production pidfd helper returned ${rc} for mismatched real executable, expected 4"
  builtin kill -0 "$real_sleep_pid" 2>/dev/null \
    || fail 'Mismatched real executable was terminated'

  # Use a temporary executable named quickshell backed by /usr/bin/sleep so the
  # production helper sees the exact expected basename in /proc/<pid>/exe.
  cp -- /usr/bin/sleep "$real_fixture/quickshell"
  chmod 0755 "$real_fixture/quickshell"
  spawn_real_process "$real_fixture/quickshell" \
    || fail 'Could not spawn real Quickshell-identity termination fixture'
  real_quickshell_pid="$SPAWNED_PID"
  real_quickshell_start="$(runtime_process_start_time "$real_quickshell_pid")"
  quickshell_update_signal_identity "$real_quickshell_pid" "$real_quickshell_start" \
    || fail 'Production pidfd helper did not terminate a verified real Quickshell identity'
  for _ in {1..100}; do
    builtin kill -0 "$real_quickshell_pid" 2>/dev/null || break
    /usr/bin/sleep 0.01
  done
  if builtin kill -0 "$real_quickshell_pid" 2>/dev/null; then
    fail 'Verified real Quickshell identity remained alive after pidfd SIGTERM'
  fi
fi

printf 'PASS: updater-owned Quickshell bootstrap regressions\n'