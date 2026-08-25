#!/usr/bin/env bash
# Regression checks for terminal concept password redraw, keyboard activation, and mouse dispatch.

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
read_key = text.split("read_key() {", 1)[1].split("\nparse_mouse_event() {", 1)[0]
run_tui = text.split("run_tui() {", 1)[1].split("\nprint_static() {", 1)[0]

bad_loop = "while true; do\n        WINDOW_RESIZED=0\n        render\n"
if bad_loop in run_tui:
    raise SystemExit("FAIL: run_tui still performs a full-screen render before every key read")

if "render_password_field_only" not in run_tui:
    raise SystemExit("FAIL: password input does not use a targeted field redraw")

# read -n treats newline as a delimiter and loses Enter. Exact-character -N
# preserves Enter and terminal escape-stream bytes verbatim.
if "read -rsN1" not in read_key:
    raise SystemExit("FAIL: input reader does not use exact-character read -N1")
if "read -rsn1" in read_key:
    raise SystemExit("FAIL: input reader still uses delimiter-sensitive read -n1")

if '[[ -n $key ]] || continue' in run_tui or '[[ -n "$key" ]] || continue' in run_tui:
    raise SystemExit("FAIL: run_tui still discards empty/delimiter Enter input")

# Mouse events must use the parser directly; the parser owns validation.
if 'if handle_mouse_event "$key"; then' not in run_tui:
    raise SystemExit("FAIL: mouse events are not dispatched through handle_mouse_event")

# Structural redraws should reassert the mouse modes without touching password-only redraws.
render = text.split("render() {", 1)[1].split("\nread_key() {", 1)[0]
if "\\033[?1000h\\033[?1006h" not in render:
    raise SystemExit("FAIL: structural render does not reassert mouse tracking")
PY

printf '%s\n' 'polkit concept input redraw/keyboard/mouse tests passed'
