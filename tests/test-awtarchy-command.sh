#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_SOURCE="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
INSTALLER_SOURCE="${ROOT}/awtarchy-install.sh"
LAUNCHER_SOURCE="${ROOT}/local/bin/awtarchy"
TMP="$(mktemp -d)"
TEST_USER=""

cleanup() {
  if [[ -n ${TEST_USER:-} ]] && command -v sudo >/dev/null 2>&1; then
    sudo userdel "$TEST_USER" >/dev/null 2>&1 || true
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo rm -rf -- "$TMP"
  else
    rm -rf -- "$TMP"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f $1 ]] || fail "missing file: $1"
}

assert_executable() {
  [[ -x $1 ]] || fail "not executable: $1"
}

bash -n "$INSTALLER_SOURCE"
bash -n "$RUNTIME_SOURCE"
bash -n "$LAUNCHER_SOURCE"

grep -Fq 'install_awtarchy_command_stage()' "$RUNTIME_SOURCE" \
  || fail "runtime is missing the command installation stage"
grep -Fq 'install_awtarchy_command_stage' "$RUNTIME_SOURCE" \
  || fail "runtime does not call the command installation stage"
grep -Fq 'AWTARCHY_REPO_DIR' "$RUNTIME_SOURCE" \
  || fail "runtime does not accept the installer source directory"

release_root="${TMP}/awtarchy-v9.9.9"
mkdir -p "$release_root"
tar --exclude='.git' -C "$ROOT" -cf - . | tar -C "$release_root" -xf -
tar -czf "${TMP}/release.tar.gz" -C "$TMP" "$(basename "$release_root")"

fakebin="${TMP}/fakebin"
mkdir -p "$fakebin"
cat >"${fakebin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
url=""
while (( $# )); do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -H|--connect-timeout|--max-time|--retry|--retry-delay)
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
if [[ $url == *'/releases/latest' ]]; then
  printf '%s\n' '{"tag_name":"v9.9.9"}'
  exit 0
fi
[[ -n $out ]] || exit 2
cp -- "$AWTARCHY_TEST_ARCHIVE" "$out"
EOF
chmod 0755 "${fakebin}/curl"

home="${TMP}/home"
mkdir -p "$home/.local/bin" "$home/.local/share/awtarchy" "$home/.local/state/awtarchy"
cp "$LAUNCHER_SOURCE" "$home/.local/bin/awtarchy"
cp "$RUNTIME_SOURCE" "$home/.local/share/awtarchy/awtarchy-runtime.sh"
chmod 0755 "$home/.local/bin/awtarchy" "$home/.local/share/awtarchy/awtarchy-runtime.sh"
printf 'tag=v0.0.0\nupdated_at=2000-01-01T00:00:00Z\n' >"$home/.local/state/awtarchy/command-version"
printf 'tag=v0.0.1\nupdated_at=2000-01-01T00:00:00Z\n' >"$home/.local/state/awtarchy/config-version"

version_output="$(
  HOME="$home" USER="$(id -un)" PATH="${fakebin}:$PATH" \
    AWTARCHY_TEST_ARCHIVE="${TMP}/release.tar.gz" \
    "$home/.local/bin/awtarchy" version
)"
grep -Fq 'Command release:   v0.0.0' <<<"$version_output" \
  || fail "version did not report the installed command release"
grep -Fq 'Config release:    v0.0.1' <<<"$version_output" \
  || fail "version did not report the installed config release"
grep -Fq 'Latest release:    v9.9.9' <<<"$version_output" \
  || fail "version did not report the latest release"

HOME="$home" USER="$(id -un)" PATH="${fakebin}:$PATH" \
  AWTARCHY_TEST_ARCHIVE="${TMP}/release.tar.gz" \
  "$home/.local/bin/awtarchy" self-update --tag v9.9.9

assert_executable "$home/.local/bin/awtarchy"
assert_executable "$home/.local/share/awtarchy/awtarchy-runtime.sh"
grep -Fxq 'tag=v9.9.9' "$home/.local/state/awtarchy/command-version" \
  || fail "self-update did not write command release state"
grep -Fxq 'tag=v0.0.1' "$home/.local/state/awtarchy/config-version" \
  || fail "self-update incorrectly changed config release state"
HOME="$home" USER="$(id -un)" AWTARCHY_SKIP_UPDATE_CHECK=1 \
  "$home/.local/bin/awtarchy" help >/dev/null

existing_output="$(HOME="$home" USER="$(id -un)" bash "$INSTALLER_SOURCE")"
grep -Fq 'Awtarchy is already installed' <<<"$existing_output" \
  || fail "installer did not detect the existing command"
grep -Fq 'awtarchy self-update' <<<"$existing_output" \
  || fail "installer did not explain the new update command"

legacy_home="${TMP}/legacy-home"
mkdir -p "$legacy_home/.cache/awtarchy"
printf 'tag=v0.8.0\nupdated_at=2000-01-01T00:00:00Z\n' \
  >"$legacy_home/.cache/awtarchy/version"
legacy_output="$(
  HOME="$legacy_home" USER="$(id -un)" AWTARCHY_INSTALL_TAG=v9.9.9 \
    bash "$INSTALLER_SOURCE"
)"
assert_executable "$legacy_home/.local/bin/awtarchy"
assert_executable "$legacy_home/.local/share/awtarchy/awtarchy-runtime.sh"
grep -Fxq 'tag=v9.9.9' "$legacy_home/.local/state/awtarchy/command-version" \
  || fail "legacy migration did not record the command release"
grep -Fxq 'tag=v0.8.0' "$legacy_home/.local/state/awtarchy/config-version" \
  || fail "legacy migration did not preserve the prior config release"
grep -Fq 'No packages or managed configs were changed' <<<"$legacy_output" \
  || fail "legacy migration did not explain its safe scope"
[[ ! -d "$legacy_home/.config" ]] \
  || fail "legacy migration unexpectedly created managed config files"

legacy_dry_home="${TMP}/legacy-dry-home"
mkdir -p "$legacy_dry_home/.cache/awtarchy"
printf 'tag=v0.8.0\n' >"$legacy_dry_home/.cache/awtarchy/version"
legacy_dry_output="$(
  HOME="$legacy_dry_home" USER="$(id -un)" \
    bash "$INSTALLER_SOURCE" --dry-run
)"
[[ ! -e "$legacy_dry_home/.local/bin/awtarchy" ]] \
  || fail "legacy dry-run installed the maintenance command"
grep -Fq 'No files were changed because --dry-run was used' <<<"$legacy_dry_output" \
  || fail "legacy dry-run did not explain the migration"

set +e
maintenance_output="$(HOME="$home" USER="$(id -un)" bash "$INSTALLER_SOURCE" update 2>&1)"
maintenance_rc=$?
set -e
(( maintenance_rc == 2 )) || fail "installer accepted a maintenance command"
grep -Fq 'Run it through: awtarchy update' <<<"$maintenance_output" \
  || fail "installer maintenance redirect was unclear"

if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  TEST_USER="awtarchy-ci-${RANDOM}-$$"
  user_home="${TMP}/${TEST_USER}"
  runtime_dir="${TMP}/runtime-${TEST_USER}"
  sudo useradd -M -d "$user_home" -s /bin/bash "$TEST_USER"
  mkdir -p \
    "$user_home/.local/bin" \
    "$user_home/.local/share/awtarchy" \
    "$user_home/.local/state/awtarchy" \
    "$runtime_dir"
  cp "$LAUNCHER_SOURCE" "$user_home/.local/bin/awtarchy"
  cp "$RUNTIME_SOURCE" "$user_home/.local/share/awtarchy/awtarchy-runtime.sh"
  chmod 0755 "$user_home/.local/bin/awtarchy" "$user_home/.local/share/awtarchy/awtarchy-runtime.sh"
  printf 'tag=v9.9.9\nupdated_at=2000-01-01T00:00:00Z\n' \
    >"$user_home/.local/state/awtarchy/command-version"
  sudo chown -R "$TEST_USER:$TEST_USER" "$user_home" "$runtime_dir"
  chmod 0755 "$TMP" "$fakebin"
  chmod 0644 "${TMP}/release.tar.gz"

  launcher_hash_before="$(sha256sum "$user_home/.local/bin/awtarchy" | awk '{print $1}')"
  runtime_hash_before="$(sha256sum "$user_home/.local/share/awtarchy/awtarchy-runtime.sh" | awk '{print $1}')"

  sudo -u "$TEST_USER" env \
    HOME="$user_home" \
    USER="$TEST_USER" \
    LOGNAME="$TEST_USER" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    PATH="${fakebin}:$PATH" \
    AWTARCHY_SKIP_UPDATE_CHECK=1 \
    AWTARCHY_TEST_ARCHIVE="${TMP}/release.tar.gz" \
    "$user_home/.local/bin/awtarchy" update --tag v9.9.9

  assert_file "$user_home/.local/state/awtarchy/config-version"
  grep -Fxq 'tag=v9.9.9' "$user_home/.local/state/awtarchy/config-version" \
    || fail "config update wrote the wrong config release state"
  grep -Fxq 'tag=v9.9.9' "$user_home/.local/state/awtarchy/command-version" \
    || fail "config update changed command release state"

  launcher_hash_after="$(sha256sum "$user_home/.local/bin/awtarchy" | awk '{print $1}')"
  runtime_hash_after="$(sha256sum "$user_home/.local/share/awtarchy/awtarchy-runtime.sh" | awk '{print $1}')"
  [[ $launcher_hash_before == "$launcher_hash_after" ]] \
    || fail "config update replaced the command launcher"
  [[ $runtime_hash_before == "$runtime_hash_after" ]] \
    || fail "config update replaced the command runtime"
fi

printf 'Awtarchy command tests passed.\n'
