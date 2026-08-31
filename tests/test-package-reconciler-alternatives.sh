#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

home="${TMP}/home"
fakebin="${TMP}/fakebin"
runtime="${TMP}/awtarchy-runtime.sh"
mkdir -p "$home/.local/state/awtarchy" "$fakebin"
printf '%s\n' 'is_laptop=false' >"$home/.local/state/awtarchy/hardware-state"

cat >"$runtime" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=(
  "Window Management:quickshell wl-clipboard cliphist"
  "Utilities:upower polkit python-gobject jq zathura-pdf-mupdf optional-window-tool"
)
declare -a PACKAGES_AUR=()
declare -a FLATPAK_CATALOG=()
EOF_RUNTIME

cat >"$fakebin/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
installed=(
  quickshell
  wl-clipboard
  cliphist
  upower
  playerctl
  hyprland-qt-support
  polkit
  python-gobject
  jq
  zathura-pdf-poppler
)
case "${1:-}" in
  -Q)
    needle="${2:-}"
    for pkg in "${installed[@]}"; do
      [[ $pkg == "$needle" ]] && exit 0
    done
    exit 1
    ;;
  *)
    printf 'unexpected pacman invocation: %q' "$@" >&2
    printf '\n' >&2
    exit 90
    ;;
esac
EOF_PACMAN
chmod +x "$fakebin/pacman"

cat >"$fakebin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
exit 1
EOF_SYSTEMCTL
chmod +x "$fakebin/systemctl"

output="$({
  PATH="$fakebin:/usr/bin:/bin" \
  HOME="$home" \
  USER=tester \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_MANAGED_PACKAGES_FILE="${TMP}/managed-packages" \
  "$RECONCILER" --review
} 2>&1)"

printf '%s\n' "$output" | grep -Fq 'optional-window-tool' \
  || fail "review did not load ordinary missing catalog packages"
if printf '%s\n' "$output" | grep -Fq 'zathura-pdf-mupdf'; then
  fail "installed zathura-pdf-poppler did not satisfy the Zathura PDF backend family"
fi

printf 'PASS: installed package alternatives satisfy reconciliation families\n'
