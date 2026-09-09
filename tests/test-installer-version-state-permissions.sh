#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_SOURCE="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
LAUNCHER_SOURCE="${ROOT}/local/bin/awtarchy"
TMP="$(mktemp -d)"
TEST_USER="awtarchy-version-state-test"
TEST_UID=61111
TEST_GID=61111

cleanup() {
  rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID} -eq 0 ]] || fail "run this test as root"
command -v setpriv >/dev/null 2>&1 || fail "setpriv is required"

getent passwd "$TEST_UID" >/dev/null 2>&1 \
  && fail "test UID is already assigned: $TEST_UID"
getent group "$TEST_GID" >/dev/null 2>&1 \
  && fail "test GID is already assigned: $TEST_GID"

home_dir="${TMP}/home"
repo_dir="${TMP}/repo"
stage_dir="${TMP}/stage"
runtime_library="${TMP}/runtime-library.sh"
fakebin="${TMP}/fakebin"

mkdir -p \
  "$home_dir" \
  "${repo_dir}/local/bin" \
  "${repo_dir}/local/share/awtarchy" \
  "$stage_dir" \
  "$fakebin"
chmod 0755 "$TMP" "$repo_dir" "${repo_dir}/local" \
  "${repo_dir}/local/bin" "${repo_dir}/local/share" \
  "${repo_dir}/local/share/awtarchy" "$stage_dir" "$fakebin"

install -m 0755 "$RUNTIME_SOURCE" \
  "${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh"
install -m 0755 "$LAUNCHER_SOURCE" "${repo_dir}/local/bin/awtarchy"

# Load the real runtime definitions without invoking its command dispatcher.
sed '$d' "$RUNTIME_SOURCE" >"$runtime_library"
chmod 0644 "$runtime_library"

cat >"${fakebin}/runuser" <<'FAKE_RUNUSER'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${1:-} == -u && ${3:-} == -- ]] || {
  printf 'unexpected runuser arguments\n' >&2
  false
}
shift 3
setpriv \
  --reuid="${AWTARCHY_TEST_UID:?}" \
  --regid="${AWTARCHY_TEST_GID:?}" \
  --clear-groups \
  -- "$@"
FAKE_RUNUSER
chmod 0755 "${fakebin}/runuser"
chown "$TEST_UID:$TEST_GID" "$home_dir"

set +e
install_output="$(
  PATH="${fakebin}:$PATH" \
    AWTARCHY_TEST_UID="$TEST_UID" \
    AWTARCHY_TEST_GID="$TEST_GID" \
    TMPDIR="$stage_dir" \
    bash -s -- \
    "$runtime_library" "$TEST_USER" "$home_dir" "$repo_dir" <<'TEST_RUNTIME' 2>&1
set -Eeuo pipefail

runtime_library="$1"
target_user="$2"
target_home="$3"
repo_dir="$4"

# shellcheck source=/dev/null
source "$runtime_library"

detect_installed_release_tag() {
  printf '%s\n' v-test
}

TARGET_USER="$target_user"
HOME_DIR="$target_home"
REPO_DIR="$repo_dir"
AWTARCHY_SKIP_SELF_UPDATE=1

install_awtarchy_command_stage
TEST_RUNTIME
)"
install_rc=$?
set -e

(( install_rc == 0 )) || {
  printf '%s\n' "$install_output" >&2
  fail "target user could not install Awtarchy version state"
}

command_version="${home_dir}/.local/state/awtarchy/command-version"
config_version="${home_dir}/.local/state/awtarchy/config-version"

for version_file in "$command_version" "$config_version"; do
  [[ -f $version_file ]] || fail "missing version state: $version_file"
  [[ $(stat -c '%u:%g' "$version_file") == "$TEST_UID:$TEST_GID" ]] \
    || fail "version state has the wrong owner: $version_file"
  [[ $(stat -c '%a' "$version_file") == 644 ]] \
    || fail "version state has the wrong mode: $version_file"
  grep -Fxq 'tag=v-test' "$version_file" \
    || fail "version state has the wrong tag: $version_file"
  grep -Eq '^installed_at=.+$' "$version_file" \
    || fail "version state is missing its installation timestamp: $version_file"
done

cmp -s "$command_version" "$config_version" \
  || fail "command and configuration version state diverged during installation"

printf 'Installer version-state permission tests passed.\n'
