#!/usr/bin/env bash
# Hypridle resume compatibility: restore only the monitor bar that Hypridle hid.
# The Quickshell process remains running throughout the idle transition.

set -euo pipefail
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
QS_SH="$CONF/hypr/scripts/quickshell.sh"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
IDLE_MARKER="${IDLE_MARKER:-$RUNTIME_DIR/quickshell.idle_restore}"
TRANSITION_LOCK="${TRANSITION_LOCK:-$RUNTIME_DIR/quickshell.idle_transition.lock}"
mkdir -p "$RUNTIME_DIR"

if command -v flock >/dev/null 2>&1; then
    exec 9>"$TRANSITION_LOCK"
    flock -x 9
fi

[[ -x "$QS_SH" ]] || exit 0

monitor="$(tr -d '\r\n' <"$IDLE_MARKER" 2>/dev/null || true)"
[[ -n "$monitor" ]] || exit 0

"$QS_SH" setenabled "$monitor" true >/dev/null 2>&1 || exit 0
rm -f "$IDLE_MARKER"
