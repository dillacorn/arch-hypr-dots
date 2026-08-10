#!/usr/bin/env bash
# Launch Steam for the custom Awtarchy desktop entry.

set -euo pipefail

if ! command -v steam >/dev/null 2>&1; then
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl notify 3 5000 "rgb(ff5555)" "Steam is not installed." >/dev/null 2>&1 || true
    fi
    exit 1
fi

/usr/bin/steam --disable-gpu "$@" &

splitratio="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/splitratio_steam.sh"
if [[ -x "$splitratio" ]]; then
    ALLOW_WAIT=1 "$splitratio" >/dev/null 2>&1 &
fi
