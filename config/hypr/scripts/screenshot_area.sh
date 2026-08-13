#!/usr/bin/env bash
# ~/.config/hypr/scripts/screenshot_area.sh
# Single-instance ONLY during capture (slurp+grim+clipboard).
# Satty stays outside the lock so you can keep editing while taking more screenshots.

set -euo pipefail

lock_dir="${XDG_RUNTIME_DIR:-/tmp}/awtarchy-locks"
mkdir -p "$lock_dir"
lock_file="$lock_dir/screenshot_capture.lock"

OUTPUT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$OUTPUT_DIR"

for cmd in grim slurp wl-copy satty notify-send mktemp flock hyprpicker; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "$cmd missing" >&2
    exit 1
  }
done

exec 9>"$lock_file"
if ! flock -n 9; then
  notify-send "Screenshot" "Capture already running."
  exit 0
fi

TMPFILE=""
FREEZE_PID=""
unlocked=0

unlock_capture() {
  if [[ "$unlocked" -eq 0 ]]; then
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    unlocked=1
  fi
}

stop_freeze() {
  if [[ -n "${FREEZE_PID:-}" ]]; then
    kill "$FREEZE_PID" 2>/dev/null || true
    wait "$FREEZE_PID" 2>/dev/null || true
    FREEZE_PID=""
  fi
}

cleanup() {
  stop_freeze
  unlock_capture
  [[ -n "${TMPFILE:-}" ]] && rm -f -- "$TMPFILE"
}

trap cleanup EXIT INT TERM

# Freeze the currently rendered frame before slurp can steal focus. This keeps
# focus-sensitive Awtarchy flyouts visible in the image while the user selects
# an area. Existing noscreenshare rules still decide whether a flyout is present
# in the frozen screencopy.
hyprpicker -r -z >/dev/null 2>&1 &
FREEZE_PID=$!
sleep 0.15
if ! kill -0 "$FREEZE_PID" 2>/dev/null; then
  wait "$FREEZE_PID" 2>/dev/null || true
  FREEZE_PID=""
fi

GEOM="$(slurp -b '#ffffff20' -c '#00000040' 9>&-)" || exit 1
[[ -n "${GEOM:-}" ]] || exit 1

TMP_DIR="${XDG_RUNTIME_DIR:-/tmp}"
TMPFILE="$(mktemp "$TMP_DIR/satty-shot-XXXXXX.png")"
OUTFILE="$OUTPUT_DIR/$(date +%m%d%Y-%I%p-%S).png"

grim -g "$GEOM" "$TMPFILE" 9>&-
stop_freeze
wl-copy --type image/png < "$TMPFILE" 9>&-

# Release lock before satty so another capture can start immediately.
unlock_capture

satty \
  --filename "$TMPFILE" \
  --output-filename "$OUTFILE" \
  --default-hide-toolbars
