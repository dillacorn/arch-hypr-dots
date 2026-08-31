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
mkdir -p "$home" "$fakebin"
: >"$state"

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

export TEST_STATE="$state"
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

if (( failures > 0 )); then
  exit 1
fi

printf 'PASS: reconciler matches installer AUR equivalence semantics\n'
