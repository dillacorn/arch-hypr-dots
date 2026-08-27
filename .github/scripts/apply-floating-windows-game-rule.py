#!/usr/bin/env python3
from pathlib import Path
import re

path = Path("config/hypr/hyprland.lua")
text = path.read_text()

old_block = '''local awtarchy_floating_windows = false -- AWTARCHY_FLOATING_WINDOWS
if awtarchy_floating_windows then
    hl.window_rule({ match = { class = ".*" }, float = true })
end

'''
if text.count(old_block) != 1:
    raise SystemExit(
        f"hyprland.lua guard failed: expected one floating block, found {text.count(old_block)}"
    )

text = text.replace(
    old_block,
    "local awtarchy_floating_windows = false -- AWTARCHY_FLOATING_WINDOWS\n\n",
    1,
)

matches = list(re.finditer(r"(?m)^local games = .+\n", text))
if len(matches) != 1:
    raise SystemExit(
        f"hyprland.lua guard failed: expected one games definition, found {len(matches)}"
    )

match = matches[0]
insert = '''
if awtarchy_floating_windows then
    hl.window_rule({ match = { class = ".*" }, float = true })
    hl.window_rule({ match = { class = games }, tile = true })
end
'''
text = text[: match.end()] + insert + text[match.end() :]
path.write_text(text)
