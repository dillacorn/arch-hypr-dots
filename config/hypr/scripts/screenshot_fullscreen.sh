#!/usr/bin/env bash
# ~/.config/hypr/scripts/screenshot_fullscreen.sh
# Single-instance ONLY during capture (slurp+grim). Satty can stay open while you take more screenshots.

set -euo pipefail

lock_dir="${XDG_RUNTIME_DIR:-/tmp}/awtarchy-locks"
mkdir -p "$lock_dir"
lock_file="$lock_dir/screenshot_capture.lock"

exec 9>"$lock_file"
if ! flock -n 9; then
  notify-send "Screenshot" "Capture already running."
  exit 0
fi

for cmd in grim slurp satty notify-send mktemp hyprpicker; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd missing" >&2; exit 1; }
done

mkdir -p "$HOME/Pictures/Screenshots"

TMPFILE=""
FREEZE_PID=""

stop_freeze() {
  if [[ -n "${FREEZE_PID:-}" ]]; then
    kill "$FREEZE_PID" 2>/dev/null || true
    wait "$FREEZE_PID" 2>/dev/null || true
    FREEZE_PID=""
  fi
}

cleanup() {
  stop_freeze
  [[ -n "${TMPFILE:-}" ]] && rm -f -- "$TMPFILE"
}
trap cleanup EXIT INT TERM

# Preserve the frame that was visible when the screenshot shortcut was pressed.
# slurp may take focus while selecting an output, but the capture still contains
# focus-sensitive Awtarchy flyouts when their capture setting allows it.
hyprpicker -r -z >/dev/null 2>&1 &
FREEZE_PID=$!
sleep 0.15
if ! kill -0 "$FREEZE_PID" 2>/dev/null; then
  wait "$FREEZE_PID" 2>/dev/null || true
  FREEZE_PID=""
fi

GEOM="$(slurp -o -r -c '#00000000')" || exit 1
[[ -n "${GEOM:-}" ]] || exit 1

TMP_DIR="${XDG_RUNTIME_DIR:-/tmp}"
TMPFILE="$(mktemp "$TMP_DIR/satty-shot-XXXXXX.png")"
OUTFILE="$HOME/Pictures/Screenshots/$(date +%m%d%Y-%I%p-%S).png"

grim -g "$GEOM" "$TMPFILE"
stop_freeze

# Release lock BEFORE satty starts, so you can take another screenshot while satty is open.
flock -u 9 || true
exec 9>&- || true

satty \
  --filename "$TMPFILE" \
  --fullscreen \
  --output-filename "$OUTFILE"
