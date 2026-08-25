#!/usr/bin/env bash
# Check for stable Awtarchy releases and meaningful command/runtime refreshes.

set -euo pipefail

REPOSITORY="dillacorn/awtarchy"
API_ROOT="https://api.github.com/repos/${REPOSITORY}"
HOME_DIR="${HOME:?}"
CACHE_HOME="${XDG_CACHE_HOME:-${HOME_DIR}/.cache}"
STATE_HOME="${XDG_STATE_HOME:-${HOME_DIR}/.local/state}"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME_DIR}/.config}"
DATA_HOME="${XDG_DATA_HOME:-${HOME_DIR}/.local/share}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_PATH="${SCRIPT_DIR}/${BASH_SOURCE[0]##*/}"

AWTARCHY_STATE_DIR="${STATE_HOME}/awtarchy"
CONFIG_VERSION_FILE="${AWTARCHY_STATE_DIR}/config-version"
COMMAND_VERSION_FILE="${AWTARCHY_STATE_DIR}/command-version"
GIT_TESTING_FILE="${AWTARCHY_STATE_DIR}/git-testing"
NOTIFICATION_STATE_FILE="${AWTARCHY_STATE_DIR}/update-notifications"
NOTIFICATION_LOCK_FILE="${NOTIFICATION_STATE_FILE}.lock"
QUICKSHELL_STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
INSTALLED_LAUNCHER="${HOME_DIR}/.local/bin/awtarchy"
INSTALLED_RUNTIME="${DATA_HOME}/awtarchy/awtarchy-runtime.sh"
DEFAULT_TERMINAL="${AWTARCHY_DEFAULT_TERMINAL:-${CONFIG_HOME}/hypr/scripts/default_terminal.sh}"

NORMAL_CHECK_INTERVAL=21600
SUPPRESSED_CHECK_INTERVAL=604800
CATCHUP_RELEASE_COUNT=5
CATCHUP_INTERVAL=2592000

LAST_CHECK=0
LAST_STABLE_TARGET=""
LAST_RUNTIME_PAYLOAD=""
LAST_CATCHUP_TARGET=""
LAST_CATCHUP_AT=0
TMP_FILE=""

cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}

trap cleanup EXIT

read_field() {
    local file="$1" key="$2"
    [[ -r "$file" ]] || return 1
    awk -F= -v wanted="$key" '
        $1 == wanted {
            sub(/^[^=]*=/, "")
            print
            exit
        }
    ' "$file"
}

valid_epoch() {
    [[ $1 =~ ^[0-9]+$ ]]
}

valid_oid() {
    [[ $1 =~ ^[0-9a-fA-F]{40}$ ]]
}

valid_stable_tag() {
    [[ $1 =~ ^v[0-9]+(\.[0-9]+)+$ ]]
}

stable_version_at_least() {
    local installed="$1" target="$2" oldest
    valid_stable_tag "$installed" || return 1
    valid_stable_tag "$target" || return 1
    oldest="$(printf '%s\n%s\n' "$target" "$installed" | LC_ALL=C sort -V | head -n 1)"
    [[ $oldest == "$target" ]]
}

valid_notification_id() {
    [[ $1 =~ ^[1-9][0-9]*$ ]]
}

state_value() {
    local key="$1" fallback="$2" value
    value="$(read_field "$NOTIFICATION_STATE_FILE" "$key" 2>/dev/null || true)"
    printf '%s\n' "${value:-$fallback}"
}

load_state() {
    LAST_CHECK="$(state_value last_check 0)"
    LAST_STABLE_TARGET="$(state_value last_stable_target '')"
    LAST_RUNTIME_PAYLOAD="$(state_value last_runtime_payload '')"
    LAST_CATCHUP_TARGET="$(state_value last_catchup_target '')"
    LAST_CATCHUP_AT="$(state_value last_catchup_at 0)"
    valid_epoch "$LAST_CHECK" || LAST_CHECK=0
    valid_epoch "$LAST_CATCHUP_AT" || LAST_CATCHUP_AT=0
}

save_state() {
    mkdir -p -- "$AWTARCHY_STATE_DIR"
    TMP_FILE="$(mktemp "${NOTIFICATION_STATE_FILE}.tmp.XXXXXX")"
    chmod 0600 "$TMP_FILE"
    printf '%s\n' \
        "last_check=${LAST_CHECK}" \
        "last_stable_target=${LAST_STABLE_TARGET}" \
        "last_runtime_payload=${LAST_RUNTIME_PAYLOAD}" \
        "last_catchup_target=${LAST_CATCHUP_TARGET}" \
        "last_catchup_at=${LAST_CATCHUP_AT}" \
        >"$TMP_FILE"
    mv -f -- "$TMP_FILE" "$NOTIFICATION_STATE_FILE"
    TMP_FILE=""
}

notifications_enabled() {
    if [[ ! -s "$QUICKSHELL_STATE_FILE" ]]; then
        return 0
    fi
    [[ $(jq -r 'if .update_notifications_enabled == false then "false" else "true" end' \
        "$QUICKSHELL_STATE_FILE" 2>/dev/null || printf 'true') == true ]]
}

api_get() {
    curl -fsSL \
        --connect-timeout 5 \
        --max-time 15 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "$1"
}

git_blob_oid() {
    python3 - "$1" <<'PY'
import hashlib
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
header = f"blob {len(data)}\0".encode()
print(hashlib.sha1(header + data).hexdigest())
PY
}

launch_update() {
    local command="$1" notification_id="${2:-}" target="${3:-}"
    [[ -x "$DEFAULT_TERMINAL" ]] || return 0
    if [[ $command == update ]] \
        && valid_notification_id "$notification_id" \
        && valid_stable_tag "$target"; then
        "$DEFAULT_TERMINAL" \
            --class awtarchy-update \
            --hold \
            --no-profile \
            -- \
            "$SCRIPT_PATH" run-stable-update "$notification_id" "$target"
    else
        "$DEFAULT_TERMINAL" \
            --class awtarchy-update \
            --hold \
            --no-profile \
            -- \
            awtarchy "$command"
    fi
}

close_notification() {
    local notification_id="$1"
    valid_notification_id "$notification_id" || return 0
    command -v busctl >/dev/null 2>&1 || return 0
    busctl --user call \
        org.freedesktop.Notifications \
        /org/freedesktop/Notifications \
        org.freedesktop.Notifications.CloseNotification \
        u "$notification_id" \
        >/dev/null 2>&1 || true
}

run_stable_update() {
    local notification_id="$1" target="$2" status installed
    valid_notification_id "$notification_id" || return 2
    valid_stable_tag "$target" || return 2

    if awtarchy update; then
        status=0
    else
        status=$?
    fi

    if (( status == 0 )); then
        installed="$(read_field "$CONFIG_VERSION_FILE" tag 2>/dev/null || true)"
        if stable_version_at_least "$installed" "$target"; then
            close_notification "$notification_id"
        fi
    fi

    return "$status"
}

open_release_page() {
    local target="$1"
    valid_stable_tag "$target" || return 0
    command -v xdg-open >/dev/null 2>&1 || return 0
    xdg-open "https://github.com/${REPOSITORY}/releases/tag/${target}" >/dev/null 2>&1 || true
}

notify_and_handle() {
    local kind="$1" title="$2" body="$3" action_id="$4" action_label="$5" command="$6"
    local release_target="${7:-}" action notification_id="" reported_id
    local -a active_notify_args notify_args=(
        notify-send
        --app-name=Awtarchy
        --urgency=normal
        --icon=github
        --action "default=Run ${kind}"
        --action "${action_id}=${action_label}"
    )

    if valid_stable_tag "$release_target"; then
        notify_args+=(
            --hint=boolean:resident:true
            --action "release=Release Notes ↗"
            --print-id
        )
        while :; do
            active_notify_args=("${notify_args[@]}")
            if valid_notification_id "$notification_id"; then
                active_notify_args+=(--replace-id="$notification_id")
            fi
            TMP_FILE="$(mktemp "${NOTIFICATION_STATE_FILE}.action.XXXXXX")"
            chmod 0600 "$TMP_FILE"
            reported_id="$(
                "${active_notify_args[@]}" \
                    --selected-action-fd=3 \
                    "$title" "$body" \
                    3>"$TMP_FILE" 2>/dev/null || true
            )"
            if valid_notification_id "$reported_id"; then
                notification_id="$reported_id"
            fi
            action="$(<"$TMP_FILE")"
            rm -f -- "$TMP_FILE"
            TMP_FILE=""

            if [[ $action == release ]]; then
                open_release_page "$release_target"
                valid_notification_id "$notification_id" || action=""
                [[ -z $action ]] || continue
            fi
            break
        done
    else
        action="$("${notify_args[@]}" "$title" "$body" 2>/dev/null || true)"
    fi

    case "$action" in
        default|"$action_id") launch_update "$command" "$notification_id" "$release_target" ;;
    esac
}

show_notification() {
    local kind="$1" title="$2" body="$3" action_id="$4" action_label="$5" command="$6"
    local release_target="${7:-}"
    command -v notify-send >/dev/null 2>&1 || return 0

    if [[ ${AWTARCHY_UPDATE_NOTIFY_FOREGROUND:-0} == 1 ]]; then
        notify_and_handle \
            "$kind" "$title" "$body" "$action_id" "$action_label" "$command" "$release_target"
    else
        notify_and_handle \
            "$kind" "$title" "$body" "$action_id" "$action_label" "$command" "$release_target" \
            9>&- </dev/null >/dev/null 2>&1 &
    fi
}

stable_release_position() {
    local releases_json="$1" target="$2" installed="$3"
    python3 -c '
import json
import re
import sys

target, installed = sys.argv[1:]
try:
    releases = json.load(sys.stdin)
except (json.JSONDecodeError, TypeError):
    raise SystemExit(1)

if not isinstance(releases, list):
    raise SystemExit(1)

stable = []
pattern = re.compile(r"^v[0-9]+(?:\.[0-9]+)+$")
for release in releases:
    if not isinstance(release, dict):
        continue
    tag = release.get("tag_name")
    if (release.get("draft") is False
            and release.get("prerelease") is False
            and isinstance(release.get("published_at"), str)
            and release["published_at"]
            and isinstance(tag, str)
            and pattern.fullmatch(tag)):
        stable.append(tag)

try:
    target_index = stable.index(target)
    installed_index = stable.index(installed)
except ValueError:
    raise SystemExit(1)

if target_index >= installed_index:
    raise SystemExit(1)
print(installed_index - target_index)
' "$target" "$installed" <<<"$releases_json"
}

check_stable_release() {
    local installed="$1" target="$2" enabled="$3" releases_json behind

    releases_json="$(api_get "${API_ROOT}/releases?per_page=100" 2>/dev/null)" || return 1
    behind="$(stable_release_position "$releases_json" "$target" "$installed" 2>/dev/null)" || return 1
    [[ $behind =~ ^[0-9]+$ ]] || return 1
    [[ $LAST_STABLE_TARGET != "$target" ]] || return 0

    if [[ $enabled == false ]]; then
        (( behind >= CATCHUP_RELEASE_COUNT )) || return 0
        [[ $LAST_CATCHUP_TARGET != "$target" ]] || return 0
        if (( LAST_CATCHUP_AT > 0 && NOW >= LAST_CATCHUP_AT \
            && NOW - LAST_CATCHUP_AT < CATCHUP_INTERVAL )); then
            return 0
        fi
        LAST_CATCHUP_TARGET="$target"
        LAST_CATCHUP_AT="$NOW"
    fi

    LAST_STABLE_TARGET="$target"
    save_state
    show_notification \
        "Update" \
        "New Awtarchy Update" \
        "${installed} → ${target}"$'\n'"Run: awtarchy update" \
        "update" "Update ↑" "update" "$target"
}

check_maintenance_refresh() {
    local installed="$1" enabled="$2"
    local main_json main_revision command_revision launcher_json runtime_json
    local remote_launcher remote_runtime installed_launcher installed_runtime payload

    [[ $enabled == true ]] || return 0
    command_revision="$(read_field "$COMMAND_VERSION_FILE" revision 2>/dev/null || true)"
    valid_oid "$command_revision" || return 0

    main_json="$(api_get "${API_ROOT}/commits/main" 2>/dev/null)" || return 0
    main_revision="$(jq -er '.sha | select(type == "string")' <<<"$main_json" 2>/dev/null)" || return 0
    valid_oid "$main_revision" || return 0
    [[ $command_revision != "$main_revision" ]] || return 0
    [[ -r "$INSTALLED_LAUNCHER" && -r "$INSTALLED_RUNTIME" ]] || return 0

    launcher_json="$(api_get "${API_ROOT}/contents/local/bin/awtarchy?ref=main" 2>/dev/null)" || return 0
    runtime_json="$(api_get "${API_ROOT}/contents/local/share/awtarchy/awtarchy-runtime.sh?ref=main" 2>/dev/null)" || return 0
    remote_launcher="$(jq -er '.sha | select(type == "string")' <<<"$launcher_json" 2>/dev/null)" || return 0
    remote_runtime="$(jq -er '.sha | select(type == "string")' <<<"$runtime_json" 2>/dev/null)" || return 0
    valid_oid "$remote_launcher" || return 0
    valid_oid "$remote_runtime" || return 0

    installed_launcher="$(git_blob_oid "$INSTALLED_LAUNCHER" 2>/dev/null)" || return 0
    installed_runtime="$(git_blob_oid "$INSTALLED_RUNTIME" 2>/dev/null)" || return 0
    if [[ $installed_launcher == "$remote_launcher" && $installed_runtime == "$remote_runtime" ]]; then
        return 0
    fi

    payload="${remote_launcher}:${remote_runtime}"
    [[ $LAST_RUNTIME_PAYLOAD != "$payload" ]] || return 0
    LAST_RUNTIME_PAYLOAD="$payload"
    save_state
    show_notification \
        "Refresh" \
        "Awtarchy Maintenance Refresh" \
        "${installed} configuration"$'\n'"Updater/runtime refresh available"$'\n'"Run: awtarchy self-update" \
        "refresh" "Refresh ↑" "self-update"
}

check_for_updates() {
    local config_tag latest_json latest_tag enabled check_interval

    config_tag="$(read_field "$CONFIG_VERSION_FILE" tag 2>/dev/null || true)"
    case "$config_tag" in
        ""|unknown|unreleased|*@*) return 0 ;;
    esac
    valid_stable_tag "$config_tag" || return 0
    [[ ! -s "$GIT_TESTING_FILE" ]] || return 0

    if notifications_enabled; then
        enabled=true
        check_interval=$NORMAL_CHECK_INTERVAL
    else
        enabled=false
        check_interval=$SUPPRESSED_CHECK_INTERVAL
    fi

    NOW="${AWTARCHY_UPDATE_NOTIFY_NOW:-$(date +%s)}"
    valid_epoch "$NOW" || return 0
    if (( LAST_CHECK > 0 && NOW >= LAST_CHECK && NOW - LAST_CHECK < check_interval )); then
        return 0
    fi
    LAST_CHECK="$NOW"
    save_state

    latest_json="$(api_get "${API_ROOT}/releases/latest" 2>/dev/null)" || return 0
    latest_tag="$(jq -er '
        select(.draft == false and .prerelease == false)
        | .published_at as $published
        | select(($published | type) == "string" and ($published | length) > 0)
        | .tag_name
        | select(type == "string")
    ' <<<"$latest_json" 2>/dev/null)" || return 0
    valid_stable_tag "$latest_tag" || return 0

    if [[ $config_tag != "$latest_tag" ]]; then
        check_stable_release "$config_tag" "$latest_tag" "$enabled" || true
        return 0
    fi

    check_maintenance_refresh "$config_tag" "$enabled"
}

main() {
    if [[ ${1:-} == run-stable-update && $# -eq 3 ]]; then
        run_stable_update "$2" "$3"
        return
    fi

    [[ ${1:-} == check && $# -eq 1 ]] || {
        printf 'usage: %s check\n' "${0##*/}" >&2
        return 2
    }

    command -v curl >/dev/null 2>&1 || return 0
    command -v jq >/dev/null 2>&1 || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    command -v flock >/dev/null 2>&1 || return 0
    command -v notify-send >/dev/null 2>&1 || return 0

    umask 077
    mkdir -p -- "$AWTARCHY_STATE_DIR"
    exec 9>"$NOTIFICATION_LOCK_FILE"
    flock -n 9 || return 0
    load_state
    check_for_updates
}

main "$@"
