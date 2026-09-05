#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
LAUNCHER="${ROOT}/local/bin/awtarchy"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
NOTIFIER="${ROOT}/config/hypr/scripts/quickshell_update_notifications.sh"

bash -n "$LAUNCHER"
bash -n "$RECONCILER"
bash -n "$NOTIFIER"

python3 - "$LAUNCHER" "$RECONCILER" "$NOTIFIER" <<'PY'
from pathlib import Path
import re
import sys

launcher = Path(sys.argv[1]).read_text(encoding="utf-8")
reconciler = Path(sys.argv[2]).read_text(encoding="utf-8")
notifier = Path(sys.argv[3]).read_text(encoding="utf-8")


def function_body(text: str, name: str) -> str:
    match = re.search(rf"(?ms)^{re.escape(name)}\(\)\s*\{{\n(.*?)^\}}\n", text)
    if not match:
        raise SystemExit(f"missing function: {name}()")
    return match.group(1)


root_free = function_body(launcher, "root_free_mib")
if "/usr/bin/df" not in root_free:
    raise SystemExit("root free-space probe does not use the trusted df path")

space = function_body(launcher, "ensure_update_disk_headroom")
for required in ("root_free_mib", "paccache", "-rk2", "sudo -n"):
    if required not in space:
        raise SystemExit(f"post-package update disk recovery is missing: {required}")

# Opening `awtarchy update` must not authenticate before the user has reviewed
# and approved a concrete package plan. The package reconciler owns that prompt.
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

if "start_update_privilege_session" in update_arm or "sudo -v" in update_arm:
    raise SystemExit("stable update authenticates sudo before package-plan approval")

ordered = (
    "offer_package_reconciliation_before_update",
    "ensure_update_disk_headroom",
    "config_release_ready_or_noop",
    "run_runtime update-reset-backup",
)
position = -1
for needle in ordered:
    next_position = update_arm.find(needle, position + 1)
    if next_position < 0:
        raise SystemExit(f"stable update flow is missing ordered step: {needle}")
    position = next_position

# Package reconciliation must authenticate only after Apply-plan approval, keep
# that credential alive during trusted package-manager work, recover low disk
# space before installations, then explicitly discard it before any AUR build.
require = function_body(reconciler, "require_sudo")
if "sudo -v" not in require:
    raise SystemExit("package reconciler does not authenticate sudo")

keepalive = function_body(reconciler, "start_package_privilege_keepalive")
for required in ("sudo -n -v", "PACKAGE_SUDO_KEEPALIVE_PID"):
    if required not in keepalive:
        raise SystemExit(f"package sudo keepalive is missing: {required}")

stop = function_body(reconciler, "stop_package_privilege_keepalive")
for required in ("kill", "wait", "PACKAGE_SUDO_KEEPALIVE_PID"):
    if required not in stop:
        raise SystemExit(f"package sudo cleanup is missing: {required}")

recovery = function_body(reconciler, "recover_package_disk_headroom")
for required in ("root_free_mib", "paccache", "-rk2", "sudo -n"):
    if required not in recovery:
        raise SystemExit(f"package-plan disk recovery is missing: {required}")

confirm = "confirm_yes_no 'Apply this package plan?' 0"
confirm_pos = reconciler.find(confirm)
require_pos = reconciler.find("require_sudo", confirm_pos)
keepalive_pos = reconciler.find("start_package_privilege_keepalive", require_pos)
recovery_pos = reconciler.find("recover_package_disk_headroom", keepalive_pos)
aur_stop_pos = reconciler.find("stop_package_privilege_keepalive", recovery_pos)
aur_invalidate_pos = reconciler.find("sudo -k", aur_stop_pos)
aur_pos = reconciler.find("ensure_aur_scanner", aur_invalidate_pos)
for label, pos in (
    ("plan confirmation", confirm_pos),
    ("sudo authentication", require_pos),
    ("trusted keepalive", keepalive_pos),
    ("disk recovery", recovery_pos),
    ("AUR keepalive stop", aur_stop_pos),
    ("AUR sudo invalidation", aur_invalidate_pos),
    ("AUR scanner", aur_pos),
):
    if pos < 0:
        raise SystemExit(f"package reconciliation flow is missing: {label}")
if not confirm_pos < require_pos < keepalive_pos < recovery_pos < aur_stop_pos < aur_invalidate_pos < aur_pos:
    raise SystemExit("package sudo/disk/AUR security boundary is out of order")

# Do not suppress makepkg's deliberate `sudo -k` behavior by injecting a global
# PACMAN_AUTH override. That would expose a reusable sudo ticket to PKGBUILD code.
if "PACMAN_AUTH" in reconciler or "PACMAN_AUTH" in launcher:
    raise SystemExit("Awtarchy must not override makepkg PACMAN_AUTH to suppress AUR sudo prompts")

launch = function_body(notifier, "launch_update")
if "setsid" not in launch or "-f" not in launch or "--wait" not in launch:
    raise SystemExit("notification update terminal is not detached into its own waited session")
if "--hold" not in launch or "--no-profile" not in launch:
    raise SystemExit("detached notification launch lost held clean-terminal behavior")
if '"$SCRIPT_PATH" run-stable-update' not in launch:
    raise SystemExit("stable notification launch no longer routes through run-stable-update")
PY

printf '%s\n' 'PASS: notification detachment, approval-timed sudo, trusted keepalive cleanup, low-disk recovery, and AUR sudo isolation are enforced.'
