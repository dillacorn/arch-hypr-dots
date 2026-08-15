#!/usr/bin/env bash
# Toggle the native Quickshell Quick Settings flyout.

set -euo pipefail

SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
exec qs -c awtarchy ipc call quicksettings toggle
