#!/usr/bin/env bash
# Toggle the Awtarchy Quickshell clipboard history UI.

set -euo pipefail
SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
exec qs -c awtarchy ipc call clipboard toggle
