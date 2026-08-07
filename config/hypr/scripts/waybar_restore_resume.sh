#!/usr/bin/env bash
# Hypridle resume compatibility: restore Quickshell bars only when timeout hid them.

set -euo pipefail
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
QS_SH="$CONF/hypr/scripts/quickshell.sh"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
IDLE_MARKER="${IDLE_MARKER:-$RUNTIME_DIR/waybar.idle_restore}"
TRANSITION_LOCK="${TRANSITION_LOCK:-$RUNTIME_DIR/waybar.idle_transition.lock}"
mkdir -p "$RUNTIME_DIR"

if command -v flock >/dev/null 2>&1; then
    exec 9>"$TRANSITION_LOCK"
    flock -x 9
fi

[[ "$(tr -d ' \t\r\n' <"$IDLE_MARKER" 2>/dev/null || true)" == "running" ]] || exit 0
[[ -x "$QS_SH" ]] || exit 0

"$QS_SH" start >/dev/null 2>&1 || exit 0
"$QS_SH" enable >/dev/null 2>&1 || exit 0
rm -f "$IDLE_MARKER"
