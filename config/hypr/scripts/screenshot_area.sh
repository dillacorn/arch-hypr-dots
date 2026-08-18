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

DEBUG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/screenshot-debug"
mkdir -p "$DEBUG_DIR"

attempt_counter="$DEBUG_DIR/attempt_counter"
attempt_counter_lock="$DEBUG_DIR/attempt_counter.lock"

exec 8>"$attempt_counter_lock"
flock 8
attempt_value="$(cat "$attempt_counter" 2>/dev/null || printf '0')"
[[ "$attempt_value" =~ ^[0-9]+$ ]] || attempt_value=0
ATTEMPT_ID=$(( attempt_value + 1 ))
printf '%s\n' "$ATTEMPT_ID" >"$attempt_counter"
flock -u 8
exec 8>&-

attempt_tag="$(printf '%06d' "$ATTEMPT_ID")"
DEBUG_LOG="$DEBUG_DIR/attempt-${attempt_tag}-$(date +%Y%m%d-%H%M%S)-$$.log"

# Keep the newest 50 capture attempts. Filenames begin with a monotonically
# increasing zero-padded attempt number, so reverse lexical order is newest first.
mapfile -t debug_logs < <(
  find "$DEBUG_DIR" -maxdepth 1 -type f -name 'attempt-*.log' -printf '%f\n' 2>/dev/null \
    | sort -r
)
if (( ${#debug_logs[@]} >= 50 )); then
  for old_log in "${debug_logs[@]:49}"; do
    rm -f -- "$DEBUG_DIR/$old_log"
  done
fi

log_event() {
  local event="$1"
  shift || true
  printf '%s attempt=%s event=%s %s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S.%N%z')" \
    "$ATTEMPT_ID" \
    "$event" \
    "$*" >>"$DEBUG_LOG"
}

cursor_snapshot() {
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl cursorpos 2>&1 || true
  fi
}

TMPFILE=""
SLURP_ERR=""
FREEZE_PID=""
CURRENT_STAGE="startup"
unlocked=0

log_event "attempt-start" \
  "pid=$$ wayland_display=${WAYLAND_DISPLAY:-unset} hyprland_instance=${HYPRLAND_INSTANCE_SIGNATURE:-unset} cursor=$(cursor_snapshot)"

exec 9>"$lock_file"
if ! flock -n 9; then
  log_event "lock-busy" "exit_status=0"
  notify-send "Screenshot" "Capture already running."
  exit 0
fi
log_event "lock-acquired"

unlock_capture() {
  if [[ "$unlocked" -eq 0 ]]; then
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    unlocked=1
    log_event "lock-released"
  fi
}

stop_freeze() {
  local freeze_rc=0
  if [[ -n "${FREEZE_PID:-}" ]]; then
    log_event "hyprpicker-stop" "pid=$FREEZE_PID"
    kill "$FREEZE_PID" 2>/dev/null || true
    wait "$FREEZE_PID" 2>/dev/null || freeze_rc=$?
    log_event "hyprpicker-stopped" "pid=$FREEZE_PID wait_status=$freeze_rc"
    FREEZE_PID=""
  fi
}

cleanup() {
  local exit_status=$?
  log_event "attempt-exit" "stage=$CURRENT_STAGE exit_status=$exit_status cursor=$(cursor_snapshot)"
  stop_freeze
  unlock_capture
  [[ -n "${SLURP_ERR:-}" ]] && rm -f -- "$SLURP_ERR"
  [[ -n "${TMPFILE:-}" ]] && rm -f -- "$TMPFILE"
}

trap cleanup EXIT INT TERM

# Freeze the currently rendered frame before slurp can steal focus. This keeps
# focus-sensitive Awtarchy flyouts visible in the image while the user selects
# an area. Existing noscreenshare rules still decide whether a flyout is present
# in the frozen screencopy.
CURRENT_STAGE="hyprpicker"
log_event "hyprpicker-start" "cursor=$(cursor_snapshot)"
hyprpicker -r -z >/dev/null 2>>"$DEBUG_LOG" &
FREEZE_PID=$!
log_event "hyprpicker-pid" "pid=$FREEZE_PID"
sleep 0.15
if kill -0 "$FREEZE_PID" 2>/dev/null; then
  freeze_state="$(ps -o pid=,stat=,etimes=,comm= -p "$FREEZE_PID" 2>/dev/null || true)"
  log_event "hyprpicker-state" "pid=$FREEZE_PID state=$freeze_state"
else
  freeze_rc=0
  wait "$FREEZE_PID" 2>/dev/null || freeze_rc=$?
  log_event "hyprpicker-state" "pid=$FREEZE_PID exited=1 wait_status=$freeze_rc"
  FREEZE_PID=""
fi

CURRENT_STAGE="slurp"
TMP_DIR="${XDG_RUNTIME_DIR:-/tmp}"
SLURP_ERR="$(mktemp "$TMP_DIR/awtarchy-slurp-XXXXXX.err")"
log_event "slurp-start" "cursor=$(cursor_snapshot)"

slurp_rc=0
if GEOM="$(slurp -b '#ffffff20' -c '#00000040' 9>&- 2>"$SLURP_ERR")"; then
  slurp_rc=0
else
  slurp_rc=$?
fi

if [[ -s "$SLURP_ERR" ]]; then
  while IFS= read -r line; do
    log_event "slurp-stderr" "$line"
  done <"$SLURP_ERR"
  cat "$SLURP_ERR" >&2
fi

quoted_geom="$(printf '%q' "${GEOM:-}")"
log_event "slurp-exit" "rc=$slurp_rc geometry=$quoted_geom cursor=$(cursor_snapshot)"
(( slurp_rc == 0 )) || exit 1
[[ -n "${GEOM:-}" ]] || {
  log_event "slurp-empty-geometry" "exit_status=1"
  exit 1
}

CURRENT_STAGE="grim"
TMPFILE="$(mktemp "$TMP_DIR/satty-shot-XXXXXX.png")"
OUTFILE="$OUTPUT_DIR/$(date +%m%d%Y-%I%p-%S).png"

log_event "grim-start" "geometry=$quoted_geom tmpfile=$TMPFILE"
grim -g "$GEOM" "$TMPFILE" 9>&-
log_event "grim-exit" "rc=0 bytes=$(stat -c %s "$TMPFILE" 2>/dev/null || printf 'unknown')"

stop_freeze

CURRENT_STAGE="clipboard"
log_event "clipboard-start"
wl-copy --type image/png < "$TMPFILE" 9>&-
log_event "clipboard-exit" "rc=0"

# Release lock before satty so another capture can start immediately.
unlock_capture

CURRENT_STAGE="satty"
log_event "satty-start" "outfile=$OUTFILE"
satty \
  --filename "$TMPFILE" \
  --output-filename "$OUTFILE" \
  --default-hide-toolbars
log_event "satty-exit" "rc=0"
CURRENT_STAGE="complete"
