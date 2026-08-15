#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/gif_capture.sh

set -euo pipefail
umask 077

# --- config ---
FPS=10
SCALE_WIDTH=640
MAX_DURATION=600
SAVE_DIR="$HOME/Videos/Gifs"

die() {
  printf 'gif_capture: %s\n' "$*" >&2
  exit 1
}

init_private_runtime() {
  local base owner mode

  base="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  [[ $base == /* && -d $base && ! -L $base ]] \
    || die 'XDG runtime directory is missing or unsafe'
  owner="$(stat -c %u -- "$base" 2>/dev/null)" \
    || die 'could not inspect XDG runtime directory owner'
  mode="$(stat -c %a -- "$base" 2>/dev/null)" \
    || die 'could not inspect XDG runtime directory mode'
  [[ $owner == "$(id -u)" && $mode =~ ^[0-7]{3,4}$ ]] \
    || die 'XDG runtime directory ownership or mode is unsafe'
  (( (8#$mode & 8#077) == 0 )) \
    || die 'XDG runtime directory must not be accessible by other users'

  STATE_DIR="${base}/awtarchy"
  [[ ! -L $STATE_DIR ]] || die 'Awtarchy runtime directory must not be a symbolic link'
  install -d -m 0700 -- "$STATE_DIR" \
    || die 'could not create Awtarchy runtime directory'
  owner="$(stat -c %u -- "$STATE_DIR" 2>/dev/null)" \
    || die 'could not inspect Awtarchy runtime directory owner'
  [[ $owner == "$(id -u)" ]] || die 'Awtarchy runtime directory has the wrong owner'
  chmod 0700 -- "$STATE_DIR" || die 'could not secure Awtarchy runtime directory'
}

process_start_time() {
  local pid="$1" proc_stat
  local -a stat_fields=()

  [[ $pid =~ ^[0-9]+$ && $pid -gt 1 ]] || return 1
  IFS= read -r proc_stat <"/proc/${pid}/stat" || return 1
  proc_stat="${proc_stat##*) }"
  IFS=' ' read -r -a stat_fields <<<"$proc_stat"
  (( ${#stat_fields[@]} >= 20 )) || return 1
  printf '%s\n' "${stat_fields[19]}"
}

write_pid_record() {
  local file="$1" pid="$2" started temporary

  started="$(process_start_time "$pid")" || return 1
  temporary="$(mktemp "${STATE_DIR}/.pid.XXXXXX")" || return 1
  printf '%s %s\n' "$pid" "$started" >"$temporary"
  chmod 0600 -- "$temporary"
  mv -Tf -- "$temporary" "$file"
}

read_pid_record() {
  local file="$1" pid started extra actual owner mode

  [[ -f $file && ! -L $file ]] || return 1
  owner="$(stat -c %u -- "$file" 2>/dev/null)" || return 1
  mode="$(stat -c %a -- "$file" 2>/dev/null)" || return 1
  [[ $owner == "$(id -u)" && $mode =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$mode & 8#077) == 0 )) || return 1
  IFS=' ' read -r pid started extra <"$file" || return 1
  [[ $pid =~ ^[0-9]+$ && $pid -gt 1 && $started =~ ^[0-9]+$ && -z ${extra:-} ]] \
    || return 1
  actual="$(process_start_time "$pid")" || return 1
  [[ $actual == "$started" ]] || return 1
  printf '%s\n' "$pid"
}

init_private_runtime

# --- deps ---
for cmd in wf-recorder slurp ffmpeg notify-send; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd is required." >&2; exit 1; }
done
mkdir -p "$SAVE_DIR"

# --- paths (stable names so the hotkey can toggle) ---
PID_FILE="${STATE_DIR}/gif-record.pid"
MP4_FILE="${STATE_DIR}/gif-record.mp4"
PAL_FILE="${STATE_DIR}/gif-record-palette.png"

stop_recording() {
  local rec_pid="$1"

  # stop recorder if running
  if kill -0 "$rec_pid" 2>/dev/null; then
      kill -TERM "$rec_pid" 2>/dev/null || true
      # wait for exit (max ~3s), then hard kill if needed
      for _ in 1 2 3 4 5 6; do
        kill -0 "$rec_pid" 2>/dev/null || break
        sleep 0.5
      done
      kill -KILL "$rec_pid" 2>/dev/null || true
  fi
  rm -f -- "$PID_FILE"
}

compile_gif() {
  # small grace to ensure mp4 gets closed
  sleep 0.25

  if [[ ! -s "$MP4_FILE" ]]; then
    rm -f "$PAL_FILE" "$MP4_FILE" 2>/dev/null || true
    notify-send "GIF Recording" "No video captured."
    exit 0
  fi

  notify-send "GIF Recording" "Compiling…"

  ffmpeg -v error -i "$MP4_FILE" -filter_complex \
    "fps=${FPS},scale=${SCALE_WIDTH}:-1:flags=lanczos,palettegen=stats_mode=full" \
    -y "$PAL_FILE"

  umask 077
  OUT="$SAVE_DIR/$(date +%Y%m%d-%H%M%S).gif"

  ffmpeg -v error -i "$MP4_FILE" -i "$PAL_FILE" -filter_complex \
    "fps=${FPS},scale=${SCALE_WIDTH}:-1:flags=lanczos,paletteuse=dither=sierra2_4a" \
    -y "$OUT"

  rm -f "$PAL_FILE" "$MP4_FILE" 2>/dev/null || true
  notify-send "GIF Saved" "Saved to $OUT"
}

# --- toggle logic ---
if [[ -e $PID_FILE || -L $PID_FILE ]]; then
  if REC_PID="$(read_pid_record "$PID_FILE")"; then
    stop_recording "$REC_PID"
  else
    rm -f -- "$PID_FILE" "$MP4_FILE" "$PAL_FILE"
    printf 'gif_capture: discarded stale or unsafe recording state\n' >&2
  fi
  if [[ -n ${REC_PID:-} ]]; then
    compile_gif
    exit 0
  fi
fi

# start branch
COORDS="$(slurp || true)"
[[ -n "${COORDS:-}" ]] || exit 1

# clean any stale files
rm -f "$MP4_FILE" "$PAL_FILE" 2>/dev/null || true

notify-send "GIF Recording" "Recording started. Press the hotkey again to stop."

# start recorder in background and record its REAL pid
wf-recorder -g "$COORDS" -f "$MP4_FILE" >/dev/null 2>&1 &
REC_PID=$!
if ! write_pid_record "$PID_FILE" "$REC_PID"; then
  kill -TERM "$REC_PID" 2>/dev/null || true
  die 'could not record the GIF capture process safely'
fi

# watchdog to enforce MAX_DURATION
(
  for _ in $(seq $MAX_DURATION); do
    kill -0 "$REC_PID" 2>/dev/null || exit 0
    sleep 1
  done
  kill -TERM "$REC_PID" 2>/dev/null || true
) &

disown
