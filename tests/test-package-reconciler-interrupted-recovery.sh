#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

home="${TMP}/home"
fakebin="${TMP}/fakebin"
runtime="${TMP}/awtarchy-runtime.sh"
mkdir -p "$home/.local/share/awtarchy" "$home/.local/state/awtarchy" "$fakebin"
printf '%s\n' 'is_laptop=true' >"$home/.local/state/awtarchy/hardware-state"

cat >"$runtime" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=(
  "Window Management:quickshell wl-clipboard cliphist"
  "Utilities:upower polkit python-gobject jq"
)
declare -a PACKAGES_AUR=(smtty)
declare -a FLATPAK_CATALOG=()
EOF_RUNTIME

cat >"$fakebin/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  -Q)
    [[ ${2:-} == ly ]]
    ;;
  *)
    exit 0
    ;;
esac
EOF_PACMAN
chmod +x "$fakebin/pacman"

cat >"$fakebin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
exit 1
EOF_SYSTEMCTL
chmod +x "$fakebin/systemctl"

export PATH="$fakebin:/usr/bin:/bin"
export HOME="$home"
export USER=tester
export AWTARCHY_RUNTIME="$runtime"
export AWTARCHY_MANAGED_PACKAGES_FILE="${TMP}/managed-packages"
export AWTARCHY_TEST_MODE=1
export AWTARCHY_AUR_SCAN_BIN="${TMP}/missing-aur-scan"

# Load real reconciler functions without executing the interactive main flow.
# The standalone collect_state call is the boundary between definitions and main.
# shellcheck disable=SC1090
source <(sed '/^collect_state$/,$d' "$RECONCILER")

if ! declare -F ensure_aur_scanner >/dev/null; then
  fail 'reconciler has no aur-scanner preparation function'
elif ensure_aur_scanner; then
  fail 'missing aur-scan test binary incorrectly passed scanner preparation'
fi

if declare -F ensure_aur_helper >/dev/null || declare -F rebuild_aur_helper >/dev/null; then
  fail 'obsolete AUR-helper recovery machinery still exists'
fi
if grep -Fq 'Rebuilding broken AUR helper' "$RECONCILER"; then
  fail 'reconciler still owns broken yay/paru rebuild behavior'
fi
if grep -Eq 'aur\.archlinux\.org/(yay|paru)\.git|pacman[[:space:]]+-U.*(yay|paru)' "$RECONCILER"; then
  fail 'reconciler still rebuilds or reinstalls AUR helpers'
fi

if ! declare -F choose_ly_action >/dev/null; then
  fail 'reconciler has no interrupted Ly setup recovery action'
else
  confirm_yes_no() { return 0; }
  export LY_STATUS='installed, not enabled on tty2'
  install_ly=0
  enable_ly=0
  choose_ly_action
  (( install_ly == 0 )) || fail 'already-installed Ly was incorrectly scheduled for reinstall'
  (( enable_ly == 1 )) || fail 'installed-but-disabled Ly was not scheduled for tty2 enablement'
fi

if (( failures > 0 )); then
  exit 1
fi

printf 'PASS: package reconciler leaves AUR helper repair upstream and still recovers interrupted Ly setup\n'
