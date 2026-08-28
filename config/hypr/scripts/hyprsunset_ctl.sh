#!/usr/bin/env bash
set -euo pipefail

# Hyprsunset controller with:
# - toggle on/off (OFF = identity)
# - +/- step adjustments
# - persistent "last temperature" so toggle OFF -> ON restores the previous temp
# - daily enable/disable scheduling using native hyprsunset profiles
# - mako notifications via notify-send

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprsunset"
OFFSET_FILE="$STATE_DIR/offset"       # offset from BASE_K (for compatibility + status)
TEMP_FILE="$STATE_DIR/last_temp"      # last absolute temperature (K)
ENABLED_FILE="$STATE_DIR/enabled"     # fallback when live Hyprsunset state is unavailable: 1=on, 0=off
SCHEDULE_FILE="$STATE_DIR/schedule"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
CONFIG_FILE="$CONFIG_DIR/hyprsunset.conf"
CONFIG_MARKER='# Managed by Awtarchy Night Light schedule.'
mkdir -p "$STATE_DIR"

# Neutral daylight baseline.
BASE_K=6500

# Used only when there is no prior saved state.
DEFAULT_ON_OFFSET=-1500

# Fine enough to tune visually without making large jumps between clicks.
STEP=250

# Samsung-style schedule defaults. These are only used before the user saves a
# schedule; disabling a configured schedule preserves the selected values.
DEFAULT_SCHEDULE_START="20:00"
DEFAULT_SCHEDULE_END="07:00"

notify() {
  local msg="$1"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "hyprsunset" -t 1400 "Night Light" "$msg" >/dev/null 2>&1 || true
  fi
}

read_int_file() {
  local file="$1" def="$2" v=""
  if [[ -f "$file" ]]; then
    v="$(<"$file")"
    if [[ "$v" =~ ^-?[0-9]+$ ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi
  printf '%s\n' "$def"
}

write_int_file() {
  local file="$1" v="$2"
  printf '%s\n' "$v" >"$file"
}

clamp_temp() {
  local t="$1"
  if (( t < 1000 )); then t=1000; fi
  if (( t > 20000 )); then t=20000; fi
  printf '%s\n' "$t"
}

valid_temp() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  (( 10#$1 >= 1000 && 10#$1 <= 20000 ))
}

valid_time() {
  local value="$1" hour minute
  [[ "$value" =~ ^([0-9]{2}):([0-9]{2})$ ]] || return 1
  hour="${BASH_REMATCH[1]}"
  minute="${BASH_REMATCH[2]}"
  (( 10#$hour <= 23 && 10#$minute <= 59 ))
}

time_minutes() {
  local value="$1" hour minute
  valid_time "$value" || return 1
  IFS=: read -r hour minute <<<"$value"
  printf '%s\n' "$((10#$hour * 60 + 10#$minute))"
}

schedule_is_next_day() {
  local start="$1" end="$2" start_minutes end_minutes
  start_minutes="$(time_minutes "$start")" || return 1
  end_minutes="$(time_minutes "$end")" || return 1
  (( end_minutes < start_minutes ))
}

schedule_active_now() {
  local start="$1" end="$2" now start_minutes end_minutes now_minutes
  start_minutes="$(time_minutes "$start")" || return 1
  end_minutes="$(time_minutes "$end")" || return 1
  now="$(date +%H:%M)"
  now_minutes="$(time_minutes "$now")" || return 1

  if (( start_minutes < end_minutes )); then
    (( now_minutes >= start_minutes && now_minutes < end_minutes ))
  else
    (( now_minutes >= start_minutes || now_minutes < end_minutes ))
  fi
}

schedule_value() {
  local key="$1" default="$2" line=""
  [[ -f "$SCHEDULE_FILE" && ! -L "$SCHEDULE_FILE" ]] || {
    printf '%s\n' "$default"
    return 0
  }
  line="$(grep -E "^${key}=" "$SCHEDULE_FILE" 2>/dev/null | tail -n1 || true)"
  [[ -n "$line" ]] && printf '%s\n' "${line#*=}" || printf '%s\n' "$default"
}

load_schedule() {
  SCHEDULE_ENABLED="$(schedule_value enabled 0)"
  SCHEDULE_START="$(schedule_value start "$DEFAULT_SCHEDULE_START")"
  SCHEDULE_END="$(schedule_value end "$DEFAULT_SCHEDULE_END")"
  SCHEDULE_TEMP="$(schedule_value temperature "$(get_last_temp)")"

  [[ "$SCHEDULE_ENABLED" =~ ^[01]$ ]] || SCHEDULE_ENABLED=0
  valid_time "$SCHEDULE_START" || SCHEDULE_START="$DEFAULT_SCHEDULE_START"
  valid_time "$SCHEDULE_END" || SCHEDULE_END="$DEFAULT_SCHEDULE_END"
  if ! valid_temp "$SCHEDULE_TEMP"; then
    SCHEDULE_TEMP="$(get_last_temp)"
  fi
  if [[ "$SCHEDULE_START" == "$SCHEDULE_END" ]]; then
    SCHEDULE_ENABLED=0
  fi
}

save_schedule_state() {
  local enabled="$1" start="$2" end="$3" temperature="$4" tmp
  tmp="${SCHEDULE_FILE}.tmp.$$"
  (
    umask 077
    printf 'enabled=%s\nstart=%s\nend=%s\ntemperature=%s\n' \
      "$enabled" "$start" "$end" "$temperature" >"$tmp"
  ) || {
    rm -f -- "$tmp"
    return 1
  }
  chmod 0600 -- "$tmp"
  mv -f -- "$tmp" "$SCHEDULE_FILE"
}

config_owned_by_awtarchy() {
  [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] \
    && grep -Fxq -- "$CONFIG_MARKER" "$CONFIG_FILE" 2>/dev/null
}

schedule_config_writable() {
  if [[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]]; then
    return 0
  fi
  if config_owned_by_awtarchy; then
    return 0
  fi
  printf 'Night Light schedule: refusing to overwrite existing user-managed %s\n' \
    "$CONFIG_FILE" >&2
  return 3
}

write_schedule_config() {
  local start="$1" end="$2" temperature="$3" tmp
  schedule_config_writable || return $?
  mkdir -p -- "$CONFIG_DIR"
  tmp="${CONFIG_FILE}.tmp.$$"

  {
    printf '%s\n' "$CONFIG_MARKER"
    printf '%s\n' '# Edit this schedule through Awtarchy Quick Settings or hyprsunset_ctl.sh.'
    printf '\n'
    if [[ "$start" < "$end" ]]; then
      printf 'profile {\n    time = %s\n    temperature = %s\n}\n\n' "$start" "$temperature"
      printf 'profile {\n    time = %s\n    identity = true\n}\n' "$end"
    else
      printf 'profile {\n    time = %s\n    identity = true\n}\n\n' "$end"
      printf 'profile {\n    time = %s\n    temperature = %s\n}\n' "$start" "$temperature"
    fi
  } >"$tmp" || {
    rm -f -- "$tmp"
    return 1
  }
  chmod 0644 -- "$tmp"
  mv -f -- "$tmp" "$CONFIG_FILE"
}

remove_schedule_config() {
  if [[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]]; then
    return 0
  fi
  config_owned_by_awtarchy || return 0
  rm -f -- "$CONFIG_FILE"
}

restart_hyprsunset() {
  local uid
  command -v hyprsunset >/dev/null 2>&1 || return 0
  command -v pkill >/dev/null 2>&1 || {
    printf 'Night Light schedule: pkill is required to reload hyprsunset profiles.\n' >&2
    return 1
  }
  command -v pgrep >/dev/null 2>&1 || {
    printf 'Night Light schedule: pgrep is required to reload hyprsunset profiles.\n' >&2
    return 1
  }

  uid="$(id -u)"
  pkill -TERM -u "$uid" -x hyprsunset >/dev/null 2>&1 || true
  for _ in {1..40}; do
    if ! pgrep -u "$uid" -x hyprsunset >/dev/null 2>&1; then
      break
    fi
    sleep 0.05
  done
  if pgrep -u "$uid" -x hyprsunset >/dev/null 2>&1; then
    printf 'Night Light schedule: existing hyprsunset process did not stop.\n' >&2
    return 1
  fi

  nohup hyprsunset >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

set_schedule() {
  local start="$1" end="$2" temperature="$3"
  valid_time "$start" || {
    printf 'Night Light schedule: invalid start time %s; use HH:MM (00:00-23:59).\n' "$start" >&2
    return 2
  }
  valid_time "$end" || {
    printf 'Night Light schedule: invalid end time %s; use HH:MM (00:00-23:59).\n' "$end" >&2
    return 2
  }
  [[ "$start" != "$end" ]] || {
    printf 'Night Light schedule: start and end times must be different.\n' >&2
    return 2
  }
  valid_temp "$temperature" || {
    printf 'Night Light schedule: temperature must be between 1000K and 20000K.\n' >&2
    return 2
  }

  write_schedule_config "$start" "$end" "$temperature" || return $?
  save_schedule_state 1 "$start" "$end" "$temperature" || return 1
  restart_hyprsunset || return 1
  notify "Schedule: ${start} → ${end}, ${temperature}K"
}

disable_schedule() {
  load_schedule
  save_schedule_state 0 "$SCHEDULE_START" "$SCHEDULE_END" "$SCHEDULE_TEMP" || return 1
  remove_schedule_config || return 1
  restart_hyprsunset || return 1
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl hyprsunset identity >/dev/null 2>&1 || true
  fi
  notify "Schedule off"
}

enable_saved_schedule() {
  load_schedule
  set_schedule "$SCHEDULE_START" "$SCHEDULE_END" "$SCHEDULE_TEMP"
}

# Best-effort: return "true" / "false" / "unknown" from Hyprsunset IPC.
get_identity_state() {
  local value=""
  if command -v hyprctl >/dev/null 2>&1; then
    value="$(hyprctl hyprsunset identity get 2>/dev/null | tr -d '\r\n' || true)"
    case "$value" in
      true|false)
        printf '%s\n' "$value"
        return 0
        ;;
    esac
  fi
  printf '%s\n' "unknown"
}

# Fallback when identity is unknown
is_enabled_fallback() {
  local e
  e="$(read_int_file "$ENABLED_FILE" 0)"
  [[ "$e" == "1" ]]
}

is_off_best_effort() {
  local id
  id="$(get_identity_state)"
  if [[ "$id" == "true" ]]; then
    return 0
  elif [[ "$id" == "false" ]]; then
    return 1
  fi

  load_schedule
  if [[ "$SCHEDULE_ENABLED" == 1 ]] && config_owned_by_awtarchy; then
    schedule_active_now "$SCHEDULE_START" "$SCHEDULE_END" && return 1
    return 0
  fi

  # unknown -> use saved manual enabled state
  if is_enabled_fallback; then
    return 1
  fi
  return 0
}

get_last_temp() {
  local t
  t="$(read_int_file "$TEMP_FILE" 0)"
  if (( t >= 1000 && t <= 20000 )); then
    clamp_temp "$t"
    return 0
  fi

  # Back-compat: derive temp from offset if temp file doesn't exist yet
  local off
  off="$(read_int_file "$OFFSET_FILE" "$DEFAULT_ON_OFFSET")"
  t=$(( BASE_K + off ))
  clamp_temp "$t"
}

apply_temp() {
  local target
  target="$(clamp_temp "$1")"

  hyprctl hyprsunset temperature "$target" >/dev/null

  # Persist state for restore
  write_int_file "$TEMP_FILE" "$target"
  write_int_file "$OFFSET_FILE" "$(( target - BASE_K ))"
  write_int_file "$ENABLED_FILE" 1

  notify "Temp: ${target}K (offset $(( target - BASE_K )))"
}

apply_offset() {
  local offset="$1"
  apply_temp "$(( BASE_K + offset ))"
}

set_off() {
  hyprctl hyprsunset identity >/dev/null
  write_int_file "$ENABLED_FILE" 0
  notify "Off (identity)"
}

set_on_restore() {
  local t
  t="$(get_last_temp)"
  apply_temp "$t"
}

set_on_default() {
  apply_offset "$DEFAULT_ON_OFFSET"
}

print_status() {
  local t off id en schedule_next_day=0
  t="$(get_last_temp)"
  off="$(( t - BASE_K ))"
  id="$(get_identity_state)"
  en="$(read_int_file "$ENABLED_FILE" 0)"
  load_schedule

  if [[ "$SCHEDULE_ENABLED" == 1 ]] && ! config_owned_by_awtarchy; then
    SCHEDULE_ENABLED=0
  fi
  if schedule_is_next_day "$SCHEDULE_START" "$SCHEDULE_END"; then
    schedule_next_day=1
  fi

  printf 'temp=%sK\noffset=%s\nidentity=%s\nenabled=%s\n' "$t" "$off" "$id" "$en"
  printf 'schedule_enabled=%s\nschedule_start=%s\nschedule_end=%s\n' \
    "$SCHEDULE_ENABLED" "$SCHEDULE_START" "$SCHEDULE_END"
  printf 'schedule_temperature=%s\nschedule_next_day=%s\n' \
    "$SCHEDULE_TEMP" "$schedule_next_day"
}

usage() {
  cat <<'EOF'
Usage: hyprsunset_ctl.sh <cmd>

Commands:
  toggle                         Toggle night light on/off. Manual overrides last until the next schedule boundary.
  up                             Increase temperature by STEP (colder). If OFF, starts from last saved temperature.
  down                           Decrease temperature by STEP (warmer). If OFF, starts from last saved temperature.
  off                            Force off (identity). Preserves last saved temperature for restore.
  on                             Force on to DEFAULT_ON_OFFSET (overwrites saved temperature).
  status                         Print current Night Light and schedule state.
  schedule set HH:MM HH:MM TEMP  Enable a daily schedule with start, end, and temperature.
  schedule enable                Re-enable the last saved schedule.
  schedule disable               Disable scheduling while preserving its saved values.

Edit in script:
  BASE_K, DEFAULT_ON_OFFSET, STEP
EOF
}

cmd="${1:-}"
case "$cmd" in
  toggle)
    if is_off_best_effort; then
      set_on_restore
    else
      set_off
    fi
    ;;

  up)
    t="$(get_last_temp)"
    t=$(( t + STEP ))
    apply_temp "$t"
    ;;

  down)
    t="$(get_last_temp)"
    t=$(( t - STEP ))
    apply_temp "$t"
    ;;

  off)
    set_off
    ;;

  on)
    set_on_default
    ;;

  status)
    print_status
    ;;

  schedule)
    subcmd="${2:-}"
    case "$subcmd" in
      set)
        [[ $# -eq 5 ]] || {
          printf 'Usage: hyprsunset_ctl.sh schedule set HH:MM HH:MM TEMP\n' >&2
          exit 2
        }
        set_schedule "$3" "$4" "$5"
        ;;
      enable)
        [[ $# -eq 2 ]] || exit 2
        enable_saved_schedule
        ;;
      disable)
        [[ $# -eq 2 ]] || exit 2
        disable_schedule
        ;;
      *)
        printf 'Unknown schedule command: %s\n' "$subcmd" >&2
        usage >&2
        exit 2
        ;;
    esac
    ;;

  ""|-h|--help|help)
    usage
    ;;

  *)
    echo "Unknown cmd: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
