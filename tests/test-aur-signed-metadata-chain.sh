#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASHRC="${ROOT}/bashrc"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

fixture="${TMPD}/bashrc-fixture"
sed 's/^\[\[ \$- != \*i\* \]\] && return$/:/' "$BASHRC" >"$fixture"

runner="${TMPD}/runner"
cat >"$runner" <<'EOF_RUNNER'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# shellcheck disable=SC1090
source "${AWTARCHY_TEST_FIXTURE:?}"

declare -F _aur_guard_verify_signed_metadata_chain >/dev/null \
  || { printf '%s\n' 'missing _aur_guard_verify_signed_metadata_chain' >&2; exit 70; }

make_case() {
  local dir="$1" mode="$2"
  local payload packages packages_hash packages_size payload_hash payload_size
  rm -rf -- "$dir"
  mkdir -p -- "$dir"

  payload='verified payload bytes'
  printf '%s\n' "$payload" >"${dir}/fixture.deb"
  payload_hash=$(sha256sum "${dir}/fixture.deb" | awk '{print $1}')
  payload_size=$(stat -c %s "${dir}/fixture.deb")

  packages="Package: fixture
Filename: pool/non-free/f/fixture/fixture.deb
Size: ${payload_size}
SHA256: ${payload_hash}
"
  printf '%s' "$packages" >"${dir}/Packages"
  packages_hash=$(sha256sum "${dir}/Packages" | awk '{print $1}')
  packages_size=$(stat -c %s "${dir}/Packages")

  cat >"${dir}/Release" <<EOF_RELEASE
Origin: Fixture Repository
SHA256:
 ${packages_hash} ${packages_size} main/binary-amd64/Packages
EOF_RELEASE
  printf '%s\n' 'detached signature fixture; production ordering proves this with makepkg --verifysource' >"${dir}/Release.sig"

  cat >"${dir}/PKGBUILD" <<'EOF_PKGBUILD'
pkgname=fixture
pkgver=1
pkgrel=1
prepare() {
  grep 'main/binary-amd64/Packages' Release | awk '{print $1 "  Packages"}' > Packages.sha256
  sha256sum -c Packages.sha256
  grep -A8 '^Package: fixture$' Packages | grep '^SHA256:' | awk '{print $2 "  fixture.deb"}' > fixture.sha256
  sha256sum -c fixture.sha256
}
EOF_PKGBUILD

  cat >"${dir}/.SRCINFO.verified" <<'EOF_SRCINFO'
pkgbase = fixture
pkgver = 1
pkgrel = 1
arch = x86_64
validpgpkeys = 0123456789ABCDEF0123456789ABCDEF01234567
source = fixture.deb::https://repo.example.invalid/pool/non-free/f/fixture/fixture.deb
source = Release::https://repo.example.invalid/dists/stable/Release
source = Release.sig::https://repo.example.invalid/dists/stable/Release.gpg
source = Packages::https://repo.example.invalid/dists/stable/main/binary-amd64/Packages
sha256sums = SKIP
sha256sums = SKIP
sha256sums = SKIP
sha256sums = SKIP
pkgname = fixture
EOF_SRCINFO

  case "$mode" in
    valid) ;;
    bad-packages) printf '%s\n' 'tamper' >>"${dir}/Packages" ;;
    bad-payload) printf '%s\n' 'tamper' >>"${dir}/fixture.deb" ;;
    bad-key) sed -i 's/0123456789ABCDEF0123456789ABCDEF01234567/DEADBEEF/' "${dir}/.SRCINFO.verified" ;;
    network-hash) sed -i '/prepare() {/a\  curl -fsSL https://attacker.invalid/hash' "${dir}/PKGBUILD" ;;
    *) return 99 ;;
  esac
}

valid="${AWTARCHY_TEST_TMP:?}/valid"
make_case "$valid" valid
_AUR_GUARD_CHAIN_VERIFIED_NAMES=''
_aur_guard_verify_signed_metadata_chain fixture "$valid/.SRCINFO.verified" "$valid"
grep -Fxq -- 'Packages' <<<"$_AUR_GUARD_CHAIN_VERIFIED_NAMES"
grep -Fxq -- 'fixture.deb' <<<"$_AUR_GUARD_CHAIN_VERIFIED_NAMES"
_aur_guard_validate_skipped_integrity fixture "$valid/.SRCINFO.verified"

for mode in bad-packages bad-payload bad-key network-hash; do
  dir="${AWTARCHY_TEST_TMP:?}/${mode}"
  make_case "$dir" "$mode"
  _AUR_GUARD_CHAIN_VERIFIED_NAMES=''
  if _aur_guard_verify_signed_metadata_chain fixture "$dir/.SRCINFO.verified" "$dir" >/dev/null 2>&1; then
    printf 'invalid signed metadata chain was accepted: %s\n' "$mode" >&2
    exit 71
  fi
done
EOF_RUNNER
chmod 0755 "$runner"

if ! env \
    AWTARCHY_TEST_FIXTURE="$fixture" \
    AWTARCHY_TEST_TMP="$TMPD" \
    "$runner"; then
  fail 'signed metadata chain regression failed'
fi

printf '%s\n' 'PASS: pinned signed metadata can authenticate nested package metadata and payload digests without package allowlists.'
