#!/usr/bin/env bash
# Present every notification popup position without changing saved settings.

set -euo pipefail

DELAY="${AWTARCHY_NOTIFICATION_DEMO_DELAY:-1.6}"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell_notification_layout_demo.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

need qs
need notify-send

clear_preview() {
    qs -c awtarchy ipc call notifications clearPopupPreview >/dev/null 2>&1 || true
}

pause_between_positions() {
    if [[ "$DELAY" != 0 && "$DELAY" != 0.0 ]]; then
        sleep "$DELAY"
    fi
}

trap clear_preview EXIT INT TERM
clear_preview

positions=(
    top-left
    top-center
    top-right
    bottom-left
    bottom-center
    bottom-right
)

for position in "${positions[@]}"; do
    qs -c awtarchy ipc call notifications setPopupPreview "$position" >/dev/null
    notify-send \
        --app-name='Awtarchy Layout Demo' \
        --urgency=normal \
        --expire-time=1300 \
        "Awtarchy notification layout · ${position}" \
        "Preview ${position}; this does not change the saved per-display setting."
    pause_between_positions
done

qs -c awtarchy ipc call notifications setPopupPreview automatic >/dev/null
notify-send \
    --app-name='Awtarchy Layout Demo' \
    --urgency=normal \
    --expire-time=1800 \
    'Awtarchy notification layout · automatic' \
    'Automatic follows this display’s bar notification icon.'
pause_between_positions
clear_preview

printf '%s\n' 'Notification position presentation complete; saved settings were not changed.'
