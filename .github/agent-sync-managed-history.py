#!/usr/bin/env python3
from pathlib import Path
import hashlib

source = Path("config/hypr/scripts/quickshell_launcher_usage.sh")
history = Path("local/share/awtarchy/quickshell-managed-history.sha256")
rel = ".config/hypr/scripts/quickshell_launcher_usage.sh"
entry = f"{hashlib.sha256(source.read_bytes()).hexdigest()}\t{rel}"
text = history.read_text(encoding="utf-8")
if entry not in text.splitlines():
    history.write_text(text.rstrip("\n") + "\n" + entry + "\n", encoding="utf-8")
