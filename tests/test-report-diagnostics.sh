#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/awtarchy_report_failure.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

HOME_DIR="$TMP/home"
STATE="$TMP/state"
CACHE="$TMP/cache"
BIN="$TMP/bin"
CONFIG="$HOME_DIR/.config"
MANAGED="$CONFIG/quickshell/awtarchy"
mkdir -p "$MANAGED" "$STATE/awtarchy" "$CACHE/awtarchy" "$BIN"

printf 'pragma Singleton\n' >"$MANAGED/Theme.qml"
printf 'import Quickshell\n' >"$MANAGED/shell.qml"
printf 'tag=v3.2.0\n' >"$STATE/awtarchy/config-version"
printf 'revision=0123456789abcdef0123456789abcdef01234567\n' >"$STATE/awtarchy/command-version"

cat >"$BIN/hyprctl" <<'SH'
#!/usr/bin/env bash
printf 'Hyprland 0.56.1\n'
SH
cat >"$BIN/qs" <<'SH'
#!/usr/bin/env bash
printf 'quickshell 0.3.0\n'
SH
cat >"$BIN/uname" <<'SH'
#!/usr/bin/env bash
printf '7.1.5-arch1-2\n'
SH
cat >"$BIN/lspci" <<'SH'
#!/usr/bin/env bash
printf '03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI]\n'
SH
chmod +x "$BIN"/*

export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$CONFIG"
export XDG_STATE_HOME="$STATE"
export XDG_CACHE_HOME="$CACHE"
export PATH="$BIN:/usr/bin:/bin"
export AWTARCHY_REPORT_NO_PROMPT=1

LOG="$CACHE/awtarchy/quickshell.log"

cat >"$LOG" <<'LOG'
 INFO: Launching config: "/home/private/.config/quickshell/awtarchy/shell.qml"
 ERROR: Failed to load configuration
 ERROR:   caused by @Theme.qml[65:1]: Syntax error
LOG

bash "$SCRIPT" capture quickshell restart_after_update quickshell_not_ready
REPORT="$STATE/awtarchy/reports/quickshell--restart_after_update--quickshell_not_ready.json"

if ! jq -e '.diagnostic == {
  "kind":"qml_parse_error",
  "managed_file":"Theme.qml",
  "line":65,
  "column":1
}' "$REPORT" >/dev/null; then
    jq . "$REPORT" >&2
    fail 'managed QML parse error was not reduced to the expected structured diagnostic'
fi

if grep -Fq 'Syntax error' "$REPORT"; then
    fail 'diagnostic leaked raw Quickshell error text'
fi
if grep -Fq '/home/' "$REPORT"; then
    fail 'diagnostic leaked a home-directory path'
fi

cat >"$LOG" <<'LOG'
 ERROR: Failed to load configuration
 ERROR:   caused by @shell.qml[10:1]: module "./modules/common/" is not installed
LOG
bash "$SCRIPT" capture quickshell restart quickshell_not_ready
REPORT="$STATE/awtarchy/reports/quickshell--restart--quickshell_not_ready.json"
if ! jq -e '.diagnostic == {
  "kind":"qml_import_error",
  "managed_file":"shell.qml",
  "line":10,
  "column":1
}' "$REPORT" >/dev/null; then
    jq . "$REPORT" >&2
    fail 'managed QML import error was not classified without raw diagnostic text'
fi

cat >"$LOG" <<'LOG'
 ERROR: Failed to load configuration
 ERROR:   caused by @/home/alice/private/Secret.qml[7:2]: Syntax error
LOG
bash "$SCRIPT" capture quickshell start quickshell_not_ready
REPORT="$STATE/awtarchy/reports/quickshell--start--quickshell_not_ready.json"
if ! jq -e 'has("diagnostic") | not' "$REPORT" >/dev/null; then
    jq . "$REPORT" >&2
    fail 'non-managed QML path was accepted as a report diagnostic'
fi

printf '%s\n' 'sanitized Quickshell diagnostic extraction tests passed'
