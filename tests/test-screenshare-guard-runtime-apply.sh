#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/config/hypr/scripts/screenshare_guard.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/cache/awtarchy" "$TMP/runtime/awtarchy" "$TMP/bin"

cat >"$TMP/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_HYPRCTL_LOG:?}"

if [[ ${1:-} == -r ]]; then
    shift
fi

case "${1:-}" in
    eval)
        shift
        if [[ ${AWTARCHY_TEST_FAIL_EVAL:-0} == 1 ]]; then
            printf '%s\n' 'error: simulated runtime apply failure' >&2
            exit 1
        fi
        if [[ $* == *'hl.exec_scheduled_prop_refresh_immediately()'* ]]; then
            printf '%s\n' "error: attempt to call a nil value (field 'exec_scheduled_prop_refresh_immediately')" >&2
            exit 1
        fi
        printf '%s\n' ok
        ;;
    repl)
        printf '%s\n' true
        ;;
    *)
        exit 2
        ;;
esac
STUB
chmod 0755 "$TMP/bin/hyprctl"

export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_RUNTIME_DIR="$TMP/runtime"
export AWTARCHY_SCREENSHARE_HYPRCTL="$TMP/bin/hyprctl"
export AWTARCHY_TEST_HYPRCTL_LOG="$TMP/hyprctl.log"

STATE_FILE="$XDG_CACHE_HOME/awtarchy/quickshell-state.json"
SESSION_FILE="$XDG_RUNTIME_DIR/awtarchy/screenshare-guard-session.json"
printf '{}\n' >"$STATE_FILE"
printf '{}\n' >"$SESSION_FILE"
: >"$AWTARCHY_TEST_HYPRCTL_LOG"

# Hyprland 0.55 already provides hyprctl -r to refresh rule changes. The helper
# must not require the 0.56-only hl.exec_scheduled_prop_refresh_immediately API.
"$HELPER" set discord allowed >/dev/null
jq -e '.discord == false' "$SESSION_FILE" >/dev/null \
    || fail 'successful runtime apply did not retain the session override'
grep -Fq -- '-r eval ' "$AWTARCHY_TEST_HYPRCTL_LOG" \
    || fail 'Screen Share Guard runtime apply did not request hyprctl state refresh'
if grep -Fq 'hl.exec_scheduled_prop_refresh_immediately()' "$AWTARCHY_TEST_HYPRCTL_LOG"; then
    fail 'Screen Share Guard still requires the Hyprland 0.56-only immediate-refresh Lua API'
fi

# A failed Hyprland apply must not leave Quick Settings claiming that the new
# capture state was accepted. Restore both desired-state files transactionally.
printf '{}\n' >"$STATE_FILE"
printf '{}\n' >"$SESSION_FILE"
if AWTARCHY_TEST_FAIL_EVAL=1 "$HELPER" set discord allowed >/dev/null 2>&1; then
    fail 'simulated Hyprland apply failure unexpectedly succeeded'
fi
if jq -e '.discord? != null' "$SESSION_FILE" >/dev/null; then
    fail 'failed runtime apply left a false session override behind'
fi
if jq -e '.screenshare_guard.discord? != null' "$STATE_FILE" >/dev/null; then
    fail 'failed runtime apply leaked into persistent Screen Share Guard state'
fi
policy_json="$("$HELPER" desired-json)"
jq -e '.targets.discord.desired_protected == true' <<<"$policy_json" >/dev/null \
    || fail 'failed runtime apply changed the desired Discord protection state'

printf '%s\n' 'Screen Share Guard runtime apply regression passed.'
