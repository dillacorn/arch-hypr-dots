#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/awtwall_launcher.sh

set -euo pipefail

notify_error() {
    local message="$1"

    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl notify 3 5000 "rgb(ff5555)" "$message" >/dev/null 2>&1 || true
    else
        printf 'awtwall: %s\n' "$message" >&2
    fi
}

if ! command -v awtwall >/dev/null 2>&1; then
    notify_error "awtwall is not installed."
    exit 127
fi

launch_handler="$HOME/.config/hypr/scripts/launch_handler.sh"
if [[ ! -x "$launch_handler" ]]; then
    notify_error "Awtarchy launch handler is missing."
    exit 127
fi

exec "$launch_handler" \
    wallpicker \
    "alacritty --class wallpicker -e awtwall --resume"
