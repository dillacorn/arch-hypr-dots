#!/usr/bin/env bash
set -euo pipefail
SCRIPT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/hypr/scripts/quickshell_resume_recover.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN" "$TMP/cache" "$TMP/runtime" "$TMP/config"
REPORT_LOG="$TMP/reports.log"
MANAGER_LOG="$TMP/manager.log"

cat >"$BIN/hyprctl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  'monitors -j') printf '[{"name":"DP-1","disabled":false}]\n' ;;
  'layers -j') printf '{}\n' ;;
  *) printf '{}\n' ;;
esac
SH
cat >"$BIN/qs" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *'ipc call control ping'* ]]; then
  [[ ${SCENARIO:-} != start_fail ]]
  exit
fi
exit 0
SH
cat >"$BIN/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$TMP/restore" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$TMP/manager" <<'SH'
#!/usr/bin/env bash
printf '%s suppress=%s\n' "$1" "${AWTARCHY_REPORT_SUPPRESS_QUICKSHELL:-unset}" >>"$MANAGER_LOG"
case "${SCENARIO:-}:$1" in
  start_fail:start|restart_fail:restart) exit 1 ;;
  *) exit 0 ;;
esac
SH
cat >"$TMP/report" <<'SH'
#!/usr/bin/env bash
printf '%s attempted=%s succeeded=%s\n' "$*" "${AWTARCHY_REPORT_RECOVERY_ATTEMPTED:-unset}" "${AWTARCHY_REPORT_RECOVERY_SUCCEEDED:-unset}" >>"$REPORT_LOG"
SH
chmod +x "$BIN"/* "$TMP/restore" "$TMP/manager" "$TMP/report"

export PATH="$BIN:/usr/bin:/bin"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_RUNTIME_DIR="$TMP/runtime"
export QUICKSHELL_RESTORE_SCRIPT="$TMP/restore"
export QUICKSHELL_MANAGER_SCRIPT="$TMP/manager"
export AWTARCHY_REPORT_SCRIPT="$TMP/report"
export QUICKSHELL_RESUME_MONITOR_ATTEMPTS=1
export QUICKSHELL_RESUME_NATURAL_ATTEMPTS=1
export QUICKSHELL_RESUME_RELOAD_ATTEMPTS=1
export QUICKSHELL_RESUME_BLUETOOTH_WAIT_ATTEMPTS=1
export QUICKSHELL_RESUME_BLUETOOTH_RETRY_SECONDS=1
export QUICKSHELL_RESUME_WAIT_INTERVAL=0
export REPORT_LOG MANAGER_LOG

run_failure() {
  local scenario="$1" expected="$2" rc
  : >"$REPORT_LOG"
  : >"$MANAGER_LOG"
  set +e
  SCENARIO="$scenario" bash "$SCRIPT" >/dev/null 2>&1
  rc=$?
  set -e
  [[ $rc -eq 1 ]]
  grep -Fxq "$expected attempted=true succeeded=false" "$REPORT_LOG"
}

run_failure start_fail 'capture resume_recovery start quickshell_start_failed'
grep -Fxq 'start suppress=1' "$MANAGER_LOG"

run_failure restart_fail 'capture resume_recovery restart quickshell_restart_failed'
grep -Fxq 'restart suppress=1' "$MANAGER_LOG"

run_failure final_missing 'capture resume_recovery final_validation expected_bars_missing'
grep -Fxq 'restart suppress=1' "$MANAGER_LOG"

printf 'quickshell resume reporting hook tests passed\n'
