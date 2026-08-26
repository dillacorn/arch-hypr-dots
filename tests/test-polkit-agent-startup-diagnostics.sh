#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AGENT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/agent.py"
LAUNCHER="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"
SERVICE="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service"

fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 still contains: $2"; }

require_contains "$AGENT" 'SYSTEMD_CAT = "/usr/bin/systemd-cat"'
require_contains "$AGENT" 'def journal_message(priority: str, message: str) -> None:'
require_contains "$AGENT" 'startup: PolicyKit authentication agent registered; terminal idle'
require_contains "$AGENT" 'authentication terminal exited before request completion'
require_contains "$AGENT" 'fatal startup:'
require_contains "$AGENT" 'except Exception as exc:'
reject_contains "$AGENT" 'startup: authentication terminal hidden and ready'
require_contains "$LAUNCHER" 'PolicyKit Python bindings are unavailable; install polkit and python-gobject.'
require_contains "$LAUNCHER" '"$PYTHON" -I "$AGENT"'
require_contains "$SERVICE" 'StandardOutput=journal'
require_contains "$SERVICE" 'StandardError=journal'

printf '%s\n' 'headless Polkit startup diagnostics contract passed'
