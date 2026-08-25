#!/usr/bin/env bash
# Regression checks for terminal concept password-entry redraw behavior.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-concept.sh"

[[ -f $SCRIPT ]]

grep -Fq 'PASSWORD_LENGTH=0' "$SCRIPT"
grep -Fq 'render_password_field_only()' "$SCRIPT"
grep -Fq 'render_password_field_only' "$SCRIPT"

if grep -Fq 'DEMO_PASSWORD' "$SCRIPT"; then
    printf '%s\n' 'FAIL: concept still stores typed password characters' >&2
    exit 1
fi

python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
run_tui = text.split("run_tui() {", 1)[1].split("\nprint_static() {", 1)[0]

bad_loop = "while true; do\n        WINDOW_RESIZED=0\n        render\n"
if bad_loop in run_tui:
    raise SystemExit("FAIL: run_tui still performs a full-screen render before every key read")

if "render_password_field_only" not in run_tui:
    raise SystemExit("FAIL: password input does not use a targeted field redraw")
PY

printf '%s\n' 'polkit concept input redraw tests passed'
