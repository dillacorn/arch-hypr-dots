#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
TEST_USER=""

cleanup() {
  if [[ -n ${TEST_USER:-} ]] && command -v sudo >/dev/null 2>&1; then
    sudo userdel -r "$TEST_USER" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$TMP"
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

bash -n "$ROOT/awtarchy.sh"
bash -n "$ROOT/local/bin/awtarchy"

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
cp "$ROOT/local/bin/awtarchy" "$home/.local/bin/awtarchy"
cp "$ROOT/awtarchy.sh" "$home/.local/share/awtarchy/awtarchy.sh"
chmod 0755 "$home/.local/bin/awtarchy" "$home/.local/share/awtarchy/awtarchy.sh"
printf 'tag=v0.0.0\nupdated_at=2000-01-01T00:00:00Z\n' >"$home/.local/state/awtarchy/version"

version_output="$(
  HOME="$home" USER="$(id -un)" PATH="${fakebin}:$PATH" \
    AWTARCHY_TEST_ARCHIVE="${TMP}/release.tar.gz" \
    "$home/.local/bin/awtarchy" version
)"
grep -Fq 'Installed release: v0.0.0' <<<"$version_output" || fail "version did not report installed release"
grep -Fq 'Latest release:    v9.9.9' <<<"$version_output" || fail "version did not report latest release"

HOME="$home" USER="$(id -un)" PATH="${fakebin}:$PATH" \
  AWTARCHY_TEST_ARCHIVE="${TMP}/release.tar.gz" \
  "$home/.local/bin/awtarchy" self-update --tag v9.9.9

assert_executable "$home/.local/bin/awtarchy"
assert_executable "$home/.local/share/awtarchy/awtarchy.sh"
grep -Fxq 'tag=v9.9.9' "$home/.local/state/awtarchy/version" || fail "self-update did not write release state"
HOME="$home" USER="$(id -un)" AWTARCHY_SKIP_UPDATE_CHECK=1 \
  "$home/.local/bin/awtarchy" help >/dev/null

if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  TEST_USER="awtarchy-ci-${RANDOM}-$$"
  user_home="${TMP}/${TEST_USER}"
  runtime_dir="${TMP}/runtime-${TEST_USER}"
  sudo useradd -m -d "$user_home" -s /bin/bash "$TEST_USER"
  mkdir -p "$runtime_dir"
  sudo chown "$TEST_USER:$TEST_USER" "$runtime_dir"
  chmod 0755 "$TMP" "$fakebin"
  chmod 0644 "${TMP}/release.tar.gz"

  sudo -u "$TEST_USER" env \
    HOME="$user_home" \
    USER="$TEST_USER" \
    LOGNAME="$TEST_USER" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    PATH="${fakebin}:$PATH" \
    AWTARCHY_TEST_ARCHIVE="${TMP}/release.tar.gz" \
    bash "$ROOT/awtarchy.sh" update-reset-backup --mode clean --tag v9.9.9

  assert_executable "$user_home/.local/bin/awtarchy"
  assert_executable "$user_home/.local/share/awtarchy/awtarchy.sh"
  assert_file "$user_home/.local/state/awtarchy/version"
  grep -Fxq 'tag=v9.9.9' "$user_home/.local/state/awtarchy/version" || fail "managed update wrote the wrong release state"
fi

printf 'Awtarchy command tests passed.\n'
