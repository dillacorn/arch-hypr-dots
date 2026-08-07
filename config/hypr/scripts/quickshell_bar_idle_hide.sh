#!/usr/bin/env bash
# Hypridle timeout compatibility: hide Quickshell bars while leaving shell
# services (notifications/launcher/etc.) alive.

set -euo pipefail
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
QS_SH="$CONF/hypr/scripts/quickshell.sh"
INHIBITOR_SH="$CONF/hypr/scripts/idle_inhibitor_global.sh"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
IDLE_MARKER="${IDLE_MARKER:-$RUNTIME_DIR/quickshell.idle_restore}"
TRANSITION_LOCK="${TRANSITION_LOCK:-$RUNTIME_DIR/quickshell.idle_transition.lock}"
mkdir -p "$RUNTIME_DIR"

if command -v flock >/dev/null 2>&1; then
    exec 9>"$TRANSITION_LOCK"
    flock -x 9
fi

[[ -x "$QS_SH" ]] || exit 0
if [[ -x "$INHIBITOR_SH" ]] && "$INHIBITOR_SH" is-active >/dev/null 2>&1; then
    exit 0
fi

# Preserve an intentionally disabled bar state.
if ! "$QS_SH" dump-state 2>/dev/null | jq -e '.enabled == true' >/dev/null 2>&1; then
    exit 0
fi

marker_tmp="${IDLE_MARKER}.tmp.$$"
printf 'running\n' >"$marker_tmp"
mv -f "$marker_tmp" "$IDLE_MARKER"
"$QS_SH" disable >/dev/null 2>&1 || true
