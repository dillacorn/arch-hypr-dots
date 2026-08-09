#!/usr/bin/env bash
# Per-output DDC brightness module for the Awtarchy Quickshell bar.
# Uses cached state and Linux inotify so no background DDC polling is required.

set -euo pipefail
export LC_ALL=C

BRIGHTNESS_SCRIPT="${HYPR_BRIGHTNESS_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/hypr-ddc-brightness.sh}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-ddc-brightness"
HELPER_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-ddc-brightness-$(id -u)"
CACHE_MAX_AGE_MS="${AWTARCHY_DDC_CACHE_MAX_AGE_MS:-30000}"
PREVIEW_MAX_AGE_MS="${AWTARCHY_DDC_PREVIEW_MAX_AGE_MS:-10000}"
STEP="${AWTARCHY_DDC_STEP:-5}"
SCROLL_DEBOUNCE_MS="${AWTARCHY_DDC_SCROLL_DEBOUNCE_MS:-1000}"
SCROLL_MAX_WAIT_MS="${AWTARCHY_DDC_SCROLL_MAX_WAIT_MS:-60000}"
QUERY_LOCK_TIMEOUT="${AWTARCHY_DDC_QUERY_LOCK_TIMEOUT:-5}"

now_ms() {
  if date +%s%3N >/dev/null 2>&1; then
    date +%s%3N
  else
    printf '%s\n' "$(( $(date +%s) * 1000 ))"
  fi
}

focused_monitor() {
  hyprctl -j monitors 2>/dev/null | jq -r '
    .[] | select(.focused == true or .focused == "yes") | .name
  ' | head -n 1
}

monitor_under_cursor() {
  local cursor x y

  cursor="$(hyprctl -j cursorpos 2>/dev/null)" || return 1
  x="$(jq -r '.x // empty' <<<"$cursor")"
  y="$(jq -r '.y // empty' <<<"$cursor")"

  [[ "$x" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
  [[ "$y" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1

  hyprctl -j monitors 2>/dev/null | jq -r \
    --argjson x "$x" \
    --argjson y "$y" '
      def rotated:
        ((.transform // 0) % 2) == 1;

      def logical_width:
        if rotated then
          (.height / (.scale // 1))
        else
          (.width / (.scale // 1))
        end;

      def logical_height:
        if rotated then
          (.width / (.scale // 1))
        else
          (.height / (.scale // 1))
        end;

      .[]
      | select(
          $x >= .x
          and $x < (.x + logical_width)
          and $y >= .y
          and $y < (.y + logical_height)
        )
      | .name
    ' | head -n 1
}

resolve_monitor() {
  local monitor="${AWTARCHY_OUTPUT_NAME:-}"

  if [[ -z "$monitor" ]]; then
    monitor="$(monitor_under_cursor || true)"
  fi

  if [[ -z "$monitor" ]]; then
    monitor="$(focused_monitor || true)"
  fi

  [[ -n "$monitor" ]] || return 1
  printf '%s\n' "$monitor"
}

state_file() {
  printf '%s/state_%s.tsv\n' "$CACHE_DIR" "$1"
}

preview_file() {
  printf '%s/preview_%s.tsv\n' "$CACHE_DIR" "$1"
}

helper_pending_file() {
  printf '%s/pending_%s.txt\n' "$HELPER_RUNTIME_DIR" "$1"
}

safe_name() {
  printf '%s' "$1" | tr '/[:space:]' '_'
}

read_status_record() {
  local file="$1"
  local cur max timestamp

  [[ -r "$file" ]] || return 1
  read -r cur max timestamp <"$file" || return 1

  [[ "$cur" =~ ^[0-9]+$ ]] || return 1
  [[ "$max" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$timestamp" =~ ^[0-9]+$ ]] || return 1

  printf '%s %s %s\n' "$cur" "$max" "$timestamp"
}

read_cached_status() {
  local monitor="$1"
  local cur max timestamp current age

  read -r cur max timestamp < <(read_status_record "$(state_file "$monitor")") || return 1

  current="$(now_ms)"
  age=$((current - timestamp))

  (( age >= 0 && age <= CACHE_MAX_AGE_MS )) || return 1
  printf '%s %s\n' "$cur" "$max"
}

read_preview_status() {
  local monitor="$1"
  local cur max timestamp state_cur state_max state_timestamp current age

  read -r cur max timestamp < <(read_status_record "$(preview_file "$monitor")") || return 1

  current="$(now_ms)"
  age=$((current - timestamp))
  (( age >= 0 && age <= PREVIEW_MAX_AGE_MS )) || return 1

  if read -r state_cur state_max state_timestamp < <(read_status_record "$(state_file "$monitor")"); then
    (( timestamp >= state_timestamp )) || return 1
  fi

  printf '%s %s\n' "$cur" "$max"
}

write_preview_status() {
  local monitor="$1" cur="$2" max="$3" timestamp file tmp

  mkdir -p "$CACHE_DIR"
  timestamp="$(now_ms)"
  file="$(preview_file "$monitor")"
  tmp="${file}.tmp.$$"

  printf '%s\t%s\t%s\n' "$cur" "$max" "$timestamp" >"$tmp"
  mv -f "$tmp" "$file"
}

query_status_unlocked() {
  local monitor="$1"
  local output cur max

  output="$(
    HYPR_DDC_NOTIFY=0 \
      "$BRIGHTNESS_SCRIPT" --monitor "$monitor" status 2>/dev/null
  )" || return 1

  cur="$(awk -F= '$1 == "cur" {print $2; exit}' <<<"$output")"
  max="$(awk -F= '$1 == "max" {print $2; exit}' <<<"$output")"

  [[ "$cur" =~ ^[0-9]+$ ]] || return 1
  [[ "$max" =~ ^[1-9][0-9]*$ ]] || return 1

  printf '%s %s\n' "$cur" "$max"
}

query_status() {
  local monitor="$1" lock_file lock_fd result rc=0

  mkdir -p "$CACHE_DIR"
  lock_file="${CACHE_DIR}/query_$(safe_name "$monitor").lock"

  if ! command -v flock >/dev/null 2>&1; then
    query_status_unlocked "$monitor"
    return $?
  fi

  exec {lock_fd}>"$lock_file"
  if ! flock -w "$QUERY_LOCK_TIMEOUT" "$lock_fd"; then
    exec {lock_fd}>&-
    return 1
  fi

  # Another bar instance may have refreshed this display while we waited.
  if result="$(read_cached_status "$monitor")"; then
    exec {lock_fd}>&-
    printf '%s\n' "$result"
    return 0
  fi

  result="$(query_status_unlocked "$monitor")" || rc=$?
  exec {lock_fd}>&-

  (( rc == 0 )) || return "$rc"
  printf '%s\n' "$result"
}

print_status_for_monitor() {
  local monitor="$1" cur max percent tooltip preview=false

  if read -r cur max < <(read_preview_status "$monitor"); then
    preview=true
  else
    if ! read -r cur max < <(read_cached_status "$monitor"); then
      if ! read -r cur max < <(query_status "$monitor"); then
        jq -cn \
          --arg monitor "$monitor" \
          '{
            text:" ?",
            tooltip:("Brightness " + $monitor + ": DDC unavailable"),
            class:["error"]
          }'
        return 0
      fi
    fi
  fi

  percent=$(((cur * 100 + max / 2) / max))
  if [[ "$preview" == true ]]; then
    tooltip="Brightness ${monitor}: ${percent}% target (pending)"
  else
    tooltip="Brightness ${monitor}: ${percent}%"
  fi
  tooltip+="
Hover briefly, then scroll to adjust this display
Left/right click to toggle Hypr Quick Settings"

  jq -cn \
    --arg text " ${percent}%" \
    --arg tooltip "$tooltip" \
    --argjson percentage "$percent" \
    --argjson pending "$preview" \
    '{
      text:$text,
      tooltip:$tooltip,
      class:(["ddc-brightness"] + (if $pending then ["pending"] else [] end)),
      percentage:$percentage,
      pending:$pending
    }'
}

print_status() {
  local monitor

  monitor="$(resolve_monitor)" || {
    jq -cn \
      '{text:" ?",tooltip:"No Hyprland monitor found",class:["error"]}'
    return 0
  }

  print_status_for_monitor "$monitor"
}

watch_state_events() {
  local monitor="$1" state_name preview_name

  state_name="$(basename "$(state_file "$monitor")")"
  preview_name="$(basename "$(preview_file "$monitor")")"
  mkdir -p "$CACHE_DIR"

  python3 - "$CACHE_DIR" "$state_name" "$preview_name" "$PREVIEW_MAX_AGE_MS" <<'PY'
import ctypes
import os
import select
import struct
import sys
import signal
import time

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

watch_dir = os.fsencode(sys.argv[1])
state_target = sys.argv[2]
preview_target = sys.argv[3]
preview_max_age_ms = int(sys.argv[4])
targets = {state_target, preview_target}
preview_path = os.path.join(sys.argv[1], preview_target)

IN_ATTRIB = 0x00000004
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
mask = IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE

libc = ctypes.CDLL(None, use_errno=True)
init = libc.inotify_init1
init.argtypes = [ctypes.c_int]
init.restype = ctypes.c_int
add_watch = libc.inotify_add_watch
add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
add_watch.restype = ctypes.c_int

fd = init(os.O_CLOEXEC)
if fd < 0:
    raise OSError(ctypes.get_errno(), "inotify_init1 failed")

wd = add_watch(fd, watch_dir, mask)
if wd < 0:
    raise OSError(ctypes.get_errno(), "inotify_add_watch failed")

print("ready", flush=True)

header = struct.Struct("iIII")
while True:
    readable, _, _ = select.select([fd], [], [], 0.25)

    if not readable:
        try:
            with open(preview_path, "r", encoding="utf-8") as preview:
                fields = preview.readline().split()
            if len(fields) >= 3:
                timestamp = int(fields[2])
                age = int(time.time() * 1000) - timestamp
                if age > preview_max_age_ms:
                    os.unlink(preview_path)
        except (FileNotFoundError, PermissionError, ValueError, OSError):
            pass
        continue

    data = os.read(fd, 65536)
    offset = 0
    changed = False

    while offset + header.size <= len(data):
        _wd, event_mask, _cookie, name_len = header.unpack_from(data, offset)
        offset += header.size
        raw_name = data[offset:offset + name_len]
        offset += name_len
        name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
        if name in targets and event_mask & mask:
            changed = True

    if changed:
        print("changed", flush=True)
PY
}

watch_status() {
  local monitor event

  monitor="$(resolve_monitor)" || {
    print_status
    exec sleep infinity
  }

  if ! command -v python3 >/dev/null 2>&1; then
    print_status_for_monitor "$monitor"
    exec sleep infinity
  fi

  while IFS= read -r event; do
    case "$event" in
      ready|changed)
        print_status_for_monitor "$monitor"
        ;;
    esac
  done < <(watch_state_events "$monitor")

  exec sleep infinity
}

update_preview_from_pending() {
  local monitor="$1" cur max _timestamp pending target pending_path

  read -r cur max _timestamp < <(read_status_record "$(state_file "$monitor")") || return 0

  pending_path="$(helper_pending_file "$monitor")"
  pending=0
  if [[ -r "$pending_path" ]]; then
    IFS= read -r pending <"$pending_path" || pending=0
  fi
  [[ "$pending" =~ ^-?[0-9]+$ ]] || pending=0

  target=$((cur + pending))
  (( target < 0 )) && target=0
  (( target > max )) && target="$max"

  write_preview_status "$monitor" "$target" "$max"
}

adjust() {
  local direction="$1"
  local monitor

  monitor="$(monitor_under_cursor || true)"
  [[ -n "$monitor" ]] || monitor="$(resolve_monitor)"

  HYPR_DDC_DEBOUNCE_MS="$SCROLL_DEBOUNCE_MS" \
    HYPR_DDC_MAX_WAIT_MS="$SCROLL_MAX_WAIT_MS" \
    "$BRIGHTNESS_SCRIPT" --monitor "$monitor" "$direction" "$STEP"

  update_preview_from_pending "$monitor"
}

toggle_quick_settings() {
  local quickshell_manager
  quickshell_manager="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh"
  "$quickshell_manager" start >/dev/null 2>&1 || true
  qs -c awtarchy ipc call quicksettings toggle >/dev/null
}

case "${1:-status}" in
  status|"")
    print_status
    ;;
  watch)
    watch_status
    ;;
  up)
    adjust up
    ;;
  down)
    adjust down
    ;;
  menu)
    toggle_quick_settings
    ;;
  *)
    printf 'Usage: %s {status|watch|up|down|menu}\n' "$0" >&2
    exit 2
    ;;
esac
