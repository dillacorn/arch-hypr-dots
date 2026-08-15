#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QML = ROOT / "config/quickshell/awtarchy/QuickSettings.qml"
BACKEND = ROOT / "config/hypr/scripts/hypr_quicksettings.sh"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected patch context not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    QML,
    '''    function openThemeMenu() {\n        ThemePicker.openForScreen(activeScreen);\n    }\n''',
    '''    function authorizeScheduler() {\n        actionMessage = "Complete sched-ext authorization in the terminal";\n        actionError = "";\n        Quickshell.execDetached([\n            terminalLauncher, "--class", "awtarchy-scxctl-auth", "--hold", "--",\n            backend, "--authorize-scheduler"\n        ]);\n    }\n\n    function openThemeMenu() {\n        ThemePicker.openForScreen(activeScreen);\n    }\n''',
)

replace_once(
    QML,
    '''                                    SettingsButton {\n                                        label: "Start / Switch"\n                                        available: Boolean(root.schedulerStatus.available)\n                                            && root.selectedSchedulerName.length > 0\n                                        textSize: root.scaledText(9)\n                                        onClicked: root.queueAction([\n                                            "scheduler-start", root.selectedSchedulerName\n                                        ], "Starting " + root.selectedSchedulerName + "…")\n                                    }\n                                    SettingsButton {\n                                        label: "Stop"\n                                        available: Boolean(root.schedulerStatus.enabled)\n                                        textSize: root.scaledText(9)\n                                        onClicked: root.queueAction(["scheduler-stop"], "Stopping sched-ext…")\n                                    }\n''',
    '''                                    SettingsButton {\n                                        label: "Authorize"\n                                        visible: Boolean(root.schedulerStatus.available)\n                                            && !Boolean(root.schedulerStatus.authorized)\n                                        available: visible\n                                        textSize: root.scaledText(9)\n                                        onClicked: root.authorizeScheduler()\n                                    }\n                                    SettingsButton {\n                                        label: "Start / Switch"\n                                        available: Boolean(root.schedulerStatus.available)\n                                            && Boolean(root.schedulerStatus.authorized)\n                                            && root.selectedSchedulerName.length > 0\n                                        textSize: root.scaledText(9)\n                                        onClicked: root.queueAction([\n                                            "scheduler-start", root.selectedSchedulerName\n                                        ], "Starting " + root.selectedSchedulerName + "…")\n                                    }\n                                    SettingsButton {\n                                        label: "Stop"\n                                        available: Boolean(root.schedulerStatus.enabled)\n                                            && Boolean(root.schedulerStatus.authorized)\n                                        textSize: root.scaledText(9)\n                                        onClicked: root.queueAction(["scheduler-stop"], "Stopping sched-ext…")\n                                    }\n''',
)

replace_once(
    QML,
    '''                                    text: !root.schedulerStatus.available\n                                        ? "scxctl is unavailable"\n                                        : "Starting sched-ext needs the existing one-time scxctl authorization"\n''',
    '''                                    text: !root.schedulerStatus.available\n                                        ? "scxctl is unavailable"\n                                        : "Authorize once to let Quick Settings start, switch, and stop sched-ext"\n''',
)

replace_once(
    BACKEND,
    '''machine_scheduler_start() {\n''',
    '''machine_scheduler_authorize() {\n  if (( EUID != 0 )) && [[ ! -t 0 ]]; then\n    printf 'sched-ext authorization requires an interactive terminal\\n' >&2\n    return 4\n  fi\n\n  if ! ensure_scxctl_nopasswd_rule; then\n    printf '%s\\n' "${MSG:-sched-ext authorization failed}" >&2\n    return 1\n  fi\n\n  printf '%s\\n' "${MSG:-sched-ext authorization complete}"\n  if have_cmd qs; then\n    qs -c awtarchy ipc call quicksettings refresh >/dev/null 2>&1 || true\n  fi\n}\n\nmachine_scheduler_start() {\n''',
)

replace_once(
    BACKEND,
    '''  --action)\n    shift\n    machine_action "$@"\n    ;;\n''',
    '''  --authorize-scheduler)\n    machine_scheduler_authorize\n    ;;\n  --action)\n    shift\n    machine_action "$@"\n    ;;\n''',
)

print("scxctl auth patch applied")
