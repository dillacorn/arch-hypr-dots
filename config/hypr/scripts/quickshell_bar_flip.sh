#!/usr/bin/env bash
# Compatibility entrypoint: flip the Quickshell bar on the focused monitor.
set -euo pipefail
exec "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh" flip-focused
