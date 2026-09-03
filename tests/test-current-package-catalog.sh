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

contains_token() {
    local token="$1" body="$2"
    grep -Eq "(^|[^[:alnum:]_.+-])${token}([^[:alnum:]_.+-]|$)" <<<"$body"
}

arch_catalog="$(array_body PKG_GROUPS)"
optional_arch="$(array_body OPTIONAL_ARCH_PACKAGES)"
virt_stack="$(array_body VIRT_MANAGER_PACKAGES)"
required_aur="$(array_body PACKAGES_AUR)"
optional_aur="$(array_body OPTIONAL_AUR_PACKAGES)"
flatpak_catalog="$(array_body FLATPAK_CATALOG)"

for stale in bridge-utils cheese termdown; do
    if contains_token "$stale" "$arch_catalog"; then
        fail "stale Arch catalog package is still present: ${stale}"
    fi
done

grep -Eq '^[[:space:]]+termdown[[:space:]]*$' "$RECONCILER" \
    || fail "termdown is not tracked as a retired package"

for pkg in moonlight-qt mousai gamemode gamescope virt-manager qemu qemu-hw-usb-host virt-viewer vde2 libguestfs swtpm; do
    contains_token "$pkg" "$optional_arch" \
        || fail "${pkg} is not in the optional Arch package catalog"
    if contains_token "$pkg" "$arch_catalog"; then
        fail "${pkg} is still in the default-selected Arch package catalog"
    fi
done

for pkg in virt-manager qemu qemu-hw-usb-host virt-viewer vde2 libguestfs swtpm; do
    contains_token "$pkg" "$virt_stack" \
        || fail "${pkg} is not linked to the virt-manager package bundle"
done

for pkg in base-devel archlinux-keyring bubblewrap gnupg coreutils clang ninja go rust firefox snapshot zathura zathura-pdf-mupdf speedcrunch pcmanfm-qt xarchiver wireguard-tools cmatrix asciiquarium figlet espeak-ng; do
    contains_token "$pkg" "$arch_catalog" \
        || fail "expected default-selected Arch package is missing: ${pkg}"
done

contains_token vesktop-bin "$optional_aur" \
    || fail "vesktop-bin is not an optional native AUR package"
if contains_token vesktop-bin "$required_aur"; then
    fail "vesktop-bin is in the default-selected AUR catalog instead of the optional catalog"
fi
for pkg in smtty hyprmoncfg-bin obs-pipewire-audio-capture-bin; do
    contains_token "$pkg" "$required_aur" \
        || fail "expected default-selected AUR package is missing: ${pkg}"
done

if grep -Eq 'dev\.vencord\.Vesktop|com\.moonlight_stream\.Moonlight|Vesktop|Moonlight' <<<"$flatpak_catalog"; then
    fail "Vesktop or Moonlight is still listed in the Flatpak catalog"
fi
grep -Fq '"0|Flatseal|com.github.tchx84.Flatseal"' <<<"$flatpak_catalog" \
    || fail "Flatseal is not the sole optional Flatpak catalog app"
[[ $(grep -Ec '^[[:space:]]*"[01]\|[^|]+\|[^|]+"[[:space:]]*$' <<<"$flatpak_catalog") -eq 1 ]] \
    || fail "Flatpak catalog contains apps other than optional Flatseal"

# Optional defaults are inserted before the normal default-selected catalog so
# users see unchecked choices first.
grep -Fq 'for pkg in "${OPTIONAL_ARCH_PACKAGES[@]}"; do' "$RUNTIME" \
    || fail "installer does not prepend optional Arch packages"
grep -Fq 'ARCH_SELECTED_FLAGS+=("0")' "$RUNTIME" \
    || fail "installer has no unchecked optional Arch package path"
grep -Fq 'for pkg in "${OPTIONAL_AUR_PACKAGES[@]}"; do' "$RUNTIME" \
    || fail "installer does not prepend optional AUR packages"
grep -Fq 'AUR_SELECTED_FLAGS+=("0")' "$RUNTIME" \
    || fail "installer has no unchecked optional AUR package path"
grep -Fq 'FLATPAK_SELECTED_FLAGS+=("${selected}")' "$RUNTIME" \
    || fail "installer does not honor Flatpak catalog default-selection metadata"

# Every installer package list gets global select/clear controls, while Arch
# categories retain their existing category-level controls.
grep -Fq 'Select all in this list' "$RUNTIME" \
    || fail "package picker has no global Select all control"
grep -Fq 'Clear all in this list' "$RUNTIME" \
    || fail "package picker has no global Clear all control"
grep -Fq 'Select all in this category' "$RUNTIME" \
    || fail "Arch category picker lost its category-level Select all control"

# Selecting virt-manager links the explicit virtualization stack.
grep -Fq 'sync_virt_manager_bundle_selection' "$RUNTIME" \
    || fail "installer does not link virt-manager to its virtualization stack"

# Reconciler must distinguish optional apps from real package drift.
grep -Fq 'OPTIONAL_ARCH_CATALOG' "$RECONCILER" \
    || fail "reconciler does not load optional Arch packages"
grep -Fq 'OPTIONAL_AUR_CATALOG' "$RECONCILER" \
    || fail "reconciler does not load optional AUR packages"
grep -Fq 'MISSING_OPTIONAL_ARCH' "$RECONCILER" \
    || fail "reconciler does not track missing optional Arch packages separately"
grep -Fq 'MISSING_OPTIONAL_AUR' "$RECONCILER" \
    || fail "reconciler does not track missing optional AUR packages separately"
grep -Fq 'MISSING_OPTIONAL_FLATPAK_IDS' "$RECONCILER" \
    || fail "reconciler does not track missing optional Flatpak apps separately"
grep -Fq 'vesktop|vesktop-bin' "$RECONCILER" \
    || fail "reconciler does not accept native Vesktop package equivalents"

printf '%s\n' 'PASS: package catalog cleanup, optional defaults, and native app sources are current.'
