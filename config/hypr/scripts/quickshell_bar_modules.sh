#!/usr/bin/env bash
# Persist per-display visibility for optional Awtarchy bar status modules.

set -Eeuo pipefail
IFS=$'\n\t'

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
STATE_LOCK_FILE="${STATE_FILE}.lock"
TMP_FILE=""

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell_bar_modules.sh: missing: %s\n' "$1" >&2
        return 127
    }
}

cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}
trap cleanup EXIT

validate_module() {
    case "$1" in
        cpu|temperature|memory) ;;
        *)
            printf 'quickshell_bar_modules.sh: invalid module: %s\n' "$1" >&2
            return 2
            ;;
    esac
}

validate_boolean() {
    case "$1" in
        true|false) ;;
        *)
            printf 'quickshell_bar_modules.sh: visibility must be true or false\n' >&2
            return 2
            ;;
    esac
}

require_state() {
    [[ -s "$STATE_FILE" ]] && jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1 || {
        printf 'quickshell_bar_modules.sh: shell state is unavailable: %s\n' "$STATE_FILE" >&2
        return 1
    }
}

new_tmp() {
    TMP_FILE="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
}

commit_tmp() {
    mv -f -- "$TMP_FILE" "$STATE_FILE"
    TMP_FILE=""
}

set_module() {
    local monitor="$1" module="$2" visible="$3"
    [[ -n "$monitor" ]] || {
        printf 'quickshell_bar_modules.sh: monitor is required\n' >&2
        return 2
    }
    validate_module "$module"
    validate_boolean "$visible"
    require_state

    new_tmp
    jq \
        --arg monitor "$monitor" \
        --arg module "$module" \
        --argjson visible "$visible" '
        .monitors = (if (.monitors | type) == "object" then .monitors else {} end)
        | .monitors[$monitor] = (if (.monitors[$monitor] | type) == "object"
            then .monitors[$monitor] else {} end)
        | .monitors[$monitor].modules = (if (.monitors[$monitor].modules | type) == "object"
            then .monitors[$monitor].modules else {} end)
        | .monitors[$monitor].modules[$module] = $visible
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

reset_modules() {
    local monitor="$1"
    [[ -n "$monitor" ]] || {
        printf 'quickshell_bar_modules.sh: monitor is required\n' >&2
        return 2
    }
    require_state

    new_tmp
    jq --arg monitor "$monitor" '
        if (.monitors | type) == "object" and (.monitors[$monitor] | type) == "object" then
            del(.monitors[$monitor].modules)
        else
            .
        end
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

usage() {
    printf 'usage: %s {set <MON> <cpu|temperature|memory> <true|false>|reset <MON>}\n' "${0##*/}" >&2
}

main() {
    need jq
    need flock
    mkdir -p -- "$(dirname -- "$STATE_FILE")"
    exec 8>"$STATE_LOCK_FILE"
    flock -x 8

    case "${1:-}" in
        set)
            [[ -n ${2:-} && -n ${3:-} && -n ${4:-} ]] || {
                usage
                return 2
            }
            set_module "$2" "$3" "$4"
            ;;
        reset)
            [[ -n ${2:-} ]] || {
                usage
                return 2
            }
            reset_modules "$2"
            ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
