#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "config/hypr/scripts/hypr_quicksettings_core.sh"
text = path.read_text(encoding="utf-8")
old = '  if sudo_can_run_scxctl_noninteractive || ensure_scxctl_nopasswd_rule; then\n'
new = '  if sudo_can_run_scxctl_noninteractive || ensure_scxctl_nopasswd_rule tty 0; then\n'
if new not in text:
    if old not in text:
        raise SystemExit("normal scheduler authorization call context not found")
    text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
