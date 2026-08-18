#!/usr/bin/env bash
# Persist application launch counts for the Quickshell launcher.

set -euo pipefail

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="${CACHE_HOME}/awtarchy"
STATE_FILE="${STATE_DIR}/launcher-usage.json"
LOCK_FILE="${STATE_FILE}.lock"
TMP_FILE=""

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell_launcher_usage.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}

trap cleanup EXIT

need jq
need flock

record_launch() {
    local entry_id="$1"
    [[ -n "$entry_id" ]] || {
        printf 'desktop entry id is required\n' >&2
        exit 2
    }

    mkdir -p -- "$STATE_DIR"
    exec 9>"$LOCK_FILE"
    flock 9

    if [[ ! -s "$STATE_FILE" ]] || ! jq -e 'type == "object" and (.launches | type == "object")' "$STATE_FILE" >/dev/null 2>&1; then
        printf '%s\n' '{"version":1,"launches":{}}' >"$STATE_FILE"
    fi

    TMP_FILE="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
    jq --arg entry_id "$entry_id" '
        .version = 1
        | .launches = (if (.launches | type) == "object" then .launches else {} end)
        | .launches[$entry_id] = (
            ((.launches[$entry_id] // 0)
                | if type == "number" and . >= 0 then floor else 0 end) + 1
          )
    ' "$STATE_FILE" >"$TMP_FILE"
    mv -f -- "$TMP_FILE" "$STATE_FILE"
    TMP_FILE=""
}

case "${1:-}" in
    record)
        [[ $# -eq 2 ]] || {
            printf 'usage: %s record DESKTOP_ENTRY_ID\n' "${0##*/}" >&2
            exit 2
        }
        record_launch "$2"
        ;;
    *)
        printf 'usage: %s record DESKTOP_ENTRY_ID\n' "${0##*/}" >&2
        exit 2
        ;;
esac
