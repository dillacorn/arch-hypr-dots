#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy}"
STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
LOG_ROOT="${STATE_HOME}/awtarchy/logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
BASELINE_COLLECTOR="${AWTARCHY_BASELINE_COLLECTOR:-${SCRIPT_DIR}/awtarchy_runtime_baseline.sh}"
UI_LATENCY_COLLECTOR="${AWTARCHY_UI_LATENCY_COLLECTOR:-${SCRIPT_DIR}/awtarchy_ui_latency.sh}"
CONTENT_READINESS_COLLECTOR="${AWTARCHY_CONTENT_READINESS_COLLECTOR:-${SCRIPT_DIR}/awtarchy_content_readiness.sh}"
OPEN_CLOSE_CYCLES="${AWTARCHY_STRESS_OPEN_CLOSE_CYCLES:-10}"
OPEN_CLOSE_DELAY="${AWTARCHY_STRESS_OPEN_CLOSE_DELAY_SECONDS:-0.04}"

SURFACES=(launcher clipboard quicksettings network bluetooth)

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

usage() {
    printf '%s\n' \
        'Usage:' \
        '  awtarchy_runtime_stress.sh run' \
        '  awtarchy_runtime_stress.sh snapshot <label>'
}

require_executable() {
    [[ -x "$1" ]] || fail "required collector is missing or not executable: $1"
}

metric_value() {
    local path="$1"
    local label="$2"
    awk -v label="$label" 'index($0, label ": ") == 1 { sub("^" label ": ", ""); print; exit }' "$path"
}

helper_count() {
    local path="$1"
    awk '
        /^=== Quickshell direct children\/helpers ===$/ { inside=1; next }
        inside && /^$/ { inside=0; exit }
        inside && $0 != "unavailable" { count++ }
        END { print count + 0 }
    ' "$path"
}

numeric_delta() {
    local before="$1"
    local after="$2"
    if [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$((after - before))"
    else
        printf '%s\n' 'unavailable'
    fi
}

close_all_surfaces() {
    local target
    for target in "${SURFACES[@]}"; do
        qs -c "$CONFIG_NAME" ipc call "$target" close >/dev/null 2>&1 || true
    done
}

run_transient_stress() {
    local output="$1"
    local cycle target

    {
        printf '%s\n' 'Awtarchy transient UI open/close stress'
        printf 'Cycles per surface: %s\n' "$OPEN_CLOSE_CYCLES"
        for ((cycle = 1; cycle <= OPEN_CLOSE_CYCLES; cycle += 1)); do
            for target in "${SURFACES[@]}"; do
                if qs -c "$CONFIG_NAME" ipc call "$target" open >/dev/null 2>&1; then
                    printf '%s cycle %d open: ok\n' "$target" "$cycle"
                else
                    printf '%s cycle %d open: IPC_ERROR\n' "$target" "$cycle"
                fi
                sleep "$OPEN_CLOSE_DELAY"
                if qs -c "$CONFIG_NAME" ipc call "$target" close >/dev/null 2>&1; then
                    printf '%s cycle %d close: ok\n' "$target" "$cycle"
                else
                    printf '%s cycle %d close: IPC_ERROR\n' "$target" "$cycle"
                fi
            done
        done
    } >"$output"
    close_all_surfaces
}

write_summary() {
    local run_dir="$1"
    local cold="${run_dir}/baseline-cold.log"
    local pre="${run_dir}/baseline-pre.log"
    local post="${run_dir}/baseline-post.log"
    local cold_rss pre_rss post_rss cold_threads pre_threads post_threads
    local cold_helpers pre_helpers post_helpers warm_rss_delta stress_rss_delta
    local warm_thread_delta stress_thread_delta

    cold_rss="$(metric_value "$cold" 'Quickshell RSS KiB')"
    pre_rss="$(metric_value "$pre" 'Quickshell RSS KiB')"
    post_rss="$(metric_value "$post" 'Quickshell RSS KiB')"
    cold_threads="$(metric_value "$cold" 'Quickshell threads')"
    pre_threads="$(metric_value "$pre" 'Quickshell threads')"
    post_threads="$(metric_value "$post" 'Quickshell threads')"
    cold_helpers="$(helper_count "$cold")"
    pre_helpers="$(helper_count "$pre")"
    post_helpers="$(helper_count "$post")"
    warm_rss_delta="$(numeric_delta "$cold_rss" "$pre_rss")"
    stress_rss_delta="$(numeric_delta "$pre_rss" "$post_rss")"
    warm_thread_delta="$(numeric_delta "$cold_threads" "$pre_threads")"
    stress_thread_delta="$(numeric_delta "$pre_threads" "$post_threads")"

    {
        printf '%s\n' 'Awtarchy runtime stress summary'
        printf 'Collected: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
        printf 'Quickshell RSS cold KiB: %s\n' "${cold_rss:-unavailable}"
        printf 'Quickshell RSS warmed KiB: %s\n' "${pre_rss:-unavailable}"
        printf 'Quickshell RSS cold-to-warm delta KiB: %s\n' "$warm_rss_delta"
        printf 'Quickshell RSS pre KiB: %s\n' "${pre_rss:-unavailable}"
        printf 'Quickshell RSS post KiB: %s\n' "${post_rss:-unavailable}"
        printf 'Quickshell RSS delta KiB: %s\n' "$stress_rss_delta"
        printf 'Quickshell threads cold: %s\n' "${cold_threads:-unavailable}"
        printf 'Quickshell threads warmed: %s\n' "${pre_threads:-unavailable}"
        printf 'Quickshell threads cold-to-warm delta: %s\n' "$warm_thread_delta"
        printf 'Quickshell threads pre: %s\n' "${pre_threads:-unavailable}"
        printf 'Quickshell threads post: %s\n' "${post_threads:-unavailable}"
        printf 'Quickshell threads delta: %s\n' "$stress_thread_delta"
        printf 'Quickshell direct helpers cold: %s\n' "$cold_helpers"
        printf 'Quickshell direct helpers pre: %s\n' "$pre_helpers"
        printf 'Quickshell direct helpers post: %s\n' "$post_helpers"
        printf '\n%s\n' 'Cold-start to warmed change is initialization evidence, not stress growth.'
        printf '%s\n' 'Stress deltas compare the warmed pre-stress baseline with the post-stress baseline.'
        printf '\n%s\n' '=== Recorded failures/timeouts ==='
        grep -Eh 'failures:|TIMEOUT|IPC_ERROR' \
            "${run_dir}/ui-latency.log" \
            "${run_dir}/content-readiness.log" \
            "${run_dir}/transient-stress.log" || true
        printf '\n%s\n' '=== Artifacts ==='
        printf '%s\n' \
            "${run_dir}/baseline-cold.log" \
            "${run_dir}/ui-latency.log" \
            "${run_dir}/content-readiness.log" \
            "${run_dir}/baseline-pre.log" \
            "${run_dir}/transient-stress.log" \
            "${run_dir}/baseline-post.log"
        printf '\n%s\n' 'Short-run RSS change is not a memory-leak determination.'
    } >"${run_dir}/summary.log"
}

run_bundle() {
    local run_dir="${LOG_ROOT}/runtime-stress-${STAMP}"

    [[ "$OPEN_CLOSE_CYCLES" =~ ^[1-9][0-9]*$ ]] \
        || fail 'AWTARCHY_STRESS_OPEN_CLOSE_CYCLES must be a positive integer'
    require_executable "$BASELINE_COLLECTOR"
    require_executable "$UI_LATENCY_COLLECTOR"
    require_executable "$CONTENT_READINESS_COLLECTOR"
    command -v qs >/dev/null 2>&1 || fail 'required command not found: qs'
    qs -c "$CONFIG_NAME" ipc call control ping >/dev/null 2>&1 \
        || fail "Awtarchy Quickshell IPC is unavailable for config ${CONFIG_NAME}"

    mkdir -p -- "$run_dir"
    trap 'close_all_surfaces >/dev/null 2>&1 || true' EXIT

    "$BASELINE_COLLECTOR" >"${run_dir}/baseline-cold.log"
    "$UI_LATENCY_COLLECTOR" >"${run_dir}/ui-latency.log"
    "$CONTENT_READINESS_COLLECTOR" >"${run_dir}/content-readiness.log"
    "$BASELINE_COLLECTOR" >"${run_dir}/baseline-pre.log"
    run_transient_stress "${run_dir}/transient-stress.log"
    "$BASELINE_COLLECTOR" >"${run_dir}/baseline-post.log"
    write_summary "$run_dir"

    trap - EXIT
    close_all_surfaces
    cat -- "${run_dir}/summary.log"
    printf 'Run directory: %s\n' "$run_dir"
}

snapshot() {
    local label="${1:-}"
    local path

    [[ -n "$label" ]] || fail 'snapshot requires a label'
    [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'snapshot label may contain only A-Z, a-z, 0-9, dot, underscore, and hyphen'
    require_executable "$BASELINE_COLLECTOR"
    mkdir -p -- "$LOG_ROOT"
    path="${LOG_ROOT}/runtime-stress-snapshot-${STAMP}-${label}.log"
    {
        printf '%s\n' 'Awtarchy runtime stress snapshot'
        printf 'Snapshot label: %s\n' "$label"
        printf 'Collected: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
        printf '\n'
        "$BASELINE_COLLECTOR"
    } >"$path"
    cat -- "$path"
    printf 'Snapshot path: %s\n' "$path"
}

case "${1:-}" in
    run)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        run_bundle
        ;;
    snapshot)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        snapshot "$2"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
