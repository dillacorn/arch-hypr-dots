#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"

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

for stale in bridge-utils cheese termdown; do
    if grep -Eq "(^|[^[:alnum:]_.+-])${stale}([^[:alnum:]_.+-]|$)" <<<"$catalog"; then
        fail "stale Arch catalog package is still present: ${stale}"
    fi
done

grep -Eq '^[[:space:]]+termdown[[:space:]]*$' "$RECONCILER" \
    || fail "termdown is not tracked as a retired package"

grep -Fq 'for _ in "${arch_labels[@]}"; do arch_flags+=(1); done' "$RECONCILER" \
    || fail "missing Arch packages do not default selected"
grep -Fq 'for _ in "${aur_labels[@]}"; do aur_flags+=(1); done' "$RECONCILER" \
    || fail "missing AUR packages do not default selected"
grep -Fq 'flatpak_flags+=(1)' "$RECONCILER" \
    || fail "missing Flatpak apps do not default selected"

printf '%s\n' 'PASS: package catalog cleanup and reconciler defaults are current.'
