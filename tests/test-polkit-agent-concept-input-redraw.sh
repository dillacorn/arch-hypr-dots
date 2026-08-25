#!/usr/bin/env bash
# Regression checks for terminal concept redraw, keyboard activation, and SGR mouse input.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent-concept.sh"
TIPS_TUI="${ROOT_DIR}/config/hypr/scripts/awtarchy-tips-tui.sh"

[[ -f $SCRIPT ]]
[[ -f $TIPS_TUI ]]

grep -Fq 'PASSWORD_LENGTH=0' "$SCRIPT"
grep -Fq 'render_password_field_only()' "$SCRIPT"
grep -Fq 'render_password_field_only' "$SCRIPT"
grep -Fq "STATUS_MSG='Password not entered.'" "$SCRIPT"
grep -Fq "STATUS_MSG='Incorrect password.'" "$SCRIPT"

if grep -Fq 'DEMO_PASSWORD' "$SCRIPT"; then
    printf '%s\n' 'FAIL: concept still stores typed password characters' >&2
    exit 1
fi

python3 - "$SCRIPT" "$TIPS_TUI" <<'PY'
from pathlib import Path
import sys

concept = Path(sys.argv[1]).read_text(encoding="utf-8")
tips = Path(sys.argv[2]).read_text(encoding="utf-8")


def function_body(text: str, name: str, next_name: str) -> str:
    return text.split(f"{name}() {{", 1)[1].split(f"\n{next_name}() {{", 1)[0]

concept_read_key = function_body(concept, "read_key", "parse_mouse_event")
tips_read_key = function_body(tips, "read_key", "parse_mouse_event")
run_tui = function_body(concept, "run_tui", "print_static")
ui_enter = function_body(concept, "ui_enter", "hyprland_geometry_available")

bad_loop = "while true; do\n        WINDOW_RESIZED=0\n        render\n"
if bad_loop in run_tui:
    raise SystemExit("FAIL: run_tui still performs a full-screen render before every key read")

if "render_password_field_only" not in run_tui:
    raise SystemExit("FAIL: password input does not use a targeted field redraw")

# Reuse the input reader already exercised by Awtarchy Tips instead of keeping
# a second subtly different terminal-event implementation.
if concept_read_key.strip() != tips_read_key.strip():
    raise SystemExit("FAIL: Polkit concept read_key diverges from the working Awtarchy Tips TUI reader")

if 'key="$(read_key || true)"' not in run_tui:
    raise SystemExit("FAIL: Polkit concept does not acquire events through the working command-substitution path")

if "READ_KEY_VALUE" in concept:
    raise SystemExit("FAIL: obsolete global READ_KEY_VALUE event path is still present")

if 'if parse_mouse_event "$key"; then' not in run_tui:
    raise SystemExit("FAIL: mouse events are not dispatched directly through parse_mouse_event")

if "\\033[?1000h\\033[?1006h" not in ui_enter:
    raise SystemExit("FAIL: SGR mouse tracking is not enabled")
if "?1002h" in concept:
    raise SystemExit("FAIL: unneeded button-motion mouse mode is enabled")
PY

# Exercise the exact standard SGR button event observed from a live terminal.
# This is terminal-cell data, not machine-specific pixel geometry.
(
    source "$SCRIPT"

    exec 3< <(printf '\033[<0;43;16M')
    key="$(read_key || true)"
    [[ $key == $'\033[<0;43;16M' ]] || {
        printf 'FAIL: SGR mouse press was not read intact: %q\n' "$key" >&2
        exit 1
    }

    parse_mouse_event "$key"
    [[ $MOUSE_BUTTON == 0 && $MOUSE_X == 43 && $MOUSE_Y == 16 && $MOUSE_RELEASE == 0 ]] || {
        printf 'FAIL: SGR mouse press parsed incorrectly: button=%s x=%s y=%s release=%s\n' \
            "$MOUSE_BUTTON" "$MOUSE_X" "$MOUSE_Y" "$MOUSE_RELEASE" >&2
        exit 1
    }

    exec 3< <(printf '\033[<0;43;16m')
    key="$(read_key || true)"
    parse_mouse_event "$key"
    [[ $MOUSE_RELEASE == 1 ]] || {
        printf '%s\n' 'FAIL: SGR mouse release was not recognized' >&2
        exit 1
    }

    exec 3< <(printf '\n')
    key="$(read_key || true)"
    [[ -z $key ]] || {
        printf 'FAIL: Enter normalization changed: %q\n' "$key" >&2
        exit 1
    }
)

printf '%s\n' 'polkit concept input redraw/keyboard/mouse tests passed'
