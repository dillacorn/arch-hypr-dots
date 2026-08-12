#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER_SOURCE="${ROOT}/awtarchy-install.sh"
TMP="$(mktemp -d)"
export AWTARCHY_TEST_RUNTIME_PASSTHROUGH=1

cleanup() {
  rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_executable() {
  [[ -x $1 ]] || fail "not executable: $1"
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "missing expected text in $1: $2"
}

bash -n "$INSTALLER_SOURCE"

repo="${TMP}/repo"
mkdir -p "$repo/local/bin" "$repo/local/share/awtarchy"
cp -- "$INSTALLER_SOURCE" "$repo/awtarchy-install.sh"

cat >"$repo/local/bin/awtarchy" <<'EOF_LAUNCHER'
#!/usr/bin/env bash
printf 'Awtarchy local launcher reached: %s\n' "$*"
EOF_LAUNCHER
chmod 0755 "$repo/local/bin/awtarchy"

cat >"$repo/local/share/awtarchy/awtarchy-runtime.sh" <<'EOF_RUNTIME'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ -x ${AWTARCHY_EXPECTED_SYSTEM_SHIM:?} ]]
grep -Fq '# Awtarchy user-local command shim' "$AWTARCHY_EXPECTED_SYSTEM_SHIM"
printf 'Fresh-install runtime reached after system shim creation.\n'
EOF_RUNTIME
chmod 0755 "$repo/local/share/awtarchy/awtarchy-runtime.sh"

existing_home="${TMP}/existing-home"
existing_bin="${TMP}/existing-system-bin"
mkdir -p \
  "$existing_home/.local/bin" \
  "$existing_home/.local/share/awtarchy" \
  "$existing_bin"
cp -- "$repo/local/bin/awtarchy" "$existing_home/.local/bin/awtarchy"
cp -- "$repo/local/share/awtarchy/awtarchy-runtime.sh" \
  "$existing_home/.local/share/awtarchy/awtarchy-runtime.sh"
chmod 0755 \
  "$existing_home/.local/bin/awtarchy" \
  "$existing_home/.local/share/awtarchy/awtarchy-runtime.sh"

existing_output="$(
  HOME="$existing_home" \
  USER="$(id -un)" \
  AWTARCHY_SYSTEM_BIN_DIR="$existing_bin" \
    bash "$repo/awtarchy-install.sh"
)"
assert_executable "$existing_bin/awtarchy"
assert_contains "$existing_bin/awtarchy" '# Awtarchy user-local command shim'
grep -Fq 'Awtarchy is already installed' <<<"$existing_output" \
  || fail 'installer did not retain existing-install detection'

shim_output="$(
  env -i \
    HOME="$existing_home" \
    USER="$(id -un)" \
    PATH="$existing_bin:/usr/bin:/bin" \
      awtarchy version
)"
grep -Fq 'Awtarchy local launcher reached: version' <<<"$shim_output" \
  || fail 'system shim did not dispatch to the user-local command'

shim_hash_before="$(sha256sum "$existing_bin/awtarchy" | awk '{print $1}')"
HOME="$existing_home" \
USER="$(id -un)" \
AWTARCHY_SYSTEM_BIN_DIR="$existing_bin" \
  bash "$repo/awtarchy-install.sh" >/dev/null
shim_hash_after="$(sha256sum "$existing_bin/awtarchy" | awk '{print $1}')"
[[ $shim_hash_before == "$shim_hash_after" ]] \
  || fail 'rerunning the installer changed the system shim unexpectedly'

conflict_bin="${TMP}/conflict-system-bin"
mkdir -p "$conflict_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 42' >"$conflict_bin/awtarchy"
chmod 0755 "$conflict_bin/awtarchy"
conflict_hash_before="$(sha256sum "$conflict_bin/awtarchy" | awk '{print $1}')"
conflict_output="$(
  HOME="$existing_home" \
  USER="$(id -un)" \
  AWTARCHY_SYSTEM_BIN_DIR="$conflict_bin" \
    bash "$repo/awtarchy-install.sh" 2>&1
)"
conflict_hash_after="$(sha256sum "$conflict_bin/awtarchy" | awk '{print $1}')"
[[ $conflict_hash_before == "$conflict_hash_after" ]] \
  || fail 'installer overwrote an unrelated system command'
grep -Fq 'Refusing to replace an existing non-Awtarchy command' <<<"$conflict_output" \
  || fail 'installer did not explain the system-command conflict'

legacy_dry_home="${TMP}/legacy-dry-home"
legacy_dry_bin="${TMP}/legacy-dry-system-bin"
mkdir -p "$legacy_dry_home/.cache/awtarchy" "$legacy_dry_bin"
printf 'tag=v0.8.0\n' >"$legacy_dry_home/.cache/awtarchy/version"
HOME="$legacy_dry_home" \
USER="$(id -un)" \
AWTARCHY_SYSTEM_BIN_DIR="$legacy_dry_bin" \
  bash "$repo/awtarchy-install.sh" --dry-run >/dev/null
[[ ! -e "$legacy_dry_bin/awtarchy" ]] \
  || fail 'dry-run installed the system command shim'

fresh_home="${TMP}/fresh-home"
fresh_bin="${TMP}/fresh-system-bin"
mkdir -p "$fresh_home" "$fresh_bin"
fresh_output="$(
  HOME="$fresh_home" \
  USER="$(id -un)" \
  AWTARCHY_SYSTEM_BIN_DIR="$fresh_bin" \
  AWTARCHY_EXPECTED_SYSTEM_SHIM="$fresh_bin/awtarchy" \
    bash "$repo/awtarchy-install.sh" --no-reboot
)"
assert_executable "$fresh_bin/awtarchy"
grep -Fq 'Fresh-install runtime reached after system shim creation.' <<<"$fresh_output" \
  || fail 'fresh install did not create the system shim before entering the runtime'

printf 'Awtarchy system command shim tests passed.\n'
