#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/screenshot_display.sh

set -euo pipefail

# deps
for cmd in grim hyprctl jq notify-send wl-copy; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd missing" >&2; exit 1; }
done

out_dir="$HOME/Pictures/Screenshots"
file="$out_dir/$(date +%m%d%Y-%I%p-%S).png"

mkdir -p "$out_dir"

# get monitor name from cursor, fallback to focused
cursor_json="$(hyprctl -j cursors 2>/dev/null || true)"
if [[ -n "$cursor_json" ]] && echo "$cursor_json" | jq -e . >/dev/null 2>&1; then
    mon="$(echo "$cursor_json" | jq -r '.[0].monitor')"
fi

if [[ -z "${mon:-}" || "$mon" == "null" ]]; then
    monitor_json="$(hyprctl -j monitors 2>/dev/null || true)"
    if [[ -n "$monitor_json" ]] && echo "$monitor_json" | jq -e . >/dev/null 2>&1; then
        mon="$(echo "$monitor_json" | jq -r '.[] | select(.focused==true) | .name' | head -n1)"
    fi
fi

[[ -n "${mon:-}" ]] || { echo "No monitor found" >&2; exit 1; }

grim -o "$mon" "$file" >/dev/null 2>&1
wl-copy --type image/png < "$file"

notify-send --app-name 'awtarchy-screenshot' 'Screenshot saved & copied' "$file" || true
