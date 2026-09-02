#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy}"
CYCLES="${AWTARCHY_UI_LATENCY_CYCLES:-5}"
TIMEOUT_MS="${AWTARCHY_UI_LATENCY_TIMEOUT_MS:-2000}"
POLL_MS="${AWTARCHY_UI_LATENCY_POLL_MS:-5}"
SETTLE_MS="${AWTARCHY_UI_LATENCY_SETTLE_MS:-180}"
STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
LOG_DIR="${STATE_HOME}/awtarchy/logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_PATH="${LOG_DIR}/ui-latency-${STAMP}.log"

SURFACES=(
    'launcher|Awtarchy Application Search'
    'clipboard|Awtarchy Clipboard History'
    'quicksettings|Awtarchy Quick Settings'
    'network|Awtarchy Network'
    'bluetooth|Awtarchy Bluetooth'
)

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

for command_name in qs hyprctl jq date sleep awk sort; do
    command -v "$command_name" >/dev/null 2>&1 \
        || fail "required command not found: ${command_name}"
done

[[ "$CYCLES" =~ ^[1-9][0-9]*$ ]] || fail 'AWTARCHY_UI_LATENCY_CYCLES must be a positive integer'
[[ "$TIMEOUT_MS" =~ ^[1-9][0-9]*$ ]] || fail 'AWTARCHY_UI_LATENCY_TIMEOUT_MS must be a positive integer'
[[ "$POLL_MS" =~ ^[1-9][0-9]*$ ]] || fail 'AWTARCHY_UI_LATENCY_POLL_MS must be a positive integer'
[[ "$SETTLE_MS" =~ ^[0-9]+$ ]] || fail 'AWTARCHY_UI_LATENCY_SETTLE_MS must be a non-negative integer'

POLL_SECONDS="$(awk -v ms="$POLL_MS" 'BEGIN { printf "%.3f", ms / 1000.0 }')"
SETTLE_SECONDS="$(awk -v ms="$SETTLE_MS" 'BEGIN { printf "%.3f", ms / 1000.0 }')"

mkdir -p -- "$LOG_DIR"

now_ns() {
    date +%s%N
}

ipc_call() {
    local target="$1"
    local action="$2"
    qs -c "$CONFIG_NAME" ipc call "$target" "$action" >/dev/null 2>&1
}

client_mapped() {
    local title="$1"
    hyprctl -j clients 2>/dev/null \
        | jq -e --arg title "$title" '
            any(.[];
                ((.mapped // true) == true)
                and ((.title // "") == $title)
            )
        ' >/dev/null 2>&1
}

wait_until_unmapped() {
    local title="$1"
    local start current elapsed_ms

    if ! client_mapped "$title"; then
        return 0
    fi

    start="$(now_ns)"
    while client_mapped "$title"; do
        current="$(now_ns)"
        elapsed_ms=$(((current - start) / 1000000))
        (( elapsed_ms < TIMEOUT_MS )) || return 1
        sleep "$POLL_SECONDS"
    done
}

close_surface() {
    local target="$1"
    local title="$2"
    ipc_call "$target" close || true
    wait_until_unmapped "$title" || true
}

close_all() {
    local record target title
    for record in "${SURFACES[@]}"; do
        IFS='|' read -r target title <<<"$record"
        close_surface "$target" "$title"
    done
}

measure_once() {
    local target="$1"
    local title="$2"
    local start current elapsed_ms

    close_all
    if (( SETTLE_MS > 0 )); then
        sleep "$SETTLE_SECONDS"
    fi

    start="$(now_ns)"
    if ! ipc_call "$target" open; then
        close_surface "$target" "$title"
        return 2
    fi

    while ! client_mapped "$title"; do
        current="$(now_ns)"
        elapsed_ms=$(((current - start) / 1000000))
        if (( elapsed_ms >= TIMEOUT_MS )); then
            close_surface "$target" "$title"
            return 1
        fi
        sleep "$POLL_SECONDS"
    done

    current="$(now_ns)"
    elapsed_ms=$((current - start))
    awk -v ns="$elapsed_ms" 'BEGIN { printf "%.2f\n", ns / 1000000.0 }'

    close_surface "$target" "$title"
}

summary_for() {
    sort -n | awk '
        {
            value[NR] = $1;
            sum += $1;
        }
        END {
            if (NR == 0)
                exit 1;
            if (NR % 2 == 1)
                median = value[(NR + 1) / 2];
            else
                median = (value[NR / 2] + value[NR / 2 + 1]) / 2.0;
            printf "min=%.2fms median=%.2fms avg=%.2fms max=%.2fms", \
                value[1], median, sum / NR, value[NR];
        }
    '
}

collect_surface() {
    local target="$1"
    local title="$2"
    local cycle value rc summary
    local timeouts=0
    local ipc_failures=0
    local -a values=()

    printf '=== %s ===\n' "$target"
    for ((cycle = 1; cycle <= CYCLES; cycle += 1)); do
        rc=0
        value="$(measure_once "$target" "$title")" || rc=$?
        case "$rc" in
            0)
                values+=("$value")
                printf '%s cycle %d: %sms\n' "$target" "$cycle" "$value"
                ;;
            1)
                timeouts=$((timeouts + 1))
                printf '%s cycle %d: TIMEOUT\n' "$target" "$cycle"
                ;;
            *)
                ipc_failures=$((ipc_failures + 1))
                printf '%s cycle %d: IPC_ERROR\n' "$target" "$cycle"
                ;;
        esac
    done

    if (( ${#values[@]} > 0 )); then
        summary="$(printf '%s\n' "${values[@]}" | summary_for)"
        printf '%s summary: %s\n' "$target" "$summary"
    else
        printf '%s summary: unavailable\n' "$target"
    fi
    if (( timeouts > 0 || ipc_failures > 0 )); then
        printf '%s failures: timeouts=%d ipc_errors=%d\n' \
            "$target" "$timeouts" "$ipc_failures"
    fi
    printf '\n'
}

focused_monitor() {
    hyprctl -j monitors 2>/dev/null \
        | jq -r '.[] | select(.focused == true) | .name' \
        | head -n 1
}

collect_report() {
    local monitor record target title

    if ! qs -c "$CONFIG_NAME" ipc call control ping >/dev/null 2>&1; then
        fail "Awtarchy Quickshell IPC is unavailable for config ${CONFIG_NAME}"
    fi

    monitor="$(focused_monitor)"
    [[ -n "$monitor" ]] || monitor='unavailable'

    printf '%s\n' 'Awtarchy UI latency baseline'
    printf 'Collected: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
    printf '%s\n' 'Transient UI interaction collector: yes'
    printf 'Focused monitor: %s\n' "$monitor"
    printf 'Cycles per surface: %s\n' "$CYCLES"
    printf 'Timeout: %sms\n' "$TIMEOUT_MS"
    printf 'Poll interval: %sms\n' "$POLL_MS"
    printf 'Settle delay: %sms\n' "$SETTLE_MS"
    printf '%s\n' 'Measurement: IPC open command -> matching Hyprland client mapped'
    printf '\n'

    for record in "${SURFACES[@]}"; do
        IFS='|' read -r target title <<<"$record"
        collect_surface "$target" "$title"
    done

    close_all
    printf 'Report path: %s\n' "$REPORT_PATH"
}

trap 'close_all >/dev/null 2>&1 || true' EXIT
collect_report | tee "$REPORT_PATH"
