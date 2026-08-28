#!/usr/bin/env bash
# Awtarchy Quickshell manager.
# One Quickshell process owns bars, launcher, clipboard, notifications and power menu.

set -euo pipefail
export LC_ALL=C.UTF-8

CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="${CACHE_HOME}/awtarchy"
STATE_FILE="${STATE_DIR}/quickshell-state.json"
STATE_LOCK_FILE="${STATE_FILE}.lock"
START_LOCK_FILE="${STATE_DIR}/quickshell-start.lock"
LEGACY_STATE_FILE="${CACHE_HOME}/waybar/state.json"
LOG_FILE="${STATE_DIR}/quickshell.log"
REPORT_SCRIPT="${AWTARCHY_REPORT_SCRIPT:-${CONFIG_HOME}/hypr/scripts/awtarchy_report_failure.sh}"
PROC_ROOT="/proc"
if [[ ${AWTARCHY_TEST_MODE:-0} == 1 && -n ${AWTARCHY_TEST_PROC_ROOT:-} ]]; then
    PROC_ROOT="${AWTARCHY_TEST_PROC_ROOT}"
fi

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
need python3

remove_legacy_quicksettings_desktop
mkdir -p "$STATE_DIR"
[[ -e "$STATE_DIR/quickshell-dnd" ]] || printf '0\n' >"$STATE_DIR/quickshell-dnd"
exec 7>"$START_LOCK_FILE"
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
                    show_cpu:true,
                    show_temp:true,
                    show_memory:true,
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

process_state_start_time() {
    local pid="$1" stat_line stat_tail
    local -a stat_fields=()

    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    IFS= read -r stat_line 2>/dev/null <"${PROC_ROOT}/${pid}/stat" || return 1
    [[ "$stat_line" == *') '* ]] || return 1

    # Field 2 (comm) may contain spaces or parentheses. Remove it from the
    # right, then field 1 is the process state and field 20 is starttime.
    stat_tail="${stat_line##*) }"
    IFS=' ' read -r -a stat_fields <<<"$stat_tail"
    (( ${#stat_fields[@]} >= 20 )) || return 1
    [[ "${stat_fields[0]}" =~ ^[A-Za-z]$ ]] || return 1
    [[ "${stat_fields[19]}" =~ ^[0-9]+$ ]] || return 1

    printf '%s %s\n' "${stat_fields[0]}" "${stat_fields[19]}"
}

process_identity_is_running() {
    local pid="$1" expected_start_time="$2" state start_time

    IFS=' ' read -r state start_time < <(process_state_start_time "$pid") || return 1
    case "$state" in
        Z|X|x) return 1 ;;
    esac
    [[ "$start_time" == "$expected_start_time" ]]
}

pid_is_quickshell() {
    local pid="$1" executable

    executable="$(readlink "${PROC_ROOT}/${pid}/exe" 2>/dev/null)" || return 1
    # Linux appends this suffix when a package upgrade unlinks the executable
    # that the still-running process has mapped.
    executable="${executable% (deleted)}"
    [[ "${executable##*/}" == quickshell ]]
}

signal_quickshell_identity() {
    local pid="$1" expected_start_time="$2" rc=0

    python3 - "$pid" "$expected_start_time" <<'PY' || rc=$?
import os
import signal
import sys

GONE_OR_REUSED = 3
UNSAFE = 4

try:
    pid = int(sys.argv[1])
    expected_start_time = sys.argv[2]
except (IndexError, ValueError):
    raise SystemExit(UNSAFE)

if pid <= 0 or not expected_start_time.isdecimal():
    raise SystemExit(UNSAFE)

try:
    pidfd = os.pidfd_open(pid, 0)
except ProcessLookupError:
    raise SystemExit(GONE_OR_REUSED)
except (AttributeError, OSError):
    raise SystemExit(UNSAFE)

try:
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8", errors="surrogateescape") as handle:
            stat_line = handle.read()
    except FileNotFoundError:
        raise SystemExit(GONE_OR_REUSED)
    except OSError:
        raise SystemExit(UNSAFE)

    marker = stat_line.rfind(") ")
    if marker < 0:
        raise SystemExit(UNSAFE)
    fields = stat_line[marker + 2:].split()
    if len(fields) < 20 or len(fields[0]) != 1 or not fields[19].isdecimal():
        raise SystemExit(UNSAFE)
    if fields[0] in {"Z", "X", "x"} or fields[19] != expected_start_time:
        raise SystemExit(GONE_OR_REUSED)

    try:
        executable = os.readlink(f"/proc/{pid}/exe")
    except FileNotFoundError:
        raise SystemExit(GONE_OR_REUSED)
    except OSError:
        raise SystemExit(UNSAFE)
    if executable.endswith(" (deleted)"):
        executable = executable[:-10]
    if os.path.basename(executable) != "quickshell":
        raise SystemExit(UNSAFE)

    try:
        signal.pidfd_send_signal(pidfd, signal.SIGTERM)
    except ProcessLookupError:
        raise SystemExit(GONE_OR_REUSED)
    except (AttributeError, OSError):
        raise SystemExit(UNSAFE)
finally:
    os.close(pidfd)
PY
    return "$rc"
}

wait_for_pids_stop() {
    local identity pid expected_start_time alive
    local -a identities=("$@")

    for _ in {1..100}; do
        alive=0
        for identity in "${identities[@]}"; do
            IFS=: read -r pid expected_start_time <<<"$identity"
            if process_identity_is_running "$pid" "$expected_start_time"; then
                alive=1
                break
            fi
        done
        (( alive == 0 )) && return 0
        sleep 0.05
    done

    return 1
}

report_quickshell_failure() {
    local stage="$1"
    [[ ${AWTARCHY_REPORT_SUPPRESS_QUICKSHELL:-0} != 1 ]] || return 0
    [[ -f "$REPORT_SCRIPT" || -x "$REPORT_SCRIPT" ]] || return 0
    bash "$REPORT_SCRIPT" capture quickshell "$stage" quickshell_not_ready || true
}

notify_pending_reports() {
    [[ -f "$REPORT_SCRIPT" || -x "$REPORT_SCRIPT" ]] || return 0
    bash "$REPORT_SCRIPT" notify-pending >/dev/null 2>&1 || true
}

start_shell() {
    local report_stage="${1:-start}"
    local stable_pings=0

    # Multiple login/startup paths can legitimately ask for Quickshell at the
    # same time. Serialize the readiness check and launch so they cannot create
    # duplicate Awtarchy instances before IPC becomes available.
    flock -x 7

    # start/restart do not otherwise need to hold the shared state lock while
    # Quickshell constructs QML. Lock only the state normalization itself so a
    # launcher/flyout state writer can never lose an update.
    flock -x 8
    ensure_state
    flock -u 8

    if is_running; then
        flock -u 7
        notify_pending_reports
        return 0
    fi

    nohup qs -c "$CONFIG_NAME" 7>&- 8>&- >>"$LOG_FILE" 2>&1 &
    disown 2>/dev/null || true

    # A configuration can expose control IPC briefly and still fail during
    # construction of another singleton. Require a short stable-ready window
    # before reporting startup success.
    for _ in {1..100}; do
        if is_running; then
            ((stable_pings += 1))
            if (( stable_pings >= 5 )); then
                flock -u 7
                notify_pending_reports
                return 0
            fi
        else
            stable_pings=0
        fi
        sleep 0.05
    done

    flock -u 7
    printf 'quickshell.sh: Quickshell did not become ready; see %s\n' "$LOG_FILE" >&2
    report_quickshell_failure "$report_stage"
    return 1
}

stop_shell() {
    local pid state start_time identity signal_rc
    local identity_error=0 signal_error=0
    local -a pids=() identities=() alive_pids=()

    mapfile -t pids < <(instance_pids)
    (( ${#pids[@]} > 0 )) || return 0

    # Do not use Quickshell's IPC teardown here. On some Qt/Quickshell builds
    # it can crash while destructing the old shell and launch the crash reporter.
    # SIGTERM is not registered by Quickshell's crash handler, so terminate the
    # exact old Awtarchy instance directly and wait for it to disappear.
    for pid in "${pids[@]}"; do
        if ! IFS=' ' read -r state start_time < <(process_state_start_time "$pid"); then
            if [[ -d "${PROC_ROOT}/${pid}" ]]; then
                printf 'quickshell.sh: could not verify process identity for PID %s; refusing to signal it.\n' "$pid" >&2
                identity_error=1
            fi
            continue
        fi
        case "$state" in
            Z|X|x) continue ;;
        esac

        if ! pid_is_quickshell "$pid"; then
            if process_identity_is_running "$pid" "$start_time"; then
                printf 'quickshell.sh: PID %s does not identify as Quickshell; refusing to signal it.\n' "$pid" >&2
                identity_error=1
            fi
            continue
        fi
        identities+=("${pid}:${start_time}")
    done

    (( identity_error == 0 )) || return 1
    (( ${#identities[@]} > 0 )) || return 0

    for identity in "${identities[@]}"; do
        IFS=: read -r pid start_time <<<"$identity"
        signal_rc=0
        signal_quickshell_identity "$pid" "$start_time" || signal_rc=$?
        case "$signal_rc" in
            0|3) ;;
            *)
                printf 'quickshell.sh: could not safely signal Quickshell PID %s.\n' "$pid" >&2
                signal_error=1
                ;;
        esac
    done

    (( signal_error == 0 )) || return 1

    wait_for_pids_stop "${identities[@]}" && return 0

    for identity in "${identities[@]}"; do
        IFS=: read -r pid start_time <<<"$identity"
        process_identity_is_running "$pid" "$start_time" && alive_pids+=("$pid")
    done
    (( ${#alive_pids[@]} > 0 )) || return 0

    printf 'quickshell.sh: Quickshell shutdown did not finish after SIGTERM for PID(s): %s\n' "${alive_pids[*]}" >&2
    return 1
}

restart_shell() {
    local report_stage="${AWTARCHY_REPORT_FAILURE_STAGE:-restart}"
    case "$report_stage" in
        restart|restart_after_update) ;;
        *) report_stage=restart ;;
    esac

    # A soft QML reload cannot reliably discover newly installed component
    # files. Fully stop the current shell before starting the updated tree.
    stop_shell
    start_shell "$report_stage"
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

getshowcpu() {
    ensure_state
    jq -r --arg monitor "$1" '(if .monitors[$monitor].show_cpu == null then true else .monitors[$monitor].show_cpu end) | if . then "true" else "false" end' "$STATE_FILE"
}

getshowtemp() {
    ensure_state
    jq -r --arg monitor "$1" '(if .monitors[$monitor].show_temp == null then true else .monitors[$monitor].show_temp end) | if . then "true" else "false" end' "$STATE_FILE"
}

getshowmemory() {
    ensure_state
    jq -r --arg monitor "$1" '(if .monitors[$monitor].show_memory == null then true else .monitors[$monitor].show_memory end) | if . then "true" else "false" end' "$STATE_FILE"
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

set_monitor_stat_visibility() {
    local monitor="$1" key="$2" enabled="$3" tmp
    case "$key" in
        show_cpu|show_temp|show_memory) ;;
        *) printf 'quickshell.sh: invalid bar stat key: %s\n' "$key" >&2; exit 2 ;;
    esac
    case "$enabled" in
        true|false) ;;
        *) printf 'quickshell.sh: bar stat visibility must be true or false\n' >&2; exit 2 ;;
    esac
    ensure_state
    tmp="${STATE_FILE}.tmp.$$"
    jq --arg monitor "$monitor" --arg key "$key" --argjson enabled "$enabled" '.monitors[$monitor][$key] = $enabled' "$STATE_FILE" >"$tmp"
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
            show_cpu:true,
            show_temp:true,
            show_memory:true,
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
  getshowcpu-focused
  getshowtemp-focused
  getshowmemory-focused
  setenabled-focused <true|false>
  setpos-focused <top|bottom|left|right>
  setsize-focused <0|20-80>
  setscale-focused <50-200>
  settextscale-focused <50-200>
  setshowcpu-focused <true|false>
  setshowtemp-focused <true|false>
  setshowmemory-focused <true|false>
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
  getshowcpu <MON>
  getshowtemp <MON>
  getshowmemory <MON>
  setenabled <MON> <true|false>
  setpos <MON> <top|bottom|left|right>
  setsize <MON> <0|20-80>
  setscale <MON> <50-200>
  settextscale <MON> <50-200>
  setshowcpu <MON> <true|false>
  setshowtemp <MON> <true|false>
  setshowmemory <MON> <true|false>
  reset-mon <MON>

bar_size 0 means Awtarchy defaults: 28px horizontal, 36px vertical.
icon_scale and text_scale are percentages; 100 preserves the tuned defaults.
CPU, temperature and memory modules are visible by default.
USAGE
}

cmd="${1:-}"
case "$cmd" in
    start|restart)
        # start_shell takes the state lock only around normalization and uses a
        # separate startup lock while Quickshell becomes ready.
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
    start) start_shell start ;;
    stop) stop_shell ;;
    restart) restart_shell ;;
    status) status ;;
    enable) set_global_enabled true; start_shell start ;;
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
    getshowcpu) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; getshowcpu "$2" ;;
    getshowcpu-focused) monitor="$(focused_monitor)"; getshowcpu "$monitor" ;;
    getshowtemp) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; getshowtemp "$2" ;;
    getshowtemp-focused) monitor="$(focused_monitor)"; getshowtemp "$monitor" ;;
    getshowmemory) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; getshowmemory "$2" ;;
    getshowmemory-focused) monitor="$(focused_monitor)"; getshowmemory "$monitor" ;;
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
    setshowcpu) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 2; }; set_monitor_stat_visibility "$2" show_cpu "$3" ;;
    setshowcpu-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; set_monitor_stat_visibility "$monitor" show_cpu "$2" ;;
    setshowtemp) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 2; }; set_monitor_stat_visibility "$2" show_temp "$3" ;;
    setshowtemp-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; set_monitor_stat_visibility "$monitor" show_temp "$2" ;;
    setshowmemory) [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 2; }; set_monitor_stat_visibility "$2" show_memory "$3" ;;
    setshowmemory-focused) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; monitor="$(focused_monitor)"; set_monitor_stat_visibility "$monitor" show_memory "$2" ;;
    reset-mon) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; reset_mon "$2" ;;
    reset-focused) monitor="$(focused_monitor)"; reset_mon "$monitor" ;;
    flip-focused) monitor="$(focused_monitor)"; flip_mon "$monitor" ;;
    rotate-focused) monitor="$(focused_monitor)"; rotate_mon "$monitor" ;;
    ""|-h|--help|help) usage ;;
    *) usage >&2; exit 2 ;;
esac
