#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BASHRC="$ROOT/bashrc"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/data"
export XDG_STATE_HOME="$TMP/state"
mkdir -p "$HOME" "$XDG_DATA_HOME/awtarchy" "$XDG_STATE_HOME/awtarchy"

# shellcheck disable=SC1090
source <(sed '/^\[\[ \$- != \*i\* \]\] && return$/d' "$BASHRC")

RUNTIME="$XDG_DATA_HOME/awtarchy/aurguard-runtime.sh"
META="$XDG_STATE_HOME/awtarchy/aurguard-runtime"
REVISION='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

cat > "$RUNTIME" <<'EOF_RUNTIME'
# AWTARCHY_AURGUARD_RUNTIME v1
# shellcheck shell=bash
_aur_guard_scan_checkout_with_aur_scan() { :; }
aurverify() { :; }
aurinstall() { :; }
aurguard() { :; }
EOF_RUNTIME
chmod 0600 "$RUNTIME"
HASH=$(sha256sum "$RUNTIME" | awk '{print $1}')
cat > "$META" <<EOF_META
version=1
target=main
revision=$REVISION
fetched_at=$(date +%s)
sha256=$HASH
EOF_META
chmod 0600 "$META"

_aur_guard_runtime_cache_valid || fail 'owner-only runtime cache fixture was rejected'

chmod 0666 "$RUNTIME"
if _aur_guard_runtime_cache_valid; then
  fail 'world-writable AurGuard runtime cache was accepted'
fi
chmod 0600 "$RUNTIME"

chmod 0666 "$META"
if _aur_guard_runtime_cache_valid; then
  fail 'world-writable AurGuard runtime metadata was accepted'
fi
chmod 0600 "$META"

_aur_guard_runtime_cache_valid || fail 'restored owner-only cache did not validate'

printf 'PASS: AurGuard runtime cache validation requires owner-only runtime and metadata files.\n'
