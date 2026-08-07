#!/usr/bin/env bash
# Compatibility entrypoint: power/session menu is now rendered by Quickshell.

set -euo pipefail
SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
exec qs -c awtarchy ipc call powermenu toggle
