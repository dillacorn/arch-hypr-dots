#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

catalog="$({
    awk '
        /^declare -a PKG_GROUPS=\(/ { inside=1; next }
        inside && /^[[:space:]]*\)[[:space:]]*$/ { exit }
        inside { print }
    ' "$RUNTIME"
})"

for stale in bridge-utils cheese; do
    if grep -Eq "(^|[^[:alnum:]_.+-])${stale}([^[:alnum:]_.+-]|$)" <<<"$catalog"; then
        fail "stale Arch catalog package is still present: ${stale}"
    fi
done

printf '%s\n' 'PASS: stale Arch package catalog entries are absent.'
