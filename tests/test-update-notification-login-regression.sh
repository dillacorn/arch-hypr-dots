#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKER="${ROOT}/config/hypr/scripts/quickshell_update_notifications.sh"
SHELL_QML="${ROOT}/config/quickshell/awtarchy/shell.qml"
TMPD="$(mktemp -d)"
trap 'rm -rf -- "$TMPD"' EXIT

failures=0
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
}

for command_name in bash curl flock jq python3; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        fail "missing required command: $command_name"
    fi
done
[[ -x $CHECKER ]] || fail "missing executable update checker: $CHECKER"
[[ -r $SHELL_QML ]] || fail "missing Quickshell root: $SHELL_QML"

fakebin="${TMPD}/bin"
mkdir -p -- "$fakebin"

cat >"${fakebin}/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail
url="${!#}"
case "$url" in
    *'/releases/latest')
        printf '%s\n' '{"tag_name":"v3.3.0","draft":false,"prerelease":false,"published_at":"2026-08-26T02:54:22Z"}'
        ;;
    *'/releases?per_page=100')
        printf '%s\n' '[{"tag_name":"v3.3.0","draft":false,"prerelease":false,"published_at":"2026-08-26T02:54:22Z"},{"tag_name":"v3.2.2","draft":false,"prerelease":false,"published_at":"2026-08-24T22:00:00Z"}]'
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
selected_action_fd=""
for argument in "$@"; do
    case "$argument" in
        --selected-action-fd=*) selected_action_fd="${argument#*=}" ;;
    esac
done
printf '%s\n' "$*" >>"${AWTARCHY_TEST_NOTIFY_LOG:?}"
if [[ ${AWTARCHY_TEST_NOTIFY_RESULT:-success} == failure ]]; then
    exit 70
fi
printf '%s\n' '42'
if [[ -n $selected_action_fd ]]; then
    printf '\n' >&"$selected_action_fd"
fi
EOF_NOTIFY

chmod 0755 "${fakebin}/curl" "${fakebin}/notify-send"

new_home() {
    local name="$1" last_check="$2"
    local home="${TMPD}/${name}"
    mkdir -p -- \
        "${home}/.cache/awtarchy" \
        "${home}/.config" \
        "${home}/.local/share" \
        "${home}/.local/state/awtarchy"
    printf '%s\n' \
        'tag=v3.2.2' \
        'updated_at=2026-08-25T00:00:00-04:00' \
        >"${home}/.local/state/awtarchy/config-version"
    printf '%s\n' \
        "last_check=${last_check}" \
        'last_stable_target=' \
        'last_runtime_payload=' \
        'last_catchup_target=' \
        'last_catchup_at=0' \
        >"${home}/.local/state/awtarchy/update-notifications"
    printf '%s\n' '{"update_notifications_enabled":true}' \
        >"${home}/.cache/awtarchy/quickshell-state.json"
    printf '%s\n' "$home"
}

state_field() {
    local home="$1" key="$2"
    awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' \
        "${home}/.local/state/awtarchy/update-notifications"
}

run_checker() {
    local home="$1" mode="$2" notify_result="$3" now="$4"
    env \
        HOME="$home" \
        XDG_CACHE_HOME="${home}/.cache" \
        XDG_CONFIG_HOME="${home}/.config" \
        XDG_DATA_HOME="${home}/.local/share" \
        XDG_STATE_HOME="${home}/.local/state" \
        PATH="${fakebin}:${PATH}" \
        AWTARCHY_TEST_NOTIFY_LOG="${home}/notify.log" \
        AWTARCHY_TEST_NOTIFY_RESULT="$notify_result" \
        AWTARCHY_UPDATE_NOTIFY_FOREGROUND=1 \
        AWTARCHY_UPDATE_NOTIFY_NOW="$now" \
        bash "$CHECKER" "$mode"
}

NOW=2000000000
ONE_HOUR_AGO=$((NOW - 3600))

periodic_home="$(new_home periodic "$ONE_HOUR_AGO")"
if ! run_checker "$periodic_home" check success "$NOW"; then
    fail 'periodic check returned nonzero status'
fi
[[ ! -e ${periodic_home}/notify.log ]] \
    || fail 'periodic check ignored the six-hour throttle'
[[ $(state_field "$periodic_home" last_check) == "$ONE_HOUR_AGO" ]] \
    || fail 'throttled periodic check unexpectedly rewrote last_check'

login_home="$(new_home login "$ONE_HOUR_AGO")"
if ! run_checker "$login_home" login success "$NOW"; then
    fail 'login check mode returned nonzero status'
fi
[[ -s ${login_home}/notify.log ]] \
    || fail 'login check was suppressed by the six-hour throttle'
[[ $(state_field "$login_home" last_check) == "$NOW" ]] \
    || fail 'successful login check did not become the new periodic throttle baseline'
[[ $(state_field "$login_home" last_stable_target) == v3.3.0 ]] \
    || fail 'successful login notification did not record the announced release'

delivery_home="$(new_home delivery 0)"
if ! run_checker "$delivery_home" check failure "$NOW"; then
    fail 'failed notification delivery made the checker return nonzero'
fi
[[ $(state_field "$delivery_home" last_stable_target) == '' ]] \
    || fail 'failed notification delivery consumed the stable release target'

rm -f -- "${delivery_home}/notify.log"
RETRY_NOW=$((NOW + 21601))
if ! run_checker "$delivery_home" check success "$RETRY_NOW"; then
    fail 'retry after failed notification delivery returned nonzero'
fi
[[ -s ${delivery_home}/notify.log ]] \
    || fail 'failed notification delivery prevented a later retry'
[[ $(state_field "$delivery_home" last_stable_target) == v3.3.0 ]] \
    || fail 'successful retry did not record the stable release target'

if ! grep -Fq 'function runUpdateNotificationCheck(mode)' "$SHELL_QML"; then
    fail 'Quickshell update check helper does not accept an explicit mode'
fi
if ! grep -Fq 'updateNotificationCheck.exec([updateNotificationsScript, mode]);' "$SHELL_QML"; then
    fail 'Quickshell update check helper does not forward its explicit mode'
fi
if ! grep -Fq 'onTriggered: root.runUpdateNotificationCheck("login")' "$SHELL_QML"; then
    fail 'initial Quickshell update timer is not wired to login mode'
fi
if ! grep -Fq 'onTriggered: root.runUpdateNotificationCheck("check")' "$SHELL_QML"; then
    fail 'periodic Quickshell update timer is not wired to periodic check mode'
fi

if (( failures > 0 )); then
    printf 'Update notification login regression tests failed: %d failure(s).\n' "$failures" >&2
    exit 1
fi

printf '%s\n' 'Update notification login regression tests passed.'
