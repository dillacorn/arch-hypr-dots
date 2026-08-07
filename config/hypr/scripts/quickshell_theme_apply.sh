#!/usr/bin/env bash
# Apply an existing Awtarchy theme selected by the Quickshell theme picker.

set -euo pipefail

name="${1:-}"
[[ -n "$name" && "$name" != */* && "$name" != .* ]] || exit 2

THEME_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes"
THEME="$THEME_DIR/$name"
[[ -f "$THEME" && -x "$THEME" ]] || exit 1

"$THEME"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
mkdir -p "$STATE_DIR"
printf '%s\n' "$name" >"$STATE_DIR/active-theme"
