#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QML = ROOT / "config/quickshell/awtarchy/QuickSettings.qml"
BACKEND = ROOT / "config/hypr/scripts/hypr_quicksettings.sh"
CORE = ROOT / "config/hypr/scripts/hypr_quicksettings_core.sh"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected patch context not found in {path}: {old[:80]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Explicit authorization must be able to ignore a warm sudo timestamp and read
# the password from a pipe owned by the Quick Settings process.
replace_once(
    CORE,
    '''ensure_scxctl_nopasswd_rule() {\n  local user sudoers_name sudoers_target tmpfile\n''',
    '''ensure_scxctl_nopasswd_rule() {\n  local auth_mode="${1:-tty}" force_repair="${2:-0}"\n  local user sudoers_name sudoers_target tmpfile\n\n  case "$auth_mode" in\n    tty|stdin) ;;\n    *)\n      MSG='sched-ext: invalid authorization mode'\n      return 2\n      ;;\n  esac\n''',
)

replace_once(
    CORE,
    '''  if sudo_can_run_scxctl_noninteractive; then\n    return 0\n  fi\n''',
    '''  if (( force_repair == 0 )) && sudo_can_run_scxctl_noninteractive; then\n    return 0\n  fi\n''',
)

replace_once(
    CORE,
    '''  printf '\\033[2J\\033[H'\n  printf '%s\\n\\n' "$TITLE"\n  printf 'sched-ext needs one sudo prompt to authorize the restricted Awtarchy scheduler helper.\\n\\n'\n\n  if ! sudo -v; then\n    MSG='sched-ext: sudo auth failed'\n    return 1\n  fi\n''',
    '''  case "$auth_mode" in\n    tty)\n      printf '\\033[2J\\033[H'\n      printf '%s\\n\\n' "$TITLE"\n      printf 'sched-ext needs one sudo prompt to authorize the restricted Awtarchy scheduler helper.\\n\\n'\n      if ! sudo -v; then\n        MSG='sched-ext: sudo auth failed'\n        return 1\n      fi\n      ;;\n    stdin)\n      # Never let a cached sudo timestamp make a stale rule look authorized.\n      # The password is supplied by Quickshell over this process stdin only.\n      sudo -k\n      if ! sudo -S -p '' -v 2>/dev/null; then\n        MSG='sched-ext: sudo authentication failed'\n        return 1\n      fi\n      ;;\n  esac\n''',
)

# Replace the temporary terminal-only backend entrypoint with a pipe-only one.
replace_once(
    BACKEND,
    '''machine_scheduler_authorize() {\n  if (( EUID != 0 )) && [[ ! -t 0 ]]; then\n    printf 'sched-ext authorization requires an interactive terminal\\n' >&2\n    return 4\n  fi\n\n  if ! ensure_scxctl_nopasswd_rule; then\n    printf '%s\\n' "${MSG:-sched-ext authorization failed}" >&2\n    return 1\n  fi\n\n  printf '%s\\n' "${MSG:-sched-ext authorization complete}"\n  if have_cmd qs; then\n    qs -c awtarchy ipc call quicksettings refresh >/dev/null 2>&1 || true\n  fi\n}\n''',
    '''machine_scheduler_authorize_stdin() {\n  if (( EUID != 0 )) && [[ -t 0 ]]; then\n    printf 'sched-ext authorization must be submitted from Quick Settings\\n' >&2\n    return 4\n  fi\n\n  if ! ensure_scxctl_nopasswd_rule stdin 1; then\n    printf '%s\\n' "${MSG:-sched-ext authorization failed}" >&2\n    return 1\n  fi\n\n  printf '%s\\n' "${MSG:-sched-ext authorization complete}"\n}\n''',
)

replace_once(
    BACKEND,
    '''  --authorize-scheduler)\n    machine_scheduler_authorize\n    ;;\n''',
    '''  --authorize-scheduler-stdin)\n    machine_scheduler_authorize_stdin\n    ;;\n''',
)

# Add short-lived inline-auth state. The pending password exists only until the
# child process starts, then is immediately written to stdin and cleared.
replace_once(
    QML,
    '''    property bool schedulerEditorOpen: false\n    property string schedulerArgsDraft: ""\n    property bool schedulerArgsDirty: false\n''',
    '''    property bool schedulerEditorOpen: false\n    property string schedulerArgsDraft: ""\n    property bool schedulerArgsDirty: false\n    property bool schedulerAuthOpen: false\n    property bool schedulerAuthBusy: false\n    property string schedulerAuthError: ""\n    property string schedulerAuthPendingPassword: ""\n''',
)

replace_once(
    QML,
    '''    function authorizeScheduler() {\n        actionMessage = "Complete sched-ext authorization in the terminal";\n        actionError = "";\n        Quickshell.execDetached([\n            terminalLauncher, "--class", "awtarchy-scxctl-auth", "--hold", "--",\n            backend, "--authorize-scheduler"\n        ]);\n    }\n''',
    '''    function openSchedulerAuthorization() {\n        if (schedulerAuthBusy)\n            return;\n        schedulerAuthOpen = true;\n        schedulerAuthError = "";\n        actionError = "";\n        actionMessage = "sched-ext authorization required";\n        Qt.callLater(() => schedulerPasswordInput.forceActiveFocus());\n    }\n\n    function cancelSchedulerAuthorization() {\n        if (schedulerAuthBusy)\n            return;\n        schedulerAuthOpen = false;\n        schedulerAuthError = "";\n        schedulerAuthPendingPassword = "";\n        schedulerPasswordInput.text = "";\n    }\n\n    function submitSchedulerAuthorization() {\n        if (schedulerAuthBusy)\n            return;\n        if (schedulerPasswordInput.text.length === 0) {\n            schedulerAuthError = "Enter your sudo password";\n            schedulerPasswordInput.forceActiveFocus();\n            return;\n        }\n\n        schedulerAuthPendingPassword = schedulerPasswordInput.text;\n        schedulerPasswordInput.text = "";\n        schedulerAuthError = "";\n        actionError = "";\n        schedulerAuthBusy = true;\n        actionMessage = "Authorizing sched-ext…";\n        schedulerAuthRunner.exec([backend, "--authorize-scheduler-stdin"]);\n    }\n''',
)

replace_once(
    QML,
    '''        schedulerEditorOpen = false;\n        brightnessHoverPercent = -1;\n''',
    '''        schedulerEditorOpen = false;\n        if (!schedulerAuthBusy)\n            cancelSchedulerAuthorization();\n        else\n            schedulerPasswordInput.text = "";\n        brightnessHoverPercent = -1;\n''',
)

replace_once(
    QML,
    '''    Process {\n        id: stateWriter\n''',
    '''    Process {\n        id: schedulerAuthRunner\n        stdinEnabled: true\n        stderr: StdioCollector {\n            onStreamFinished: {\n                const errorText = text.trim();\n                if (errorText.length > 0)\n                    root.schedulerAuthError = errorText.split("\\n")[0];\n            }\n        }\n        onStarted: {\n            // sudo may request up to three attempts. Extra blank responses make\n            // a wrong password fail promptly instead of leaving a hidden process\n            // blocked waiting for another line of input.\n            schedulerAuthRunner.write(root.schedulerAuthPendingPassword + "\\n\\n\\n");\n            root.schedulerAuthPendingPassword = "";\n        }\n        onExited: (exitCode, exitStatus) => {\n            root.schedulerAuthPendingPassword = "";\n            root.schedulerAuthBusy = false;\n            if (exitCode === 0) {\n                root.schedulerAuthOpen = false;\n                root.schedulerAuthError = "";\n                root.actionMessage = "sched-ext authorization complete";\n                root.refreshStatus();\n                return;\n            }\n\n            if (root.schedulerAuthError.length === 0)\n                root.schedulerAuthError = "sched-ext authorization failed";\n            root.actionMessage = root.schedulerAuthError;\n            if (quickSettingsWindow.visible)\n                Qt.callLater(() => schedulerPasswordInput.forceActiveFocus());\n        }\n    }\n\n    Process {\n        id: stateWriter\n''',
)

replace_once(
    QML,
    '''                                        onClicked: root.authorizeScheduler()\n''',
    '''                                        onClicked: root.openSchedulerAuthorization()\n''',
)

replace_once(
    QML,
    '''                                Flow {\n                                    Layout.fillWidth: true\n                                    Layout.preferredHeight: childrenRect.height\n                                    spacing: 5\n                                    Repeater {\n                                        model: root.schedulerStatus.schedulers || []\n''',
    '''                                ColumnLayout {\n                                    Layout.fillWidth: true\n                                    visible: root.schedulerAuthOpen\n                                        && Boolean(root.schedulerStatus.available)\n                                        && !Boolean(root.schedulerStatus.authorized)\n                                    spacing: 5\n\n                                    Text {\n                                        Layout.fillWidth: true\n                                        text: root.schedulerAuthError.length > 0\n                                            ? root.schedulerAuthError\n                                            : "Enter your sudo password to authorize the restricted scheduler helper"\n                                        color: root.schedulerAuthError.length > 0 ? Theme.urgent : Theme.muted\n                                        font.family: Theme.fontFamily\n                                        font.pixelSize: root.scaledText(9)\n                                        wrapMode: Text.Wrap\n                                    }\n\n                                    RowLayout {\n                                        Layout.fillWidth: true\n                                        spacing: 6\n\n                                        Text {\n                                            text: "Password"\n                                            color: Theme.foreground\n                                            font.family: Theme.fontFamily\n                                            font.pixelSize: root.scaledText(9)\n                                        }\n\n                                        Rectangle {\n                                            Layout.fillWidth: true\n                                            Layout.preferredHeight: 30\n                                            color: Theme.active\n                                            border.width: 1\n                                            border.color: schedulerPasswordInput.activeFocus\n                                                ? Theme.focus : Theme.muted\n\n                                            TextInput {\n                                                id: schedulerPasswordInput\n                                                anchors.fill: parent\n                                                anchors.leftMargin: 7\n                                                anchors.rightMargin: 7\n                                                enabled: !root.schedulerAuthBusy\n                                                echoMode: TextInput.Password\n                                                color: Theme.foreground\n                                                selectionColor: Theme.focus\n                                                selectedTextColor: Theme.foreground\n                                                font.family: Theme.fontFamily\n                                                font.pixelSize: root.scaledText(9)\n                                                verticalAlignment: TextInput.AlignVCenter\n                                                clip: true\n                                                selectByMouse: true\n                                                onAccepted: root.submitSchedulerAuthorization()\n                                                Keys.onEscapePressed: root.cancelSchedulerAuthorization()\n                                            }\n                                        }\n\n                                        SettingsButton {\n                                            label: root.schedulerAuthBusy ? "Authorizing…" : "Authorize"\n                                            available: !root.schedulerAuthBusy\n                                                && schedulerPasswordInput.text.length > 0\n                                            textSize: root.scaledText(9)\n                                            onClicked: root.submitSchedulerAuthorization()\n                                        }\n\n                                        SettingsButton {\n                                            label: "Cancel"\n                                            available: !root.schedulerAuthBusy\n                                            textSize: root.scaledText(9)\n                                            onClicked: root.cancelSchedulerAuthorization()\n                                        }\n                                    }\n                                }\n\n                                Flow {\n                                    Layout.fillWidth: true\n                                    Layout.preferredHeight: childrenRect.height\n                                    spacing: 5\n                                    Repeater {\n                                        model: root.schedulerStatus.schedulers || []\n''',
)

print("inline sched-ext auth patch applied")
