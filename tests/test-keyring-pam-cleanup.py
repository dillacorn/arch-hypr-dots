#!/usr/bin/env python3
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "local/share/awtarchy/keyring-pam-cleanup.py"
RUNTIME = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
HYPRLAND = ROOT / "config/hypr/hyprland.lua"

spec = spec_from_file_location("keyring_pam_cleanup", SCRIPT)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL: could not load keyring PAM cleanup transform")
module = module_from_spec(spec)
spec.loader.exec_module(module)


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def check(name: str, source: str, expected: str, changed: bool) -> None:
    actual, actual_changed = module.clean_legacy_keyring_block(source)
    if actual != expected:
        fail(f"{name}: cleanup output changed unexpected content")
    if actual_changed is not changed:
        fail(f"{name}: cleanup changed={actual_changed}, expected {changed}")


base = """#%PAM-1.0

auth       requisite    pam_nologin.so
auth       include      system-local-login
account    include      system-local-login
session    include      system-local-login
password   include      system-local-login

"""
block = """# GNOME Keyring Integration (added Sun Jun  7 09:42:18 PM UTC 2026)
auth       optional     pam_gnome_keyring.so
session    optional     pam_gnome_keyring.so auto_start
"""
check("dated Awtarchy marker", base + block, base, True)

old_block = """# Unlock GNOME Keyring (added by dotfiles setup)
auth       optional     pam_gnome_keyring.so
session    optional     pam_gnome_keyring.so auto_start
"""
check("legacy dotfiles marker", base + old_block, base, True)

plain_block = """# GNOME Keyring Integration
auth       optional     pam_gnome_keyring.so
session    optional     pam_gnome_keyring.so auto_start
"""
check("plain Awtarchy marker", base + plain_block, base, True)

custom = """# GNOME Keyring Integration
auth       required     pam_gnome_keyring.so
session    optional     pam_gnome_keyring.so auto_start
"""
check("modified PAM policy", base + custom, base + custom, False)

unmarked = """auth       optional     pam_gnome_keyring.so
session    optional     pam_gnome_keyring.so auto_start
"""
check("unmarked PAM hooks", base + unmarked, base + unmarked, False)

runtime = RUNTIME.read_text(encoding="utf-8")
if "cleanup_legacy_keyring_pam_stage()" not in runtime:
    fail("runtime does not define the legacy keyring PAM cleanup stage")
if 'cleanup_legacy_keyring_pam_stage "$REPO_DIR"' not in runtime:
    fail("fresh-install path does not reconcile legacy keyring PAM state")
if 'cleanup_legacy_keyring_pam_stage "$repo_dir"' not in runtime:
    fail("update path does not reconcile legacy keyring PAM state")
if "if (( INSTALL_LY == 1 )); then" not in runtime:
    fail("Ly install path does not avoid duplicate global keyring PAM hooks")
if "if (( REVIEW_ONLY == 0 )); then" not in runtime:
    fail("update cleanup is not guarded from review-only mode")

hyprland = HYPRLAND.read_text(encoding="utf-8")
if "gnome-keyring-daemon --start" in hyprland:
    fail("Hyprland still starts GNOME Keyring manually")

print("GNOME Keyring PAM cleanup tests passed.")
