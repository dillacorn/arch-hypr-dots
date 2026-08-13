#!/usr/bin/env bash
set -euo pipefail

value="${1:-}"
case "$value" in
    true|false) ;;
    *) exit 2 ;;
esac

exec hyprctl eval "hl.config({ input = { numlock_by_default = ${value} } })"
