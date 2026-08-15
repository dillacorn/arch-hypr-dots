#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/restore_brightness.sh

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
uid="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"

BRIGHTNESS_SCRIPT="${HYPR_BRIGHTNESS_SCRIPT:-${CONF}/hypr/scripts/hypr-ddc-brightness.sh}"
LOG_FILE="${HYPRIDLE_ACTION_LOG:-${CACHE}/hypridle/actions.log}"
BR_FILE="${RUNTIME_DIR}/hypridle-brightness-level"
DIM_MARKER="${RUNTIME_DIR}/hypridle-ddc-dimmed"
DEFAULT_BRIGHTNESS="70"

# Optional: pin a display. The brightness controller inherits this value.
: "${DDCUTIL_BUS:=}"
export DDCUTIL_BUS

mkdir -p "$RUNTIME_DIR" "$(dirname "$LOG_FILE")"

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

# Do nothing unless this idle cycle actually dimmed the monitor.
if [[ ! -f "$DIM_MARKER" ]]; then
    log "brightness restore skipped: no dim marker"
    exit 0
fi

hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1 || true
sleep 0.6

if [[ -r "$BR_FILE" ]]; then
    BRIGHTNESS="$(tr -dc '0-9' <"$BR_FILE")"
else
    BRIGHTNESS=""
fi

if [[ ! "$BRIGHTNESS" =~ ^[0-9]+$ ]] ||
   (( BRIGHTNESS < 0 || BRIGHTNESS > 100 )); then
    BRIGHTNESS="$DEFAULT_BRIGHTNESS"
fi

if [[ ! -x "$BRIGHTNESS_SCRIPT" ]]; then
    log "brightness restore failed: controller unavailable"
    exit 1
fi

# The controller writes through the selected backlight or DDC backend.
if HYPR_DDC_NOTIFY=0 "$BRIGHTNESS_SCRIPT" set "$BRIGHTNESS" >/dev/null 2>&1; then
    rm -f "$DIM_MARKER"
    log "brightness restored: ${BRIGHTNESS}"
    exit 0
fi

log "brightness restore failed; marker retained"
exit 1
