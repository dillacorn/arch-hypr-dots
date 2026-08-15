#!/usr/bin/env bash
# Toggle the Awtarchy Quickshell application launcher.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"

"$SCRIPTS_DIR/quickshell_runtime_rules.sh" >/dev/null 2>&1 || true
"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
exec qs -c awtarchy ipc call launcher toggle
