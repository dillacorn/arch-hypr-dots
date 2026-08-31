#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
BACKEND="$ROOT/config/hypr/scripts/hypr_quicksettings.sh"
CORE="$ROOT/config/hypr/scripts/hypr_quicksettings_core.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

contains "$CORE" 'SCHED_EXT_LAST_SELECTED=""' \
    'sched-ext state does not track the last successfully selected scheduler'
contains "$CORE" 'SCHED_EXT_RESTORE_ENABLED="0"' \
    'sched-ext state does not track whether session restore is enabled'
contains "$CORE" "printf 'SCHED_EXT_LAST_SELECTED=%q\\n' \"\$SCHED_EXT_LAST_SELECTED\"" \
    'sched-ext state file does not persist the last selected scheduler'
contains "$CORE" "printf 'SCHED_EXT_RESTORE_ENABLED=%q\\n' \"\$SCHED_EXT_RESTORE_ENABLED\"" \
    'sched-ext state file does not persist restore enablement'

python3 - "$CORE" <<'PY' || fail 'successful scheduler start/switch does not persist restore state'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index('sched_ext_switch_or_start() {')
end = text.index('\nsched_ext_stop() {', start)
block = text[start:end]
for needle in (
    'SCHED_EXT_LAST_SELECTED="$sched_full"',
    "SCHED_EXT_RESTORE_ENABLED='1'",
    'sched_ext_state_save',
):
    if needle not in block:
        raise SystemExit(1)
PY

python3 - "$CORE" <<'PY' || fail 'explicit sched-ext Stop does not disable automatic session restore'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index('sched_ext_stop() {')
end = text.index('\ndraw_sched_ext_menu() {', start)
block = text[start:end]
if "SCHED_EXT_RESTORE_ENABLED='0'" not in block or 'sched_ext_state_save' not in block:
    raise SystemExit(1)
PY

contains "$BACKEND" 'machine_scheduler_restore()' \
    'Quick Settings backend has no one-shot scheduler restore action'
contains "$BACKEND" '--restore-scheduler)' \
    'Quick Settings backend exposes no scheduler restore entrypoint for session startup'
contains "$BACKEND" "[[ \"\$SCHED_EXT_RUNNING\" == \"\$SCHED_EXT_LAST_SELECTED\" ]] && return 0" \
    'scheduler restore would unnecessarily restart an already-running saved scheduler'
contains "$BACKEND" 'machine_scheduler_reapply_if_running()' \
    'scheduler config edits cannot reapply the active scheduler after removing Apply'

python3 - "$BACKEND" <<'PY' || fail 'scheduler configuration actions do not reapply the currently running scheduler'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
for action in ('scheduler-profile)', 'scheduler-args)', 'scheduler-autopower)', 'scheduler-reset)'):
    start = text.index(action)
    block = text[start:start + 900]
    if 'machine_scheduler_reapply_if_running "$scheduler"' not in block:
        raise SystemExit(action)
PY

python3 - "$QML" <<'PY' || fail 'selecting a scheduler does not immediately start/switch to it'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index('    function selectScheduler(name) {')
end = text.index('\n    }', start) + 6
block = text[start:end]
for needle in (
    'selectedSchedulerName = name;',
    'queueAction(["scheduler-start", name]',
):
    if needle not in block:
        raise SystemExit(1)
PY

python3 - "$QML" <<'PY' || fail 'sched-ext card still requires a separate Apply button'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index('Layout.row: root.quickSettingsSectionRow("scheduler")')
end = text.index('Layout.row: root.quickSettingsSectionRow("numlock")', start)
block = text[start:end]
if 'label: "Apply"' in block:
    raise SystemExit(1)
if 'onClicked: root.selectScheduler(String(modelData.name))' not in block:
    raise SystemExit(1)
PY

contains "$QML" 'id: schedulerRestoreRunner' \
    'Quick Settings has no one-shot scheduler restore process'
contains "$QML" 'backend, "--restore-scheduler"' \
    'Quick Settings does not request scheduler restore when its singleton starts'
contains "$QML" 'last_selected:' \
    'Quick Settings empty scheduler status does not model persisted selection state'
contains "$BACKEND" "last_selected:\$scheduler_last_selected" \
    'backend scheduler status does not expose the persisted scheduler selection'

# Exercise the core persistence behavior with no real scxctl or sudo calls.
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
CORE_PATH="$CORE" STATE_ROOT="$tmp" bash <<'BASH'
set -Eeuo pipefail
source <(sed '/^main "$@"$/d' "$CORE_PATH")
STATE_DIR="$STATE_ROOT/state"
SCHED_EXT_STATE_FILE="$STATE_DIR/sched_ext_state.sh"
SCHED_EXT_ENABLED='0'
SCHED_EXT_RUNNING='off'
scxctl_run_quiet() { return 0; }
refresh_sched_ext() {
    if [[ "$SCHED_EXT_RESTORE_ENABLED" == '0' && "$SCHED_EXT_LAST_SELECTED" == 'scx_p2dq' ]]; then
        SCHED_EXT_ENABLED='0'
        SCHED_EXT_RUNNING='off'
    else
        SCHED_EXT_ENABLED='1'
        SCHED_EXT_RUNNING="${SCHED_EXT_LAST_SELECTED:-scx_p2dq}"
    fi
}
sched_ext_deps_ok() { return 0; }

sched_ext_state_load
sched_ext_switch_or_start scx_p2dq
[[ "$SCHED_EXT_LAST_SELECTED" == scx_p2dq ]]
[[ "$SCHED_EXT_RESTORE_ENABLED" == 1 ]]
grep -Fq 'SCHED_EXT_LAST_SELECTED=scx_p2dq' "$SCHED_EXT_STATE_FILE"
grep -Fq 'SCHED_EXT_RESTORE_ENABLED=1' "$SCHED_EXT_STATE_FILE"

SCHED_EXT_ENABLED='1'
SCHED_EXT_RUNNING='scx_p2dq'
sched_ext_stop
[[ "$SCHED_EXT_RESTORE_ENABLED" == 0 ]]
grep -Fq 'SCHED_EXT_RESTORE_ENABLED=0' "$SCHED_EXT_STATE_FILE"
BASH

printf '%s\n' 'PASS: sched-ext selection applies immediately, persists the last scheduler, restores it per session, and Stop disables restore.'
