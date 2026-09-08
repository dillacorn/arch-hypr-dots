#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
POWER_MENU="${ROOT}/config/quickshell/awtarchy/PowerMenu.qml"

python3 - "$POWER_MENU" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def require(needle: str, message: str) -> None:
    if needle not in text:
        fail(message)


run_marker = "    function runAction(action) {"
ipc_marker = "\n\n    IpcHandler {"
if run_marker not in text or ipc_marker not in text:
    fail("power menu action function layout changed unexpectedly")
run_action = text.split(run_marker, 1)[1].split(ipc_marker, 1)[0]

if "close();" in run_action:
    fail("power menu closes before the selected action can take over the screen")
if "Quickshell.execDetached" in run_action:
    fail("power menu action handoff is still detached and cannot observe failures")

require("property bool actionPending: false",
        "power menu does not track an in-progress action handoff")
require("property bool closeAfterActionSuccess: false",
        "power menu does not distinguish secure-cover actions from session termination")
require("if (actionPending)\n            return;",
        "power menu does not block dismissal or repeated activation during handoff")
require("actionProcess.command = [\"sh\", \"-lc\", action.command];",
        "power menu does not launch actions through the tracked handoff process")
require("id: actionProcess",
        "power menu has no tracked process for action completion/failure")
require("onExited: exitCode => {",
        "power menu does not react to action completion/failure")
require("function finishHandoffClose()",
        "power menu has no explicit close path for an already-covered screen")

require('command: "~/.config/hypr/scripts/awtarchy_lock.sh lock && ~/.config/hypr/scripts/awtarchy_lock.sh wait-secure 5", closeAfterSuccess: true',
        "Lock does not keep the power menu visible until compositor-secure confirmation")
require('command: "~/.config/hypr/scripts/awtarchy_lock.sh hibernate", closeAfterSuccess: true',
        "Hibernate does not retain the overlay through its secure-lock handoff")
require('command: "~/.config/hypr/scripts/awtarchy_lock.sh suspend", closeAfterSuccess: true',
        "Suspend does not retain the overlay through its secure-lock handoff")
require('command: "systemctl reboot", closeAfterSuccess: false',
        "Reboot is allowed to fade the power menu away after command success")
require('command: "systemctl poweroff", closeAfterSuccess: false',
        "Shutdown is allowed to fade the power menu away after command success")
require('command: "loginctl kill-session \\"$XDG_SESSION_ID\\"", closeAfterSuccess: false',
        "Logout is allowed to fade the power menu away after command success")

print("PASS: power menu action handoff keeps the desktop covered")
PY
