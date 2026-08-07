#!/usr/bin/env bash
# Compatibility helper for callers that still expect the old Waybar JSON format.

set -euo pipefail
QS_SH="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh"
"$QS_SH" start >/dev/null

case "${1:-status}" in
    toggle) qs -c awtarchy ipc call notifications toggleDnd >/dev/null ;;
    on|enable) qs -c awtarchy ipc call notifications enable >/dev/null ;;
    off|disable) qs -c awtarchy ipc call notifications disable >/dev/null ;;
esac

if [[ "$(qs -c awtarchy ipc call notifications dndEnabled 2>/dev/null || printf false)" == "true" ]]; then
    printf '{"text":"","class":"muted","tooltip":"Notifications disabled\\nLeft: enable notifications"}\n'
else
    printf '{"text":"","class":"normal","tooltip":"Notifications enabled\\nLeft: disable notifications"}\n'
fi
