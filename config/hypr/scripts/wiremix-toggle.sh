#!/usr/bin/env bash
# Toggle Wiremix inside Alacritty without killing unrelated tiled windows.

set -euo pipefail

WM_CLASS="Wiremix"

kill_list() {
  mapfile -t pids
  [ "${#pids[@]}" -gt 0 ] || return 0
  kill -TERM "${pids[@]}" 2>/dev/null || true
  kill -KILL "${pids[@]}" 2>/dev/null || true
}

launch_new() {
  alacritty \
    --class "$WM_CLASS" \
    --title "$WM_CLASS" \
    -o window.dynamic_title=false \
    -e wiremix -p auto -f 30 >/dev/null 2>&1 &
}

ws="$(hyprctl activeworkspace -j 2>/dev/null | jq -r 'try .id // 0')"
clients="$(hyprctl clients -j 2>/dev/null || printf '[]')"

here_float="$(printf '%s' "$clients" | jq -r --arg c "$WM_CLASS" --argjson ws "$ws" '
  .[]? | select(
    ((.class==$c) or (.initialClass==$c) or (.title==$c)) and
    ((.floating // false) == true) and
    ((.hidden // false) == false) and
    ((.workspace.id // -1) == $ws)
  ) | .pid
')"

elsewhere_float="$(printf '%s' "$clients" | jq -r --arg c "$WM_CLASS" --argjson ws "$ws" '
  .[]? | select(
    ((.class==$c) or (.initialClass==$c) or (.title==$c)) and
    ((.floating // false) == true) and
    (
      ((.workspace.id // -1) != $ws) or
      ((.hidden // false) == true)
    )
  ) | .pid
')"

if [ -n "$here_float" ]; then
  printf '%s\n' "$here_float" | kill_list
  exit 0
fi

if [ -n "$elsewhere_float" ]; then
  printf '%s\n' "$elsewhere_float" | kill_list
  launch_new
  exit 0
fi

launch_new
