#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy}"
CYCLES="${AWTARCHY_CONTENT_READINESS_CYCLES:-5}"
TIMEOUT_MS="${AWTARCHY_CONTENT_READINESS_TIMEOUT_MS:-3000}"
POLL_MS="${AWTARCHY_CONTENT_READINESS_POLL_MS:-5}"
SETTLE_MS="${AWTARCHY_CONTENT_READINESS_SETTLE_MS:-180}"
STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
LOG_DIR="${STATE_HOME}/awtarchy/logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_PATH="${LOG_DIR}/content-readiness-${STAMP}.log"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

for command_name in qs hyprctl jq date sleep awk sort tr; do
    command -v "$command_name" >/dev/null 2>&1 \
        || fail "required command not found: ${command_name}"
done

[[ "$CYCLES" =~ ^[1-9][0-9]*$ ]] \
    || fail 'AWTARCHY_CONTENT_READINESS_CYCLES must be a positive integer'
[[ "$TIMEOUT_MS" =~ ^[1-9][0-9]*$ ]] \
    || fail 'AWTARCHY_CONTENT_READINESS_TIMEOUT_MS must be a positive integer'
[[ "$POLL_MS" =~ ^[1-9][0-9]*$ ]] \
    || fail 'AWTARCHY_CONTENT_READINESS_POLL_MS must be a positive integer'
[[ "$SETTLE_MS" =~ ^[0-9]+$ ]] \
    || fail 'AWTARCHY_CONTENT_READINESS_SETTLE_MS must be a non-negative integer'

POLL_SECONDS="$(awk -v ms="$POLL_MS" 'BEGIN { printf "%.3f", ms / 1000.0 }')"
SETTLE_SECONDS="$(awk -v ms="$SETTLE_MS" 'BEGIN { printf "%.3f", ms / 1000.0 }')"

mkdir -p -- "$LOG_DIR"

now_ns() {
    date +%s%N
}

elapsed_ms() {
    local start_ns="$1"
    local current_ns="$2"
    awk -v start="$start_ns" -v current="$current_ns" \
        'BEGIN { printf "%.2f", (current - start) / 1000000.0 }'
}

ipc_call() {
    local target="$1"
    local action="$2"
    qs -c "$CONFIG_NAME" ipc call "$target" "$action" >/dev/null 2>&1
}

ipc_prop() {
    local target="$1"
    local property="$2"
    qs -c "$CONFIG_NAME" ipc prop get "$target" "$property" 2>/dev/null \
        | tr -d '[:space:]'
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
    local start_ns current_ns elapsed

    if ! client_mapped "$title"; then
        return 0
    fi

    start_ns="$(now_ns)"
    while client_mapped "$title"; do
        current_ns="$(now_ns)"
        elapsed=$(((current_ns - start_ns) / 1000000))
        (( elapsed < TIMEOUT_MS )) || return 1
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
    close_surface launcher 'Awtarchy Application Search'
    close_surface clipboard 'Awtarchy Clipboard History'
}

settle_before_cycle() {
    close_all
    if (( SETTLE_MS > 0 )); then
        sleep "$SETTLE_SECONDS"
    fi
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

print_summary() {
    local label="$1"
    shift
    local -a values=("$@")
    local summary

    if (( ${#values[@]} == 0 )); then
        printf '%s summary: unavailable\n' "$label"
        return 0
    fi

    summary="$(printf '%s\n' "${values[@]}" | summary_for)"
    printf '%s summary: %s\n' "$label" "$summary"
}

measure_launcher() {
    local start_ns current_ns elapsed
    local mapped_ms='' ready_ms='' ready='false' results='0'

    settle_before_cycle
    start_ns="$(now_ns)"
    if ! ipc_call launcher open; then
        close_surface launcher 'Awtarchy Application Search'
        return 2
    fi

    while true; do
        if [[ -z "$mapped_ms" ]] && client_mapped 'Awtarchy Application Search'; then
            current_ns="$(now_ns)"
            mapped_ms="$(elapsed_ms "$start_ns" "$current_ns")"
        fi

        ready="$(ipc_prop launcher diagnosticReady || true)"
        results="$(ipc_prop launcher diagnosticResultCount || true)"
        [[ "$results" =~ ^[0-9]+$ ]] || results='0'

        if [[ "$ready" == 'true' ]]; then
            current_ns="$(now_ns)"
            ready_ms="$(elapsed_ms "$start_ns" "$current_ns")"
            [[ -n "$mapped_ms" ]] || mapped_ms="$ready_ms"
            printf '%s|%s|%s\n' "$mapped_ms" "$ready_ms" "$results"
            close_surface launcher 'Awtarchy Application Search'
            return 0
        fi

        current_ns="$(now_ns)"
        elapsed=$(((current_ns - start_ns) / 1000000))
        if (( elapsed >= TIMEOUT_MS )); then
            close_surface launcher 'Awtarchy Application Search'
            return 1
        fi
        sleep "$POLL_SECONDS"
    done
}

measure_clipboard() {
    local start_ns current_ns elapsed
    local mapped_ms='' first_entry_ms='' first_visible_ms='' first_thumbnail_ms=''
    local entry_count='0' first_row='false' candidates='0' thumbnails='0' loading='true'

    settle_before_cycle
    start_ns="$(now_ns)"
    if ! ipc_call clipboard open; then
        close_surface clipboard 'Awtarchy Clipboard History'
        return 2
    fi

    while true; do
        if [[ -z "$mapped_ms" ]] && client_mapped 'Awtarchy Clipboard History'; then
            current_ns="$(now_ns)"
            mapped_ms="$(elapsed_ms "$start_ns" "$current_ns")"
        fi

        entry_count="$(ipc_prop clipboard diagnosticEntryCount || true)"
        first_row="$(ipc_prop clipboard diagnosticFirstRowReady || true)"
        candidates="$(ipc_prop clipboard diagnosticThumbnailCandidateCount || true)"
        thumbnails="$(ipc_prop clipboard diagnosticThumbnailReadyCount || true)"
        loading="$(ipc_prop clipboard diagnosticListLoading || true)"

        [[ "$entry_count" =~ ^[0-9]+$ ]] || entry_count='0'
        [[ "$candidates" =~ ^[0-9]+$ ]] || candidates='0'
        [[ "$thumbnails" =~ ^[0-9]+$ ]] || thumbnails='0'

        current_ns="$(now_ns)"
        if [[ -z "$first_entry_ms" ]] && (( entry_count > 0 )); then
            first_entry_ms="$(elapsed_ms "$start_ns" "$current_ns")"
        fi
        if [[ -z "$first_visible_ms" && "$first_row" == 'true' ]]; then
            first_visible_ms="$(elapsed_ms "$start_ns" "$current_ns")"
        fi
        if [[ -z "$first_thumbnail_ms" ]] && (( thumbnails > 0 )); then
            first_thumbnail_ms="$(elapsed_ms "$start_ns" "$current_ns")"
        fi

        if [[ -n "$first_visible_ms" ]]; then
            [[ -n "$mapped_ms" ]] || mapped_ms="$first_visible_ms"
            [[ -n "$first_entry_ms" ]] || first_entry_ms="$first_visible_ms"
            if (( candidates > 0 )) && [[ -n "$first_thumbnail_ms" ]]; then
                printf '%s|%s|%s|%s|%s\n' \
                    "$mapped_ms" "$first_entry_ms" "$first_visible_ms" \
                    "$first_thumbnail_ms" "$candidates"
                close_surface clipboard 'Awtarchy Clipboard History'
                return 0
            fi
            if (( candidates == 0 )) && [[ "$loading" == 'false' ]]; then
                printf '%s|%s|%s|n/a|0\n' \
                    "$mapped_ms" "$first_entry_ms" "$first_visible_ms"
                close_surface clipboard 'Awtarchy Clipboard History'
                return 0
            fi
        fi

        elapsed=$(((current_ns - start_ns) / 1000000))
        if (( elapsed >= TIMEOUT_MS )); then
            close_surface clipboard 'Awtarchy Clipboard History'
            return 1
        fi
        sleep "$POLL_SECONDS"
    done
}

collect_launcher() {
    local cycle value rc mapped ready results
    local -a mapped_values=() ready_values=()

    printf '%s\n' '=== launcher ==='
    for ((cycle = 1; cycle <= CYCLES; cycle += 1)); do
        rc=0
        value="$(measure_launcher)" || rc=$?
        if (( rc == 0 )); then
            IFS='|' read -r mapped ready results <<<"$value"
            mapped_values+=("$mapped")
            ready_values+=("$ready")
            printf 'launcher cycle %d: mapped=%sms ready=%sms results=%s\n' \
                "$cycle" "$mapped" "$ready" "$results"
        elif (( rc == 1 )); then
            printf 'launcher cycle %d: TIMEOUT\n' "$cycle"
        else
            printf 'launcher cycle %d: IPC_ERROR\n' "$cycle"
        fi
    done

    print_summary 'launcher mapped' "${mapped_values[@]}"
    print_summary 'launcher ready' "${ready_values[@]}"
    printf '\n'
}

collect_clipboard() {
    local cycle value rc mapped first_entry first_visible first_thumbnail candidates
    local -a mapped_values=() entry_values=() visible_values=() thumbnail_values=()

    printf '%s\n' '=== clipboard ==='
    for ((cycle = 1; cycle <= CYCLES; cycle += 1)); do
        rc=0
        value="$(measure_clipboard)" || rc=$?
        if (( rc == 0 )); then
            IFS='|' read -r mapped first_entry first_visible first_thumbnail candidates <<<"$value"
            mapped_values+=("$mapped")
            entry_values+=("$first_entry")
            visible_values+=("$first_visible")
            if [[ "$first_thumbnail" != 'n/a' ]]; then
                thumbnail_values+=("$first_thumbnail")
            fi
            printf 'clipboard cycle %d: mapped=%sms first_entry=%sms first_visible=%sms first_thumbnail=%s candidates=%s\n' \
                "$cycle" "$mapped" "$first_entry" "$first_visible" \
                "$([[ "$first_thumbnail" == 'n/a' ]] && printf 'n/a' || printf '%sms' "$first_thumbnail")" \
                "$candidates"
        elif (( rc == 1 )); then
            printf 'clipboard cycle %d: TIMEOUT\n' "$cycle"
        else
            printf 'clipboard cycle %d: IPC_ERROR\n' "$cycle"
        fi
    done

    print_summary 'clipboard mapped' "${mapped_values[@]}"
    print_summary 'clipboard first entry' "${entry_values[@]}"
    print_summary 'clipboard first visible' "${visible_values[@]}"
    print_summary 'clipboard first thumbnail' "${thumbnail_values[@]}"
    printf '\n'
}

focused_monitor() {
    hyprctl -j monitors 2>/dev/null \
        | jq -r '.[] | select(.focused == true) | .name' \
        | head -n 1
}

collect_report() {
    local monitor

    if ! qs -c "$CONFIG_NAME" ipc call control ping >/dev/null 2>&1; then
        fail "Awtarchy Quickshell IPC is unavailable for config ${CONFIG_NAME}"
    fi

    monitor="$(focused_monitor)"
    [[ -n "$monitor" ]] || monitor='unavailable'

    printf '%s\n' 'Awtarchy content readiness baseline'
    printf 'Collected: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
    printf '%s\n' 'Read-only diagnostic property collector: yes'
    printf 'Focused monitor: %s\n' "$monitor"
    printf 'Cycles per surface: %s\n' "$CYCLES"
    printf 'Timeout: %sms\n' "$TIMEOUT_MS"
    printf 'Poll interval: %sms\n' "$POLL_MS"
    printf 'Settle delay: %sms\n' "$SETTLE_MS"
    printf '%s\n' 'Measurement: IPC open -> mapped window -> usable rendered content'
    printf '\n'

    collect_launcher
    collect_clipboard

    close_all
    printf 'Report path: %s\n' "$REPORT_PATH"
}

trap 'close_all >/dev/null 2>&1 || true' EXIT
collect_report | tee "$REPORT_PATH"
