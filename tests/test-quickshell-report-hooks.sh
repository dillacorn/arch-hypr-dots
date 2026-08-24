#!/usr/bin/env bash
set -euo pipefail
SCRIPT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/hypr/scripts/quickshell.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN" "$TMP/cache" "$TMP/config"
REPORT_LOG="$TMP/reports.log"

cat >"$BIN/qs" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *'list --json'* ]]; then printf '[]\n'; exit 0; fi
if [[ "$*" == *'ipc call control ping'* ]]; then exit 1; fi
exit 0
SH
cat >"$BIN/hyprctl" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == 'monitors -j' ]]; then printf '[]\n'; else printf '{}\n'; fi
SH
cat >"$BIN/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$TMP/report" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$REPORT_LOG"
SH
chmod +x "$BIN"/* "$TMP/report"

export PATH="$BIN:/usr/bin:/bin"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_CONFIG_HOME="$TMP/config"
export AWTARCHY_REPORT_SCRIPT="$TMP/report"
export REPORT_LOG

set +e
bash "$SCRIPT" start >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 1 ]]
grep -Fxq 'capture quickshell start quickshell_not_ready' "$REPORT_LOG"

: >"$REPORT_LOG"
set +e
bash "$SCRIPT" restart >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 1 ]]
grep -Fxq 'capture quickshell restart quickshell_not_ready' "$REPORT_LOG"

: >"$REPORT_LOG"
set +e
AWTARCHY_REPORT_FAILURE_STAGE=restart_after_update bash "$SCRIPT" restart >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 1 ]]
grep -Fxq 'capture quickshell restart_after_update quickshell_not_ready' "$REPORT_LOG"

: >"$REPORT_LOG"
set +e
AWTARCHY_REPORT_SUPPRESS_QUICKSHELL=1 bash "$SCRIPT" start >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 1 ]]
[[ ! -s "$REPORT_LOG" ]]

printf 'quickshell reporting hook tests passed\n'
