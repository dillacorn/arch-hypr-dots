#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QML = ROOT / "config/quickshell/awtarchy/QuickSettings.qml"
BACKEND = ROOT / "config/hypr/scripts/hypr_quicksettings.sh"
CORE = ROOT / "config/hypr/scripts/hypr_quicksettings_core.sh"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_exact(text: str, old: str, new: str, *, count: int = 1, label: str) -> str:
    found = text.count(old)
    if found != count:
        raise SystemExit(f"{label}: expected {count} match(es), found {found}")
    return text.replace(old, new)


# Core sched-ext persistent state and successful selection tracking.
core = CORE.read_text(encoding="utf-8")
core = replace_exact(
    core,
    '''SCHED_EXT_RUNNING="off"
SCHED_EXT_MODE=""
SCHED_EXT_ENABLED="0"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr_quicksettings"
''',
    '''SCHED_EXT_RUNNING="off"
SCHED_EXT_MODE=""
SCHED_EXT_ENABLED="0"
SCHED_EXT_LAST_SELECTED=""
SCHED_EXT_RESTORE_ENABLED="0"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr_quicksettings"
''',
    label="sched-ext persistent scalar declarations",
)
core = replace_exact(
    core,
    '''    source <(sed -E 's/^declare -A /declare -gA /' "$SCHED_EXT_STATE_FILE")
    sched_ext_state_init_defaults
  fi
}
''',
    '''    source <(sed -E 's/^declare -A /declare -gA /' "$SCHED_EXT_STATE_FILE")
    sched_ext_state_init_defaults
  fi

  case "$SCHED_EXT_RESTORE_ENABLED" in
    1) ;;
    *) SCHED_EXT_RESTORE_ENABLED='0' ;;
  esac
}
''',
    label="sched-ext restore-state normalization",
)
core = replace_exact(
    core,
    '''    printf '#!/usr/bin/env bash\\n'
    declare -p SCHED_EXT_PROFILE_MAP | sed -E 's/^declare -A /declare -gA /'
''',
    '''    printf '#!/usr/bin/env bash\\n'
    printf 'SCHED_EXT_LAST_SELECTED=%q\\n' "$SCHED_EXT_LAST_SELECTED"
    printf 'SCHED_EXT_RESTORE_ENABLED=%q\\n' "$SCHED_EXT_RESTORE_ENABLED"
    declare -p SCHED_EXT_PROFILE_MAP | sed -E 's/^declare -A /declare -gA /'
''',
    label="sched-ext scalar state persistence",
)
old_switch = '''sched_ext_switch_or_start() {
  local sched_full="$1" sched_short verb args summary
  sched_short="${sched_full#scx_}"
  args="$(sched_ext_effective_args "$sched_full")"
  summary="$(sched_ext_config_summary "$sched_full")"

  if [[ "$SCHED_EXT_ENABLED" == '1' ]]; then
    verb='switch'
  else
    verb='start'
  fi

  if [[ -n "$args" ]]; then
    if scxctl_run_quiet "$verb" --sched "$sched_short" --args "$args"; then
      refresh_sched_ext
      MSG="sched-ext: ${sched_full} [${summary}]"
      return 0
    fi
  else
    if scxctl_run_quiet "$verb" --sched "$sched_short"; then
      refresh_sched_ext
      MSG="sched-ext: ${sched_full} [${summary}]"
      return 0
    fi
  fi

  refresh_sched_ext
  MSG='sched-ext: failed'
  return 1
}
'''
new_switch = '''sched_ext_switch_or_start() {
  local sched_full="$1" sched_short verb args summary rc=1
  sched_short="${sched_full#scx_}"
  args="$(sched_ext_effective_args "$sched_full")"
  summary="$(sched_ext_config_summary "$sched_full")"

  if [[ "$SCHED_EXT_ENABLED" == '1' ]]; then
    verb='switch'
  else
    verb='start'
  fi

  if [[ -n "$args" ]]; then
    scxctl_run_quiet "$verb" --sched "$sched_short" --args "$args" && rc=0
  else
    scxctl_run_quiet "$verb" --sched "$sched_short" && rc=0
  fi

  if (( rc == 0 )); then
    SCHED_EXT_LAST_SELECTED="$sched_full"
    SCHED_EXT_RESTORE_ENABLED='1'
    sched_ext_state_save
    refresh_sched_ext
    MSG="sched-ext: ${sched_full} [${summary}]"
    return 0
  fi

  refresh_sched_ext
  MSG='sched-ext: failed'
  return 1
}
'''
core = replace_exact(core, old_switch, new_switch, label="sched-ext switch persistence")
core = replace_exact(
    core,
    '''sched_ext_stop() {
  if ! sched_ext_deps_ok; then
    return 1
  fi

  if [[ "$SCHED_EXT_ENABLED" != '1' ]]; then
    MSG='sched-ext: already off'
    return 0
  fi

  if scxctl_run_quiet stop; then
    refresh_sched_ext
    MSG='sched-ext: stopped'
    return 0
  fi
''',
    '''sched_ext_stop() {
  if ! sched_ext_deps_ok; then
    return 1
  fi

  SCHED_EXT_RESTORE_ENABLED='0'
  sched_ext_state_save

  if [[ "$SCHED_EXT_ENABLED" != '1' ]]; then
    MSG='sched-ext: already off'
    return 0
  fi

  if scxctl_run_quiet stop; then
    refresh_sched_ext
    MSG='sched-ext: stopped'
    return 0
  fi
''',
    label="sched-ext Stop restore disable",
)
CORE.write_text(core, encoding="utf-8")

# Backend restore/status/reapply behavior.
backend = BACKEND.read_text(encoding="utf-8")
backend = replace_exact(
    backend,
    '  local scheduler profiles_json profile custom autopower summary sun_temp sunset_status\n',
    '  local scheduler profiles_json profile custom autopower summary sun_temp sunset_status\n  local scheduler_last_selected scheduler_restore_enabled\n',
    label="scheduler status locals",
)
backend = replace_exact(
    backend,
    '''  sched_ext_state_load
  refresh_all
''',
    '''  sched_ext_state_load
  scheduler_last_selected="$SCHED_EXT_LAST_SELECTED"
  scheduler_restore_enabled="$SCHED_EXT_RESTORE_ENABLED"
  refresh_all
''',
    label="scheduler saved-state status capture",
)
backend = replace_exact(
    backend,
    '''    --arg scheduler_enabled "$SCHED_EXT_ENABLED" \\
    --arg scheduler_available "$(have_cmd scxctl && printf true || printf false)" \\
''',
    '''    --arg scheduler_enabled "$SCHED_EXT_ENABLED" \\
    --arg scheduler_last_selected "$scheduler_last_selected" \\
    --arg scheduler_restore_enabled "$scheduler_restore_enabled" \\
    --arg scheduler_available "$(have_cmd scxctl && printf true || printf false)" \\
''',
    label="scheduler status jq arguments",
)
backend = replace_exact(
    backend,
    '''          enabled:($scheduler_enabled == "1"),
          available:($scheduler_available == "true"),
''',
    '''          enabled:($scheduler_enabled == "1"),
          last_selected:$scheduler_last_selected,
          restore_enabled:($scheduler_restore_enabled == "1"),
          available:($scheduler_available == "true"),
''',
    label="scheduler status persisted fields",
)
backend = replace_exact(
    backend,
    '''machine_scheduler_stop() {
  refresh_sched_ext
  if (( EUID != 0 )) && ! sudo_can_run_scxctl_noninteractive; then
    scxctl_auth_state_clear
    printf 'sched-ext authorization has not been configured\\n' >&2
    return 3
  fi
  if (( EUID != 0 )); then
    scxctl_auth_state_mark || true
  fi
  sched_ext_stop
}

machine_action() {
''',
    '''machine_scheduler_stop() {
  refresh_sched_ext
  if (( EUID != 0 )) && ! sudo_can_run_scxctl_noninteractive; then
    scxctl_auth_state_clear
    printf 'sched-ext authorization has not been configured\\n' >&2
    return 3
  fi
  if (( EUID != 0 )); then
    scxctl_auth_state_mark || true
  fi
  sched_ext_stop
}

machine_scheduler_restore() {
  sched_ext_state_load
  [[ "$SCHED_EXT_RESTORE_ENABLED" == '1' ]] || return 0
  valid_scheduler "$SCHED_EXT_LAST_SELECTED" || return 0

  refresh_sched_ext
  [[ "$SCHED_EXT_RUNNING" == "$SCHED_EXT_LAST_SELECTED" ]] && return 0
  sched_ext_deps_ok || return 0

  if (( EUID != 0 )) && ! sudo_can_run_scxctl_noninteractive; then
    return 0
  fi
  if (( EUID != 0 )); then
    scxctl_auth_state_mark || true
  fi

  sched_ext_switch_or_start "$SCHED_EXT_LAST_SELECTED"
}

machine_scheduler_reapply_if_running() {
  local scheduler="$1"
  refresh_sched_ext
  [[ "$SCHED_EXT_ENABLED" == '1' && "$SCHED_EXT_RUNNING" == "$scheduler" ]] || return 0
  sched_ext_deps_ok || return 1

  if (( EUID != 0 )) && ! sudo_can_run_scxctl_noninteractive; then
    scxctl_auth_state_clear
    printf 'sched-ext authorization has not been configured\\n' >&2
    return 3
  fi
  if (( EUID != 0 )); then
    scxctl_auth_state_mark || true
  fi

  sched_ext_switch_or_start "$scheduler"
}

machine_action() {
''',
    label="scheduler restore and active config reapply helpers",
)
for old, new, label in (
    (
        '''      SCHED_EXT_PROFILE_MAP["$scheduler"]="$profile"
      sched_ext_state_save
      ;;
''',
        '''      SCHED_EXT_PROFILE_MAP["$scheduler"]="$profile"
      sched_ext_state_save
      machine_scheduler_reapply_if_running "$scheduler"
      ;;
''',
        "profile live reapply",
    ),
    (
        '''      SCHED_EXT_CUSTOM_ARGS_MAP["$scheduler"]="$(sched_ext_normalize_args "$custom")"
      sched_ext_state_save
      ;;
''',
        '''      SCHED_EXT_CUSTOM_ARGS_MAP["$scheduler"]="$(sched_ext_normalize_args "$custom")"
      sched_ext_state_save
      machine_scheduler_reapply_if_running "$scheduler"
      ;;
''',
        "custom args live reapply",
    ),
    (
        '''      SCHED_EXT_LAVD_AUTOPOWER_MAP["$scheduler"]=$([[ "$value" == true ]] && printf 1 || printf 0)
      sched_ext_state_save
      ;;
''',
        '''      SCHED_EXT_LAVD_AUTOPOWER_MAP["$scheduler"]=$([[ "$value" == true ]] && printf 1 || printf 0)
      sched_ext_state_save
      machine_scheduler_reapply_if_running "$scheduler"
      ;;
''',
        "autopower live reapply",
    ),
    (
        '''      sched_ext_state_load
      sched_ext_reset_config "$scheduler"
      ;;
''',
        '''      sched_ext_state_load
      sched_ext_reset_config "$scheduler"
      machine_scheduler_reapply_if_running "$scheduler"
      ;;
''',
        "reset live reapply",
    ),
):
    backend = replace_exact(backend, old, new, label=label)
backend = replace_exact(
    backend,
    '''  --authorize-scheduler-stdin)
    machine_scheduler_authorize_stdin
    ;;
  --action)
''',
    '''  --authorize-scheduler-stdin)
    machine_scheduler_authorize_stdin
    ;;
  --restore-scheduler)
    machine_scheduler_restore
    ;;
  --action)
''',
    label="scheduler restore CLI entrypoint",
)
BACKEND.write_text(backend, encoding="utf-8")

# Quick Settings UX: immediate scheduler choice, one-shot restore, Bar hints.
qml = QML.read_text(encoding="utf-8")
qml = replace_exact(
    qml,
    '''                enabled: false,
                available: false,
                authorized: false,
                schedulers: []
''',
    '''                enabled: false,
                last_selected: "",
                restore_enabled: false,
                available: false,
                authorized: false,
                schedulers: []
''',
    label="Quick Settings scheduler persisted-state model",
)
qml = replace_exact(
    qml,
    '''        let selected = schedulerByName(selectedSchedulerName);
        if (!selected) {
            selected = schedulerByName(String(schedulerStatus.running || "")) || schedulers[0];
            selectedSchedulerName = String(selected.name || "");
''',
    '''        let selected = schedulerByName(selectedSchedulerName);
        if (!selected) {
            selected = schedulerByName(String(schedulerStatus.running || ""))
                || schedulerByName(String(schedulerStatus.last_selected || ""))
                || schedulers[0];
            selectedSchedulerName = String(selected.name || "");
''',
    label="Quick Settings saved scheduler selection fallback",
)
qml = replace_exact(
    qml,
    '''    function selectScheduler(name) {
        selectedSchedulerName = name;
        const selected = schedulerByName(name);
        schedulerArgsDraft = selected ? String(selected.custom_args || "") : "";
        schedulerArgsDirty = false;
        schedulerEditorOpen = true;
    }
''',
    '''    function selectScheduler(name) {
        selectedSchedulerName = name;
        const selected = schedulerByName(name);
        schedulerArgsDraft = selected ? String(selected.custom_args || "") : "";
        schedulerArgsDirty = false;
        schedulerEditorOpen = true;
        if (Boolean(schedulerStatus.available) && Boolean(schedulerStatus.authorized))
            queueAction(["scheduler-start", name], "Switching to " + name + "…");
    }
''',
    label="immediate scheduler selection",
)
qml = replace_exact(
    qml,
    '''    Process {
        id: prepareProcess
        onExited: root.finishPreparedOpen()
    }
''',
    '''    Timer {
        interval: 1800
        repeat: false
        running: true
        onTriggered: {
            if (!schedulerRestoreRunner.running)
                schedulerRestoreRunner.exec([backend, "--restore-scheduler"]);
        }
    }

    Process {
        id: schedulerRestoreRunner
        onExited: {
            if (quickSettingsWindow.visible)
                root.refreshStatus();
        }
    }

    Process {
        id: prepareProcess
        onExited: root.finishPreparedOpen()
    }
''',
    label="one-shot session scheduler restore",
)
qml = replace_exact(
    qml,
    '''                                    SettingsButton {
                                        label: "Apply"
                                        available: Boolean(root.schedulerStatus.available)
                                            && Boolean(root.schedulerStatus.authorized)
                                            && root.selectedSchedulerName.length > 0
                                        textSize: root.scaledText(9)
                                        onClicked: root.queueAction([
                                            "scheduler-start", root.selectedSchedulerName
                                        ], "Starting " + root.selectedSchedulerName + "…")
                                    }
''',
    '',
    label="remove scheduler Apply button",
)
qml = replace_exact(
    qml,
    '''                                            active: root.selectedSchedulerName === String(modelData.name)
                                            textSize: root.scaledText(9)
                                            onClicked: root.selectScheduler(String(modelData.name))
''',
    '''                                            active: root.selectedSchedulerName === String(modelData.name)
                                            available: Boolean(root.schedulerStatus.available)
                                                && Boolean(root.schedulerStatus.authorized)
                                            textSize: root.scaledText(9)
                                            onClicked: root.selectScheduler(String(modelData.name))
''',
    label="scheduler selection authorization gate",
)
qml = replace_exact(
    qml,
    '''                                    Text {
                                        Layout.fillWidth: true
                                        text: "Tip: drag the bar with SUPER+Mouse1 or ALT+Mouse1."
                                        color: Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(8)
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }
''',
    '''                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Position: SUPER+Mouse1 / ALT+Mouse1 drag · CTRL+SUPER+B / SUPER+ALT+B change edge"
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            horizontalAlignment: Text.AlignRight
                                            wrapMode: Text.Wrap
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Visibility: CTRL+SUPER+ALT+B toggle"
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
''',
    label="Bar keyboard shortcut hints",
)
QML.write_text(qml, encoding="utf-8")

# Append managed-stock checksums for the exact new bytes.
history = HISTORY.read_text(encoding="utf-8")
if history and not history.endswith("\n"):
    history += "\n"
for source, rel in (
    (QML, ".config/quickshell/awtarchy/QuickSettings.qml"),
    (BACKEND, ".config/hypr/scripts/hypr_quicksettings.sh"),
    (CORE, ".config/hypr/scripts/hypr_quicksettings_core.sh"),
):
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    entry = f"{digest}\t{rel}\n"
    if entry not in history:
        history += entry
HISTORY.write_text(history, encoding="utf-8")
