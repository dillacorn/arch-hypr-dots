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
logfile="${TMP}/commands.log"
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
printf 'pacman' >>"$TEST_LOG"
printf ' %q' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
case "${1:-}" in
  -Q)
    case "${2:-}" in
      ly|yay) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  -U)
    cat >"$TEST_FAKEBIN/yay" <<'EOF_YAY_FIXED'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'yay v99-rebuilt'
  exit 0
fi
exit 0
EOF_YAY_FIXED
    chmod +x "$TEST_FAKEBIN/yay"
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF_PACMAN
chmod +x "$fakebin/pacman"

cat >"$fakebin/yay" <<'EOF_YAY_BROKEN'
#!/usr/bin/env bash
printf '%s\n' 'yay: error while loading shared libraries: libalpm.so.15: cannot open shared object file: No such file or directory' >&2
exit 127
EOF_YAY_BROKEN
chmod +x "$fakebin/yay"

cat >"$fakebin/git" <<'EOF_GIT'
#!/usr/bin/env bash
set -euo pipefail
printf 'git' >>"$TEST_LOG"
printf ' %q' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
[[ ${1:-} == clone ]] || exit 90
dest="${@: -1}"
mkdir -p "$dest"
printf '%s\n' '# test PKGBUILD placeholder' >"$dest/PKGBUILD"
EOF_GIT
chmod +x "$fakebin/git"

cat >"$fakebin/makepkg" <<'EOF_MAKEPKG'
#!/usr/bin/env bash
set -euo pipefail
printf 'makepkg' >>"$TEST_LOG"
printf ' %q' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
touch "$PWD/yay-99-1-x86_64.pkg.tar.zst"
EOF_MAKEPKG
chmod +x "$fakebin/makepkg"

cat >"$fakebin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
exit 1
EOF_SYSTEMCTL
chmod +x "$fakebin/systemctl"

export TEST_LOG="$logfile"
export TEST_FAKEBIN="$fakebin"
export PATH="$fakebin:/usr/bin:/bin"
export HOME="$home"
export USER=tester
export AWTARCHY_RUNTIME="$runtime"
export AWTARCHY_MANAGED_PACKAGES_FILE="${TMP}/managed-packages"

# Load real reconciler functions without executing the interactive main flow.
# The standalone collect_state call is the boundary between definitions and main.
# shellcheck disable=SC1090
source <(sed '/^collect_state$/,$d' "$RECONCILER")

# Keep the test unprivileged while exercising the real helper-rebuild path.
as_root() {
  "$@"
}

if ! declare -F ensure_aur_helper >/dev/null; then
  fail 'reconciler has no AUR-helper recovery function'
else
  AUR_HELPER=""
  if ! ensure_aur_helper; then
    fail 'broken installed AUR helper was not repaired'
  elif [[ $AUR_HELPER != yay ]]; then
    fail "expected repaired yay helper, got: ${AUR_HELPER:-none}"
  elif ! yay --version >/dev/null 2>&1; then
    fail 'repaired yay is still unusable'
  fi
fi

if ! grep -Fq 'git clone' "$logfile" 2>/dev/null; then
  fail 'broken yay did not trigger an AUR source rebuild'
fi
if ! grep -Fq 'pacman -U' "$logfile" 2>/dev/null; then
  fail 'rebuilt yay package was not installed with pacman -U'
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

printf 'PASS: package reconciler repairs broken AUR helpers and interrupted Ly setup\n'
