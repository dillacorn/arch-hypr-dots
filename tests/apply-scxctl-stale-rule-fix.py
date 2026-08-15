#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / "config/hypr/scripts/hypr_quicksettings_core.sh"
text = path.read_text(encoding="utf-8")

old_cached = '''  if sudo test -f "$sudoers_target" && sudo_can_run_scxctl_noninteractive; then\n    return 0\n  fi\n\n'''
if old_cached not in text:
    raise SystemExit("cached-sudo shortcut context not found")
text = text.replace(old_cached, "", 1)

old_verify = '''  if ! sudo_can_run_scxctl_noninteractive; then\n    MSG='sched-ext: sudoers rule installed but unusable'\n    return 1\n  fi\n'''
new_verify = '''  sudo -k\n  if ! sudo -n "$SCXCTL_HELPER" list >/dev/null 2>&1; then\n    MSG='sched-ext: sudoers rule installed but unusable'\n    return 1\n  fi\n'''
if old_verify not in text:
    raise SystemExit("post-install verification context not found")
text = text.replace(old_verify, new_verify, 1)

path.write_text(text, encoding="utf-8")
