#!/usr/bin/env bash
# Hypridle timeout compatibility: hide only the focused monitor's Quickshell
# bar while leaving the Quickshell process and all other shell services alive.

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

monitor="$($QS_SH focused-monitor 2>/dev/null || true)"
[[ -n "$monitor" ]] || exit 0

# Preserve a bar the user already disabled manually. Only create a restore
# marker when Hypridle is the thing that actually hides this monitor's bar.
if [[ "$($QS_SH getenabled "$monitor" 2>/dev/null || true)" != "true" ]]; then
    exit 0
fi

marker_tmp="${IDLE_MARKER}.tmp.$$"
printf '%s\n' "$monitor" >"$marker_tmp"
mv -f "$marker_tmp" "$IDLE_MARKER"

"$QS_SH" setenabled "$monitor" false >/dev/null 2>&1 || true
