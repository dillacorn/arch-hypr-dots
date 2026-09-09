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

if [[ ${1:-} == -j && ${2:-} == clients ]]; then
    cat <<'JSON'
[
  {
    "address": "0xabc",
    "class": "localsend",
    "title": "LocalSend",
    "initialClass": "localsend",
    "initialTitle": "LocalSend"
  },
  {
    "address": "0xdef",
    "class": "signal",
    "title": "Signal",
    "initialClass": "signal",
    "initialTitle": "Signal"
  }
]
JSON
    exit 0
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
        case "${2:-}" in
            *awtarchy_screenshare_guard_registry_v1*)
                printf '%b\n' \
                    'localsend\tLocalSend\tprotected\ttrue\t^(localsend|LocalSend)$\t' \
                    'discord\tDiscord / Vesktop / Fluxer\tprotected\ttrue\t^(discord|vesktop)$\t' \
                    'signal\tSignal\tprotected\ttrue\t^(signal|org\\.signal\\.Signal)$\t' \
                    'obs\tOBS\toptional\tfalse\t^(obs)$\t'
                ;;
            *awtarchy_screenshare_guard_status_v1*)
                printf '%s\n' \
                    'localsend=false' \
                    'discord=false' \
                    'signal=false' \
                    'obs=false'
                ;;
            *)
                exit 2
                ;;
        esac
        ;;
    dispatch)
        if [[ ${AWTARCHY_TEST_FAIL_DISPATCH:-0} == 1 ]]; then
            printf '%s\n' 'error: simulated set_prop failure' >&2
            exit 1
        fi
        printf '%s\n' ok
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

# Runtime registry entries, including user registrations, must be surfaced by
# the helper rather than being hidden behind a fixed Bash target list.
policy_json="$("$HELPER" desired-json)"
jq -e '.targets.signal.label == "Signal"
    and .targets.signal.section == "protected"
    and .targets.signal.default_protected == true
    and .targets.obs.section == "optional"' <<<"$policy_json" >/dev/null \
    || fail 'runtime registry target metadata was not exposed by desired-json'

# The real Hyprland failure leaves the named rule disabled while an already-open
# window still has no_screen_share=true. A successful toggle must synchronize the
# live window property too.
"$HELPER" set localsend allowed >/dev/null
jq -e '.localsend == false' "$SESSION_FILE" >/dev/null \
    || fail 'successful LocalSend runtime apply did not retain the session override'
grep -Fq -- 'awtarchy_screenshare_guard_set_group_v1("localsend", false)' "$AWTARCHY_TEST_HYPRCTL_LOG" \
    || fail 'LocalSend named rule was not disabled'
grep -Fq -- 'hl.dsp.window.set_prop({ prop = "no_screen_share", value = "false", window = "address:0xabc" })' "$AWTARCHY_TEST_HYPRCTL_LOG" \
    || fail 'existing LocalSend window did not receive a live no_screen_share=false override'

# A custom user target must use the same runtime path and apply to an already-open
# matching window.
"$HELPER" set signal allowed >/dev/null
jq -e '.signal == false' "$SESSION_FILE" >/dev/null \
    || fail 'custom Signal toggle was not stored as a session override'
grep -Fq -- 'awtarchy_screenshare_guard_set_group_v1("signal", false)' "$AWTARCHY_TEST_HYPRCTL_LOG" \
    || fail 'custom Signal named rule was not disabled'
grep -Fq -- 'hl.dsp.window.set_prop({ prop = "no_screen_share", value = "false", window = "address:0xdef" })' "$AWTARCHY_TEST_HYPRCTL_LOG" \
    || fail 'existing custom Signal window did not receive a live no_screen_share=false override'

# A real false runtime state must stay false in status-json. jq's // operator
# treats false like a fallback value, which previously turned this into null.
status_json="$("$HELPER" status-json)"
jq -e '.targets.localsend.effective_protected == false
    and .targets.localsend.desired_protected == false
    and .targets.localsend.in_sync == true' <<<"$status_json" >/dev/null \
    || fail 'false runtime protection state was lost or reported out of sync'

# Hyprland 0.55+ provides hyprctl -r to refresh rule changes. The helper must not
# depend on the 0.56-only immediate-refresh Lua API.
grep -Fq -- '-r eval ' "$AWTARCHY_TEST_HYPRCTL_LOG" \
    || fail 'Screen Share Guard runtime apply did not request hyprctl state refresh'
if grep -Fq 'hl.exec_scheduled_prop_refresh_immediately()' "$AWTARCHY_TEST_HYPRCTL_LOG"; then
    fail 'Screen Share Guard still requires the Hyprland 0.56-only immediate-refresh Lua API'
fi

# A failed named-rule apply must not leave Quick Settings claiming that the new
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

# Live-window synchronization is part of accepting a change. If set_prop fails,
# roll state back just like a named-rule failure.
printf '{}\n' >"$STATE_FILE"
printf '{}\n' >"$SESSION_FILE"
if AWTARCHY_TEST_FAIL_DISPATCH=1 "$HELPER" set localsend allowed >/dev/null 2>&1; then
    fail 'simulated live-window synchronization failure unexpectedly succeeded'
fi
if jq -e '.localsend? != null' "$SESSION_FILE" >/dev/null; then
    fail 'failed live-window synchronization left a false session override behind'
fi

printf '%s\n' 'Screen Share Guard runtime apply regression passed.'
