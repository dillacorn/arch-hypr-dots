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

for needle in \
  '_aur_guard_runtime_dispatch()' \
  '_aur_guard_runtime_ensure()' \
  '# AWTARCHY_AURGUARD_RUNTIME_BEGIN v1' \
  '# AWTARCHY_AURGUARD_RUNTIME_END v1' \
  'AWTARCHY_AURGUARD_RUNTIME_ACTIVE=1' \
  'aurguard-runtime.sh' \
  'aurguard-runtime'; do
  grep -Fq -- "$needle" "$BASHRC" || fail "missing runtime-refresh boundary: $needle"
done

grep -Fq 'flock' "$BASHRC" || fail 'runtime refresh is not serialized with flock'

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/data"
export XDG_STATE_HOME="$TMP/state"
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$TMP/bin"

NETWORK_LOG="$TMP/network.log"
HEAD_FILE="$TMP/head-sequence"
SOURCE_FILE="$TMP/remote-bashrc"
FAIL_FILE="$TMP/fail-network"
export AWTARCHY_TEST_RUNTIME_NETWORK_LOG="$NETWORK_LOG"
export AWTARCHY_TEST_RUNTIME_HEAD_FILE="$HEAD_FILE"
export AWTARCHY_TEST_RUNTIME_SOURCE_FILE="$SOURCE_FILE"
export AWTARCHY_TEST_RUNTIME_FAIL_FILE="$FAIL_FILE"

cat > "$TMP/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail

output=''
url=''
while (( $# > 0 )); do
  case "$1" in
    -o|--output)
      output="$2"
      shift 2
      ;;
    -H|--header|--connect-timeout|--max-time|--retry|--retry-delay|--speed-limit|--speed-time|--proto)
      shift 2
      ;;
    -f|-L|-s|-S|-fsSL|--fail|--location|--silent|--show-error|--tlsv1.2)
      shift
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$url" ]] || exit 64
printf '%s\n' "$url" >> "${AWTARCHY_TEST_RUNTIME_NETWORK_LOG:?}"
[[ ! -e "${AWTARCHY_TEST_RUNTIME_FAIL_FILE:?}" ]] || exit 22

payload=''
if [[ "$url" == *'/commits/'* ]]; then
  mapfile -t heads < "${AWTARCHY_TEST_RUNTIME_HEAD_FILE:?}"
  (( ${#heads[@]} > 0 )) || exit 65
  head=${heads[0]}
  if (( ${#heads[@]} > 1 )); then
    printf '%s\n' "${heads[@]:1}" > "${AWTARCHY_TEST_RUNTIME_HEAD_FILE}"
  fi
  payload=$(printf '{"sha":"%s"}\n' "$head")
elif [[ "$url" == *'raw.githubusercontent.com/dillacorn/awtarchy/'*'/bashrc' ]]; then
  payload=$(cat "${AWTARCHY_TEST_RUNTIME_SOURCE_FILE:?}")
else
  exit 66
fi

if [[ -n "$output" ]]; then
  printf '%s\n' "$payload" > "$output"
else
  printf '%s\n' "$payload"
fi
EOF_CURL
chmod 0755 "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

cat > "$SOURCE_FILE" <<'EOF_REMOTE'
# shellcheck shell=bash
# AWTARCHY_AURGUARD_RUNTIME_BEGIN v1
_aur_guard_scan_checkout_with_aur_scan() { :; }
aurverify() { printf 'REMOTE aurverify %s\n' "$*"; }
aurinstall() { printf 'REMOTE aurinstall %s\n' "$*"; }
aurguard() { printf 'REMOTE aurguard %s\n' "$*"; }
# AWTARCHY_AURGUARD_RUNTIME_END v1
EOF_REMOTE

# Source the user's Bash configuration fixture without its interactive-shell early return.
# shellcheck disable=SC1090
source <(sed '/^\[\[ \$- != \*i\* \]\] && return$/d' "$BASHRC")

RUNTIME="$XDG_DATA_HOME/awtarchy/aurguard-runtime.sh"
META="$XDG_STATE_HOME/awtarchy/aurguard-runtime"
GIT_STATE="$XDG_STATE_HOME/awtarchy/git-testing"
CONFIG_STATE="$XDG_STATE_HOME/awtarchy/config-version"
COMMIT_A='1111111111111111111111111111111111111111'
COMMIT_B='2222222222222222222222222222222222222222'
COMMIT_GIT='3333333333333333333333333333333333333333'
COMMIT_C='4444444444444444444444444444444444444444'

set_meta_time() {
  local when="$1"
  local tmp="$META.tmp"
  awk -F= -v when="$when" '
    $1 == "fetched_at" { print "fetched_at=" when; next }
    { print }
  ' "$META" > "$tmp"
  mv -f -- "$tmp" "$META"
}

meta_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$META"
}

printf '%s\n' "$COMMIT_A" "$COMMIT_A" > "$HEAD_FILE"
: > "$NETWORK_LOG"
output=$(aurverify first)
[[ "$output" == *'REMOTE aurverify first'* ]] || fail 'missing-cache dispatch did not execute downloaded runtime'
[[ -f "$RUNTIME" && ! -L "$RUNTIME" ]] || fail 'runtime cache was not atomically installed as a regular file'
[[ -f "$META" && ! -L "$META" ]] || fail 'runtime metadata was not written as a regular file'
[[ $(meta_value revision) == "$COMMIT_A" ]] || fail 'runtime metadata did not pin the resolved exact commit'
grep -Fq '# AWTARCHY_AURGUARD_RUNTIME v1' "$RUNTIME" || fail 'cached runtime identity marker is missing'

: > "$NETWORK_LOG"
output=$(aurverify fresh)
[[ "$output" == *'REMOTE aurverify fresh'* ]] || fail 'fresh cache did not dispatch'
[[ ! -s "$NETWORK_LOG" ]] || fail 'fresh cache performed a network refresh before 24 hours'

set_meta_time "$(( $(date +%s) - 90000 ))"
printf '%s\n' "$COMMIT_A" "$COMMIT_A" > "$HEAD_FILE"
: > "$NETWORK_LOG"
output=$(aurverify stale)
[[ "$output" == *'REMOTE aurverify stale'* ]] || fail 'stale cache refresh did not dispatch'
[[ -s "$NETWORK_LOG" ]] || fail 'stale cache did not attempt a refresh'

set_meta_time "$(( $(date +%s) - 90000 ))"
touch "$FAIL_FILE"
: > "$NETWORK_LOG"
if ! output=$(aurverify fallback 2>&1); then
  fail 'refresh failure did not fall back to a previously validated cache'
fi
[[ "$output" == *'REMOTE aurverify fallback'* ]] || fail 'validated stale cache was not dispatched after refresh failure'
[[ "$output" == *'cached AurGuard runtime'* ]] || fail 'refresh fallback did not emit a concise cached-runtime warning'
rm -f -- "$FAIL_FILE"

cp -a -- "$RUNTIME" "$TMP/valid-runtime"
cp -a -- "$META" "$TMP/valid-meta"
rm -f -- "$RUNTIME" "$META"
touch "$FAIL_FILE"
if aurverify no-cache >/dev/null 2>&1; then
  fail 'refresh failure without a valid cache did not fail closed'
fi
rm -f -- "$FAIL_FILE"
install -Dm600 "$TMP/valid-runtime" "$RUNTIME"
install -Dm600 "$TMP/valid-meta" "$META"

valid_hash=$(sha256sum "$RUNTIME" | awk '{print $1}')
set_meta_time "$(( $(date +%s) - 90000 ))"
cat > "$SOURCE_FILE" <<'EOF_BAD'
# AWTARCHY_AURGUARD_RUNTIME_BEGIN v1
aurverify() {
# AWTARCHY_AURGUARD_RUNTIME_END v1
EOF_BAD
printf '%s\n' "$COMMIT_A" "$COMMIT_A" > "$HEAD_FILE"
if ! output=$(aurverify bad-candidate 2>&1); then
  fail 'bad refresh candidate did not preserve the validated old cache'
fi
[[ "$output" == *'REMOTE aurverify bad-candidate'* ]] || fail 'old cache was not used after bad candidate rejection'
[[ $(sha256sum "$RUNTIME" | awk '{print $1}') == "$valid_hash" ]] || fail 'bad candidate replaced the validated runtime cache'

cat > "$SOURCE_FILE" <<'EOF_REMOTE'
# shellcheck shell=bash
# AWTARCHY_AURGUARD_RUNTIME_BEGIN v1
_aur_guard_scan_checkout_with_aur_scan() { :; }
aurverify() { printf 'REMOTE aurverify %s\n' "$*"; }
aurinstall() { printf 'REMOTE aurinstall %s\n' "$*"; }
aurguard() { printf 'REMOTE aurguard %s\n' "$*"; }
# AWTARCHY_AURGUARD_RUNTIME_END v1
EOF_REMOTE
rm -f -- "$RUNTIME" "$META"
printf '%s\n' "$COMMIT_A" "$COMMIT_B" "$COMMIT_B" "$COMMIT_B" > "$HEAD_FILE"
: > "$NETWORK_LOG"
output=$(aurverify moved-head)
[[ "$output" == *'REMOTE aurverify moved-head'* ]] || fail 'branch-head retry did not dispatch a stable candidate'
[[ $(meta_value revision) == "$COMMIT_B" ]] || fail 'candidate fetched across a moving branch head was not rejected and retried'
grep -Fq "/$COMMIT_A/bashrc" "$NETWORK_LOG" || fail 'moving-head test did not fetch the first exact revision'
grep -Fq "/$COMMIT_B/bashrc" "$NETWORK_LOG" || fail 'moving-head test did not retry with the stable exact revision'

rm -f -- "$RUNTIME" "$META"
mkdir -p -- "$(dirname -- "$GIT_STATE")"
printf 'branch=feature/runtime-test\nrevision=%s\nstable_release=v0\n' "$COMMIT_GIT" > "$GIT_STATE"
printf 'tag=feature/runtime-test@%s\n' "$COMMIT_GIT" > "$CONFIG_STATE"
printf '%s\n' "$COMMIT_A" > "$HEAD_FILE"
: > "$NETWORK_LOG"
output=$(aurverify git-pin)
[[ "$output" == *'REMOTE aurverify git-pin'* ]] || fail 'Git-testing exact revision did not dispatch'
[[ $(meta_value revision) == "$COMMIT_GIT" ]] || fail 'Git-testing runtime was not pinned to the exact testing revision'
grep -Fq "/$COMMIT_GIT/bashrc" "$NETWORK_LOG" || fail 'Git-testing runtime did not fetch the exact testing commit'
if grep -Fq '/commits/main' "$NETWORK_LOG"; then
  fail 'Git-testing runtime incorrectly resolved mutable main'
fi

rm -f -- "$GIT_STATE" "$CONFIG_STATE" "$RUNTIME" "$META"
printf '%s\n' "$COMMIT_C" "$COMMIT_C" > "$HEAD_FILE"
: > "$NETWORK_LOG"
(aurverify concurrent-one > "$TMP/concurrent-one.log" 2>&1) &
pid_one=$!
(aurverify concurrent-two > "$TMP/concurrent-two.log" 2>&1) &
pid_two=$!
wait "$pid_one"
wait "$pid_two"
grep -Fq 'REMOTE aurverify concurrent-one' "$TMP/concurrent-one.log" || fail 'first concurrent dispatch failed'
grep -Fq 'REMOTE aurverify concurrent-two' "$TMP/concurrent-two.log" || fail 'second concurrent dispatch failed'
raw_count=$(grep -c 'raw.githubusercontent.com/dillacorn/awtarchy/' "$NETWORK_LOG" || true)
[[ "$raw_count" == 1 ]] || fail "concurrent cache miss performed $raw_count candidate downloads instead of one"

: > "$NETWORK_LOG"
printf '%s\n' "$COMMIT_C" "$COMMIT_C" > "$HEAD_FILE"
aurguard refresh >/dev/null
[[ -s "$NETWORK_LOG" ]] || fail 'aurguard refresh did not force an exact-commit refresh'

old_runtime_hash=$(sha256sum "$RUNTIME" | awk '{print $1}')
old_meta_hash=$(sha256sum "$META" | awk '{print $1}')
rollback_candidate="$TMP/rollback-candidate"
cat > "$rollback_candidate" <<'EOF_ROLLBACK'
# AWTARCHY_AURGUARD_RUNTIME v1
# shellcheck shell=bash
_aur_guard_scan_checkout_with_aur_scan() { :; }
aurverify() { printf 'NEW aurverify %s\n' "$*"; }
aurinstall() { printf 'NEW aurinstall %s\n' "$*"; }
aurguard() { printf 'NEW aurguard %s\n' "$*"; }
EOF_ROLLBACK
chmod 0600 "$rollback_candidate"

mv() {
  local destination="${@: -1}"
  if [[ "$destination" == "$META" ]]; then
    return 1
  fi
  command mv "$@"
}
if _aur_guard_runtime_activate_candidate "$rollback_candidate" main "$COMMIT_A"; then
  fail 'runtime activation unexpectedly succeeded when metadata activation failed'
fi
unset -f mv
[[ $(sha256sum "$RUNTIME" | awk '{print $1}') == "$old_runtime_hash" ]] \
  || fail 'metadata activation failure destroyed the previously validated runtime cache'
[[ $(sha256sum "$META" | awk '{print $1}') == "$old_meta_hash" ]] \
  || fail 'metadata activation failure modified the previously validated runtime metadata'
_aur_guard_runtime_cache_valid \
  || fail 'metadata activation failure did not leave the previous cache valid'

printf 'PASS: AurGuard runtime refresh uses a 24-hour exact-commit cache, fail-closed validation, Git-testing pinning, flock serialization, and activation rollback.\n'