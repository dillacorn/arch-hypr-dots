#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/awtarchy_report_failure.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HOME_DIR="$TMP/home"
STATE="$TMP/state"
BIN="$TMP/bin"
mkdir -p "$HOME_DIR" "$STATE/awtarchy" "$BIN"

cat >"$STATE/awtarchy/config-version" <<'STATE'
tag=v3.1.6
STATE
cat >"$STATE/awtarchy/command-version" <<'STATE'
revision=0123456789abcdef0123456789abcdef01234567
STATE

cat >"$BIN/hyprctl" <<'SH'
#!/usr/bin/env bash
printf 'Hyprland 0.51.1 built from branch main\n'
SH
cat >"$BIN/qs" <<'SH'
#!/usr/bin/env bash
printf 'quickshell 0.2.0\n'
SH
cat >"$BIN/uname" <<'SH'
#!/usr/bin/env bash
printf '6.17.1-arch1-1\n'
SH
cat >"$BIN/lspci" <<'SH'
#!/usr/bin/env bash
printf '03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI]\n'
SH
cat >"$BIN/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_CALLS"
if [[ ${CURL_FAIL:-0} == 1 ]]; then exit 22; fi
printf '{"ok":true,"created":true,"deduplicated":false,"issue_number":99,"issue_url":"https://github.com/dillacorn/awtarchy/issues/99"}\n'
SH
chmod +x "$BIN"/*

export HOME="$HOME_DIR"
export XDG_STATE_HOME="$STATE"
export PATH="$BIN:/usr/bin:/bin"
export CURL_CALLS="$TMP/curl.calls"
export AWTARCHY_REPORT_NO_PROMPT=1

bash "$SCRIPT" capture quickshell restart_after_update quickshell_not_ready
REPORT="$STATE/awtarchy/reports/quickshell--restart_after_update--quickshell_not_ready.json"
[[ -f "$REPORT" ]]
[[ "$(stat -c '%a' "$REPORT")" == 600 ]]
[[ ! -e "$CURL_CALLS" ]]

jq -e '
  keys == [
    "awtarchy_command_revision",
    "awtarchy_config_version",
    "component",
    "error_code",
    "failure_stage",
    "gpu_family",
    "hyprland_version",
    "kernel_version",
    "quickshell_version",
    "report_type",
    "schema_version"
  ]
  and .schema_version == 1
  and .report_type == "failure"
  and .component == "quickshell"
  and .failure_stage == "restart_after_update"
  and .error_code == "quickshell_not_ready"
  and .gpu_family == "AMD"
' "$REPORT" >/dev/null

if grep -Fq -- "$HOME_DIR" "$REPORT"; then
    echo 'report leaked home path' >&2
    exit 1
fi
if grep -Fq -- "$(id -un)" "$REPORT"; then
    echo 'report leaked username' >&2
    exit 1
fi
if grep -Fq -- "$(hostname)" "$REPORT"; then
    echo 'report leaked hostname' >&2
    exit 1
fi

OUTSIDE="$TMP/outside-report.json"
cp -- "$REPORT" "$OUTSIDE"
if bash "$SCRIPT" send "$OUTSIDE" >/dev/null 2>&1; then
    echo 'send accepted a file outside the pending-report directory' >&2
    exit 1
fi
[[ -f "$OUTSIDE" ]]
[[ ! -e "$CURL_CALLS" ]]

DO_NOT_DELETE="$TMP/do-not-delete.json"
printf '{"keep":true}\n' >"$DO_NOT_DELETE"
if bash "$SCRIPT" discard "$DO_NOT_DELETE" >/dev/null 2>&1; then
    echo 'discard accepted a file outside the pending-report directory' >&2
    exit 1
fi
[[ -f "$DO_NOT_DELETE" ]]

ORIGINAL="$TMP/original-report.json"
cp -- "$REPORT" "$ORIGINAL"
jq '.secret = "must-never-leave-the-client"' "$REPORT" >"${REPORT}.tmp"
mv -f -- "${REPORT}.tmp" "$REPORT"
if bash "$SCRIPT" send "$REPORT" >/dev/null 2>&1; then
    echo 'send accepted a tampered pending report with an unknown field' >&2
    exit 1
fi
[[ -f "$REPORT" ]]
[[ ! -e "$CURL_CALLS" ]]
cp -- "$ORIGINAL" "$REPORT"
chmod 0600 "$REPORT"

bash "$SCRIPT" send "$REPORT" >/dev/null
[[ ! -e "$REPORT" ]]
[[ -s "$CURL_CALLS" ]]

after_success_calls="$(wc -l <"$CURL_CALLS")"
bash "$SCRIPT" capture quickshell start quickshell_not_ready
REPORT="$STATE/awtarchy/reports/quickshell--start--quickshell_not_ready.json"
export CURL_FAIL=1
if bash "$SCRIPT" send "$REPORT" >/dev/null 2>&1; then
    echo 'failed HTTP submission unexpectedly succeeded' >&2
    exit 1
fi
[[ -f "$REPORT" ]]
[[ "$(wc -l <"$CURL_CALLS")" -gt "$after_success_calls" ]]
unset CURL_FAIL

bash "$SCRIPT" discard "$REPORT"
[[ ! -e "$REPORT" ]]

export AWTARCHY_REPORT_RECOVERY_ATTEMPTED=true
export AWTARCHY_REPORT_RECOVERY_SUCCEEDED=false
bash "$SCRIPT" capture resume_recovery final_validation expected_bars_missing
REPORT="$STATE/awtarchy/reports/resume_recovery--final_validation--expected_bars_missing.json"
jq -e '.context == {"recovery_attempted":true,"recovery_succeeded":false}' "$REPORT" >/dev/null

bash "$SCRIPT" capture quickshell attacker arbitrary >/dev/null 2>&1 || true
[[ ! -e "$STATE/awtarchy/reports/quickshell--attacker--arbitrary.json" ]]

printf 'anonymous reporting helper tests passed\n'
