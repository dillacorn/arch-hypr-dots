#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

array_body() {
    local name="$1"
    awk -v name="$name" '
        $0 ~ "^declare -a " name "=\\(" { inside=1; next }
        inside && /^[[:space:]]*\)[[:space:]]*$/ { exit }
        inside { print }
    ' "$RUNTIME"
}

arch_catalog="$(array_body PKG_GROUPS)"
optional_arch="$(array_body OPTIONAL_ARCH_PACKAGES)"
required_aur="$(array_body PACKAGES_AUR)"
optional_aur="$(array_body OPTIONAL_AUR_PACKAGES)"
flatpak_catalog="$(array_body FLATPAK_CATALOG)"

for stale in bridge-utils cheese termdown; do
    if grep -Eq "(^|[^[:alnum:]_.+-])${stale}([^[:alnum:]_.+-]|$)" <<<"$arch_catalog"; then
        fail "stale Arch catalog package is still present: ${stale}"
    fi
done

grep -Eq '^[[:space:]]+termdown[[:space:]]*$' "$RECONCILER" \
    || fail "termdown is not tracked as a retired package"

grep -Eq '(^|[[:space:]])moonlight-qt([[:space:]]|$)' <<<"$optional_arch" \
    || fail "moonlight-qt is not an optional native Arch package"
if grep -Eq '(^|[[:space:]])moonlight-qt([[:space:]]|$)' <<<"$arch_catalog"; then
    fail "moonlight-qt is in the default-selected Arch catalog instead of the optional catalog"
fi

grep -Eq '(^|[[:space:]])vesktop-bin([[:space:]]|$)' <<<"$optional_aur" \
    || fail "vesktop-bin is not an optional native AUR package"
if grep -Eq '(^|[[:space:]])vesktop-bin([[:space:]]|$)' <<<"$required_aur"; then
    fail "vesktop-bin is in the default-selected AUR catalog instead of the optional catalog"
fi

if grep -Eq 'dev\.vencord\.Vesktop|com\.moonlight_stream\.Moonlight|Vesktop|Moonlight' <<<"$flatpak_catalog"; then
    fail "Vesktop or Moonlight is still listed in the Flatpak catalog"
fi
grep -Fq '"0|Flatseal|com.github.tchx84.Flatseal"' <<<"$flatpak_catalog" \
    || fail "Flatseal is not the sole optional Flatpak catalog app"

# Existing current packages still default selected; the three optional apps do not.
grep -Fq 'ARCH_SELECTED_FLAGS+=("0")' "$RUNTIME" \
    || fail "installer has no unchecked optional Arch package path"
grep -Fq 'AUR_SELECTED_FLAGS+=("0")' "$RUNTIME" \
    || fail "installer has no unchecked optional AUR package path"
grep -Fq 'FLATPAK_SELECTED_FLAGS+=("$selected")' "$RUNTIME" \
    || fail "installer does not honor Flatpak catalog default-selection metadata"

grep -Fq 'array_contains "$pkg" "${OPTIONAL_ARCH_CATALOG[@]}"' "$RECONCILER" \
    || fail "reconciler does not recognize optional Arch packages"
grep -Fq 'array_contains "$pkg" "${OPTIONAL_AUR_CATALOG[@]}"' "$RECONCILER" \
    || fail "reconciler does not recognize optional AUR packages"

printf '%s\n' 'PASS: package catalog cleanup and optional native app defaults are current.'
