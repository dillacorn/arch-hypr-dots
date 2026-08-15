#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
LAUNCHER="${ROOT}/local/bin/awtarchy"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

BRANCH="feature/testing"
BRANCH_ENCODED="feature%2Ftesting"
BRANCH_HEAD="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
ANCESTOR_COMMIT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OTHER_COMMIT="cccccccccccccccccccccccccccccccccccccccc"
MAIN_COMMIT="dddddddddddddddddddddddddddddddddddddddd"
RELEASE_COMMIT="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_arg_sequence() {
  local file="$1"
  shift
  local expected
  expected="$(printf '%s\n' "$@")"
  [[ $(<"$file") == "$expected" ]] \
    || fail "unexpected runtime arguments in ${file}: $(tr '\n' ' ' <"$file")"
}

fakebin="${TMPD}/bin"
home="${TMPD}/home"
runtime_log="${TMPD}/runtime.args"
curl_log="${TMPD}/curl.log"
mkdir -p -- \
  "$fakebin" \
  "$home/.local/bin" \
  "$home/.local/share/awtarchy" \
  "$home/.local/state/awtarchy"

cp -- "$LAUNCHER" "$home/.local/bin/awtarchy"
chmod 0755 "$home/.local/bin/awtarchy"

cat >"$home/.local/share/awtarchy/awtarchy-runtime.sh" <<'EOF_RUNTIME'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >"${AWTARCHY_TEST_RUNTIME_LOG:?}"
EOF_RUNTIME
chmod 0755 "$home/.local/share/awtarchy/awtarchy-runtime.sh"

printf 'tag=main\nrevision=%s\nupdated_at=2000-01-01T00:00:00Z\n' "$MAIN_COMMIT" \
  >"$home/.local/state/awtarchy/command-version"
printf 'tag=v2.0.0-1\nupdated_at=2000-01-01T00:00:00Z\n' \
  >"$home/.local/state/awtarchy/config-version"

cat >"${fakebin}/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -Eeuo pipefail

url=""
data_ref=""
while (( $# )); do
  case "$1" in
    -H|--connect-timeout|--max-time|--retry|--retry-delay|--speed-limit|--speed-time|-o|--output)
      shift 2
      ;;
    --get|--silent|--show-error|--progress-bar|-f|-L|-fL)
      shift
      ;;
    --data-urlencode)
      data_ref="${2#ref=}"
      shift 2
      ;;
    -* )
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

printf '%s\n' "$url" >>"${AWTARCHY_TEST_CURL_LOG:?}"

case "$url" in
  'https://api.github.com/repos/dillacorn/awtarchy/branches?per_page=100&page=1')
    printf '[{"name":"%s","commit":{"sha":"%s"}}]\n' \
      "${AWTARCHY_TEST_BRANCH:?}" "${AWTARCHY_TEST_BRANCH_HEAD:?}"
    ;;
  'https://api.github.com/repos/dillacorn/awtarchy/branches?per_page=100&page=2')
    printf '[]\n'
    ;;
  "https://api.github.com/repos/dillacorn/awtarchy/branches/${AWTARCHY_TEST_BRANCH_ENCODED:?}")
    printf '{"name":"%s","commit":{"sha":"%s"}}\n' \
      "${AWTARCHY_TEST_BRANCH:?}" "${AWTARCHY_TEST_BRANCH_HEAD:?}"
    ;;
  "https://api.github.com/repos/dillacorn/awtarchy/compare/${AWTARCHY_TEST_REQUESTED_COMMIT:?}...${AWTARCHY_TEST_BRANCH_HEAD:?}")
    printf '{"status":"%s","merge_base_commit":{"sha":"%s"}}\n' \
      "${AWTARCHY_TEST_COMPARE_STATUS:-ahead}" \
      "${AWTARCHY_TEST_MERGE_BASE:-${AWTARCHY_TEST_REQUESTED_COMMIT:?}}"
    ;;
  'https://api.github.com/repos/dillacorn/awtarchy/commits/main')
    printf '{"sha":"%s"}\n' "${AWTARCHY_TEST_MAIN_COMMIT:?}"
    ;;
  'https://api.github.com/repos/dillacorn/awtarchy/releases/latest')
    [[ ${AWTARCHY_TEST_RELEASE_API_FAIL:-0} == 0 ]] || exit 22
    printf '%s\n' '{"tag_name":"v9.9.9"}'
    ;;
  'https://api.github.com/repos/dillacorn/awtarchy/releases/tags/v9.9.9')
    printf '%s\n' '{"tag_name":"v9.9.9","draft":false,"published_at":"2026-01-01T00:00:00Z"}'
    ;;
  'https://api.github.com/repos/dillacorn/awtarchy/git/ref/tags/v9.9.9')
    printf '{"object":{"type":"commit","sha":"%s"}}\n' \
      "${AWTARCHY_TEST_RELEASE_COMMIT:?}"
    ;;
  'https://api.github.com/repos/dillacorn/awtarchy/contents/local/share/awtarchy/quickshell-managed-history.sha256')
    if [[ $data_ref == "${AWTARCHY_TEST_MAIN_COMMIT:?}" \
      && ${AWTARCHY_TEST_MAIN_HAS_QUICKSHELL:-0} == 1 ]];
    then
      exit 0
    fi
    if [[ $data_ref == "${AWTARCHY_TEST_RELEASE_COMMIT:?}" \
      && ${AWTARCHY_TEST_RELEASE_HAS_QUICKSHELL:-0} == 1 ]];
    then
      exit 0
    fi
    if [[ $data_ref == "${AWTARCHY_TEST_BRANCH:?}" \
      && ${AWTARCHY_TEST_BRANCH_AS_RELEASE:-0} == 1 ]];
    then
      exit 0
    fi
    exit 22
    ;;
  *)
    printf 'unexpected URL: %s\n' "$url" >&2
    exit 22
    ;;
esac
EOF_CURL
chmod 0755 "${fakebin}/curl"

common_env=(
  "HOME=$home"
  "USER=$(id -un)"
  "LOGNAME=$(id -un)"
  "PATH=${fakebin}:$PATH"
  "AWTARCHY_SKIP_UPDATE_CHECK=1"
  "AWTARCHY_TEST_RUNTIME_LOG=$runtime_log"
  "AWTARCHY_TEST_CURL_LOG=$curl_log"
  "AWTARCHY_TEST_BRANCH=$BRANCH"
  "AWTARCHY_TEST_BRANCH_ENCODED=$BRANCH_ENCODED"
  "AWTARCHY_TEST_BRANCH_HEAD=$BRANCH_HEAD"
  "AWTARCHY_TEST_REQUESTED_COMMIT=$ANCESTOR_COMMIT"
  "AWTARCHY_TEST_MAIN_COMMIT=$MAIN_COMMIT"
  "AWTARCHY_TEST_RELEASE_COMMIT=$RELEASE_COMMIT"
)

: >"$curl_log"
env "${common_env[@]}" \
  "$home/.local/bin/awtarchy" git review --branch "$BRANCH"
assert_arg_sequence "$runtime_log" \
  update-reset-backup \
  --mode preserve \
  --review-only \
  --testing-branch "$BRANCH" \
  --testing-commit "$BRANCH_HEAD"
grep -Fxq \
  "https://api.github.com/repos/dillacorn/awtarchy/branches/${BRANCH_ENCODED}" \
  "$curl_log" \
  || fail "git review did not resolve the selected remote branch"

: >"$runtime_log"
: >"$curl_log"
env "${common_env[@]}" \
  "$home/.local/bin/awtarchy" git update \
    --branch "$BRANCH" \
    --commit "$ANCESTOR_COMMIT" \
    --conflict-policy keep-local
assert_arg_sequence "$runtime_log" \
  update-reset-backup \
  --mode preserve \
  --testing-branch "$BRANCH" \
  --testing-commit "$ANCESTOR_COMMIT" \
  --conflict-policy keep-local
grep -Fxq \
  "https://api.github.com/repos/dillacorn/awtarchy/compare/${ANCESTOR_COMMIT}...${BRANCH_HEAD}" \
  "$curl_log" \
  || fail "exact git commit was not checked against the selected branch"

: >"$runtime_log"
env "${common_env[@]}" \
  "$home/.local/bin/awtarchy" git reset \
    --branch "$BRANCH" \
    --commit "$ANCESTOR_COMMIT" \
    --yes
assert_arg_sequence "$runtime_log" \
  update-reset-backup \
  --mode clean \
  --testing-branch "$BRANCH" \
  --testing-commit "$ANCESTOR_COMMIT" \
  --yes

: >"$runtime_log"
set +e
env \
  "${common_env[@]}" \
  "AWTARCHY_TEST_COMPARE_STATUS=diverged" \
  "AWTARCHY_TEST_MERGE_BASE=$OTHER_COMMIT" \
  "$home/.local/bin/awtarchy" git update \
    --branch "$BRANCH" \
    --commit "$ANCESTOR_COMMIT" \
    >"${TMPD}/wrong-branch.out" 2>&1
wrong_branch_rc=$?
set -e
(( wrong_branch_rc != 0 )) || fail "git mode accepted a commit outside the selected branch"
[[ ! -s $runtime_log ]] || fail "wrong-branch commit reached the updater runtime"
grep -Eqi 'selected branch|does not belong|not.*branch' "${TMPD}/wrong-branch.out" \
  || fail "wrong-branch rejection did not explain the ancestry failure"

set +e
env "${common_env[@]}" \
  "$home/.local/bin/awtarchy" git review --commit "$ANCESTOR_COMMIT" \
  >"${TMPD}/missing-branch.out" 2>&1
missing_branch_rc=$?
set -e
(( missing_branch_rc != 0 )) || fail "exact commit mode did not require a branch"
grep -Fqi -- '--branch' "${TMPD}/missing-branch.out" \
  || fail "missing-branch failure did not identify the required option"

set +e
env "${common_env[@]}" \
  "$home/.local/bin/awtarchy" git review \
    --branch "$BRANCH" \
    --commit deadbeef \
    >"${TMPD}/short-sha.out" 2>&1
short_sha_rc=$?
set -e
(( short_sha_rc != 0 )) || fail "git mode accepted a shortened commit SHA"
grep -Fqi '40-character' "${TMPD}/short-sha.out" \
  || fail "short-SHA failure did not explain the exact-SHA requirement"

: >"$runtime_log"
set +e
env "${common_env[@]}" \
  "$home/.local/bin/awtarchy" update --testing-commit "$ANCESTOR_COMMIT" \
  >"${TMPD}/stable-override.out" 2>&1
stable_override_rc=$?
set -e
(( stable_override_rc != 0 )) \
  || fail "stable update accepted a hidden testing-commit override"
[[ ! -s $runtime_log ]] || fail "stable testing override reached the updater runtime"
grep -Fqi 'awtarchy git' "${TMPD}/stable-override.out" \
  || fail "stable override rejection did not direct the user to git mode"

: >"$runtime_log"
set +e
env \
  "${common_env[@]}" \
  AWTARCHY_TEST_BRANCH_AS_RELEASE=1 \
  "$home/.local/bin/awtarchy" update --tag "$BRANCH" \
  >"${TMPD}/branch-as-release.out" 2>&1
branch_as_release_rc=$?
set -e
(( branch_as_release_rc != 0 )) \
  || fail "stable update accepted a repository branch as a release tag"
[[ ! -s $runtime_log ]] \
  || fail "branch supplied through --tag reached the stable updater runtime"
grep -Eqi 'published release|release tag' "${TMPD}/branch-as-release.out" \
  || fail "branch-as-release rejection did not explain the published-release requirement"

# When the installed configs are from Git testing, a pre-Quickshell stable
# release must be rejected before the command/runtime can refresh from an older
# main implementation that does not understand the integrated testing state.
printf 'tag=%s@%s\nupdated_at=2000-01-01T00:00:00Z\n' \
  "$BRANCH" "$ANCESTOR_COMMIT" \
  >"$home/.local/state/awtarchy/config-version"
cat >"$home/.local/state/awtarchy/git-testing" <<EOF_STATE
branch=${BRANCH}
revision=${ANCESTOR_COMMIT}
stable_release=v2.0.0-1
tested_at=2000-01-01T00:00:00Z
EOF_STATE
: >"$runtime_log"
: >"$curl_log"
set +e
env "${common_env[@]}" AWTARCHY_SKIP_UPDATE_CHECK=0 \
  "$home/.local/bin/awtarchy" update \
  >"${TMPD}/pre-release-return.out" 2>&1
pre_release_return_rc=$?
set -e
(( pre_release_return_rc != 0 )) \
  || fail "stable update entered a pre-Quickshell release from active git-testing state"
[[ ! -s $runtime_log ]] \
  || fail "pre-Quickshell stable return reached the updater runtime"
! grep -Fxq \
  'https://api.github.com/repos/dillacorn/awtarchy/commits/main' \
  "$curl_log" \
  || fail "git-testing guard ran only after refreshing the updater from main"
grep -Fqi 'predates the Quickshell migration' "${TMPD}/pre-release-return.out" \
  || fail "pre-Quickshell stable return did not explain the compatibility block"

printf 'tag=unreleased\nrevision=%s\ninstalled_at=2000-01-01T00:00:00Z\n' \
  "$BRANCH_HEAD" >"$home/.local/state/awtarchy/command-version"
: >"$curl_log"
set +e
env "${common_env[@]}" \
  "$home/.local/bin/awtarchy" self-update \
  >"${TMPD}/incompatible-self-update.out" 2>&1
incompatible_self_update_rc=$?
set -e
(( incompatible_self_update_rc != 0 )) \
  || fail "self-update replaced Git-aware command state with an incompatible main runtime"
grep -Eqi 'current main.*predates|main.*does not.*Quickshell' \
  "${TMPD}/incompatible-self-update.out" \
  || fail "incompatible self-update did not explain the main compatibility block"
! grep -Fq "/archive/${MAIN_COMMIT}.tar.gz" "$curl_log" \
  || fail "incompatible self-update downloaded main before checking compatibility"

printf 'tag=%s@%s\nupdated_at=2000-01-01T00:00:00Z\n' \
  "$BRANCH" "$ANCESTOR_COMMIT" \
  >"$home/.local/state/awtarchy/config-version"
cat >"$home/.local/state/awtarchy/git-testing" <<EOF_STATE
branch=${BRANCH}
revision=${ANCESTOR_COMMIT}
stable_release=v2.0.0-1
tested_at=2000-01-01T00:00:00Z
EOF_STATE
version_output="$(env "${common_env[@]}" "$home/.local/bin/awtarchy" version)"
grep -Fq 'Git testing:        active' <<<"$version_output" \
  || fail "version did not identify active git-testing state"
grep -Fq "Git branch:         ${BRANCH}" <<<"$version_output" \
  || fail "version did not show the tested branch"
grep -Fq "Git revision:       ${ANCESTOR_COMMIT}" <<<"$version_output" \
  || fail "version did not show the tested revision"
grep -Fq 'Stable predecessor: v2.0.0-1' <<<"$version_output" \
  || fail "version did not preserve the preceding stable release"
offline_version_output="$(
  env "${common_env[@]}" AWTARCHY_TEST_RELEASE_API_FAIL=1 \
    "$home/.local/bin/awtarchy" version
)"
grep -Fq 'Git testing:        active' <<<"$offline_version_output" \
  || fail "version hid active git-testing state when the release API was unavailable"
grep -Fq "Git revision:       ${ANCESTOR_COMMIT}" <<<"$offline_version_output" \
  || fail "offline version output hid the tested revision"

printf 'tag=v9.9.9\nupdated_at=2000-01-01T00:00:00Z\n' \
  >"$home/.local/state/awtarchy/config-version"
stale_marker_output="$(env "${common_env[@]}" "$home/.local/bin/awtarchy" version)"
grep -Fq 'Git testing:        inactive' <<<"$stale_marker_output" \
  || fail "version trusted a stale git-testing marker over stable config state"

command -v script >/dev/null 2>&1 || fail "script is required for the git menu test"
: >"$runtime_log"
rm -f -- "$home/.local/state/awtarchy/git-testing"
printf 'tag=v2.0.0-1\nupdated_at=2000-01-01T00:00:00Z\n' \
  >"$home/.local/state/awtarchy/config-version"
printf '\n\n' | env "${common_env[@]}" \
  script -qefc "bash '$home/.local/bin/awtarchy' git" /dev/null \
  >"${TMPD}/interactive.out" 2>&1
assert_arg_sequence "$runtime_log" \
  update-reset-backup \
  --mode preserve \
  --review-only \
  --testing-branch "$BRANCH" \
  --testing-commit "$BRANCH_HEAD"
grep -Fq "Selected remote branch: ${BRANCH}" "${TMPD}/interactive.out" \
  || fail "interactive git menu did not identify the selected branch"
grep -Fq "Exact revision: ${BRANCH_HEAD}" "${TMPD}/interactive.out" \
  || fail "interactive git menu did not display the pinned revision"

printf 'Awtarchy git mode tests passed.\n'
