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
state="${TMP}/installed-packages"
runtime="${TMP}/awtarchy-runtime.sh"
scan_log="${TMP}/aur-scan.log"
mkdir -p "$home" "$fakebin"
: >"$state"
: >"$scan_log"

cat >"$runtime" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=()
declare -a PACKAGES_AUR=()
declare -a FLATPAK_CATALOG=()
EOF_RUNTIME

cat >"$fakebin/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -Q ]]; then
  grep -Fxq -- "${2:-}" "$TEST_STATE"
  exit
fi
exit 0
EOF_PACMAN
chmod +x "$fakebin/pacman"

cat >"$fakebin/aur-scan" <<'EOF_SCAN'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'aur-scan test'
  exit 0
fi
{
  printf 'aur-scan'
  printf ' %q' "$@"
  printf '\n'
} >>"$TEST_SCAN_LOG"
if [[ ${1:-} != install ]]; then
  exit 90
fi
pkg="${2:-}"
if [[ $pkg == awtwall ]]; then
  exit 1
fi
printf '%s\n' "$pkg" >>"$TEST_STATE"
EOF_SCAN
chmod +x "$fakebin/aur-scan"

export TEST_STATE="$state"
export TEST_SCAN_LOG="$scan_log"
export AWTARCHY_AUR_SCAN_BIN="$fakebin/aur-scan"
export PATH="$fakebin:/usr/bin:/bin"
export HOME="$home"
export AWTARCHY_RUNTIME="$runtime"

# Load function definitions only. Main execution begins at collect_state.
# shellcheck disable=SC1090
source <(sed '/^collect_state$/,$d' "$RECONCILER")

if ! declare -F aur_package_satisfied >/dev/null; then
  fail 'reconciler has no installer-aligned AUR package satisfaction function'
else
  printf '%s\n' alacritty >"$state"
  aur_package_satisfied alacritty-graphics \
    || fail 'installed alacritty did not satisfy alacritty-graphics'

  printf '%s\n' alacritty-graphics >"$state"
  aur_package_satisfied alacritty \
    || fail 'installed alacritty-graphics did not satisfy alacritty'

  printf '%s\n' qimgv-git >"$state"
  aur_package_satisfied qimgv \
    || fail 'installed qimgv-git did not satisfy qimgv'

  printf '%s\n' qimgv >"$state"
  aur_package_satisfied qimgv-git \
    || fail 'installed qimgv did not satisfy qimgv-git'

  printf '%s\n' obs-pipewire-audio-capture >"$state"
  aur_package_satisfied obs-pipewire-audio-capture-bin \
    || fail 'installed OBS PipeWire source package did not satisfy bin package'

  printf '%s\n' obs-pipewire-audio-capture-bin >"$state"
  aur_package_satisfied obs-pipewire-audio-capture \
    || fail 'installed OBS PipeWire bin package did not satisfy source package'

  : >"$state"
  plugin="${HOME}/.config/obs-studio/plugins/linux-pipewire-audio/bin/64bit/linux-pipewire-audio.so"
  mkdir -p -- "$(dirname -- "$plugin")"
  : >"$plugin"
  aur_package_satisfied obs-pipewire-audio-capture-bin \
    || fail 'existing per-user OBS PipeWire plugin did not satisfy AUR package'

  : >"$state"
  if aur_package_satisfied smtty; then
    fail 'uninstalled unrelated AUR package was incorrectly satisfied'
  fi
fi

cat >"$runtime" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=()
declare -a PACKAGES_AUR=(
  alacritty-graphics
  qimgv
  obs-pipewire-audio-capture-bin
  smtty
)
declare -a FLATPAK_CATALOG=()
EOF_RUNTIME
printf '%s\n' alacritty qimgv-git >"$state"
review_output="$(bash "$RECONCILER" --review)"
aur_section="$(printf '%s\n' "$review_output" | sed -n '/^Missing current AUR catalog packages:/,/^Missing current Flatpak catalog apps:/p')"

if printf '%s\n' "$aur_section" | grep -Fq 'alacritty-graphics'; then
  fail 'review still offered alacritty-graphics despite installed alacritty'
fi
if printf '%s\n' "$aur_section" | grep -Fq 'qimgv'; then
  fail 'review still offered qimgv despite installed qimgv-git'
fi
if printf '%s\n' "$aur_section" | grep -Fq 'obs-pipewire-audio-capture-bin'; then
  fail 'review still offered OBS PipeWire package despite existing user plugin'
fi
printf '%s\n' "$aur_section" | grep -Fq -- '- smtty' \
  || fail 'review did not retain genuinely missing smtty'

if ! declare -F ensure_aur_scanner >/dev/null; then
  fail 'reconciler has no aur-scanner preparation function'
fi
if ! declare -F install_selected_aur_packages >/dev/null; then
  fail 'reconciler has no per-package AUR installer'
else
  record_managed_packages() {
    :
  }
  FAILED_AUR=()
  : >"$state"
  : >"$scan_log"

  install_selected_aur_packages awtwall mpvpaper \
    || fail 'per-package AUR installer aborted instead of continuing'

  [[ $(grep -c '^aur-scan ' "$scan_log") -eq 2 ]] \
    || fail 'selected AUR packages were not installed as separate aur-scan transactions'
  grep -Fqx 'aur-scan install awtwall --noconfirm' "$scan_log" \
    || fail 'awtwall did not get its own aur-scan install transaction'
  grep -Fqx 'aur-scan install mpvpaper --noconfirm' "$scan_log" \
    || fail 'mpvpaper did not get its own aur-scan install transaction'
  if grep -F 'awtwall' "$scan_log" | grep -Fq 'mpvpaper'; then
    fail 'multiple AUR targets were still batched into one transaction'
  fi
  [[ ${#FAILED_AUR[@]} -eq 1 && ${FAILED_AUR[0]} == awtwall ]] \
    || fail 'failed AUR package was not recorded for end-of-run reporting'

  printf '%s\n' alacritty >"$state"
  : >"$scan_log"
  FAILED_AUR=()
  install_selected_aur_packages alacritty-graphics \
    || fail 'equivalent-installed AUR package check returned failure'
  [[ ! -s $scan_log ]] \
    || fail 'equivalent-installed AUR package still invoked aur-scan'
  (( ${#FAILED_AUR[@]} == 0 )) \
    || fail 'equivalent-installed AUR package was incorrectly recorded as failed'
fi

if declare -F ensure_aur_helper >/dev/null; then
  fail 'obsolete updater AUR-helper preparation function still exists'
fi
if declare -F rebuild_aur_helper >/dev/null; then
  fail 'obsolete updater AUR-helper rebuild machinery still exists'
fi
if grep -Fq 'AUR_HELPER=' "$RECONCILER"; then
  fail 'reconciler still maintains an AUR helper transaction-engine state variable'
fi
if ! grep -Fq '/usr/bin/yay -S --noconfirm --pgpfetch aur-scanner' "$RECONCILER"; then
  fail 'reconciler does not limit direct yay installation to the aur-scanner bootstrap'
fi
if grep -Eq '"\$AUR_HELPER"[[:space:]]+-S|\b(paru|yay)[[:space:]]+-S[[:space:]]+--needed' "$RECONCILER"; then
  fail 'reconciler still contains a normal selected-package helper install path'
fi

if (( failures > 0 )); then
  exit 1
fi

printf 'PASS: reconciler preserves AUR equivalence and delegates best-effort per-package installs to aur-scan\n'
