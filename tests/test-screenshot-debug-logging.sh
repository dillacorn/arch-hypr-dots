#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/screenshot_area.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$3"; }

contains "$SCRIPT" 'screenshot-debug' 'debug directory missing'
contains "$SCRIPT" 'attempt_counter' 'attempt counter missing'
contains "$SCRIPT" 'ATTEMPT_ID=' 'attempt identifier missing'
contains "$SCRIPT" 'log_event "slurp-start"' 'slurp start is not logged'
contains "$SCRIPT" 'log_event "slurp-exit"' 'slurp exit is not logged'
contains "$SCRIPT" 'geometry=' 'slurp geometry is not logged'
contains "$SCRIPT" 'hyprpicker-start' 'hyprpicker start is not logged'
contains "$SCRIPT" 'hyprpicker-state' 'hyprpicker process state is not logged'
contains "$SCRIPT" 'cursor=' 'cursor position is not logged'
contains "$SCRIPT" 'exit_status=' 'attempt exit status is not logged'
contains "$SCRIPT" 'find "$DEBUG_DIR"' 'old debug logs are not bounded'

printf '%s\n' 'PASS: screenshot capture attempts keep bounded per-invocation diagnostics.'
