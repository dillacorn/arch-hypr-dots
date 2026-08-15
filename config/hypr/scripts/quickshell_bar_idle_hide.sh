#!/usr/bin/env bash
# Hypridle timeout: temporarily hide every Quickshell bar without changing any
# saved per-monitor visibility setting.

set -euo pipefail
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
INHIBITOR_SH="$CONF/hypr/scripts/idle_inhibitor_global.sh"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
IDLE_STATE="${IDLE_STATE:-$RUNTIME_DIR/awtarchy-quickshell-idle-hidden}"
TRANSITION_LOCK="${TRANSITION_LOCK:-$RUNTIME_DIR/quickshell.idle_transition.lock}"
mkdir -p "$RUNTIME_DIR"

if command -v flock >/dev/null 2>&1; then
    exec 9>"$TRANSITION_LOCK"
    flock -x 9
fi

if [[ -x "$INHIBITOR_SH" ]] && "$INHIBITOR_SH" is-active >/dev/null 2>&1; then
    exit 0
fi

printf '1\n' >"$IDLE_STATE"

if command -v qs >/dev/null 2>&1; then
    qs -c awtarchy ipc call barstate setIdleHidden true >/dev/null 2>&1 ||
        qs -c awtarchy ipc call barstate refreshIdle >/dev/null 2>&1 ||
        true
fi
