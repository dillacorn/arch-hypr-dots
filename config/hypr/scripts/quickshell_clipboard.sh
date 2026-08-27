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
        && magick "$tmp" -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}>" "png:$png" >/dev/null 2>&1; then
        rm -f -- "$tmp"
        printf '%s\n' "$png"
        return 0
    fi

    rm -f -- "$tmp" "$png"
    return 1
}

list_items() {
    local raw label index=0 list_fd list_pid list_status=0

    : >"$RAW_FILE"
    coproc AWTARCHY_CLIPHIST_LIST {
        CLIPHIST_PREVIEW_WIDTH="$PREVIEW_WIDTH" cliphist list
    }
    list_pid="$AWTARCHY_CLIPHIST_LIST_PID"
    exec {list_fd}<&"${AWTARCHY_CLIPHIST_LIST[0]}"

    while (( index < LIST_LIMIT )) && IFS= read -r raw <&"$list_fd"; do
        printf '%s\n' "$raw" >>"$RAW_FILE"
        label="$(printf '%s' "$raw" | strip_id_line)"

        jq -cn \
            --argjson index "$index" \
            --arg label "$label" \
            --argjson binary "$(is_binary_row "$raw" && printf true || printf false)" \
            '{index:$index,label:$label,thumb:"",binary:$binary}'

        ((index += 1)) || true
    done

    exec {list_fd}<&-
    if (( index >= LIST_LIMIT )) && kill -0 "$list_pid" 2>/dev/null; then
        kill "$list_pid" 2>/dev/null || true
        wait "$list_pid" 2>/dev/null || true
        return 0
    fi

    wait "$list_pid" || list_status=$?
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

case "${1:-list}" in
    list) list_items ;;
    decode) decode_item "${2:-}" ;;
    thumb) thumbnail_item "${2:-}" ;;
    select) select_item "${2:-}" ;;
    *)
        printf 'usage: %s [list|decode INDEX|thumb INDEX|select INDEX]\n' "$0" >&2
        exit 2
        ;;
esac
