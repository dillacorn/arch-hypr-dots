#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/dim_display.sh

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
uid="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"

INHIBITOR_SH="${INHIBITOR_SH:-${CONF}/waybar/scripts/idle_inhibitor_global.sh}"
BRIGHTNESS_SCRIPT="${HYPR_BRIGHTNESS_SCRIPT:-${CONF}/hypr/scripts/hypr-ddc-brightness.sh}"
LOG_FILE="${HYPRIDLE_ACTION_LOG:-${CACHE}/hypridle/actions.log}"
BR_FILE="${RUNTIME_DIR}/hypridle-brightness-level"
DIM_MARKER="${RUNTIME_DIR}/hypridle-ddc-dimmed"

# Optional: pin a display. Use exactly one token, e.g. "--bus=5"
: "${DDCUTIL_BUS:=}"
DDCUTIL_ARGS=()
[[ -n "$DDCUTIL_BUS" ]] && DDCUTIL_ARGS+=("$DDCUTIL_BUS")

mkdir -p "$RUNTIME_DIR" "$(dirname "$LOG_FILE")"

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

sync_brightness_state() {
    [[ -x "$BRIGHTNESS_SCRIPT" ]] || return 0
    HYPR_DDC_NOTIFY=0 "$BRIGHTNESS_SCRIPT" status >/dev/null 2>&1 || true
}

if [[ -x "$INHIBITOR_SH" ]] && "$INHIBITOR_SH" is-active >/dev/null 2>&1; then
    rm -f "$DIM_MARKER"
    log "blocked DDC dim: idle inhibitor active"
    exit 0
fi

rm -f "$DIM_MARKER"

# Save current brightness. Do not replace a valid saved value with empty output.
saved_brightness="$(
    timeout 2 ddcutil "${DDCUTIL_ARGS[@]}" getvcp 0x10 2>/dev/null |
        awk -F'current value = ' 'NF > 1 { print $2 }' |
        awk -F',' '{ print $1 }' |
        tr -dc '0-9' ||
        true
)"

if [[ "$saved_brightness" =~ ^[0-9]+$ ]] &&
   (( saved_brightness >= 0 && saved_brightness <= 100 )); then
    printf '%s\n' "$saved_brightness" >"$BR_FILE"
fi

if timeout 3 ddcutil "${DDCUTIL_ARGS[@]}" setvcp 0x10 20 >/dev/null 2>&1; then
    printf 'dimmed\n' >"$DIM_MARKER"
    sync_brightness_state
    log "DDC dim applied: brightness 20"
    exit 0
fi

sleep 0.35

if timeout 3 ddcutil "${DDCUTIL_ARGS[@]}" setvcp 0x10 20 >/dev/null 2>&1; then
    printf 'dimmed\n' >"$DIM_MARKER"
    sync_brightness_state
    log "DDC dim applied after retry: brightness 20"
else
    rm -f "$DIM_MARKER"
    log "DDC dim failed"
fi
