#!/usr/bin/env bash
# Awtarchy Quickshell manager.
# One Quickshell process owns bars, launcher, clipboard, notifications and power menu.

set -euo pipefail
export LC_ALL=C

CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="${CACHE_HOME}/awtarchy"
STATE_FILE="${STATE_DIR}/quickshell-state.json"
LEGACY_STATE_FILE="${CACHE_HOME}/waybar/state.json"
LOG_FILE="${STATE_DIR}/quickshell.log"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

need qs
need hyprctl
need jq

mkdir -p "$STATE_DIR"
[[ -e "$STATE_DIR/quickshell-dnd" ]] || printf '0\n' >"$STATE_DIR/quickshell-dnd"

ensure_state() {
    local monitors tmp

    if [[ ! -s "$STATE_FILE" ]] || ! jq -e '.' "$STATE_FILE" >/dev/null 2>&1; then
        if [[ -s "$LEGACY_STATE_FILE" ]] && jq -e 'type == "object" and (.monitors | type == "object")' "$LEGACY_STATE_FILE" >/dev/null 2>&1; then
            jq '{enabled:(if .enabled == null then true else .enabled end), monitors:(.monitors // {})}' "$LEGACY_STATE_FILE" >"$STATE_FILE"
            rm -rf -- "${CACHE_HOME}/waybar"
        else
            printf '{"enabled":true,"monitors":{}}\n' >"$STATE_FILE"
        fi
    fi

    monitors="$(hyprctl monitors -j 2>/dev/null | jq -c '[.[].name]' 2>/dev/null || printf '[]')"
    tmp="${STATE_FILE}.tmp.$$"
    jq --argjson monitors "$monitors" '
        .enabled = (if .enabled == null then true else .enabled end)
        | .monitors = (.monitors // {})
        | .monitors = reduce $monitors[] as $m
            (.monitors; .[$m] = ({position:"top",enabled:true} * (.[$m] // {})))
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

ipc() {
    qs -c "$CONFIG_NAME" ipc call "$@"
}

is_running() {
    ipc control ping >/dev/null 2>&1
}

start_shell() {
    ensure_state
    is_running && return 0
    nohup qs -c "$CONFIG_NAME" >>"$LOG_FILE" 2>&1 &
    disown 2>/dev/null || true

    for _ in {1..100}; do
        is_running && return 0
        sleep 0.05
    done

    printf 'quickshell.sh: Quickshell did not become ready; see %s\n' "$LOG_FILE" >&2
    return 1
}

stop_shell() {
    is_running && ipc control quit >/dev/null 2>&1 || true
}

restart_shell() {
    if is_running; then
        ipc control reload >/dev/null 2>&1 || true
    else
        start_shell
    fi
}

focused_monitor() {
    local monitor
    monitor="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' | head -n1)"
    [[ -n "$monitor" ]] || monitor="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // empty')"
    [[ -n "$monitor" ]] || monitor="$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty')"
    [[ -n "$monitor" ]] || return 1
    printf '%s\n' "$monitor"
}

getpos() {
    ensure_state
    jq -r --arg monitor "$1" '.monitors[$monitor].position // "top"' "$STATE_FILE"
}

getenabled() {
    ensure_state
    jq -r --arg monitor "$1" '(if .monitors[$monitor].enabled == null then true else .monitors[$monitor].enabled end) | if . then "true" else "false" end' "$STATE_FILE"
}

set_monitor_enabled() {
    local monitor="$1" enabled="$2" tmp
    case "$enabled" in
        true|false) ;;
        *) printf 'quickshell.sh: enabled must be true or false\n' >&2; exit 2 ;;
    esac
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg monitor "$monitor" --argjson enabled "$enabled" '.monitors[$monitor].enabled = $enabled' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

setpos() {
    local monitor="$1" pos="$2" tmp
    case "$pos" in top|bottom|left|right) ;; *) printf 'quickshell.sh: invalid position: %s\n' "$pos" >&2; exit 2 ;; esac
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg monitor "$monitor" --arg pos "$pos" '.monitors[$monitor].position = $pos' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

toggle_mon() {
    local monitor="$1"

    # A focused-monitor toggle must always be able to recover a visible bar.
    # Older Hypridle logic used the global enabled flag, so clear that stale
    # state before applying the per-monitor toggle.
    ensure_state
    if ! jq -e '.enabled == true' "$STATE_FILE" >/dev/null 2>&1; then
        set_global_enabled true
        set_monitor_enabled "$monitor" true
        return 0
    fi

    if [[ "$(getenabled "$monitor")" == "true" ]]; then
        set_monitor_enabled "$monitor" false
    else
        set_monitor_enabled "$monitor" true
    fi
}

flip_mon() {
    local monitor="$1" current next
    current="$(getpos "$monitor")"
    case "$current" in
        top) next=bottom ;;
        bottom) next=top ;;
        left) next=right ;;
        right) next=left ;;
        *) next=top ;;
    esac
    setpos "$monitor" "$next"
}

rotate_mon() {
    local monitor="$1" current target tmp
    current="$(getpos "$monitor")"
    ensure_state

    tmp="${STATE_FILE}.tmp.$$"
    if [[ "$current" == "left" || "$current" == "right" ]]; then
        jq --arg monitor "$monitor" --arg current "$current" '.monitors[$monitor].last_vertical = $current' "$STATE_FILE" >"$tmp"
        mv -f "$tmp" "$STATE_FILE"
        target="$(jq -r --arg monitor "$monitor" '.monitors[$monitor].last_horizontal // "top"' "$STATE_FILE")"
    else
        jq --arg monitor "$monitor" --arg current "$current" '.monitors[$monitor].last_horizontal = $current' "$STATE_FILE" >"$tmp"
        mv -f "$tmp" "$STATE_FILE"
        target="$(jq -r --arg monitor "$monitor" '.monitors[$monitor].last_vertical // "right"' "$STATE_FILE")"
    fi

    setpos "$monitor" "$target"
}

set_global_enabled() {
    local enabled="$1" tmp
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --argjson enabled "$enabled" '.enabled = $enabled' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

status() {
    if is_running; then printf 'running\n'; else printf 'stopped\n'; fi
}

usage() {
    cat <<'USAGE'
usage: quickshell.sh <command>

global:
  start | stop | restart | status
  enable | disable
  dump-state

focused monitor:
  focused-monitor
  toggle-focused
  getpos-focused
  getenabled-focused
  setenabled-focused <true|false>
  setpos-focused <top|bottom|left|right>
  flip-focused
  rotate-focused

per monitor:
  toggle-mon <MON>
  getpos <MON>
  getenabled <MON>
  setenabled <MON> <true|false>
  setpos <MON> <top|bottom|left|right>
USAGE
}

cmd="${1:-}"
case "$cmd" in
    start) start_shell ;;
    stop) stop_shell ;;
    restart) restart_shell ;;
    status) status ;;
    enable) set_global_enabled true; start_shell ;;
    disable) set_global_enabled false ;;
    dump-state) ensure_state; cat "$STATE_FILE" ;;
    focused-monitor) focused_monitor ;;
    toggle-focused) monitor="$(focused_monitor)"; toggle_mon "$monitor" ;;
    toggle-mon) [[ -n "${2:-}" ]] || { usage; exit 2; }; toggle_mon "$2" ;;
    getpos) [[ -n "${2:-}" ]] || { usage; exit 2; }; getpos "$2" ;;
    getpos-focused) monitor="$(focused_monitor)"; getpos "$monitor" ;;
    getenabled) [[ -n "${2:-}" ]] || { usage; exit 2; }; getenabled "$2" ;;
    getenabled-focused) monitor="$(focused_monitor)"; getenabled "$monitor" ;;
    setenabled) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage; exit 2; }; set_monitor_enabled "$2" "$3" ;;
    setenabled-focused) [[ -n "${2:-}" ]] || { usage; exit 2; }; monitor="$(focused_monitor)"; set_monitor_enabled "$monitor" "$2" ;;
    setpos) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage; exit 2; }; setpos "$2" "$3" ;;
    setpos-focused) [[ -n "${2:-}" ]] || { usage; exit 2; }; monitor="$(focused_monitor)"; setpos "$monitor" "$2" ;;
    flip-focused) monitor="$(focused_monitor)"; flip_mon "$monitor" ;;
    rotate-focused) monitor="$(focused_monitor)"; rotate_mon "$monitor" ;;
    ""|-h|--help|help) usage ;;
    *) usage; exit 2 ;;
esac
