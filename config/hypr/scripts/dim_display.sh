#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/dim_display.sh

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
uid="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"

INHIBITOR_SH="${INHIBITOR_SH:-${CONF}/hypr/scripts/idle_inhibitor_global.sh}"
BRIGHTNESS_SCRIPT="${HYPR_BRIGHTNESS_SCRIPT:-${CONF}/hypr/scripts/hypr-ddc-brightness.sh}"
LOG_FILE="${HYPRIDLE_ACTION_LOG:-${CACHE}/hypridle/actions.log}"
BR_FILE="${RUNTIME_DIR}/hypridle-brightness-level"
DIM_MARKER="${RUNTIME_DIR}/hypridle-ddc-dimmed"

# Optional: pin a display. The brightness controller inherits this value.
: "${DDCUTIL_BUS:=}"
export DDCUTIL_BUS

mkdir -p "$RUNTIME_DIR" "$(dirname "$LOG_FILE")"

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

if [[ -x "$INHIBITOR_SH" ]] && "$INHIBITOR_SH" is-active >/dev/null 2>&1; then
    rm -f "$DIM_MARKER"
    log "blocked brightness dim: idle inhibitor active"
    exit 0
fi

rm -f "$DIM_MARKER"

if [[ ! -x "$BRIGHTNESS_SCRIPT" ]]; then
    log "brightness dim failed: controller unavailable"
    exit 1
fi

# One status read records the current value and primes the controller cache.
status_output="$(
    HYPR_DDC_NOTIFY=0 "$BRIGHTNESS_SCRIPT" status 2>/dev/null || true
)"
saved_brightness="$(
    awk -F= '$1 == "cur" { print $2; exit }' <<<"$status_output"
)"

# Do not replace a valid saved value with empty or malformed output.
if [[ "$saved_brightness" =~ ^[0-9]+$ ]] &&
   (( saved_brightness >= 0 && saved_brightness <= 100 )); then
    printf '%s\n' "$saved_brightness" >"$BR_FILE"
fi

# The controller writes through the selected backlight or DDC backend.
if HYPR_DDC_NOTIFY=0 "$BRIGHTNESS_SCRIPT" set 20 >/dev/null 2>&1; then
    printf 'dimmed\n' >"$DIM_MARKER"
    log "brightness dim applied: 20"
    exit 0
fi

rm -f "$DIM_MARKER"
log "brightness dim failed"
exit 1
