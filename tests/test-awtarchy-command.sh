#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_SOURCE="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
INSTALLER_SOURCE="${ROOT}/awtarchy-install.sh"
LAUNCHER_SOURCE="${ROOT}/local/bin/awtarchy"
TMP="$(mktemp -d)"
TEST_USER=""
TEST_MAIN_COMMIT="2222222222222222222222222222222222222222"

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
grep -Fq 'refresh_existing_command()' "$INSTALLER_SOURCE" \
  || fail "installer does not refresh an existing command"
grep -Fq 'UPDATER_BRANCH="main"' "$LAUNCHER_SOURCE" \
  || fail "maintenance command does not pin updater refreshes to main"
grep -Fq 'commits/${UPDATER_BRANCH}' "$LAUNCHER_SOURCE" \
  || fail "maintenance command does not resolve the main updater head"
grep -Fq 'archive/${commit}.tar.gz' "$LAUNCHER_SOURCE" \
  || fail "maintenance command does not pin updater downloads to an exact main commit"

release_root="${TMP}/awtarchy-v9.9.9"
mkdir -p "$release_root"
tar --exclude='.git' -C "$ROOT" -cf - . | tar -C "$release_root" -xf -
tar -czf "${TMP}/release.tar.gz" -C "$TMP" "$(basename "$release_root")"
STABLE_INSTALLER="${release_root}/awtarchy-install.sh"

main_parent="${TMP}/main-archive"
main_root="${main_parent}/awtarchy-${TEST_MAIN_COMMIT}"
mkdir -p "$main_root"
tar --exclude='.git' -C "$ROOT" -cf - . | tar -C "$main_root" -xf -
tar -czf "${TMP}/main.tar.gz" -C "$main_parent" "$(basename "$main_root")"

fakebin="${TMP}/fakebin"
mkdir -p "$fakebin"
cat >"${fakebin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
url=""
progress=0
speed_limit=""
speed_time=""
while (( $# )); do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -H|--connect-timeout|--max-time|--retry|--retry-delay)
      shift 2
      ;;
    --progress-bar)
      progress=1
      shift
      ;;
    --speed-limit)
      speed_limit="$2"
      shift 2
      ;;
    --speed-time)
      speed_time="$2"
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
printf '%s\n' "$url" >>"${AWTARCHY_TEST_CURL_LOG:?}"
if [[ $url == *'/releases/latest' ]]; then
  printf '%s\n' '{"tag_name":"v9.9.9"}'
  exit 0
fi
if [[ $url == 'https://api.github.com/repos/dillacorn/awtarchy/commits/main' ]]; then
  printf '{"sha":"%s"}\n' "${AWTARCHY_TEST_MAIN_COMMIT:?}"
  exit 0
fi
[[ -n $out ]] || exit 2
(( progress == 1 )) || exit 3
[[ $speed_limit == 1024 ]] || exit 4
[[ $speed_time == 30 ]] || exit 5
if [[ $url == "https://github.com/dillacorn/awtarchy/archive/${AWTARCHY_TEST_MAIN_COMMIT:?}.tar.gz" ]]; then
  cp -- "${AWTARCHY_TEST_MAIN_ARCHIVE:?}" "$out"
  exit 0
fi
if [[ $url == 'https://github.com/dillacorn/awtarchy/archive/refs/tags/v9.9.9.tar.gz' ]]; then
  cp -- "${AWTARCHY_TEST_RELEASE_ARCHIVE:?}" "$out"
  exit 0
fi
exit 6
EOF
chmod 0755 "${fakebin}/curl"

curl_log="${TMP}/curl.log"
: >"$curl_log"
common_test_env=(
  "PATH=${fakebin}:$PATH"
  "AWTARCHY_TEST_CURL_LOG=$curl_log"
  "AWTARCHY_TEST_MAIN_COMMIT=$TEST_MAIN_COMMIT"
  "AWTARCHY_TEST_MAIN_ARCHIVE=${TMP}/main.tar.gz"
  "AWTARCHY_TEST_RELEASE_ARCHIVE=${TMP}/release.tar.gz"
)

home="${TMP}/home"
mkdir -p "$home/.local/bin" "$home/.local/share/awtarchy" "$home/.local/state/awtarchy"
cp "$LAUNCHER_SOURCE" "$home/.local/bin/awtarchy"
cp "$RUNTIME_SOURCE" "$home/.local/share/awtarchy/awtarchy-runtime.sh"
chmod 0755 "$home/.local/bin/awtarchy" "$home/.local/share/awtarchy/awtarchy-runtime.sh"
printf 'tag=v0.0.0\nupdated_at=2000-01-01T00:00:00Z\n' >"$home/.local/state/awtarchy/command-version"
printf 'tag=v0.0.1\nupdated_at=2000-01-01T00:00:00Z\n' >"$home/.local/state/awtarchy/config-version"

version_output="$(
  env "${common_test_env[@]}" HOME="$home" USER="$(id -un)" \
    "$home/.local/bin/awtarchy" version
)"
grep -Fq 'Updater branch:     main' <<<"$version_output" \
  || fail "version did not report main as the updater source"
grep -Fq 'Updater commit:     unknown' <<<"$version_output" \
  || fail "legacy command state was not identified as an untracked updater"
grep -Fq "Remote main head:   ${TEST_MAIN_COMMIT}" <<<"$version_output" \
  || fail "version did not report the remote main updater head"
grep -Fq 'Config release:     v0.0.1' <<<"$version_output" \
  || fail "version did not report the installed config release"
grep -Fq 'Latest release:     v9.9.9' <<<"$version_output" \
  || fail "version did not report the latest config release"

env "${common_test_env[@]}" HOME="$home" USER="$(id -un)" \
  "$home/.local/bin/awtarchy" self-update

assert_executable "$home/.local/bin/awtarchy"
assert_executable "$home/.local/share/awtarchy/awtarchy-runtime.sh"
grep -Fxq 'tag=main' "$home/.local/state/awtarchy/command-version" \
  || fail "self-update did not record main as the updater source"
grep -Fxq "revision=${TEST_MAIN_COMMIT}" "$home/.local/state/awtarchy/command-version" \
  || fail "self-update did not record the exact main updater commit"
grep -Fxq 'tag=v0.0.1' "$home/.local/state/awtarchy/config-version" \
  || fail "self-update incorrectly changed config release state"
cmp -s "$home/.local/bin/awtarchy" "$main_root/local/bin/awtarchy" \
  || fail "self-update did not install the main updater launcher"
cmp -s \
  "$home/.local/share/awtarchy/awtarchy-runtime.sh" \
  "$main_root/local/share/awtarchy/awtarchy-runtime.sh" \
  || fail "self-update did not install the main updater runtime"
grep -Fxq "https://github.com/dillacorn/awtarchy/archive/${TEST_MAIN_COMMIT}.tar.gz" "$curl_log" \
  || fail "self-update did not download the exact main commit archive"

set +e
env "${common_test_env[@]}" HOME="$home" USER="$(id -un)" \
  "$home/.local/bin/awtarchy" self-update --tag v9.9.9 \
  >"${TMP}/self-update-tag.out" 2>&1
self_update_tag_rc=$?
set -e
(( self_update_tag_rc != 0 )) \
  || fail "self-update accepted a release tag even though updater source must remain main"
grep -Fq 'updater source is always main' "${TMP}/self-update-tag.out" \
  || fail "self-update did not explain that updater source is fixed to main"

HOME="$home" USER="$(id -un)" AWTARCHY_SKIP_UPDATE_CHECK=1 \
  "$home/.local/bin/awtarchy" help >/dev/null

printf '%s\n' '#!/usr/bin/env bash' 'exit 99' >"$home/.local/bin/awtarchy"
printf '%s\n' '#!/usr/bin/env bash' 'exit 98' >"$home/.local/share/awtarchy/awtarchy-runtime.sh"
chmod 0755 \
  "$home/.local/bin/awtarchy" \
  "$home/.local/share/awtarchy/awtarchy-runtime.sh"
printf 'tag=v0.0.0\nupdated_at=2000-01-01T00:00:00Z\n' \
  >"$home/.local/state/awtarchy/command-version"

existing_output="$(
  env "${common_test_env[@]}" HOME="$home" USER="$(id -un)" \
    AWTARCHY_SYSTEM_BIN_DIR="${TMP}/existing-system-bin" \
    bash "$STABLE_INSTALLER"
)"
grep -Fq 'Awtarchy is already installed' <<<"$existing_output" \
  || fail "installer did not detect the existing command"
cmp -s "$home/.local/bin/awtarchy" "$main_root/local/bin/awtarchy" \
  || fail "installer did not leave the latest main updater launcher installed"
cmp -s \
  "$home/.local/share/awtarchy/awtarchy-runtime.sh" \
  "$main_root/local/share/awtarchy/awtarchy-runtime.sh" \
  || fail "installer did not leave the latest main updater runtime installed"
grep -Fxq 'tag=main' "$home/.local/state/awtarchy/command-version" \
  || fail "installer did not record main as the updater source"
grep -Fxq "revision=${TEST_MAIN_COMMIT}" "$home/.local/state/awtarchy/command-version" \
  || fail "installer did not record the latest main updater commit"
grep -Fxq 'tag=v0.0.1' "$home/.local/state/awtarchy/config-version" \
  || fail "command refresh changed the installed config release"

legacy_home="${TMP}/legacy-home"
mkdir -p "$legacy_home/.cache/awtarchy"
printf 'tag=v0.8.0\nupdated_at=2000-01-01T00:00:00Z\n' \
  >"$legacy_home/.cache/awtarchy/version"
legacy_output="$(
  env "${common_test_env[@]}" HOME="$legacy_home" USER="$(id -un)" \
    AWTARCHY_SYSTEM_BIN_DIR="${TMP}/legacy-system-bin" \
    AWTARCHY_INSTALL_TAG=v9.9.9 bash "$STABLE_INSTALLER"
)"
assert_executable "$legacy_home/.local/bin/awtarchy"
assert_executable "$legacy_home/.local/share/awtarchy/awtarchy-runtime.sh"
grep -Fxq 'tag=main' "$legacy_home/.local/state/awtarchy/command-version" \
  || fail "legacy migration did not finish on the main updater source"
grep -Fxq "revision=${TEST_MAIN_COMMIT}" "$legacy_home/.local/state/awtarchy/command-version" \
  || fail "legacy migration did not install the current main updater"
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
    bash "$STABLE_INSTALLER" --dry-run
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
  printf 'tag=main\nrevision=%s\nupdated_at=2000-01-01T00:00:00Z\n' "$TEST_MAIN_COMMIT" \
    >"$user_home/.local/state/awtarchy/command-version"
  sudo chown -R "$TEST_USER:$TEST_USER" "$user_home" "$runtime_dir"
  chmod 0755 "$TMP" "$fakebin"
  chmod 0644 "${TMP}/release.tar.gz" "${TMP}/main.tar.gz"

  launcher_hash_before="$(sha256sum "$user_home/.local/bin/awtarchy" | awk '{print $1}')"
  runtime_hash_before="$(sha256sum "$user_home/.local/share/awtarchy/awtarchy-runtime.sh" | awk '{print $1}')"

  sudo -u "$TEST_USER" env \
    "${common_test_env[@]}" \
    HOME="$user_home" \
    USER="$TEST_USER" \
    LOGNAME="$TEST_USER" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    AWTARCHY_SKIP_UPDATE_CHECK=1 \
    "$user_home/.local/bin/awtarchy" update --tag v9.9.9

  assert_file "$user_home/.local/state/awtarchy/config-version"
  grep -Fxq 'tag=v9.9.9' "$user_home/.local/state/awtarchy/config-version" \
    || fail "config update wrote the wrong config release state"
  grep -Fxq 'tag=main' "$user_home/.local/state/awtarchy/command-version" \
    || fail "config update changed updater source state"
  grep -Fxq "revision=${TEST_MAIN_COMMIT}" "$user_home/.local/state/awtarchy/command-version" \
    || fail "config update changed updater commit state"

  launcher_hash_after="$(sha256sum "$user_home/.local/bin/awtarchy" | awk '{print $1}')"
  runtime_hash_after="$(sha256sum "$user_home/.local/share/awtarchy/awtarchy-runtime.sh" | awk '{print $1}')"
  [[ $launcher_hash_before == "$launcher_hash_after" ]] \
    || fail "config update replaced the command launcher while update checks were disabled"
  [[ $runtime_hash_before == "$runtime_hash_after" ]] \
    || fail "config update replaced the command runtime while update checks were disabled"
fi

printf 'Awtarchy command tests passed.\n'
