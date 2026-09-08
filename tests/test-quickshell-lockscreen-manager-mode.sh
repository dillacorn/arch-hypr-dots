#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER="${ROOT}/config/hypr/scripts/awtarchy_lock.sh"

[[ -f "$MANAGER" ]] || {
    printf 'FAIL: lock manager is missing: %s\n' "$MANAGER" >&2
    exit 1
}

[[ -x "$MANAGER" ]] || {
    printf 'FAIL: lock manager is not executable: %s\n' "$MANAGER" >&2
    exit 1
}

printf 'PASS: lock manager is executable\n'
