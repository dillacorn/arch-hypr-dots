#!/usr/bin/env python3
from pathlib import Path

path = Path("config/hypr/hyprland.lua")
text = path.read_text()
old = '''        { "SUPER + A", toggle_animations },
    { "SUPER + ALT + F", floating_windows_toggle },
    }) do
'''
new = '''        { "SUPER + A", toggle_animations },
        { "SUPER + ALT + F", floating_windows_toggle },
    }) do
'''
if text.count(old) != 1:
    raise SystemExit("expected one mis-indented noalt floating bind")
path.write_text(text.replace(old, new, 1))
