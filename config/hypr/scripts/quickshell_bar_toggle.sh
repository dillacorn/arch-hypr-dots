#!/usr/bin/env bash
# Compatibility entrypoint: toggle the Quickshell bar on one monitor.
set -euo pipefail
QS_SH="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh"
case "${1:-}" in
    --mon)
        [[ -n "${2:-}" ]] || { printf 'usage: quickshell_bar_toggle.sh --mon <MON>\n' >&2; exit 2; }
        exec "$QS_SH" toggle-mon "$2"
        ;;
    ""|--focused|-f) exec "$QS_SH" toggle-focused ;;
    *) printf 'usage: quickshell_bar_toggle.sh [--focused] | --mon <MON>\n' >&2; exit 2 ;;
esac
