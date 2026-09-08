#!/usr/bin/env bash
# Persist Awtarchy's preferred Hyprland submap across logins while preserving
# the existing runtime state-file contract used by Quickshell and launchers.

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}"
RUNTIME_FILE="${HYPR_SUBMAP_STATE_FILE:-${RUNTIME_DIR}/awtarchy-hypr-submap}"
PERSIST_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
PERSIST_FILE="${HYPR_SUBMAP_PERSIST_FILE:-${PERSIST_DIR}/hypr-submap}"

valid_submap() {
    case "${1:-}" in
        ""|noalt|mouse|vm) return 0 ;;
        *) return 1 ;;
    esac
}

read_state() {
    local file="$1" value=""
    if [[ -r "$file" ]]; then
        IFS= read -r value <"$file" || true
        value="${value//$'\r'/}"
        value="${value//$'\n'/}"
        value="${value//[[:space:]]/}"
    fi
    printf '%s' "$value"
}

write_persistent() {
    local value="$1"
    mkdir -p -- "$(dirname -- "$PERSIST_FILE")"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value" >"$PERSIST_FILE"
    else
        : >"$PERSIST_FILE"
    fi
}

normalize_persistent() {
    local value
    mkdir -p -- "$(dirname -- "$PERSIST_FILE")"
    [[ -e "$PERSIST_FILE" ]] || : >"$PERSIST_FILE"
    value="$(read_state "$PERSIST_FILE")"
    if ! valid_submap "$value"; then
        : >"$PERSIST_FILE"
        value=""
    fi
    printf '%s' "$value"
}

ensure_runtime_link() {
    local legacy_state="" target=""

    normalize_persistent >/dev/null
    mkdir -p -- "$(dirname -- "$RUNTIME_FILE")"

    if [[ -L "$RUNTIME_FILE" ]]; then
        target="$(readlink -f -- "$RUNTIME_FILE" 2>/dev/null || true)"
        if [[ "$target" == "$(readlink -f -- "$PERSIST_FILE")" ]]; then
            return 0
        fi
        rm -f -- "$RUNTIME_FILE"
    elif [[ -e "$RUNTIME_FILE" ]]; then
        legacy_state="$(read_state "$RUNTIME_FILE")"
        if valid_submap "$legacy_state"; then
            write_persistent "$legacy_state"
        else
            write_persistent ""
        fi
        rm -f -- "$RUNTIME_FILE"
        ln -s -- "$PERSIST_FILE" "$RUNTIME_FILE"
        return 2
    fi

    ln -s -- "$PERSIST_FILE" "$RUNTIME_FILE"
    return 0
}

restore_if_new_session() {
    local had_runtime=0 link_rc=0 value
    [[ -e "$RUNTIME_FILE" || -L "$RUNTIME_FILE" ]] && had_runtime=1

    ensure_runtime_link || link_rc=$?
    if (( link_rc == 2 )); then
        # Existing regular runtime state represented the already-active submap.
        return 0
    fi
    (( link_rc == 0 )) || return "$link_rc"
    (( had_runtime == 0 )) || return 0

    value="$(normalize_persistent)"
    case "$value" in
        noalt|mouse|vm)
            command -v hyprctl >/dev/null 2>&1 || return 0
            hyprctl dispatch "hl.dsp.submap(\"${value}\")" >/dev/null 2>&1 || true
            ;;
    esac
}

set_submap() {
    local value="$1" link_rc=0
    case "$value" in
        noalt|mouse|vm) ;;
        *)
            printf 'submap_state.sh: invalid submap: %s\n' "$value" >&2
            return 2
            ;;
    esac

    ensure_runtime_link || link_rc=$?
    (( link_rc == 0 || link_rc == 2 )) || return "$link_rc"
    write_persistent "$value"
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch "hl.dsp.submap(\"${value}\")" >/dev/null 2>&1 || true
    fi
}

reset_submap() {
    local link_rc=0
    ensure_runtime_link || link_rc=$?
    (( link_rc == 0 || link_rc == 2 )) || return "$link_rc"
    write_persistent ""
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || true
    fi
}

case "${1:-init}" in
    init|restore)
        restore_if_new_session
        ;;
    set)
        [[ $# -eq 2 ]] || {
            printf 'usage: %s set {noalt|mouse|vm}\n' "$0" >&2
            exit 2
        }
        set_submap "$2"
        ;;
    reset|off)
        reset_submap
        ;;
    current)
        normalize_persistent
        printf '\n'
        ;;
    *)
        printf 'usage: %s {init|restore|set {noalt|mouse|vm}|reset|current}\n' "$0" >&2
        exit 2
        ;;
esac
