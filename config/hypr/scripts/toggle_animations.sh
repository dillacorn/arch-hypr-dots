#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/toggle_animations.sh

set -euo pipefail

HYPRCTL="$(command -v hyprctl || true)"
NOTIFY_SEND="$(command -v notify-send || true)"

STATE_FILE="${STATE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/hypr-animations-enabled}"

if [[ -z "$HYPRCTL" ]]; then
  echo "hyprctl not found in PATH" >&2
  exit 1
fi

normalize_state() {
  case "${1:-}" in
    1|true|yes|on) echo "1" ;;
    0|false|no|off) echo "0" ;;
    *) echo "" ;;
  esac
}

read_live_state_json() {
  "$HYPRCTL" getoption "animations.enabled" -j 2>/dev/null \
    | sed -nE 's/.*"(int|bool)"[[:space:]]*:[[:space:]]*"?([0-9]+|true|false)"?.*/\2/p' \
    | head -n1
}

read_live_state_fallback() {
  "$HYPRCTL" getoption "animations.enabled" 2>/dev/null \
    | awk '
        /int:/ {
          for (i=1; i<=NF; i++) {
            if ($i ~ /^[0-9]+$/) {
              print $i
              exit
            }
          }
        }

        /bool:/ {
          for (i=1; i<=NF; i++) {
            if ($i == "true") {
              print 1
              exit
            }
            if ($i == "false") {
              print 0
              exit
            }
          }
        }
      '
}

read_state() {
  local state=""

  state="$(normalize_state "$(read_live_state_json || true)")"
  if [[ -n "$state" ]]; then
    echo "$state"
    return 0
  fi

  state="$(normalize_state "$(read_live_state_fallback || true)")"
  if [[ -n "$state" ]]; then
    echo "$state"
    return 0
  fi

  if [[ -f "$STATE_FILE" ]]; then
    state="$(normalize_state "$(cat "$STATE_FILE" 2>/dev/null || true)")"
    if [[ -n "$state" ]]; then
      echo "$state"
      return 0
    fi
  fi

  echo "1"
}

apply_hyprland_animation_state() {
  local target="$1"
  local lua_bool

  if [[ "$target" == "1" ]]; then
    lua_bool="true"
  else
    lua_bool="false"
  fi

  "$HYPRCTL" eval "hl.config({ animations = { enabled = ${lua_bool} } })"
}

state="$(read_state)"

if [[ "$state" == "1" ]]; then
  target="0"
  msg="OFF"
else
  target="1"
  msg="ON"
fi

apply_hyprland_animation_state "$target"
printf '%s\n' "$target" > "$STATE_FILE"


if [[ -n "$NOTIFY_SEND" ]]; then
  "$NOTIFY_SEND" -a "Hyprland" \
    -r 49110 \
    -t 1000 \
    "Animations: $msg" \
    "animations.enabled = $target"
fi
