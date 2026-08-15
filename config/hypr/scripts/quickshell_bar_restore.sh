#!/usr/bin/env bash
# Hypridle resume: clear the temporary global bar-hide state. Saved per-monitor
# visibility remains untouched, so only bars the user enabled are restored.

set -euo pipefail
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
IDLE_STATE="${IDLE_STATE:-$RUNTIME_DIR/awtarchy-quickshell-idle-hidden}"
TRANSITION_LOCK="${TRANSITION_LOCK:-$RUNTIME_DIR/quickshell.idle_transition.lock}"
mkdir -p "$RUNTIME_DIR"

if command -v flock >/dev/null 2>&1; then
    exec 9>"$TRANSITION_LOCK"
    flock -x 9
fi

printf '0\n' >"$IDLE_STATE"

if command -v qs >/dev/null 2>&1; then
    qs -c awtarchy ipc call barstate setIdleHidden false 9>&- >/dev/null 2>&1 ||
        qs -c awtarchy ipc call barstate refreshIdle 9>&- >/dev/null 2>&1 ||
        true
fi
