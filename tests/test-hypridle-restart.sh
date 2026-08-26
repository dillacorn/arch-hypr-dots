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
env_log="${TMP}/hypridle.env"
pkill_log="${TMP}/pkill.log"
fd_leak="${TMP}/fd-leak"
restore_marker="${TMP}/restore.called"
manager_env="${TMP}/user-manager.env"
idle_state="${runtime_dir}/awtarchy-quickshell-idle-hidden"

mkdir -p "$fakebin" "${config_home}/hypr" "${config_home}/hypr/scripts" "$runtime_dir"
printf '%s\n' '# test Hypridle config' >"${config_home}/hypr/hypridle.conf"
printf '%s\n' 'stale' >"$process_state"
printf '%s\n' '1' >"$idle_state"
cat >"$manager_env" <<'EOF'
WAYLAND_DISPLAY=wayland-test
HYPRLAND_INSTANCE_SIGNATURE=test-hyprland-instance
XDG_CURRENT_DESKTOP=Hyprland
XDG_SESSION_TYPE=wayland
EOF

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

cat >"${fakebin}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == '--user show-environment' ]]; then
    cat "${AWTARCHY_TEST_USER_MANAGER_ENV:?}"
    exit 0
fi
exit 1
EOF

cat >"${fakebin}/hypridle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${AWTARCHY_TEST_HYPRIDLE_ARGS:?}"
{
    printf 'XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-}"
    printf 'WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:-}"
    printf 'HYPRLAND_INSTANCE_SIGNATURE=%s\n' "${HYPRLAND_INSTANCE_SIGNATURE:-}"
    printf 'XDG_CURRENT_DESKTOP=%s\n' "${XDG_CURRENT_DESKTOP:-}"
    printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-}"
} >"${AWTARCHY_TEST_HYPRIDLE_ENV:?}"
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

grep -Fq 'export XDG_RUNTIME_DIR="$RUNTIME_DIR"' "$HELPER" \
    || fail 'Hypridle restart helper does not export its runtime fallback to the child process'

: >"$pkill_log"
exec 9>"${TMP}/inherited-updater.lock"

env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u XDG_CURRENT_DESKTOP -u XDG_SESSION_TYPE \
    "PATH=${fakebin}:$PATH" \
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
    "AWTARCHY_TEST_HYPRIDLE_ENV=$env_log" \
    "AWTARCHY_TEST_HYPRIDLE_FD_LEAK=$fd_leak" \
    "AWTARCHY_TEST_PKILL_LOG=$pkill_log" \
    "AWTARCHY_TEST_IDLE_STATE=$idle_state" \
    "AWTARCHY_TEST_RESTORE_MARKER=$restore_marker" \
    "AWTARCHY_TEST_USER_MANAGER_ENV=$manager_env" \
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
grep -Fxq "XDG_RUNTIME_DIR=$runtime_dir" "$env_log" \
    || fail 'replacement Hypridle did not inherit XDG_RUNTIME_DIR'
grep -Fxq 'WAYLAND_DISPLAY=wayland-test' "$env_log" \
    || fail 'replacement Hypridle did not recover WAYLAND_DISPLAY from the user manager'
grep -Fxq 'HYPRLAND_INSTANCE_SIGNATURE=test-hyprland-instance' "$env_log" \
    || fail 'replacement Hypridle did not recover HYPRLAND_INSTANCE_SIGNATURE from the user manager'
grep -Fxq 'XDG_CURRENT_DESKTOP=Hyprland' "$env_log" \
    || fail 'replacement Hypridle did not recover XDG_CURRENT_DESKTOP from the user manager'
grep -Fxq 'XDG_SESSION_TYPE=wayland' "$env_log" \
    || fail 'replacement Hypridle did not recover XDG_SESSION_TYPE from the user manager'

printf 'Hypridle restart tests passed.\n'