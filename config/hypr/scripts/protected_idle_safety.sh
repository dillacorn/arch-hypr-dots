#!/usr/bin/env bash
# Four-hour display safety for sessions whose normal idle actions are protected.
# Detection remains authoritative in hypridle_action.sh; this helper only
# coordinates the long-idle lock + DPMS action.

set -Eeuo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
SCRIPTS_DIR="${CONF}/hypr/scripts"

INHIBITOR_SH="${INHIBITOR_SH:-${SCRIPTS_DIR}/idle_inhibitor_global.sh}"
HYPRIDLE_ACTION_SCRIPT="${HYPRIDLE_ACTION_SCRIPT:-${SCRIPTS_DIR}/hypridle_action.sh}"
HYPRCTL_BIN="${HYPRCTL_BIN:-hyprctl}"
LOGINCTL_BIN="${LOGINCTL_BIN:-loginctl}"
LOG_FILE="${HYPRIDLE_ACTION_LOG:-${CACHE}/hypridle/actions.log}"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    printf '%s %s\n' \
        "$(date '+%F %T')" \
        "$*" \
        >>"$LOG_FILE" 2>/dev/null || true
}

always_awake_is_active() {
    [[ -x "$INHIBITOR_SH" ]] &&
        "$INHIBITOR_SH" is-always-awake >/dev/null 2>&1
}

manual_inhibitor_is_active() {
    [[ -x "$INHIBITOR_SH" ]] &&
        "$INHIBITOR_SH" is-active >/dev/null 2>&1
}

probe_hypridle_guard() {
    local action="$1"
    [[ -x "$HYPRIDLE_ACTION_SCRIPT" ]] || return 1
    "$HYPRIDLE_ACTION_SCRIPT" "$action" >/dev/null 2>&1
}

protected_reason() {
    if manual_inhibitor_is_active; then
        printf '%s\n' 'Keep Awake active'
        return 0
    fi

    if probe_hypridle_guard teams-inhibit-active; then
        printf '%s\n' 'Teams inhibitor active'
        return 0
    fi

    if probe_hypridle_guard obs-active; then
        printf '%s\n' 'OBS output active'
        return 0
    fi

    if probe_hypridle_guard game-active; then
        printf '%s\n' 'game active'
        return 0
    fi

    if probe_hypridle_guard video-active; then
        printf '%s\n' 'visible video playback active'
        return 0
    fi

    return 1
}

main() {
    local reason

    if always_awake_is_active; then
        log 'blocked four-hour protected-session safety: Always Awake active'
        return 0
    fi

    reason="$(protected_reason || true)"
    if [[ -z "$reason" ]]; then
        log 'four-hour protected-session safety: no protected session active; no-op'
        return 0
    fi

    log "four-hour protected-session safety: ${reason}; locking session and disabling displays"

    if ! "$LOGINCTL_BIN" lock-session; then
        log 'four-hour protected-session safety: failed to lock session; leaving displays on'
        return 1
    fi

    if ! "$HYPRCTL_BIN" dispatch 'hl.dsp.dpms({ action = "disable" })'; then
        log 'four-hour protected-session safety: session locked but failed to disable displays'
        return 1
    fi
}

main "$@"
