#!/usr/bin/env bash
# Apply short-lived capture locks for sensitive Quickshell views.

set -euo pipefail

surface="${1:-}"
action="${2:-}"

case "$surface" in
    network) ;;
    *)
        printf 'Unsupported sensitive capture surface: %s\n' "$surface" >&2
        exit 2
        ;;
esac

case "$action" in
    lock|unlock) ;;
    *)
        printf 'Usage: %s network {lock|unlock}\n' "$0" >&2
        exit 2
        ;;
esac

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
RUNTIME_ROOT="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy-runtime}"
LOCK_DIR="${RUNTIME_ROOT}/awtarchy"
LOCK_FILE="${LOCK_DIR}/network-sensitive-capture.lock"
RUNTIME_RULES="${CONFIG_HOME}/hypr/scripts/quickshell_runtime_rules.sh"

[[ -x "$RUNTIME_RULES" ]] || {
    printf 'Missing Quickshell runtime rules helper: %s\n' "$RUNTIME_RULES" >&2
    exit 1
}

case "$action" in
    lock)
        umask 077
        mkdir -p -- "$LOCK_DIR"
        : >"$LOCK_FILE"
        ;;
    unlock)
        rm -f -- "$LOCK_FILE"
        ;;
esac

exec "$RUNTIME_RULES"
