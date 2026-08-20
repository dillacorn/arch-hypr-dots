#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="${ROOT}/local/bin/awtarchy"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f $LAUNCHER ]] || fail "missing launcher: $LAUNCHER"

function_text="$(awk '
  /^updater_branch_head\(\) \{/ { capture=1 }
  capture { print }
  capture && /^}$/ { exit }
' "$LAUNCHER")"
[[ $function_text == updater_branch_head* ]] \
  || fail 'could not extract updater_branch_head()'

fakebin="$TMP/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail
sha='2222222222222222222222222222222222222222'
printf '{"sha":"%s","padding":"' "$sha"
head -c 262144 /dev/zero | tr '\0' x
printf '"}\n'
EOF_CURL
chmod 0755 "$fakebin/curl"

have() {
  command -v "$1" >/dev/null 2>&1
}

curl_args() {
  CURL_ARGS=()
}

REPO_OWNER=dillacorn
REPO_NAME=awtarchy
UPDATER_BRANCH=main
CURL_ARGS=()

eval "$function_text"

result="$(PATH="$fakebin:$PATH" updater_branch_head)" \
  || fail 'updater_branch_head could not parse a large GitHub commit response'
[[ $result == 2222222222222222222222222222222222222222 ]] \
  || fail "unexpected updater head: $result"

printf '%s\n' 'Large main commit response regression test passed.'
