#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/toggle_resize_if_ok.sh
#
# Behavior:
# - Toggle "resize" submap on/off with safety checks
# - Auto-exit resize if workspace changes
# - Always notify Waybar (signal RTMIN+12) so custom/submap updates

set -euo pipefail
umask 077

SELF="$(readlink -f "$0")"

die() {
  printf 'toggle_resize_if_ok: %s\n' "$*" >&2
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

  RUNTIME_STATE_DIR="${base}/awtarchy"
  [[ ! -L $RUNTIME_STATE_DIR ]] \
    || die 'Awtarchy runtime directory must not be a symbolic link'
  install -d -m 0700 -- "$RUNTIME_STATE_DIR" \
    || die 'could not create Awtarchy runtime directory'
  owner="$(stat -c %u -- "$RUNTIME_STATE_DIR" 2>/dev/null)" \
    || die 'could not inspect Awtarchy runtime directory owner'
  [[ $owner == "$(id -u)" ]] || die 'Awtarchy runtime directory has the wrong owner'
  chmod 0700 -- "$RUNTIME_STATE_DIR" \
    || die 'could not secure Awtarchy runtime directory'
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
  temporary="$(mktemp "${RUNTIME_STATE_DIR}/.pid.XXXXXX")" || return 1
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

write_state_file() {
  local workspace="$1" temporary

  temporary="$(mktemp "${RUNTIME_STATE_DIR}/.resize-state.XXXXXX")" || return 1
  printf '%s\n' "$workspace" >"$temporary"
  chmod 0600 -- "$temporary"
  mv -Tf -- "$temporary" "$STATE_FILE"
}

init_private_runtime
STATE_FILE="${RUNTIME_STATE_DIR}/hypr-resize.state"
WATCH_PID_FILE="${RUNTIME_STATE_DIR}/hypr-resize.wpid"

notify_waybar() {
  # Tell Waybar to refresh custom/submap ("signal": 12)
  pkill -RTMIN+12 waybar 2>/dev/null || true
}

reset_mode() {
  hyprctl dispatch submap reset >/dev/null 2>&1 || true

  if pid="$(read_pid_record "$WATCH_PID_FILE")"; then
    kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -f -- "$WATCH_PID_FILE"

  rm -f -- "$STATE_FILE"

  notify_waybar
}

# Explicit reset (used by your exit binds)
if [[ "${1:-}" == "reset" ]]; then
  reset_mode
  exit 0
fi

# If we believe we're already active, toggle OFF
if [[ -f "$STATE_FILE" ]]; then
  reset_mode
  exit 0
fi

# Require an active window
aw="$(hyprctl -j activewindow 2>/dev/null || echo null)"
[[ "$aw" == "null" || -z "$aw" ]] && exit 0

# Block if fullscreen (covers multiple Hyprland versions)
if printf '%s' "$aw" | jq -e '
  (.fullscreen == true)
  or ((.fullscreen? | numbers) > 0)
  or ((.fullscreenstate?.internal? // 0) > 0)
  or ((.fullscreenstate?.client?   // 0) > 0)
' >/dev/null; then
  exit 0
fi

# Workspace must have >1 window
ws_id="$(hyprctl -j activeworkspace | jq -r '.id')"
count="$(hyprctl -j clients | jq --argjson ws "$ws_id" '[.[] | select(.workspace.id == $ws)] | length')"
[[ "${count:-0}" -le 1 ]] && exit 0

# Enter resize submap
hyprctl dispatch submap resize >/dev/null 2>&1 || true

# Record current workspace
write_state_file "$ws_id" || {
  reset_mode
  die 'could not record resize state safely'
}

# Spawn watcher: exit resize if workspace changes
(
  start_ws="$ws_id"
  while :; do
    cur_ws="$(hyprctl -j activeworkspace | jq -r '.id' 2>/dev/null || echo "")"
    if [[ -n "$cur_ws" && "$cur_ws" != "$start_ws" ]]; then
      "$SELF" reset
      break
    fi
    sleep 0.2
  done
) &
watch_pid=$!
write_pid_record "$WATCH_PID_FILE" "$watch_pid" || {
  kill "$watch_pid" >/dev/null 2>&1 || true
  reset_mode
  die 'could not record resize watcher state safely'
}

notify_waybar
