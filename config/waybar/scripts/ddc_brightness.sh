#!/usr/bin/env bash
# Per-output DDC brightness module for Waybar.
# Uses cached state and Linux inotify so no background DDC polling is required.

set -euo pipefail
export LC_ALL=C

BRIGHTNESS_SCRIPT="${HYPR_BRIGHTNESS_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/hypr-ddc-brightness.sh}"
QUICK_SETTINGS="${HYPR_QUICK_SETTINGS_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/hypr_quicksettings.sh}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-ddc-brightness"
CACHE_MAX_AGE_MS="${WAYBAR_DDC_CACHE_MAX_AGE_MS:-30000}"
STEP="${WAYBAR_DDC_STEP:-5}"
QUERY_LOCK_TIMEOUT="${WAYBAR_DDC_QUERY_LOCK_TIMEOUT:-5}"

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
  local monitor="${WAYBAR_OUTPUT_NAME:-}"

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

safe_name() {
  printf '%s' "$1" | tr '/[:space:]' '__'
}

read_cached_status() {
  local monitor="$1"
  local file cur max timestamp current age

  file="$(state_file "$monitor")"
  [[ -r "$file" ]] || return 1

  read -r cur max timestamp <"$file" || return 1

  [[ "$cur" =~ ^[0-9]+$ ]] || return 1
  [[ "$max" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$timestamp" =~ ^[0-9]+$ ]] || return 1

  current="$(now_ms)"
  age=$((current - timestamp))

  (( age >= 0 && age <= CACHE_MAX_AGE_MS )) || return 1
  printf '%s %s\n' "$cur" "$max"
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
  local monitor="$1" lock_file

  mkdir -p "$CACHE_DIR"
  lock_file="${CACHE_DIR}/query_$(safe_name "$monitor").lock"

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock_file"
    flock -w "$QUERY_LOCK_TIMEOUT" 9 || return 1

    # Another Waybar instance may have refreshed this display while we waited.
    if read_cached_status "$monitor"; then
      return 0
    fi
  fi

  query_status_unlocked "$monitor"
}

print_status_for_monitor() {
  local monitor="$1" cur max percent tooltip

  if ! read -r cur max < <(read_cached_status "$monitor"); then
    if ! read -r cur max < <(query_status "$monitor"); then
      jq -cn \
        --arg monitor "$monitor" \
        '{
          text:" ?",
          tooltip:("Brightness " + $monitor + ": DDC unavailable"),
          class:["error"]
        }'
      return 0
    fi
  fi

  percent=$((cur * 100 / max))
  tooltip="Brightness ${monitor}: ${cur}/${max}
Scroll to adjust this display
Left/right click to toggle Hypr Quick Settings"

  jq -cn \
    --arg text " ${cur}" \
    --arg tooltip "$tooltip" \
    --argjson percentage "$percent" \
    '{
      text:$text,
      tooltip:$tooltip,
      class:["ddc-brightness"],
      percentage:$percentage
    }'
}

print_status() {
  local monitor

  monitor="$(resolve_monitor)" || {
    jq -cn \
      '{text:" ?",tooltip:"No Hyprland monitor found",class:["error"]}'
    return 0
  }

  print_status_for_monitor "$monitor"
}

watch_state_events() {
  local monitor="$1" file

  file="$(basename "$(state_file "$monitor")")"
  mkdir -p "$CACHE_DIR"

  python3 - "$CACHE_DIR" "$file" <<'PY'
import ctypes
import os
import struct
import sys
import signal

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

watch_dir = os.fsencode(sys.argv[1])
target = sys.argv[2]

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

# Tell the shell that the watch is active before it prints the initial value.
print("ready", flush=True)

header = struct.Struct("iIII")
while True:
    data = os.read(fd, 65536)
    offset = 0
    while offset + header.size <= len(data):
        _wd, event_mask, _cookie, name_len = header.unpack_from(data, offset)
        offset += header.size
        raw_name = data[offset:offset + name_len]
        offset += name_len
        name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
        if name == target and event_mask & mask:
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

  # Avoid a hot restart loop if inotify becomes unavailable at runtime.
  exec sleep infinity
}

adjust() {
  local direction="$1"
  local monitor

  monitor="$(monitor_under_cursor || true)"
  [[ -n "$monitor" ]] || monitor="$(resolve_monitor)"

  "$BRIGHTNESS_SCRIPT" --monitor "$monitor" "$direction" "$STEP"
}

quick_settings_addresses() {
  hyprctl clients -j 2>/dev/null |
    jq -r '
      (. // [])[]
      | select(
          .mapped == true
          and .hidden == false
          and (
            .class == "hypr_quicksettings"
            or .initialClass == "hypr_quicksettings"
          )
        )
      | .address
    '
}

toggle_quick_settings() {
  local monitor runtime_dir lock_file lock_dir address
  local -a addresses=()

  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  lock_file="${runtime_dir}/waybar-ddc-quicksettings.lock"
  lock_dir="${lock_file}.d"

  mkdir -p "$runtime_dir"

  # Never wait behind another click. Extra clicks during launch/close are dropped.
  if command -v flock >/dev/null 2>&1; then
    exec 8>"$lock_file"
    flock -n 8 || return 0
  else
    mkdir "$lock_dir" 2>/dev/null || return 0
    trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
  fi

  mapfile -t addresses < <(quick_settings_addresses)

  # Existing instance: close every match and do not relaunch.
  if (( ${#addresses[@]} > 0 )); then
    for address in "${addresses[@]}"; do
      [[ -n "$address" ]] || continue

      hyprctl dispatch "hl.dsp.window.close({ window = \"address:${address}\" })" >/dev/null 2>&1 || true
    done

    # Hold the nonblocking lock only until Hyprland removes the window.
    for _ in {1..20}; do
      [[ -z "$(quick_settings_addresses)" ]] && return 0
      sleep 0.05
    done

    return 0
  fi

  monitor="$(monitor_under_cursor || true)"
  [[ -n "$monitor" ]] || monitor="$(resolve_monitor)"

  # Launch Alacritty directly. --ui prevents hypr_quicksettings.sh from
  # attempting to launch a second terminal.
  HYPR_BRIGHTNESS_MONITOR="$monitor" \
    alacritty \
      --class hypr_quicksettings,hypr_quicksettings \
      --title "Awtarchy Quick Settings" \
      -e bash "$QUICK_SETTINGS" --ui \
      >/dev/null 2>&1 8>&- &

  # Release the lock immediately once the actual window becomes visible.
  for _ in {1..40}; do
    [[ -n "$(quick_settings_addresses)" ]] && return 0
    sleep 0.05
  done

  return 0
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
