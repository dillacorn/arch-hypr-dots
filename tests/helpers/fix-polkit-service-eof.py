#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[2] / "config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service"
text = path.read_text(encoding="utf-8")
path.write_text(text.rstrip("\n") + "\n", encoding="utf-8")
