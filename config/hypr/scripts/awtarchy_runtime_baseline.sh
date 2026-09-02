#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROC_ROOT="${AWTARCHY_PROC_ROOT:-/proc}"
SAMPLE_SECONDS="${AWTARCHY_SAMPLE_SECONDS:-2}"
CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy}"
STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
AWTARCHY_STATE_DIR="${STATE_HOME}/awtarchy"
AWTARCHY_LOG_DIR="${AWTARCHY_STATE_DIR}/logs"
QUICKSHELL_CACHE_DIR="${CACHE_HOME}/awtarchy"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_PATH="${AWTARCHY_LOG_DIR}/runtime-baseline-${STAMP}.log"

if ! [[ "$SAMPLE_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf 'Invalid AWTARCHY_SAMPLE_SECONDS: %s\n' "$SAMPLE_SECONDS" >&2
    exit 2
fi

mkdir -p -- "$AWTARCHY_LOG_DIR"

trim_line() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

command_output() {
    local fallback="$1"
    shift
    if ! command -v "$1" >/dev/null 2>&1; then
        printf '%s\n' "$fallback"
        return 0
    fi
    "$@" 2>&1 || printf '%s\n' "$fallback"
}

quickshell_instance_pid() {
    local listing pid
    command -v qs >/dev/null 2>&1 || return 0
    listing="$(qs -c "$CONFIG_NAME" list --json 2>/dev/null || true)"
    pid="$(grep -oE '"pid"[[:space:]]*:[[:space:]]*[0-9]+' <<<"$listing" \
        | head -n 1 \
        | grep -oE '[0-9]+' || true)"
    if [[ "$pid" =~ ^[1-9][0-9]*$ && -d "${PROC_ROOT}/${pid}" ]]; then
        printf '%s\n' "$pid"
    fi
}

find_quickshell_pid() {
    local listed snapshot preferred fallback

    listed="$(quickshell_instance_pid)"
    if [[ -n "$listed" ]]; then
        printf '%s\n' "$listed"
        return 0
    fi

    snapshot="$(ps -eo pid=,ppid=,comm=,args= 2>/dev/null || true)"
    preferred="$(awk '$3 == "quickshell" && $0 ~ /awtarchy/ { print $1; exit }' <<<"$snapshot")"
    if [[ -n "$preferred" ]]; then
        printf '%s\n' "$preferred"
        return 0
    fi
    fallback="$(awk '$3 == "quickshell" { print $1; exit }' <<<"$snapshot")"
    printf '%s\n' "$fallback"
}

ps_value() {
    local pid="$1"
    local field="$2"
    local value
    value="$(ps -p "$pid" -o "${field}=" 2>/dev/null || true)"
    trim_line "$value"
}

percent_or_unavailable() {
    local value="${1:-}"
    if [[ -z "$value" || "$value" == 'unavailable' ]]; then
        printf '%s' 'unavailable'
    else
        printf '%s%%' "$value"
    fi
}

thread_count_for() {
    local pid="$1"
    local task_dir="${PROC_ROOT}/${pid}/task"
    if [[ ! -d "$task_dir" ]]; then
        printf '%s\n' 'unavailable'
        return 0
    fi
    find "$task_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d '[:space:]'
}

thread_types_for() {
    local pid="$1"
    local thread_types
    thread_types="$(
        ps -L -p "$pid" -o comm= 2>/dev/null \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
            | sed '/^$/d' \
            | sort \
            | uniq -c \
            | sort -nr \
            || true
    )"
    if [[ -n "$thread_types" ]]; then
        printf '%s\n' "$thread_types"
    else
        printf '%s\n' 'unavailable'
    fi
}

proc_process_ticks() {
    local pid="$1"
    local stat_path="${PROC_ROOT}/${pid}/stat"
    local line rest
    local -a fields=()
    [[ -r "$stat_path" ]] || return 1
    IFS= read -r line <"$stat_path" || return 1
    [[ "$line" == *") "* ]] || return 1
    rest="${line#*) }"
    IFS=' ' read -r -a fields <<<"$rest"
    (( ${#fields[@]} >= 13 )) || return 1
    printf '%s\n' "$(( fields[11] + fields[12] ))"
}

proc_total_ticks() {
    local stat_path="${PROC_ROOT}/stat"
    [[ -r "$stat_path" ]] || return 1
    awk '/^cpu[[:space:]]/ { total=0; for (i=2; i<=NF; ++i) total += $i; print total; exit }' "$stat_path"
}

interval_cpu_percent() {
    local process_before="$1"
    local process_after="$2"
    local total_before="$3"
    local total_after="$4"
    local cpus="$5"
    awk -v pb="$process_before" -v pa="$process_after" -v tb="$total_before" -v ta="$total_after" -v n="$cpus" '
        BEGIN {
            pd = pa - pb;
            td = ta - tb;
            if (pd < 0 || td <= 0 || n <= 0) {
                print "unavailable";
                exit;
            }
            printf "%.2f", (pd / td) * n * 100.0;
        }
    '
}

print_file_or_unavailable() {
    local path="$1"
    local max_lines="${2:-0}"
    if [[ ! -r "$path" ]]; then
        printf '%s\n' 'unavailable'
        return 0
    fi
    if (( max_lines > 0 )); then
        tail -n "$max_lines" -- "$path"
    else
        cat -- "$path"
    fi
}

collect_report() {
    local qs_pid uptime rss threads cpu_first cpu_second
    local proc_before='' proc_after='' total_before='' total_after='' cpu_interval='unavailable'
    local cpu_count='1'

    qs_pid="$(find_quickshell_pid)"

    printf '%s\n' 'Awtarchy runtime baseline'
    printf 'Collected: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
    printf '%s\n' 'Read-only collector: yes'
    printf 'Kernel: %s\n' "$(command_output unavailable uname -a)"
    printf 'Sample window seconds: %s\n' "$SAMPLE_SECONDS"
    printf '\n'

    printf '%s\n' '=== Runtime ==='
    if [[ -z "$qs_pid" ]]; then
        printf '%s\n' 'Quickshell PID: unavailable'
        printf '%s\n' 'Quickshell uptime seconds: unavailable'
        printf '%s\n' 'Quickshell RSS KiB: unavailable'
        printf '%s\n' 'Quickshell threads: unavailable'
        printf '%s\n' 'Quickshell CPU sample 1: unavailable'
        printf '%s\n' 'Quickshell CPU sample 2: unavailable'
        printf '%s\n' 'Quickshell CPU interval: unavailable'
    else
        uptime="$(ps_value "$qs_pid" etimes)"
        rss="$(ps_value "$qs_pid" rss)"
        threads="$(thread_count_for "$qs_pid")"
        cpu_first="$(ps_value "$qs_pid" %cpu)"

        proc_before="$(proc_process_ticks "$qs_pid" 2>/dev/null || true)"
        total_before="$(proc_total_ticks 2>/dev/null || true)"
        if command -v getconf >/dev/null 2>&1; then
            cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
            [[ "$cpu_count" =~ ^[0-9]+$ ]] || cpu_count='1'
        fi

        sleep "$SAMPLE_SECONDS"

        cpu_second="$(ps_value "$qs_pid" %cpu)"
        proc_after="$(proc_process_ticks "$qs_pid" 2>/dev/null || true)"
        total_after="$(proc_total_ticks 2>/dev/null || true)"
        if [[ -n "$proc_before" && -n "$proc_after" && -n "$total_before" && -n "$total_after" ]]; then
            cpu_interval="$(interval_cpu_percent "$proc_before" "$proc_after" "$total_before" "$total_after" "$cpu_count")"
        fi

        printf 'Quickshell PID: %s\n' "$qs_pid"
        printf 'Quickshell uptime seconds: %s\n' "${uptime:-unavailable}"
        printf 'Quickshell RSS KiB: %s\n' "${rss:-unavailable}"
        printf 'Quickshell threads: %s\n' "$threads"
        printf 'Quickshell CPU sample 1: %s\n' "$(percent_or_unavailable "$cpu_first")"
        printf 'Quickshell CPU sample 2: %s\n' "$(percent_or_unavailable "$cpu_second")"
        printf 'Quickshell CPU interval: %s\n' "$(percent_or_unavailable "$cpu_interval")"
    fi
    printf '\n'

    printf '%s\n' '=== Quickshell direct children/helpers ==='
    if [[ -n "$qs_pid" ]]; then
        ps --ppid "$qs_pid" -o pid=,ppid=,comm=,args= 2>/dev/null || printf '%s\n' 'unavailable'
    else
        printf '%s\n' 'unavailable'
    fi
    printf '\n'

    printf '%s\n' '=== Quickshell thread types ==='
    if [[ -n "$qs_pid" ]]; then
        thread_types_for "$qs_pid"
    else
        printf '%s\n' 'unavailable'
    fi
    printf '\n'

    printf '%s\n' '=== Versions ==='
    command_output unavailable hyprctl version
    command_output unavailable qs --version
    printf '\n'

    printf '%s\n' '=== Hyprland monitors ==='
    command_output unavailable hyprctl monitors -j
    printf '\n'

    printf '%s\n' '=== Hyprland active workspace ==='
    command_output unavailable hyprctl activeworkspace -j
    printf '\n'

    printf '%s\n' '=== Hyprland clients ==='
    command_output unavailable hyprctl clients -j
    printf '\n'

    printf '%s\n' '=== Awtarchy config-version ==='
    print_file_or_unavailable "${AWTARCHY_STATE_DIR}/config-version"
    printf '\n'

    printf '%s\n' '=== Awtarchy command-version ==='
    print_file_or_unavailable "${AWTARCHY_STATE_DIR}/command-version"
    printf '\n'

    printf '%s\n' '=== Awtarchy git-testing ==='
    print_file_or_unavailable "${AWTARCHY_STATE_DIR}/git-testing"
    printf '\n'

    printf '%s\n' '=== Quickshell state ==='
    print_file_or_unavailable "${QUICKSHELL_CACHE_DIR}/quickshell-state.json"
    printf '\n'

    printf '%s\n' '=== Recent Quickshell log ==='
    print_file_or_unavailable "${QUICKSHELL_CACHE_DIR}/quickshell.log" 120
    printf '\n'

    printf 'Report path: %s\n' "$REPORT_PATH"
}

collect_report | tee "$REPORT_PATH"
