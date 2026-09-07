#!/usr/bin/env python3
from hashlib import sha256
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"
TRACKED = (
    "config/quickshell/awtarchy/Bar.qml",
    "config/quickshell/awtarchy/PowerMenu.qml",
)

text = HISTORY.read_text(encoding="utf-8")
entries = []
for rel in TRACKED:
    digest = sha256((ROOT / rel).read_bytes()).hexdigest()
    entry = f"{digest}\t.{rel}"
    if entry not in text:
        entries.append(entry)

if entries:
    if not text.endswith("\n"):
        text += "\n"
    text += "\n".join(entries) + "\n"
    HISTORY.write_text(text, encoding="utf-8")
