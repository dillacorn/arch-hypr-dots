#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RECOVERY_SCRIPT="${ROOT}/config/hypr/scripts/quickshell_resume_recover.sh"
HYPRIDLE_ACTION="${ROOT}/config/hypr/scripts/hypridle_action.sh"
TMP="$(mktemp -d)"

cleanup() {
    rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local expected="$1" file="$2"
    grep -Fqx -- "$expected" "$file" || fail "missing '$expected' in $file"
}

assert_not_contains() {
    local unexpected="$1" file="$2"
    if grep -Fqx -- "$unexpected" "$file"; then
        fail "unexpected '$unexpected' in $file"
    fi
}

fakebin="${TMP}/fakebin"
test_home="${TMP}/home"
test_cache="${TMP}/cache"
test_runtime="${TMP}/runtime"
state_file="${test_cache}/awtarchy/quickshell-state.json"
monitor_file="${TMP}/monitors.json"
layer_state="${TMP}/layer-state"
shell_state="${TMP}/shell-state"
qs_log="${TMP}/qs.log"
manager_log="${TMP}/manager.log"
restore_log="${TMP}/restore.log"
bluetooth_restore_log="${TMP}/bluetooth-restore.log"
event_log="${TMP}/events.log"
fd_leak_file="${TMP}/manager-inherited-recovery-lock"

mkdir -p "$fakebin" "$test_home" "$(dirname "$state_file")" "$test_runtime"

cat >"${fakebin}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    monitors)
        cat "${AWTARCHY_TEST_MONITOR_FILE:?}"
        ;;
    layers)
        if [[ $(<"${AWTARCHY_TEST_LAYER_STATE:?}") == 1 ]]; then
            printf '%s\n' '{"LVDS-1":{"levels":{"2":[{"namespace":"awtarchy-bar"}]}}}'
        else
            printf '%s\n' '{"LVDS-1":{"levels":{"2":[]}}}'
        fi
        ;;
    dispatch)
        printf '%s\n' dpms >>"${AWTARCHY_TEST_EVENT_LOG:?}"
        ;;
    *)
        exit 2
        ;;
esac
EOF

cat >"${fakebin}/qs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_QS_LOG:?}"
if [[ $* == *'ipc call control ping'* ]]; then
    [[ -f ${AWTARCHY_TEST_SHELL_STATE:?} ]] || exit 1
    printf '%s\n' ok
elif [[ $* == *'ipc call control hardReload'* ]]; then
    if [[ ${AWTARCHY_TEST_RELOAD_CREATES_BAR:-0} == 1 ]]; then
        printf '%s\n' 1 >"${AWTARCHY_TEST_LAYER_STATE:?}"
    fi
else
    exit 2
fi
EOF

cat >"${fakebin}/restore" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' restore >>"${AWTARCHY_TEST_RESTORE_LOG:?}"
EOF

cat >"${fakebin}/bluetooth-state" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|wait=%s|retry=%s\n' \
    "$*" \
    "${AWTARCHY_BLUETOOTH_WAIT_ATTEMPTS:-unset}" \
    "${AWTARCHY_BLUETOOTH_POWER_RETRY_SECONDS:-unset}" \
    >>"${AWTARCHY_TEST_BLUETOOTH_RESTORE_LOG:?}"
EOF

cat >"${fakebin}/manager" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -e /proc/$$/fd/8 ]]; then
    : >"${AWTARCHY_TEST_FD_LEAK_FILE:?}"
fi
printf '%s\n' "${1:-}" >>"${AWTARCHY_TEST_MANAGER_LOG:?}"
case "${1:-}" in
    start|restart)
        : >"${AWTARCHY_TEST_SHELL_STATE:?}"
        if [[ ${AWTARCHY_TEST_MANAGER_CREATES_BAR:-0} == 1 ]]; then
            printf '%s\n' 1 >"${AWTARCHY_TEST_LAYER_STATE:?}"
        fi
        ;;
    *)
        exit 2
        ;;
esac
EOF

cat >"${fakebin}/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

cat >"${fakebin}/resume-hook" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' recovery >>"${AWTARCHY_TEST_EVENT_LOG:?}"
EOF

chmod +x "${fakebin}/hyprctl" "${fakebin}/qs" "${fakebin}/restore" \
    "${fakebin}/bluetooth-state" "${fakebin}/manager" "${fakebin}/systemctl" \
    "${fakebin}/resume-hook"

printf '%s\n' '[{"name":"LVDS-1","focused":true,"disabled":false}]' >"$monitor_file"

reset_scenario() {
    rm -f -- "$shell_state" "$fd_leak_file"
    : >"$qs_log"
    : >"$manager_log"
    : >"$restore_log"
    : >"$bluetooth_restore_log"
    : >"$event_log"
    printf '%s\n' 0 >"$layer_state"
    printf '%s\n' '{"enabled":true,"monitors":{"LVDS-1":{"enabled":true}}}' >"$state_file"
}

run_recovery() {
    env \
        PATH="${fakebin}:${PATH}" \
        HOME="$test_home" \
        XDG_CACHE_HOME="$test_cache" \
        XDG_RUNTIME_DIR="$test_runtime" \
        QUICKSHELL_STATE_FILE="$state_file" \
        QUICKSHELL_RESTORE_SCRIPT="${fakebin}/restore" \
        QUICKSHELL_MANAGER_SCRIPT="${fakebin}/manager" \
        QUICKSHELL_BLUETOOTH_STATE_SCRIPT="${fakebin}/bluetooth-state" \
        QUICKSHELL_RESUME_LOG="${TMP}/resume.log" \
        QUICKSHELL_RESUME_MONITOR_ATTEMPTS=1 \
        QUICKSHELL_RESUME_NATURAL_ATTEMPTS=1 \
        QUICKSHELL_RESUME_RELOAD_ATTEMPTS=1 \
        QUICKSHELL_RESUME_WAIT_INTERVAL=0 \
        QS_BIN="${fakebin}/qs" \
        HYPRCTL_BIN="${fakebin}/hyprctl" \
        SLEEP_BIN=true \
        AWTARCHY_TEST_MONITOR_FILE="$monitor_file" \
        AWTARCHY_TEST_LAYER_STATE="$layer_state" \
        AWTARCHY_TEST_SHELL_STATE="$shell_state" \
        AWTARCHY_TEST_QS_LOG="$qs_log" \
        AWTARCHY_TEST_MANAGER_LOG="$manager_log" \
        AWTARCHY_TEST_RESTORE_LOG="$restore_log" \
        AWTARCHY_TEST_BLUETOOTH_RESTORE_LOG="$bluetooth_restore_log" \
        AWTARCHY_TEST_EVENT_LOG="$event_log" \
        AWTARCHY_TEST_FD_LEAK_FILE="$fd_leak_file" \
        AWTARCHY_TEST_RELOAD_CREATES_BAR="${AWTARCHY_TEST_RELOAD_CREATES_BAR:-0}" \
        AWTARCHY_TEST_MANAGER_CREATES_BAR="${AWTARCHY_TEST_MANAGER_CREATES_BAR:-0}" \
        bash "$RECOVERY_SCRIPT"
}

# A healthy, already-visible bar should clear idle-hidden state and restore
# the persisted Bluetooth preference without forcing a Quickshell reload.
reset_scenario
: >"$shell_state"
printf '%s\n' 1 >"$layer_state"
run_recovery
assert_contains restore "$restore_log"
assert_contains 'restore|wait=50|retry=3' "$bluetooth_restore_log"
assert_not_contains '-c awtarchy ipc call control hardReload' "$qs_log"
[[ ! -s $manager_log ]] || fail 'healthy resume unexpectedly invoked the manager'

# If IPC survived but the PanelWindow did not, a hard reload should recreate it.
reset_scenario
: >"$shell_state"
AWTARCHY_TEST_RELOAD_CREATES_BAR=1 run_recovery
assert_contains '-c awtarchy ipc call control hardReload' "$qs_log"
[[ $(<"$layer_state") == 1 ]] || fail 'hard reload did not restore the test bar layer'
[[ ! -s $manager_log ]] || fail 'successful hard reload unexpectedly restarted Quickshell'

# If Quickshell exited during sleep, start it before evaluating its bar layers.
reset_scenario
AWTARCHY_TEST_MANAGER_CREATES_BAR=1 run_recovery
assert_contains start "$manager_log"
assert_not_contains '-c awtarchy ipc call control hardReload' "$qs_log"
[[ ! -e $fd_leak_file ]] || fail 'resume lock descriptor leaked into the manager'

# A full restart is the final fallback when hard reload cannot recreate a bar.
reset_scenario
: >"$shell_state"
AWTARCHY_TEST_MANAGER_CREATES_BAR=1 run_recovery
assert_contains '-c awtarchy ipc call control hardReload' "$qs_log"
assert_contains restart "$manager_log"
[[ ! -e $fd_leak_file ]] || fail 'resume lock descriptor leaked into restart'

# Intentionally disabled bars must not trigger reload or restart attempts.
reset_scenario
: >"$shell_state"
printf '%s\n' '{"enabled":false,"monitors":{"LVDS-1":{"enabled":true}}}' >"$state_file"
run_recovery
assert_not_contains '-c awtarchy ipc call control hardReload' "$qs_log"
[[ ! -s $manager_log ]] || fail 'disabled bars unexpectedly invoked the manager'

# The real-suspend hook must enable DPMS before running bar recovery.
reset_scenario
env \
    PATH="${fakebin}:${PATH}" \
    HOME="$test_home" \
    XDG_CACHE_HOME="$test_cache" \
    XDG_RUNTIME_DIR="$test_runtime" \
    INHIBITOR_SH=/bin/true \
    HYPRCTL_BIN="${fakebin}/hyprctl" \
    SYSTEMCTL_BIN="${fakebin}/systemctl" \
    QUICKSHELL_RESUME_SCRIPT="${fakebin}/resume-hook" \
    SUSPEND_WATCH_PID_FILE="${TMP}/missing-suspend-watch.pid" \
    AWTARCHY_TEST_EVENT_LOG="$event_log" \
    AWTARCHY_TEST_MONITOR_FILE="$monitor_file" \
    AWTARCHY_TEST_LAYER_STATE="$layer_state" \
    bash "$HYPRIDLE_ACTION" resume-sleep

[[ $(sed -n '1p' "$event_log") == dpms ]] || fail 'resume recovery ran before DPMS enable'
[[ $(sed -n '2p' "$event_log") == recovery ]] || fail 'resume hook did not run after DPMS enable'

printf '%s\n' 'Quickshell resume recovery regression test passed.'
