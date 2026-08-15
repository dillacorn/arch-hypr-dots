#!/usr/bin/env bash
# Rotate the focused monitor's Quickshell bar between horizontal and vertical.
set -euo pipefail
exec "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh" rotate-focused
