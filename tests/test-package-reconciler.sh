#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
LAUNCHER="${ROOT}/local/bin/awtarchy"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f $RECONCILER ]] || fail "package reconciler source is missing"
[[ -x $RECONCILER ]] || fail "package reconciler source is not executable"
bash -n "$RECONCILER"

grep -Fq 'awtarchy packages' "$LAUNCHER" \
  || fail "launcher help does not expose awtarchy packages"
grep -Fq 'Reconcile packages (install current / remove replaced)' "$LAUNCHER" \
  || fail "maintenance menu does not expose package reconciliation"
grep -Fq 'new_package_reconciler=' "$LAUNCHER" \
  || fail "self-update does not install the package reconciler"

home="${TMP}/home"
fakebin="${TMP}/fakebin"
managed="${TMP}/managed-packages"
runtime="${TMP}/awtarchy-runtime.sh"
mkdir -p "$home/.local/state/awtarchy" "$fakebin"
printf '%s\n' 'is_laptop=true' >"$home/.local/state/awtarchy/hardware-state"
printf '%s\n' waybar >"$managed"

cat >"$runtime" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=(
  "Window Management:quickshell wl-clipboard cliphist optional-window-tool"
  "Utilities:upower polkit python-gobject jq"
)
declare -a PACKAGES_AUR=(
  smtty
)
declare -a FLATPAK_CATALOG=(
  "1|Flatseal|com.github.tchx84.Flatseal"
  "0|Moonlight|com.moonlight_stream.Moonlight"
)
EOF_RUNTIME

cat >"$fakebin/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
installed=(quickshell wl-clipboard upower playerctl hyprland-qt-support polkit python-gobject jq waybar mako)
case "${1:-}" in
  -Qq)
    printf '%s\n' "${installed[@]}"
    ;;
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
set -euo pipefail
case "${1:-}" in
  is-enabled|is-active) exit 1 ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
chmod +x "$fakebin/systemctl"

cat >"$fakebin/flatpak" <<'EOF_FLATPAK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *'list --app --columns=application'* ]]; then
  exit 0
fi
exit 0
EOF_FLATPAK
chmod +x "$fakebin/flatpak"

output="$({
  PATH="$fakebin:/usr/bin:/bin" \
  HOME="$home" \
  USER=tester \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_MANAGED_PACKAGES_FILE="$managed" \
  "$RECONCILER" --review
} 2>&1)"

printf '%s\n' "$output" | grep -Fq 'System type: laptop' \
  || fail "review did not reuse saved laptop state"
printf '%s\n' "$output" | grep -Fq 'cliphist' \
  || fail "review did not identify missing cliphist"
printf '%s\n' "$output" | grep -Fq 'waybar' \
  || fail "review did not identify managed retired waybar"
printf '%s\n' "$output" | grep -Fq 'mako' \
  || fail "review did not report installed unowned retired mako"
printf '%s\n' "$output" | grep -Fq 'Ly TTY login manager: not installed' \
  || fail "review did not report Ly state"
printf '%s\n' "$output" | grep -Fq 'Arch catalog packages:' \
  || fail "review did not load the current runtime package catalog"
printf '%s\n' "$output" | grep -Fq 'AUR catalog packages:' \
  || fail "review did not load the current runtime AUR catalog"
printf '%s\n' "$output" | grep -Fq 'Flatpak catalog apps:' \
  || fail "review did not load the current runtime Flatpak catalog"

printf 'PASS: package reconciler review and launcher contracts\n'
