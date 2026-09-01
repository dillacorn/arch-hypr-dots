#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
LAUNCHER="${ROOT}/local/bin/awtarchy"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

BRANCH='feature/testing'
TEST_REV='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
MAIN_REV='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

home="${TMPD}/home"
fakebin="${TMPD}/bin"
archive_parent="${TMPD}/archive"
archive_root="${archive_parent}/awtarchy-${TEST_REV}"
archive="${TMPD}/testing.tar.gz"
curl_log="${TMPD}/curl.log"
mkdir -p -- \
  "$home/.local/bin" \
  "$home/.local/share/awtarchy" \
  "$home/.local/state/awtarchy" \
  "$fakebin" \
  "$archive_root/local/share/awtarchy"

cp -- "$LAUNCHER" "$home/.local/bin/awtarchy"
chmod 0755 "$home/.local/bin/awtarchy"

cat >"$home/.local/share/awtarchy/awtarchy-runtime.sh" <<'EOF_MAIN_RUNTIME'
#!/usr/bin/env bash
# MAIN-RUNTIME
EOF_MAIN_RUNTIME
chmod 0755 "$home/.local/share/awtarchy/awtarchy-runtime.sh"

cat >"$home/.local/share/awtarchy/awtarchy-package-reconcile.sh" <<'EOF_MAIN_RECONCILER'
#!/usr/bin/env bash
printf '%s\n' 'MAIN-RECONCILER'
EOF_MAIN_RECONCILER
chmod 0755 "$home/.local/share/awtarchy/awtarchy-package-reconcile.sh"

cat >"$archive_root/local/share/awtarchy/awtarchy-runtime.sh" <<'EOF_TEST_RUNTIME'
#!/usr/bin/env bash
# TESTING-RUNTIME
EOF_TEST_RUNTIME
chmod 0755 "$archive_root/local/share/awtarchy/awtarchy-runtime.sh"

cat >"$archive_root/local/share/awtarchy/awtarchy-package-reconcile.sh" <<'EOF_TEST_RECONCILER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' 'TESTING-RECONCILER'
grep -Fq 'TESTING-RUNTIME' "${AWTARCHY_RUNTIME:?}" \
  || { printf '%s\n' 'WRONG-RUNTIME' >&2; exit 44; }
printf 'runtime=%s\n' "$AWTARCHY_RUNTIME"
EOF_TEST_RECONCILER
chmod 0755 "$archive_root/local/share/awtarchy/awtarchy-package-reconcile.sh"

tar -czf "$archive" -C "$archive_parent" "$(basename -- "$archive_root")"

printf 'tag=main\nrevision=%s\nupdated_at=2000-01-01T00:00:00Z\n' "$MAIN_REV" \
  >"$home/.local/state/awtarchy/command-version"
printf 'tag=%s@%s\nupdated_at=2000-01-01T00:00:00Z\n' "$BRANCH" "$TEST_REV" \
  >"$home/.local/state/awtarchy/config-version"
cat >"$home/.local/state/awtarchy/git-testing" <<EOF_STATE
branch=${BRANCH}
revision=${TEST_REV}
stable_release=v9.9.9
tested_at=2000-01-01T00:00:00Z
EOF_STATE

cat >"$fakebin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -Eeuo pipefail

out=''
url=''
while (( $# )); do
  case "$1" in
    -o|--output)
      out="$2"
      shift 2
      ;;
    -H|--connect-timeout|--max-time|--retry|--retry-delay|--speed-limit|--speed-time)
      shift 2
      ;;
    --get|--silent|--show-error|--progress-bar|-f|-L|-fL)
      shift
      ;;
    --data-urlencode)
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

if [[ $url == 'https://api.github.com/repos/dillacorn/awtarchy/commits/main' ]]; then
  printf '{"sha":"%s"}\n' "${AWTARCHY_TEST_MAIN_REV:?}"
  exit 0
fi

if [[ $url == "https://github.com/dillacorn/awtarchy/archive/${AWTARCHY_TEST_REV:?}.tar.gz" ]]; then
  [[ -n $out ]] || exit 3
  cp -- "${AWTARCHY_TEST_ARCHIVE:?}" "$out"
  exit 0
fi

printf 'unexpected URL: %s\n' "$url" >&2
exit 22
EOF_CURL
chmod 0755 "$fakebin/curl"

: >"$curl_log"
output="$(
  env \
    HOME="$home" \
    USER="$(id -un)" \
    LOGNAME="$(id -un)" \
    PATH="${fakebin}:$PATH" \
    AWTARCHY_TEST_CURL_LOG="$curl_log" \
    AWTARCHY_TEST_MAIN_REV="$MAIN_REV" \
    AWTARCHY_TEST_REV="$TEST_REV" \
    AWTARCHY_TEST_ARCHIVE="$archive" \
    "$home/.local/bin/awtarchy" packages --review
)"

grep -Fq 'TESTING-RECONCILER' <<<"$output" \
  || fail "packages did not execute the reconciler from the active Git-testing revision"
! grep -Fq 'MAIN-RECONCILER' <<<"$output" \
  || fail "packages executed the installed main reconciler during active Git testing"
grep -Fq "/archive/${TEST_REV}.tar.gz" "$curl_log" \
  || fail "packages did not fetch the exact active Git-testing revision"

grep -Fxq 'tag=main' "$home/.local/state/awtarchy/command-version" \
  || fail "Git-testing package execution changed main command state"
grep -Fxq "revision=${MAIN_REV}" "$home/.local/state/awtarchy/command-version" \
  || fail "Git-testing package execution changed main command revision"

printf 'Awtarchy Git-testing package handoff test passed.\n'
