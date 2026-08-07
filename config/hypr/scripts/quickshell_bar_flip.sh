#!/usr/bin/env bash
# Flip the Quickshell bar side on the focused monitor.
set -euo pipefail
exec "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh" flip-focused
