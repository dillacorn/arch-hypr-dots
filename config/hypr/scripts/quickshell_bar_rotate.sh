#!/usr/bin/env bash
# Compatibility entrypoint: rotate the Quickshell bar between horizontal/vertical.
set -euo pipefail
exec "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh" rotate-focused
