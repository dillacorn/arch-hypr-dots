#!/usr/bin/env bash
# Regression checks for terminal concept password redraw, keyboard activation, and mouse dispatch.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-concept.sh"

[[ -f $SCRIPT ]]

grep -Fq 'PASSWORD_LENGTH=0' "$SCRIPT"
grep -Fq 'render_password_field_only()' "$SCRIPT"
grep -Fq 'render_password_field_only' "$SCRIPT"
grep -Fq "STATUS_MSG='Password not entered.'" "$SCRIPT"
grep -Fq "STATUS_MSG='Incorrect password.'" "$SCRIPT"

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
ui_enter = text.split("ui_enter() {", 1)[1].split("\nhyprland_geometry_available() {", 1)[0]

bad_loop = "while true; do\n        WINDOW_RESIZED=0\n        render\n"
if bad_loop in run_tui:
    raise SystemExit("FAIL: run_tui still performs a full-screen render before every key read")

if "render_password_field_only" not in run_tui:
    raise SystemExit("FAIL: password input does not use a targeted field redraw")

# Keep the last input primitive that was confirmed to deliver mouse events on
# the live Awtarchy/Alacritty setup. Enter is handled explicitly when -n1
# returns an empty value for the delimiter.
if "read -rsn1" not in read_key:
    raise SystemExit("FAIL: known-good read -n1 input path was replaced")
if "read -rsN1" in read_key:
    raise SystemExit("FAIL: regressed read -N1 path is present")
if "if [[ -z $key ]]; then" not in read_key or "READ_KEY_VALUE=$'\\n'" not in read_key:
    raise SystemExit("FAIL: Enter delimiter is not explicitly preserved")

if 'if handle_mouse_event "$key"; then' not in run_tui:
    raise SystemExit("FAIL: mouse events are not dispatched through handle_mouse_event")

# Match the last live-confirmed mouse protocol exactly: button events + SGR.
if "\\033[?1000h\\033[?1006h" not in ui_enter:
    raise SystemExit("FAIL: known-good SGR mouse tracking is not enabled")
if "?1002h" in text:
    raise SystemExit("FAIL: unverified button-motion mouse mode is enabled")
PY

printf '%s\n' 'polkit concept input redraw/keyboard/mouse tests passed'
