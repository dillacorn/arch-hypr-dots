#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AGENT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/agent.py"
CONTROLLER="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-live-test.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

require_contains() {
    local file="$1" pattern="$2"
    grep -Fq -- "$pattern" "$file" || fail "$file missing: $pattern"
}

reject_contains() {
    local file="$1" pattern="$2"
    ! grep -Fq -- "$pattern" "$file" || fail "$file still contains: $pattern"
}

require_contains "$AGENT" 'SYSTEMD_CAT = "/usr/bin/systemd-cat"'
require_contains "$AGENT" 'def journal_message(priority: str, message: str) -> None:'
require_contains "$AGENT" 'startup: PolicyKit authentication agent registered; terminal idle'
reject_contains "$AGENT" 'startup: authentication terminal hidden and ready'
require_contains "$AGENT" 'fatal startup:'
require_contains "$AGENT" 'except Exception as exc:'

require_contains "$CONTROLLER" '/usr/bin/journalctl'
require_contains "$CONTROLLER" 'show_startup_diagnostics()'
require_contains "$CONTROLLER" 'ActiveState='
require_contains "$CONTROLLER" 'headless Python backend MainPID verification failed'
require_contains "$CONTROLLER" 'journalctl --user -u "$SERVICE_NAME" -b --no-pager -n 30'

printf '%s\n' 'headless Polkit startup diagnostics contract passed'
