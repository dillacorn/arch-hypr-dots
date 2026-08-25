#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKER="${ROOT}/config/hypr/scripts/quickshell_update_notifications.sh"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
DEFAULT_TERMINAL="${ROOT}/config/hypr/scripts/default_terminal.sh"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x $CHECKER ]] || fail "missing executable update checker: $CHECKER"
[[ -x $APP_STATE ]] || fail "missing executable Quickshell state writer: $APP_STATE"
[[ -x $DEFAULT_TERMINAL ]] || fail "missing executable default terminal helper: $DEFAULT_TERMINAL"

fakebin="${TMPD}/bin"
mkdir -p -- "$fakebin"

cat >"${fakebin}/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail

url="${!#}"
scenario="${AWTARCHY_TEST_SCENARIO:?}"

if [[ $scenario == offline ]]; then
  exit 22
fi

latest_tag=v3.2.1
installed_tag=v3.2.1
case "$scenario" in
  stable-update) installed_tag=v3.1.5 ;;
  suppressed-five) installed_tag=v3.1.2 ;;
  suppressed-new-target)
    latest_tag=v3.2.2
    installed_tag=v3.1.2
    ;;
  prerelease)
    latest_tag=v3.3.0-rc1
    ;;
esac

case "$url" in
  *'/releases/latest')
    if [[ $scenario == prerelease ]]; then
      printf '%s\n' '{"tag_name":"v3.3.0-rc1","draft":false,"prerelease":true,"published_at":"2026-09-01T00:00:00Z"}'
    else
      printf '{"tag_name":"%s","draft":false,"prerelease":false,"published_at":"2026-09-01T00:00:00Z"}\n' "$latest_tag"
    fi
    ;;
  *'/releases?per_page=100')
    if [[ $scenario == suppressed-new-target ]]; then
      printf '%s\n' '[{"tag_name":"v3.2.2","draft":false,"prerelease":false,"published_at":"2026-09-02T00:00:00Z"},{"tag_name":"v3.2.1","draft":false,"prerelease":false,"published_at":"2026-09-01T00:00:00Z"},{"tag_name":"v3.2.0","draft":false,"prerelease":false,"published_at":"2026-08-31T00:00:00Z"},{"tag_name":"v3.1.5","draft":false,"prerelease":false,"published_at":"2026-08-30T00:00:00Z"},{"tag_name":"v3.1.4","draft":false,"prerelease":false,"published_at":"2026-08-29T00:00:00Z"},{"tag_name":"v3.1.3","draft":false,"prerelease":false,"published_at":"2026-08-28T00:00:00Z"},{"tag_name":"v3.1.2","draft":false,"prerelease":false,"published_at":"2026-08-27T00:00:00Z"}]'
    else
      printf '%s\n' '[{"tag_name":"v3.2.1","draft":false,"prerelease":false,"published_at":"2026-09-01T00:00:00Z"},{"tag_name":"v3.2.0","draft":false,"prerelease":false,"published_at":"2026-08-31T00:00:00Z"},{"tag_name":"v3.1.5","draft":false,"prerelease":false,"published_at":"2026-08-30T00:00:00Z"},{"tag_name":"v3.1.4","draft":false,"prerelease":false,"published_at":"2026-08-29T00:00:00Z"},{"tag_name":"v3.1.3","draft":false,"prerelease":false,"published_at":"2026-08-28T00:00:00Z"},{"tag_name":"v3.1.2","draft":false,"prerelease":false,"published_at":"2026-08-27T00:00:00Z"}]'
    fi
    ;;
  *'/commits/main')
    printf '%s\n' '{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'
    ;;
  *'/contents/local/bin/awtarchy?ref=main')
    if [[ $scenario == maintenance ]]; then
      printf '%s\n' '{"sha":"cf38f834176b1dc723240ad3702bf724cb24fa16"}'
    else
      printf '%s\n' '{"sha":"4b7466765911025eda8c118e2ecefac5e849c6ab"}'
    fi
    ;;
  *'/contents/local/share/awtarchy/awtarchy-runtime.sh?ref=main')
    if [[ $scenario == maintenance ]]; then
      printf '%s\n' '{"sha":"03bfa73745ec1ca66ef0b5bec8ae98ff0162bb1f"}'
    else
      printf '%s\n' '{"sha":"7c508a43503b8361f26872e28b6bc1a26b9360e5"}'
    fi
    ;;
  *)
    printf 'unexpected URL: %s\n' "$url" >&2
    exit 22
    ;;
esac
EOF_CURL

cat >"${fakebin}/notify-send" <<'EOF_NOTIFY'
#!/usr/bin/env bash
set -euo pipefail
python3 - "${AWTARCHY_TEST_NOTIFY_LOG:?}" "$@" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps(sys.argv[2:]), encoding="utf-8")
PY
printf '%s\n' "${AWTARCHY_TEST_ACTION:-}"
EOF_NOTIFY

cat >"${fakebin}/default-terminal" <<'EOF_TERMINAL'
#!/usr/bin/env bash
set -euo pipefail
python3 - "${AWTARCHY_TEST_TERMINAL_LOG:?}" "$@" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps(sys.argv[2:]), encoding="utf-8")
PY
EOF_TERMINAL

cat >"${fakebin}/xdg-open" <<'EOF_XDG_OPEN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"${AWTARCHY_TEST_RELEASE_LOG:?}"
EOF_XDG_OPEN

chmod 0755 \
  "${fakebin}/curl" \
  "${fakebin}/notify-send" \
  "${fakebin}/default-terminal" \
  "${fakebin}/xdg-open"

new_home() {
  local name="$1" config_tag="$2" command_revision="${3:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
  local home="${TMPD}/${name}"
  mkdir -p -- \
    "${home}/.cache/awtarchy" \
    "${home}/.config/hypr/scripts" \
    "${home}/.local/bin" \
    "${home}/.local/share/awtarchy" \
    "${home}/.local/state/awtarchy"
  printf '%s\n' 'launcher-current' >"${home}/.local/bin/awtarchy"
  printf '%s\n' 'runtime-current' >"${home}/.local/share/awtarchy/awtarchy-runtime.sh"
  printf 'tag=%s\nupdated_at=2026-01-01T00:00:00Z\n' "$config_tag" \
    >"${home}/.local/state/awtarchy/config-version"
  printf 'tag=main\nrevision=%s\nupdated_at=2026-01-01T00:00:00Z\n' "$command_revision" \
    >"${home}/.local/state/awtarchy/command-version"
  printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' \
    >"${home}/.cache/awtarchy/quickshell-state.json"
  printf '%s\n' "$home"
}

run_check() {
  local home="$1" scenario="$2" action="${3:-}" now="${4:-2000000000}"
  env \
    HOME="$home" \
    USER="$(id -un)" \
    LOGNAME="$(id -un)" \
    XDG_CACHE_HOME="${home}/.cache" \
    XDG_CONFIG_HOME="${home}/.config" \
    XDG_DATA_HOME="${home}/.local/share" \
    XDG_STATE_HOME="${home}/.local/state" \
    PATH="${fakebin}:${PATH}" \
    AWTARCHY_DEFAULT_TERMINAL="${fakebin}/default-terminal" \
    AWTARCHY_TEST_ACTION="$action" \
    AWTARCHY_TEST_NOTIFY_LOG="${home}/notify.json" \
    AWTARCHY_TEST_TERMINAL_LOG="${home}/terminal.json" \
    AWTARCHY_TEST_RELEASE_LOG="${home}/release-url" \
    AWTARCHY_TEST_SCENARIO="$scenario" \
    AWTARCHY_UPDATE_NOTIFY_FOREGROUND=1 \
    AWTARCHY_UPDATE_NOTIFY_NOW="$now" \
    bash "$CHECKER" check
}

assert_notification() {
  local file="$1" title="$2" body="$3" action="$4"
  python3 - "$file" "$title" "$body" "$action" <<'PY'
import json
import sys

args = json.load(open(sys.argv[1], encoding="utf-8"))
for expected in sys.argv[2:]:
    if expected not in args:
        raise SystemExit(f"missing notification argument {expected!r}: {args!r}")
PY
}

assert_terminal() {
  local file="$1" command="$2"
  python3 - "$file" "$command" <<'PY'
import json
import sys

args = json.load(open(sys.argv[1], encoding="utf-8"))
expected = ["--class", "awtarchy-update", "--hold", "--no-profile", "--", "awtarchy", sys.argv[2]]
if args != expected:
    raise SystemExit(f"unexpected terminal arguments: {args!r}")
PY
}

assert_notification_omits() {
  local file="$1" unwanted="$2"
  python3 - "$file" "$unwanted" <<'PY'
import json
import sys

args = json.load(open(sys.argv[1], encoding="utf-8"))
if sys.argv[2] in args:
    raise SystemExit(f"unexpected notification argument {sys.argv[2]!r}: {args!r}")
PY
}

stable_home="$(new_home stable v3.1.5)"
run_check "$stable_home" stable-update update
assert_notification \
  "${stable_home}/notify.json" \
  'New Awtarchy Update' \
  $'v3.1.5 → v3.2.1\nRun: awtarchy update' \
  'update=Update ↑' \
  'release=Release Notes ↗' \
  '--icon=github'
assert_terminal "${stable_home}/terminal.json" update
rm -f -- "${stable_home}/notify.json" "${stable_home}/terminal.json"
run_check "$stable_home" stable-update update 2000022000
[[ ! -e ${stable_home}/notify.json ]] || fail 'stable target was announced twice'

release_home="$(new_home release v3.1.5)"
run_check "$release_home" stable-update release
[[ $(<"${release_home}/release-url") == 'https://github.com/dillacorn/awtarchy/releases/tag/v3.2.1' ]] \
  || fail 'release action did not open the exact stable release page'
[[ ! -e ${release_home}/terminal.json ]] \
  || fail 'release action unexpectedly launched the updater terminal'

same_payload_home="$(new_home same-payload v3.2.1)"
run_check "$same_payload_home" same-payload
[[ ! -e ${same_payload_home}/notify.json ]] \
  || fail 'main commit-only change generated a maintenance notification'

maintenance_home="$(new_home maintenance v3.2.1)"
run_check "$maintenance_home" maintenance refresh
assert_notification \
  "${maintenance_home}/notify.json" \
  'Awtarchy Maintenance Refresh' \
  $'v3.2.1 configuration\nUpdater/runtime refresh available\nRun: awtarchy self-update' \
  'refresh=Refresh ↑' \
  '--icon=github'
assert_notification_omits "${maintenance_home}/notify.json" 'release=Release Notes ↗'
assert_terminal "${maintenance_home}/terminal.json" self-update

prerelease_home="$(new_home prerelease v3.2.1)"
run_check "$prerelease_home" prerelease
[[ ! -e ${prerelease_home}/notify.json ]] || fail 'prerelease generated a stable notification'

testing_home="$(new_home testing 'feature/testing@1111111111111111111111111111111111111111')"
cat >"${testing_home}/.local/state/awtarchy/git-testing" <<'EOF_TESTING'
branch=feature/testing
revision=1111111111111111111111111111111111111111
stable_release=v3.2.1
tested_at=2026-01-01T00:00:00Z
EOF_TESTING
run_check "$testing_home" stable-update
[[ ! -e ${testing_home}/notify.json ]] || fail 'Git-testing state generated an automatic notification'

suppressed_home="$(new_home suppressed v3.1.5)"
jq '.update_notifications_enabled = false' \
  "${suppressed_home}/.cache/awtarchy/quickshell-state.json" \
  >"${suppressed_home}/state.tmp"
mv -- "${suppressed_home}/state.tmp" \
  "${suppressed_home}/.cache/awtarchy/quickshell-state.json"
run_check "$suppressed_home" stable-update
[[ ! -e ${suppressed_home}/notify.json ]] || fail 'suppressed normal update generated a notification'

catchup_home="$(new_home catchup v3.1.2)"
jq '.update_notifications_enabled = false' \
  "${catchup_home}/.cache/awtarchy/quickshell-state.json" \
  >"${catchup_home}/state.tmp"
mv -- "${catchup_home}/state.tmp" \
  "${catchup_home}/.cache/awtarchy/quickshell-state.json"
run_check "$catchup_home" suppressed-five
assert_notification \
  "${catchup_home}/notify.json" \
  'New Awtarchy Update' \
  $'v3.1.2 → v3.2.1\nRun: awtarchy update' \
  'update=Update ↑'
rm -f -- "${catchup_home}/notify.json"
jq '.update_notifications_enabled = true' \
  "${catchup_home}/.cache/awtarchy/quickshell-state.json" \
  >"${catchup_home}/state.tmp"
mv -- "${catchup_home}/state.tmp" \
  "${catchup_home}/.cache/awtarchy/quickshell-state.json"
run_check "$catchup_home" suppressed-five '' 2000022000
[[ ! -e ${catchup_home}/notify.json ]] \
  || fail 're-enabling notifications repeated an announced catch-up target'
jq '.update_notifications_enabled = false' \
  "${catchup_home}/.cache/awtarchy/quickshell-state.json" \
  >"${catchup_home}/state.tmp"
mv -- "${catchup_home}/state.tmp" \
  "${catchup_home}/.cache/awtarchy/quickshell-state.json"
run_check "$catchup_home" suppressed-new-target '' 2000691200
[[ ! -e ${catchup_home}/notify.json ]] \
  || fail 'suppression override ignored the 30-day catch-up cooldown'

offline_home="$(new_home offline v3.1.5)"
run_check "$offline_home" offline
[[ ! -e ${offline_home}/notify.json ]] || fail 'offline check generated a notification'

state_home="$(new_home state v3.2.1)"
env \
  HOME="$state_home" \
  XDG_CACHE_HOME="${state_home}/.cache" \
  XDG_CONFIG_HOME="${state_home}/.config" \
  bash "$APP_STATE" set-update-notifications false
jq -e '.update_notifications_enabled == false' \
  "${state_home}/.cache/awtarchy/quickshell-state.json" >/dev/null \
  || fail 'state writer did not suppress update notifications'
env \
  HOME="$state_home" \
  XDG_CACHE_HOME="${state_home}/.cache" \
  XDG_CONFIG_HOME="${state_home}/.config" \
  bash "$APP_STATE" set-update-notifications true
jq -e '.update_notifications_enabled == true' \
  "${state_home}/.cache/awtarchy/quickshell-state.json" >/dev/null \
  || fail 'state writer did not enable update notifications'

cat >"${fakebin}/terminal-capture" <<'EOF_CAPTURE'
#!/usr/bin/env bash
set -uo pipefail
python3 - "${AWTARCHY_TEST_TERMINAL_CAPTURE:?}" "$@" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps(sys.argv[2:]), encoding="utf-8")
PY
[[ ${1:-} == -e ]] || false
shift
set +e
printf '\n' | "$@" >"${AWTARCHY_TEST_TERMINAL_OUTPUT:?}" 2>&1
status=$?
set -e
printf '%s\n' "$status" >"${AWTARCHY_TEST_TERMINAL_STATUS:?}"
[[ $status -eq 0 ]]
EOF_CAPTURE
chmod 0755 "${fakebin}/terminal-capture"

held_home="${TMPD}/held-home"
mkdir -p -- "$held_home"
printf '%s\n' 'printf "profile-marker\\n"' >"${held_home}/.bash_profile"
if env \
  HOME="$held_home" \
  TERMINAL="${fakebin}/terminal-capture" \
  AWTARCHY_TEST_TERMINAL_CAPTURE="${held_home}/capture.json" \
  AWTARCHY_TEST_TERMINAL_OUTPUT="${held_home}/output" \
  AWTARCHY_TEST_TERMINAL_STATUS="${held_home}/status" \
  bash "$DEFAULT_TERMINAL" \
    --class awtarchy-update \
    --hold \
    --no-profile \
    -- \
    /usr/bin/sh -c 'printf "held-command\\n"; false';
then
  fail 'held terminal did not preserve the command failure status'
fi
python3 - "${held_home}/capture.json" <<'PY'
import json
import sys

args = json.load(open(sys.argv[1], encoding="utf-8"))
expected_prefix = ["-e", "bash", "--noprofile", "--norc", "-c"]
if args[:5] != expected_prefix:
    raise SystemExit(f"held terminal did not use a clean Bash shell: {args!r}")
PY
grep -Fq 'held-command' "${held_home}/output" \
  || fail 'held terminal did not run the requested command'
grep -Fq '[command finished: 1]' "${held_home}/output" \
  || fail 'held terminal did not report the command failure status'
! grep -Fq 'profile-marker' "${held_home}/output" \
  || fail 'held terminal sourced the login profile'
[[ $(<"${held_home}/status") == 1 ]] \
  || fail 'held terminal did not return the command failure status'

printf '%s\n' 'Awtarchy update notification tests passed.'
