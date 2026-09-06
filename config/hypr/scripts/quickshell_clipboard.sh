#!/usr/bin/env bash
# Awtarchy Quickshell clipboard backend.
# Provides the cliphist data model and thumbnail cache without a dmenu launcher.

set -euo pipefail
export LC_ALL=C

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
RUNTIME_DIR="${RUNTIME_BASE}/awtarchy-quickshell"
RAW_FILE="${RUNTIME_DIR}/clipboard.raw"
THUMB_DIR="${RUNTIME_DIR}/clipboard-thumbs"
LIST_LIMIT="${LIST_LIMIT:-60}"
PREVIEW_WIDTH="${PREVIEW_WIDTH:-1000}"
THUMB_SIZE="${THUMB_SIZE:-512}"
DECODE_TIMEOUT="${DECODE_TIMEOUT:-0.70s}"
THUMB_TIMEOUT="${THUMB_TIMEOUT:-2s}"
LIST_PRODUCER_PID=""
LIST_PRODUCER_FD=""

mkdir -p "$RUNTIME_DIR" "$THUMB_DIR"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell_clipboard: missing dependency: %s\n' "$1" >&2
        exit 127
    }
}

need cliphist
need wl-copy
need jq
need sha1sum
need timeout
need sed
need grep

cleanup_list_producer() {
    local attempt producer_pid="${LIST_PRODUCER_PID:-}"

    trap - EXIT HUP INT TERM
    if [[ -n "${LIST_PRODUCER_FD:-}" ]]; then
        exec {LIST_PRODUCER_FD}<&- 2>/dev/null || true
        LIST_PRODUCER_FD=""
    fi

    if [[ -n "$producer_pid" ]] && kill -0 "$producer_pid" 2>/dev/null; then
        kill -TERM "$producer_pid" 2>/dev/null || true
        for (( attempt = 0; attempt < 20; attempt += 1 )); do
            kill -0 "$producer_pid" 2>/dev/null || break
            sleep 0.01
        done
        kill -KILL "$producer_pid" 2>/dev/null || true
    fi
    if [[ -n "$producer_pid" ]]; then
        wait "$producer_pid" 2>/dev/null || true
    fi
    LIST_PRODUCER_PID=""
}

arm_list_producer_cleanup() {
    trap cleanup_list_producer EXIT
    trap 'cleanup_list_producer; exit 129' HUP
    trap 'cleanup_list_producer; exit 130' INT
    trap 'cleanup_list_producer; exit 143' TERM
}

strip_id_line() {
    sed -E 's/^[0-9]+\t//'
}

is_binary_row() {
    local row="${1:-}"
    grep -qiE '(\[image\]|\[binary\]|\[\[[[:space:]]*(binary|image)[[:space:]]+data)' <<<"$row"
}

make_thumb() {
    local raw="$1" key png tmp

    command -v magick >/dev/null 2>&1 || return 1

    key="$(printf '%s' "$raw" | sha1sum | awk '{print $1}')"
    png="${THUMB_DIR}/${key}.png"
    [[ -s "$png" ]] && { printf '%s\n' "$png"; return 0; }

    tmp="${THUMB_DIR}/${key}.tmp"
    rm -f -- "$tmp"

    if timeout "$DECODE_TIMEOUT" cliphist decode <<<"$raw" >"$tmp" 2>/dev/null \
        && [[ -s "$tmp" ]] \
        && timeout --kill-after=1s "$THUMB_TIMEOUT" magick \
            -limit memory 256MiB -limit map 256MiB -limit disk 512MiB \
            "${tmp}[0]" -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}>" "png:$png" >/dev/null 2>&1; then
        rm -f -- "$tmp"
        printf '%s\n' "$png"
        return 0
    fi

    rm -f -- "$tmp" "$png"
    return 1
}

list_items() {
    local raw label index=0 list_status=0

    : >"$RAW_FILE"
    arm_list_producer_cleanup
    coproc AWTARCHY_CLIPHIST_LIST {
        export CLIPHIST_PREVIEW_WIDTH="$PREVIEW_WIDTH"
        exec cliphist list
    }
    LIST_PRODUCER_PID="$AWTARCHY_CLIPHIST_LIST_PID"
    exec {LIST_PRODUCER_FD}<&"${AWTARCHY_CLIPHIST_LIST[0]}"

    while (( index < LIST_LIMIT )) \
            && IFS= read -r raw <&"$LIST_PRODUCER_FD"; do
        printf '%s\n' "$raw" >>"$RAW_FILE"
        label="$(printf '%s' "$raw" | strip_id_line)"

        jq -cn \
            --argjson index "$index" \
            --arg label "$label" \
            --argjson binary "$(is_binary_row "$raw" && printf true || printf false)" \
            '{index:$index,label:$label,thumb:"",binary:$binary}'

        ((index += 1)) || true
    done

    exec {LIST_PRODUCER_FD}<&-
    LIST_PRODUCER_FD=""
    if (( index >= LIST_LIMIT )) \
            && kill -0 "$LIST_PRODUCER_PID" 2>/dev/null; then
        cleanup_list_producer
        return 0
    fi

    wait "$LIST_PRODUCER_PID" || list_status=$?
    LIST_PRODUCER_PID=""
    trap - EXIT HUP INT TERM
    return "$list_status"
}

decode_item() {
    local index="${1:-}"
    local raw

    [[ "$index" =~ ^[0-9]+$ ]] || exit 2
    [[ -r "$RAW_FILE" ]] || exit 1

    raw="$(sed -n "$((index + 1))p" "$RAW_FILE")"
    [[ -n "$raw" ]] || exit 1
    is_binary_row "$raw" && exit 3

    cliphist decode <<<"$raw"
}

thumbnail_item() {
    local index="${1:-}"
    local raw

    [[ "$index" =~ ^[0-9]+$ ]] || exit 2
    [[ -r "$RAW_FILE" ]] || exit 1

    raw="$(sed -n "$((index + 1))p" "$RAW_FILE")"
    [[ -n "$raw" ]] || exit 1
    is_binary_row "$raw" || exit 3

    make_thumb "$raw"
}

select_item() {
    local index="${1:-}"
    local raw

    [[ "$index" =~ ^[0-9]+$ ]] || exit 2
    [[ -r "$RAW_FILE" ]] || exit 1

    raw="$(sed -n "$((index + 1))p" "$RAW_FILE")"
    [[ -n "$raw" ]] || exit 1

    cliphist decode <<<"$raw" | wl-copy -n
}

delete_item() {
    local index="${1:-}"
    local raw key

    [[ "$index" =~ ^[0-9]+$ ]] || exit 2
    [[ -r "$RAW_FILE" ]] || exit 1

    raw="$(sed -n "$((index + 1))p" "$RAW_FILE")"
    [[ -n "$raw" ]] || exit 1

    cliphist delete <<<"$raw"
    key="$(printf '%s' "$raw" | sha1sum | awk '{print $1}')"
    rm -f -- "${THUMB_DIR}/${key}.png" "${THUMB_DIR}/${key}.tmp"
}

case "${1:-list}" in
    list) list_items ;;
    decode) decode_item "${2:-}" ;;
    thumb) thumbnail_item "${2:-}" ;;
    select) select_item "${2:-}" ;;
    delete) delete_item "${2:-}" ;;
    *)
        printf 'usage: %s [list|decode INDEX|thumb INDEX|select INDEX|delete INDEX]\n' "$0" >&2
        exit 2
        ;;
esac
