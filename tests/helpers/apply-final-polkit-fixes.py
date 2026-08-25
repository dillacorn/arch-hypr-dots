#!/usr/bin/env python3
from pathlib import Path

# One-shot branch patch helper. Deleted by the gated workflow after use.
runtime_path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = runtime_path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    '"Utilities:upower gnome-keyring ',
    '"Utilities:upower polkit gnome-keyring ',
    "explicit polkit package dependency",
)

replace_once(
    "  local polkit_migration_rc=0 polkit_activation_rc=0\n",
    "  local polkit_migration_rc=0 polkit_activation_rc=0 polkit_remove_legacy_ready=0\n",
    "Polkit migration cleanup state",
)

replace_once(
    "        0)\n          remove_legacy_polkit_gnome_package\n          ;;\n",
    "        0)\n          polkit_remove_legacy_ready=1\n          ;;\n",
    "successful live activation cleanup deferral",
)

replace_once(
    "  persist_quickshell_hyprland_user_patch\n  remove_quickshell_update_legacy_packages\n\n  commit_baseline \"$target_home\" \"$source_label\" \"$active_theme\"\n",
    "  persist_quickshell_hyprland_user_patch\n  remove_quickshell_update_legacy_packages\n\n  if (( polkit_remove_legacy_ready == 1 )); then\n    remove_legacy_polkit_gnome_package\n  fi\n\n  commit_baseline \"$target_home\" \"$source_label\" \"$active_theme\"\n",
    "late legacy GNOME Polkit cleanup",
)

runtime_path.write_text(text, encoding="utf-8")
