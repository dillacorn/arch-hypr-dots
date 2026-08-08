#!/usr/bin/env bash
# Awtarchy mouse-submap toggle used by the Quickshell bar.

set -euo pipefail

SUBMAP_FILE="/tmp/hypr-submap"
RUNTIME_RULES_SCRIPT="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell_runtime_rules.sh"

lua_eval() {
  hyprctl eval "$1" >/dev/null 2>&1 || true
}

enter_mouse() {
  lua_eval 'hl.unbind("ALT + mouse:272"); hl.unbind("ALT + mouse:273"); hl.unbind("mouse:272"); hl.unbind("mouse:273"); hl.unbind("mouse:274"); hl.bind("mouse:272", hl.dsp.window.drag(), { mouse = true }); hl.bind("mouse:273", hl.dsp.window.resize(), { mouse = true }); hl.bind("mouse:274", hl.dsp.window.float({ action = "toggle" }), {})'

  printf '%s\n' mouse > "$SUBMAP_FILE"
  notify-send -a Hyprland -t 1000 "mouse mode: ON" >/dev/null 2>&1 || true
  hyprctl dispatch 'hl.dsp.submap("mouse")' >/dev/null 2>&1 || true
}

reset_mouse() {
  hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || true

  lua_eval 'hl.unbind("mouse:272"); hl.unbind("mouse:273"); hl.unbind("mouse:274"); hl.unbind("ALT + mouse:272"); hl.unbind("ALT + mouse:273"); hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true }); hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })'
  if [[ -x "$RUNTIME_RULES_SCRIPT" ]]; then
    "$RUNTIME_RULES_SCRIPT" >/dev/null 2>&1 || true
  fi

  truncate -s 0 "$SUBMAP_FILE" 2>/dev/null || true
  notify-send -a Hyprland -t 1000 "mouse mode: OFF" >/dev/null 2>&1 || true
}

current_submap="$(hyprctl submap 2>/dev/null | tr -d '\r\n[:space:]' || true)"
current_file=""
[[ -s "$SUBMAP_FILE" ]] && current_file="$(tr -d '\r\n[:space:]' < "$SUBMAP_FILE" 2>/dev/null || true)"

case "${1:-toggle}" in
  on)
    enter_mouse
    ;;
  off|reset)
    reset_mouse
    ;;
  toggle)
    if [[ "$current_submap" == "mouse" || "$current_file" == "mouse" ]]; then
      reset_mouse
    else
      enter_mouse
    fi
    ;;
  *)
    echo "usage: $0 [toggle|on|off|reset]" >&2
    exit 2
    ;;
esac
