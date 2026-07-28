#!/usr/bin/env bash
# ~/.config/waybar/scripts/ddc_brightness_vertical.sh
# Splits the event-driven brightness stream into vertical icon/value modules.

set -euo pipefail

mode="${1:-}"
SRC="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/ddc_brightness.sh"

"$SRC" watch | python3 /dev/fd/3 "$mode" 3<<'PY'
import json
import sys

mode = sys.argv[1]

for raw in sys.stdin:
    raw = raw.rstrip("\n")
    try:
        data = json.loads(raw)
    except Exception:
        print(raw, flush=True)
        continue

    text = str(data.get("text", ""))
    parts = text.split(maxsplit=1)
    icon = parts[0] if parts else ""
    value = parts[1] if len(parts) > 1 else ""

    if mode == "icon":
        data["text"] = icon
    elif mode == "value":
        data["text"] = value

    print(json.dumps(data, ensure_ascii=False), flush=True)
PY
