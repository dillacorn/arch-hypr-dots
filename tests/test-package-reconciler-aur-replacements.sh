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
state="${TMP}/installed-packages"
logfile="${TMP}/commands.log"
mkdir -p "$home/.local/state/awtarchy" "$fakebin"
printf '%s\n' 'is_laptop=false' >"$home/.local/state/awtarchy/hardware-state"
printf '%s\n' alacritty >"$state"

cat >"$runtime" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=()
declare -a PACKAGES_AUR=(alacritty-graphics)
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
    grep -Fxq -- "${2:-}" "$TEST_STATE"
    ;;
  -R)
    pkg="${@: -1}"
    grep -Fxv -- "$pkg" "$TEST_STATE" >"${TEST_STATE}.new" || true
    mv -- "${TEST_STATE}.new" "$TEST_STATE"
    ;;
  -S)
    pkg="${@: -1}"
    grep -Fxq -- "$pkg" "$TEST_STATE" || printf '%s\n' "$pkg" >>"$TEST_STATE"
    ;;
  *)
    exit 0
    ;;
esac
EOF_PACMAN
chmod +x "$fakebin/pacman"

cat >"$fakebin/yay" <<'EOF_YAY'
#!/usr/bin/env bash
set -euo pipefail
printf 'yay' >>"$TEST_LOG"
printf ' %q' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'yay v99-test'
  exit 0
fi
if [[ ${TEST_YAY_FAIL:-0} == 1 ]]; then
  exit 42
fi
pkg="${@: -1}"
grep -Fxq -- "$pkg" "$TEST_STATE" || printf '%s\n' "$pkg" >>"$TEST_STATE"
EOF_YAY
chmod +x "$fakebin/yay"

export TEST_LOG="$logfile"
export TEST_STATE="$state"
export PATH="$fakebin:/usr/bin:/bin"
export HOME="$home"
export USER=tester
export AWTARCHY_RUNTIME="$runtime"
export AWTARCHY_MANAGED_PACKAGES_FILE="${TMP}/managed-packages"

# Load function definitions only. Main execution begins at collect_state.
# shellcheck disable=SC1090
source <(sed '/^collect_state$/,$d' "$RECONCILER")

as_root() {
  "$@"
}
record_managed_packages() {
  :
}
forget_managed_packages() {
  :
}

if ! declare -F aur_replacement_source >/dev/null; then
  fail 'reconciler has no AUR replacement mapping function'
else
  replacement="$(aur_replacement_source alacritty-graphics || true)"
  [[ $replacement == alacritty ]] \
    || fail "expected alacritty-graphics to replace alacritty, got: ${replacement:-none}"
fi

if ! declare -F install_aur_package_with_replacement >/dev/null; then
  fail 'reconciler has no controlled AUR replacement installer'
else
  export AUR_HELPER=yay
  : >"$logfile"
  printf '%s\n' alacritty >"$state"
  unset TEST_YAY_FAIL

  if ! install_aur_package_with_replacement alacritty-graphics; then
    fail 'alacritty-graphics replacement unexpectedly failed'
  fi
  grep -Fxq alacritty-graphics "$state" \
    || fail 'alacritty-graphics was not installed'
  if grep -Fxq alacritty "$state"; then
    fail 'repo alacritty remained installed after successful replacement'
  fi

  remove_line="$(grep -nF 'pacman -R --noconfirm alacritty' "$logfile" | head -n1 | cut -d: -f1 || true)"
  install_line="$(grep -nF 'yay -S --needed --noconfirm alacritty-graphics' "$logfile" | head -n1 | cut -d: -f1 || true)"
  [[ -n $remove_line && -n $install_line && $remove_line -lt $install_line ]] \
    || fail 'repo alacritty was not removed immediately before installing alacritty-graphics'

  : >"$logfile"
  printf '%s\n' alacritty >"$state"
  export TEST_YAY_FAIL=1
  if (install_aur_package_with_replacement alacritty-graphics); then
    fail 'replacement install failure unexpectedly returned success'
  fi
  grep -Fxq alacritty "$state" \
    || fail 'repo alacritty was not restored after replacement failure'
  if grep -Fxq alacritty-graphics "$state"; then
    fail 'failed replacement incorrectly left alacritty-graphics installed'
  fi
  grep -Fq 'pacman -S --needed --noconfirm alacritty' "$logfile" \
    || fail 'rollback did not reinstall repo alacritty'
fi

if (( failures > 0 )); then
  exit 1
fi

printf 'PASS: AUR replacements are explicit and rollback-safe\n'
