#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
LAUNCHER="${ROOT}/local/bin/awtarchy"
NOTIFIER="${ROOT}/config/hypr/scripts/quickshell_update_notifications.sh"

bash -n "$LAUNCHER"
bash -n "$NOTIFIER"

python3 - "$LAUNCHER" "$NOTIFIER" <<'PY'
from pathlib import Path
import re
import sys

launcher = Path(sys.argv[1]).read_text(encoding="utf-8")
notifier = Path(sys.argv[2]).read_text(encoding="utf-8")


def function_body(text: str, name: str) -> str:
    match = re.search(rf"(?ms)^{re.escape(name)}\(\)\s*\{{\n(.*?)^\}}\n", text)
    if not match:
        raise SystemExit(f"missing function: {name}()")
    return match.group(1)


start = function_body(launcher, "start_update_privilege_session")
for required in (
    "sudo -v",
    "sudo -n -v",
    "UPDATE_SUDO_KEEPALIVE_PID",
):
    if required not in start:
        raise SystemExit(f"update privilege session is missing: {required}")

stop = function_body(launcher, "stop_update_privilege_session")
for required in ("kill", "wait", "UPDATE_SUDO_KEEPALIVE_PID"):
    if required not in stop:
        raise SystemExit(f"update privilege cleanup is missing: {required}")

root_free = function_body(launcher, "root_free_mib")
if "/usr/bin/df" not in root_free:
    raise SystemExit("root free-space probe does not use the trusted df path")

space = function_body(launcher, "ensure_update_disk_headroom")
for required in (
    "root_free_mib",
    "paccache",
    "-rk2",
    "sudo -n",
):
    if required not in space:
        raise SystemExit(f"update disk recovery is missing: {required}")

# Stable CLI updates must authenticate and check space before the package UI,
# then re-check space after package work before the managed-file updater runs.
main = function_body(launcher, "main")
update_marker = "    update)"
update_pos = main.find(update_marker)
if update_pos < 0:
    raise SystemExit("main update command arm is missing")
update_arm = main[update_pos:]
end_pos = update_arm.find("\n    reset)")
if end_pos < 0:
    raise SystemExit("could not bound main update command arm")
update_arm = update_arm[:end_pos]

ordered = (
    "start_update_privilege_session",
    "ensure_update_disk_headroom",
    "offer_package_reconciliation_before_update",
    "ensure_update_disk_headroom",
    "run_runtime update-reset-backup",
    "stop_update_privilege_session",
)
position = -1
for needle in ordered:
    next_position = update_arm.find(needle, position + 1)
    if next_position < 0:
        raise SystemExit(f"stable update flow is missing ordered step: {needle}")
    position = next_position

if "trap stop_update_privilege_session EXIT HUP INT TERM" not in update_arm:
    raise SystemExit("stable update flow does not clean up the sudo keepalive on interruption")
if "trap - EXIT HUP INT TERM" not in update_arm:
    raise SystemExit("stable update flow does not clear its temporary cleanup trap")

launch = function_body(notifier, "launch_update")
if "setsid" not in launch or "-f" not in launch or "--wait" not in launch:
    raise SystemExit("notification update terminal is not detached into its own waited session")
if "--hold" not in launch or "--no-profile" not in launch:
    raise SystemExit("detached notification launch lost held clean-terminal behavior")
if '"$SCRIPT_PATH" run-stable-update' not in launch:
    raise SystemExit("stable notification launch no longer routes through run-stable-update")
PY

printf '%s\n' 'PASS: update terminal detachment, single sudo session, interruption cleanup, and low-disk recovery are enforced.'