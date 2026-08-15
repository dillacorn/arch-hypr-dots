#!/usr/bin/env bash
set -euo pipefail

# Hyprsunset controller with:
# - toggle on/off (OFF = identity)
# - +/- step adjustments
# - persistent "last temperature" so toggle OFF -> ON restores the previous temp
# - mako notifications via notify-send

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprsunset"
OFFSET_FILE="$STATE_DIR/offset"       # offset from BASE_K (for compatibility + status)
TEMP_FILE="$STATE_DIR/last_temp"      # last absolute temperature (K)
ENABLED_FILE="$STATE_DIR/enabled"     # fallback when JSON/jq isn't available: 1=on, 0=off
mkdir -p "$STATE_DIR"

# Neutral daylight baseline.
BASE_K=6500

# Used only when there is no prior saved state.
DEFAULT_ON_OFFSET=-1500

# Fine enough to tune visually without making large jumps between clicks.
STEP=250

notify() {
  local msg="$1"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "hyprsunset" -t 1400 "Night Light" "$msg"
  fi
}

have_jq() { command -v jq >/dev/null 2>&1; }

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

# Best-effort: return "true" / "false" / "unknown"
get_identity_state() {
  if have_jq && hyprctl -j hyprsunset >/dev/null 2>&1; then
    # Some hyprctl -j outputs have a noisy prefix line; strip anything before the first '{'
    local json
    json="$(hyprctl -j hyprsunset 2>/dev/null | sed -n '0,/{/s/^[^{]*//;/{/,$p' || true)"
    if [[ -n "$json" ]]; then
      local v
      v="$(jq -r '(.identity // "unknown")' <<<"$json" 2>/dev/null || true)"
      [[ -n "$v" ]] && { printf '%s\n' "$v"; return 0; }
    fi
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

  # unknown -> use saved enabled state
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

usage() {
  cat <<'EOF'
Usage: hyprsunset_ctl.sh <cmd>

Commands:
  toggle         Toggle night light on/off (OFF = identity). Toggle ON restores last saved temperature.
  up             Increase temperature by STEP (colder). If OFF, starts from last saved temperature.
  down           Decrease temperature by STEP (warmer). If OFF, starts from last saved temperature.
  off            Force off (identity). Preserves last saved temperature for restore.
  on             Force on to DEFAULT_ON_OFFSET (overwrites saved temperature).
  status         Print last temp/offset + best-effort identity/enabled state

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
    t="$(get_last_temp)"
    off="$(( t - BASE_K ))"
    id="$(get_identity_state)"
    en="$(read_int_file "$ENABLED_FILE" 0)"
    printf 'temp=%sK\noffset=%s\nidentity=%s\nenabled=%s\n' "$t" "$off" "$id" "$en"
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
