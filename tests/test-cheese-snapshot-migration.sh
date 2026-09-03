#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -n "$RUNTIME"
bash -n "$RECONCILER"

grep -Eq '"Multimedia:[^"]*(^|[[:space:]])snapshot([[:space:]]|$)' "$RUNTIME" \
  || fail "Snapshot is not present in the Multimedia Arch package catalog"
if grep -Eq '"Multimedia:[^"]*(^|[[:space:]])cheese([[:space:]]|$)' "$RUNTIME"; then
  fail "Cheese is still present in the current Arch package catalog"
fi

grep -Fq 'migrate_cheese_to_snapshot_stage()' "$RUNTIME" \
  || fail "runtime has no Cheese to Snapshot migration helper"
[[ $(grep -Fc 'migrate_cheese_to_snapshot_stage' "$RUNTIME") -ge 3 ]] \
  || fail "Cheese migration is not wired into both install and update paths"
grep -Fq -- '--migrate-replacements' "$RECONCILER" \
  || fail "package reconciler has no noninteractive replacement migration mode"

home="${TMP}/home"
fakebin="${TMP}/fakebin"
state="${TMP}/installed"
managed="${TMP}/managed-packages"
runtime_stub="${TMP}/awtarchy-runtime.sh"
mkdir -p "$home" "$fakebin"
printf '%s\n' cheese >"$state"
printf '%s\n' cheese >"$managed"

cat >"$runtime_stub" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=(
  "Multimedia:snapshot"
)
declare -a PACKAGES_AUR=()
declare -a FLATPAK_CATALOG=()
EOF_RUNTIME

cat >"$fakebin/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${AWTARCHY_TEST_PACKAGE_STATE:?}"
case "${1:-}" in
  -Q)
    grep -Fxq -- "${2:-}" "$state"
    ;;
  -Qq)
    if (( $# == 1 )); then
      cat "$state"
    else
      grep -Fxq -- "${2:-}" "$state"
    fi
    ;;
  -S|-Syu)
    pkg="${@: -1}"
    grep -Fxq -- "$pkg" "$state" || printf '%s\n' "$pkg" >>"$state"
    ;;
  -Rns)
    pkg="${@: -1}"
    tmp="${state}.tmp"
    grep -Fxv -- "$pkg" "$state" >"$tmp" || true
    mv -f -- "$tmp" "$state"
    ;;
  *)
    printf 'unexpected pacman invocation:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    exit 90
    ;;
esac
EOF_PACMAN
chmod +x "$fakebin/pacman"

cat >"$fakebin/sudo" <<'EOF_SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == -v ]]; then
  exit 0
fi
exec "$@"
EOF_SUDO
chmod +x "$fakebin/sudo"

PATH="$fakebin:/usr/bin:/bin" \
HOME="$home" \
USER=tester \
AWTARCHY_RUNTIME="$runtime_stub" \
AWTARCHY_MANAGED_PACKAGES_FILE="$managed" \
AWTARCHY_TEST_PACKAGE_STATE="$state" \
"$RECONCILER" --migrate-replacements

grep -Fxq snapshot "$state" \
  || fail "replacement migration did not install Snapshot"
if grep -Fxq cheese "$state"; then
  fail "replacement migration did not remove Cheese"
fi
grep -Fxq snapshot "$managed" \
  || fail "replacement migration did not record Snapshot as Awtarchy-managed"
if grep -Fxq cheese "$managed"; then
  fail "replacement migration did not remove Cheese from the managed-package ledger"
fi

printf 'PASS: Cheese is replaced by Snapshot across package migration paths.\n'
