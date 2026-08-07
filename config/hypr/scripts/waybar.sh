#!/usr/bin/env bash
# Compatibility entrypoint for Awtarchy's former Waybar manager.
# Bar lifecycle/state is now owned by Quickshell.

set -euo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts}"
QS_SH="${QS_SH:-$SCRIPTS_DIR/quickshell.sh}"
[[ -x "$QS_SH" ]] || { printf 'waybar.sh: missing Quickshell manager: %s\n' "$QS_SH" >&2; exit 1; }

case "${1:-}" in
    start)
        "$QS_SH" start
        "$QS_SH" enable
        ;;
    stop)
        # Legacy "stop Waybar" semantics now hide bars without killing the
        # launcher, notification daemon, clipboard UI, or power menu.
        "$QS_SH" disable
        ;;
    restart)
        "$QS_SH" restart
        "$QS_SH" enable
        ;;
    *) exec "$QS_SH" "$@" ;;
esac
