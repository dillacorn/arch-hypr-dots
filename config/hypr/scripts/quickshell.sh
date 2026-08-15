#!/usr/bin/env bash
# Awtarchy Quickshell manager.
# One Quickshell process owns bars, launcher, clipboard, notifications and power menu.

set -euo pipefail
export LC_ALL=C.UTF-8

CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="${CACHE_HOME}/awtarchy"
STATE_FILE="${STATE_DIR}/quickshell-state.json"
STATE_LOCK_FILE="${STATE_FILE}.lock"
LEGACY_STATE_FILE="${CACHE_HOME}/waybar/state.json"
LOG_FILE="${STATE_DIR}/quickshell.log"

DEFAULT_HORIZONTAL_SIZE=28
DEFAULT_VERTICAL_SIZE=36
DEFAULT_ICON_SCALE=100
DEFAULT_TEXT_SCALE=100
MIN_BAR_SIZE=20
MAX_BAR_SIZE=80
MIN_ICON_SCALE=50
MAX_ICON_SCALE=200
MIN_TEXT_SCALE=50
MAX_TEXT_SCALE=200

remove_legacy_quicksettings_desktop() {
    local desktop="${XDG_DATA_HOME:-$HOME/.local/share}/applications/hypr_quicksettings.desktop"

    [[ -f "$desktop" ]] || return 0
    if grep -Fqx 'Name=Awtarchy Quick Settings' "$desktop" \
        && grep -Fqx 'StartupWMClass=hypr_quicksettings' "$desktop" \
        && grep -Fq 'hypr_quicksettings.sh' "$desktop" \
        && grep -Fq -- '--ui' "$desktop"; then
        rm -f -- "$desktop"
    fi
}

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

need qs
need hyprctl
need jq
need flock

remove_legacy_quicksettings_desktop
mkdir -p "$STATE_DIR"
[[ -e "$STATE_DIR/quickshell-dnd" ]] || printf '0\n' >"$STATE_DIR/quickshell-dnd"
exec 8>"$STATE_LOCK_FILE"

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
            (.monitors;
                .[$m] = ({
                    position:"top",
                    enabled:true,
                    bar_size:0,
                    icon_scale:100,
                    text_scale:100,
                    last_horizontal:"top",
                    last_vertical:"right"
                } * (.[$m] // {})))
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

ipc() {
    qs -c "$CONFIG_NAME" ipc call "$@"
}

is_running() {
    ipc control ping >/dev/null 2>&1
}

instance_pids() {
    qs -c "$CONFIG_NAME" list --json 2>/dev/null \
        | jq -r '.[] | .pid | select(type == "number" and . > 0)' 2>/dev/null
}

wait_for_pids_stop() {
    local pid alive
    local -a pids=("$@")

    for _ in {1..100}; do
        alive=0
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                alive=1
                break
            fi
        done
        (( alive == 0 )) && return 0
        sleep 0.05
    done

    return 1
}

start_shell() {
    local stable_pings=0

    # start/restart do not otherwise need to hold the shared state lock while
    # Quickshell constructs QML. Lock only the state normalization itself so a
    # launcher/flyout state writer can never lose an update.
    flock -x 8
    ensure_state
    flock -u 8

    is_running && return 0
    nohup qs -c "$CONFIG_NAME" 8>&- >>"$LOG_FILE" 2>&1 &
    disown 2>/dev/null || true

    # A configuration can expose control IPC briefly and still fail during
    # construction of another singleton. Require a short stable-ready window
    # before reporting startup success.
    for _ in {1..100}; do
        if is_running; then
            ((stable_pings += 1))
            if (( stable_pings >= 5 )); then
                return 0
            fi
        else
            stable_pings=0
        fi
        sleep 0.05
    done

    printf 'quickshell.sh: Quickshell did not become ready; see %s\n' "$LOG_FILE" >&2
    return 1
}

stop_shell() {
    local pid
    local -a pids=()

    mapfile -t pids < <(instance_pids)
    (( ${#pids[@]} > 0 )) || return 0

    # Quickshell's kill command is an IPC shutdown request. Target each exact
    # old PID, then wait for those processes to really exit before starting a
    # replacement. IPC can disappear slightly before Qt/Wayland teardown is
    # complete, and starting the new instance in that gap can race the old one.
    for pid in "${pids[@]}"; do
        qs kill --pid "$pid" >/dev/null 2>&1 || true
    done

    wait_for_pids_stop "${pids[@]}" && return 0

    # Quickshell's IPC shutdown can occasionally stall during Qt teardown.
    # Use SIGTERM as recovery because Quickshell does not register SIGTERM
    # with its crash reporter. Avoid SIGKILL, which presents a crash dialog.
    printf 'quickshell.sh: graceful shutdown stalled for PID(s): %s; using SIGTERM fallback.\n' "${pids[*]}" >&2
    for pid in "${pids[@]}"; do
        [[ "$(basename "$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)")" == "quickshell" ]] || continue
        kill -TERM -- "$pid" 2>/dev/null || true
    done

    wait_for_pids_stop "${pids[@]}" && return 0

    printf 'quickshell.sh: Quickshell shutdown did not finish after SIGTERM for PID(s): %s\n' "${pids[*]}" >&2
    return 1
}

restart_shell() {
    # A soft QML reload cannot reliably discover newly installed component
    # files. Fully stop the current shell before starting the updated tree.
    stop_shell
    start_shell
}

list_monitors() {
    hyprctl monitors -j 2>/dev/null | jq -r '.[] | select((.disabled // false) == false) | .name'
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

getsize() {
    ensure_state
    jq -r --arg monitor "$1" '(.monitors[$monitor].bar_size // 0) | tonumber' "$STATE_FILE"
}

getscale() {
    ensure_state
    jq -r --arg monitor "$1" '(.monitors[$monitor].icon_scale // 100) | tonumber' "$STATE_FILE"
}

gettextscale() {
    ensure_state
    jq -r --arg monitor "$1" '(.monitors[$monitor].text_scale // 100) | tonumber' "$STATE_FILE"
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
    if [[ "$pos" == "top" || "$pos" == "bottom" ]]; then
        jq --arg monitor "$monitor" --arg pos "$pos" '.monitors[$monitor].position = $pos | .monitors[$monitor].last_horizontal = $pos' "$STATE_FILE" >"$tmp"
    else
        jq --arg monitor "$monitor" --arg pos "$pos" '.monitors[$monitor].position = $pos | .monitors[$monitor].last_vertical = $pos' "$STATE_FILE" >"$tmp"
    fi
    mv -f "$tmp" "$STATE_FILE"
}

setsize() {
    local monitor="$1" size="$2" tmp
    [[ "$size" =~ ^[0-9]+$ ]] || { printf 'quickshell.sh: bar size must be an integer\n' >&2; exit 2; }
    if (( size != 0 && (size < MIN_BAR_SIZE || size > MAX_BAR_SIZE) )); then
        printf 'quickshell.sh: bar size must be 0 or %d-%d\n' "$MIN_BAR_SIZE" "$MAX_BAR_SIZE" >&2
        exit 2
    fi
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg monitor "$monitor" --argjson size "$size" '.monitors[$monitor].bar_size = $size' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

setscale() {
    local monitor="$1" scale="$2" tmp
    [[ "$scale" =~ ^[0-9]+$ ]] || { printf 'quickshell.sh: icon scale must be an integer\n' >&2; exit 2; }
    if (( scale < MIN_ICON_SCALE || scale > MAX_ICON_SCALE )); then
        printf 'quickshell.sh: icon scale must be %d-%d\n' "$MIN_ICON_SCALE" "$MAX_ICON_SCALE" >&2
        exit 2
    fi
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg monitor "$monitor" --argjson scale "$scale" '.monitors[$monitor].icon_scale = $scale' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

settextscale() {
    local monitor="$1" scale="$2" tmp
    [[ "$scale" =~ ^[0-9]+$ ]] || { printf 'quickshell.sh: text scale must be an integer\n' >&2; exit 2; }
    if (( scale < MIN_TEXT_SCALE || scale > MAX_TEXT_SCALE )); then
        printf 'quickshell.sh: text scale must be %d-%d\n' "$MIN_TEXT_SCALE" "$MAX_TEXT_SCALE" >&2
        exit 2
    fi
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg monitor "$monitor" --argjson scale "$scale" '.monitors[$monitor].text_scale = $scale' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

reset_mon() {
    local monitor="$1" tmp
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg monitor "$monitor" '
        .monitors[$monitor] = {
            position:"top",
            enabled:true,
            bar_size:0,
            icon_scale:100,
            text_scale:100,
            last_horizontal:"top",
            last_vertical:"right"
        }
    ' "$STATE_FILE" >"$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

reset_all() {
    local monitor
    while IFS= read -r monitor; do
        [[ -n "$monitor" ]] || continue
        reset_mon "$monitor"
    done < <(list_monitors)
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
  list-monitors
  reset-all

focused monitor:
  focused-monitor
  toggle-focused
  getpos-focused
  getenabled-focused
  getsize-focused
  getscale-focused
  gettextscale-focused
  setenabled-focused <true|false>
  setpos-focused <top|bottom|left|right>
  setsize-focused <0|20-80>
  setscale-focused <50-200>
  settextscale-focused <50-200>
  reset-focused
  flip-focused
  rotate-focused

per monitor:
  toggle-mon <MON>
  getpos <MON>
  getenabled <MON>
  getsize <MON>
  getscale <MON>
  gettextscale <MON>
  setenabled <MON> <true|false>
  setpos <MON> <top|bottom|left|right>
  setsize <MON> <0|20-80>
  setscale <MON> <50-200>
  settextscale <MON> <50-200>
  reset-mon <MON>

bar_size 0 means Awtarchy defaults: 28px horizontal, 36px vertical.
icon_scale and text_scale are percentages; 100 preserves the tuned defaults.
USAGE
}

cmd="${1:-}"
case "$cmd" in
    start|restart)
        # start_shell takes the lock only around state normalization and releases
        # it before Quickshell construction to avoid blocking QML-owned writers.
        ;;
    stop|status|list-monitors|focused-monitor|""|-h|--help|help)
        ;;
    *)
        # All remaining public commands can read/modify quickshell-state.json.
        # Keep the entire read-modify-write sequence serialized with the same
        # lock used by quickshell_application_state.sh.
        flock -x 8
        ;;
esac

case "$cmd" in
    start) start_shell ;;
    stop) stop_shell ;;
    restart) restart_shell ;;
    status) status ;;
    enable) set_global_enabled true; start_shell ;;
    disable) set_global_enabled false ;;
    dump-state) ensure_state; cat "$STATE_FILE" ;;
    list-monitors) list_monitors ;;
    reset-all) reset_all ;;
    focused-monitor) focused_monitor ;;
    toggle-focused) monitor="$(focused_monitor)"; toggle_mon "$monitor" ;;
    toggle-mon) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; toggle_mon "$2" ;;
    getpos) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; getpos "$2" ;;
    getpos-focused) monitor="$(focused_monitor)"; getpos "$monitor" ;;
    getenabled) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; getenabled "$2" ;;
    getenabled-focused) monitor="$(focused_monitor)"; getenabled "$monitor" ;;
    getsize) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; getsize "$2" ;;
    getsize-focused) monitor="$(focused_monitor)"; getsize "$monitor" ;;
    getscale) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; getscale "$2" ;;
    getscale-focused) monitor="$(focused_monitor)"; getscale "$monitor" ;;
    gettextscale) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; gettextscale "$2" ;;
    gettextscale-focused) monitor="$(focused_monitor)"; gettextscale "$monitor" ;;
    setenabled) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 2; }; set_monitor_enabled "$2" "$3" ;;
    setenabled-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; set_monitor_enabled "$monitor" "$2" ;;
    setpos) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 2; }; setpos "$2" "$3" ;;
    setpos-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; setpos "$monitor" "$2" ;;
    setsize) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 2; }; setsize "$2" "$3" ;;
    setsize-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; setsize "$monitor" "$2" ;;
    setscale) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 2; }; setscale "$2" "$3" ;;
    setscale-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; setscale "$monitor" "$2" ;;
    settextscale) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 2; }; settextscale "$2" "$3" ;;
    settextscale-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; settextscale "$monitor" "$2" ;;
    reset-mon) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; reset_mon "$2" ;;
    reset-focused) monitor="$(focused_monitor)"; reset_mon "$monitor" ;;
    flip-focused) monitor="$(focused_monitor)"; flip_mon "$monitor" ;;
    rotate-focused) monitor="$(focused_monitor)"; rotate_mon "$monitor" ;;
    ""|-h|--help|help) usage ;;
    *) usage >&2; exit 2 ;;
esac
