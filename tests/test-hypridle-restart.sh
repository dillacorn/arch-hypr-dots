#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/hypridle_restart.sh"
TMP="$(mktemp -d)"
NEW_PID=""

cleanup() {
    if [[ -n "$NEW_PID" ]]; then
        kill "$NEW_PID" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

fakebin="${TMP}/fakebin"
config_home="${TMP}/config"
cache_home="${TMP}/cache"
runtime_dir="${TMP}/runtime"
process_state="${TMP}/hypridle.state"
pid_file="${TMP}/hypridle.pid"
args_log="${TMP}/hypridle.args"
pkill_log="${TMP}/pkill.log"
fd_leak="${TMP}/fd-leak"
restore_marker="${TMP}/restore.called"
idle_state="${runtime_dir}/awtarchy-quickshell-idle-hidden"

mkdir -p "$fakebin" "${config_home}/hypr" "${config_home}/hypr/scripts" "$runtime_dir"
printf '%s\n' '# test Hypridle config' >"${config_home}/hypr/hypridle.conf"
printf '%s\n' 'stale' >"$process_state"
printf '%s\n' '1' >"$idle_state"

cat >"${fakebin}/pgrep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${AWTARCHY_TEST_HYPRIDLE_STATE:?}"
[[ -s "$state" ]] || exit 1
value="$(<"$state")"
if [[ "$value" =~ ^[0-9]+$ ]]; then
    kill -0 "$value" 2>/dev/null
else
    [[ "$value" == stale ]]
fi
EOF

cat >"${fakebin}/pkill" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_PKILL_LOG:?}"
rm -f -- "${AWTARCHY_TEST_HYPRIDLE_STATE:?}"
EOF

cat >"${fakebin}/hypridle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${AWTARCHY_TEST_HYPRIDLE_ARGS:?}"
if [[ -e /proc/$$/fd/8 || -e /proc/$$/fd/9 ]]; then
    : >"${AWTARCHY_TEST_HYPRIDLE_FD_LEAK:?}"
fi
printf '%s\n' "$$" >"${AWTARCHY_TEST_HYPRIDLE_PID:?}"
printf '%s\n' "$$" >"${AWTARCHY_TEST_HYPRIDLE_STATE:?}"
trap 'rm -f -- "${AWTARCHY_TEST_HYPRIDLE_STATE:?}"' EXIT
while :; do
    /bin/sleep 0.1
done
EOF

cat >"${config_home}/hypr/scripts/quickshell_bar_restore.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '0' >"${AWTARCHY_TEST_IDLE_STATE:?}"
: >"${AWTARCHY_TEST_RESTORE_MARKER:?}"
EOF

chmod 0755 "${fakebin}/"* "${config_home}/hypr/scripts/quickshell_bar_restore.sh"

: >"$pkill_log"
exec 9>"${TMP}/inherited-updater.lock"

env \
    "HOME=${TMP}/home" \
    "XDG_CONFIG_HOME=$config_home" \
    "XDG_CACHE_HOME=$cache_home" \
    "XDG_RUNTIME_DIR=$runtime_dir" \
    "HYPRIDLE_BIN=${fakebin}/hypridle" \
    "HYPRIDLE_PGREP_BIN=${fakebin}/pgrep" \
    "HYPRIDLE_PKILL_BIN=${fakebin}/pkill" \
    "HYPRIDLE_SLEEP_BIN=/bin/sleep" \
    "HYPRIDLE_STOP_ATTEMPTS=3" \
    "HYPRIDLE_START_ATTEMPTS=20" \
    "HYPRIDLE_START_STABLE_CHECKS=3" \
    "HYPRIDLE_WAIT_INTERVAL=0.01" \
    "AWTARCHY_TEST_HYPRIDLE_STATE=$process_state" \
    "AWTARCHY_TEST_HYPRIDLE_PID=$pid_file" \
    "AWTARCHY_TEST_HYPRIDLE_ARGS=$args_log" \
    "AWTARCHY_TEST_HYPRIDLE_FD_LEAK=$fd_leak" \
    "AWTARCHY_TEST_PKILL_LOG=$pkill_log" \
    "AWTARCHY_TEST_IDLE_STATE=$idle_state" \
    "AWTARCHY_TEST_RESTORE_MARKER=$restore_marker" \
    bash "$HELPER"

[[ -s "$pid_file" ]] || fail 'replacement Hypridle process did not start'
NEW_PID="$(cat "$pid_file")"
kill -0 "$NEW_PID" 2>/dev/null || fail 'replacement Hypridle process is not running'
grep -Fxq -- "-c ${config_home}/hypr/hypridle.conf" "$args_log" \
    || fail 'replacement Hypridle did not use the managed config'
grep -Fxq -- "-TERM -u $(id -u) -x hypridle" "$pkill_log" \
    || fail 'stale per-user Hypridle process was not terminated'
[[ ! -e "$fd_leak" ]] || fail 'replacement Hypridle inherited an updater lock'
[[ -e "$restore_marker" ]] || fail 'bar restore helper was not called'
[[ $(<"$idle_state") == 0 ]] || fail 'idle-hidden bar state was not cleared'

printf 'Hypridle restart tests passed.\n'
