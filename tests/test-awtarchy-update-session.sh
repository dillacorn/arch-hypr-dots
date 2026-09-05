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
# and approved a concrete package plan. Privileged work authenticates only when needed.
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

# Package reconciliation must not keep a reusable sudo ticket alive or
# authenticate merely because an AUR-only plan was approved. Privileged
# Awtarchy work should authenticate only when the actual root operation runs.
for forbidden in (
    "PACKAGE_SUDO_KEEPALIVE_PID",
    "start_package_privilege_keepalive",
    "stop_package_privilege_keepalive",
    "resume_package_privilege_keepalive",
):
    if forbidden in reconciler:
        raise SystemExit(f"stale package sudo keepalive remains: {forbidden}")

recovery = function_body(reconciler, "recover_package_disk_headroom")
for required in ("root_free_mib", "paccache", "-rk2", "as_root"):
    if required not in recovery:
        raise SystemExit(f"package-plan disk recovery is missing: {required}")
if "sudo -n" in recovery:
    raise SystemExit("package disk recovery still depends on a pre-authenticated sudo ticket")

confirm = "confirm_yes_no 'Apply this package plan?' 0"
confirm_pos = reconciler.find(confirm)
recovery_pos = reconciler.find("recover_package_disk_headroom", confirm_pos)
arch_pos = reconciler.find('if (( ${#install_arch[@]} )); then', recovery_pos)
for label, pos in (
    ("plan confirmation", confirm_pos),
    ("disk recovery", recovery_pos),
    ("first package action", arch_pos),
):
    if pos < 0:
        raise SystemExit(f"package reconciliation flow is missing: {label}")
if not confirm_pos < recovery_pos < arch_pos:
    raise SystemExit("package approval/disk/action ordering is incorrect")
pre_action = reconciler[confirm_pos:arch_pos]
if "require_sudo" in pre_action or "sudo -v" in pre_action:
    raise SystemExit("AUR-only package approval still authenticates sudo before privileged work")

# Each individual aur-scan invocation must invalidate any ticket left by the
# previous package's final pacman install. Otherwise the next PKGBUILD could run
# before makepkg reaches its own sudo -k boundary.
aur_install = function_body(reconciler, "install_selected_aur_packages")
per_package_k = aur_install.find("sudo -k")
per_package_install = aur_install.find('"$AUR_SCAN_BIN" install')
if per_package_k < 0 or per_package_install < 0 or per_package_k > per_package_install:
    raise SystemExit("each aur-scan install is not preceded by sudo credential invalidation")

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

printf '%s\n' 'PASS: notification detachment, AUR-only no-preauth, low-disk recovery, and per-package AUR sudo isolation are enforced.'
