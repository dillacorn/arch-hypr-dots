#!/usr/bin/env python3
from pathlib import Path
import hashlib

history = Path("local/share/awtarchy/quickshell-managed-history.sha256")
managed = []

for source in sorted(Path("config/quickshell/awtarchy").iterdir()):
    if source.is_file():
        managed.append((source, Path(".config/quickshell/awtarchy") / source.name))

for source in sorted(Path("config/hypr/scripts").iterdir()):
    if not source.is_file():
        continue
    if source.name.startswith("quickshell") or source.name in {
        "ddc_brightness.sh",
        "hypr-ddc-brightness.sh",
    }:
        managed.append((source, Path(".config/hypr/scripts") / source.name))

for source in sorted(Path("local/share/applications").iterdir()):
    if source.is_file() and source.name.startswith("quickshell_bar_") and source.suffix == ".desktop":
        managed.append((source, Path(".local/share/applications") / source.name))

text = history.read_text(encoding="utf-8")
lines = text.splitlines()
existing = set(lines)
missing = []
for source, rel in managed:
    entry = f"{hashlib.sha256(source.read_bytes()).hexdigest()}\t{rel.as_posix()}"
    if entry not in existing:
        missing.append(entry)
        existing.add(entry)

if missing:
    history.write_text(text.rstrip("\n") + "\n" + "\n".join(sorted(missing)) + "\n", encoding="utf-8")
