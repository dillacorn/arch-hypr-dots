#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECONCILER = ROOT / "local/share/awtarchy/awtarchy-package-reconcile.sh"

text = RECONCILER.read_text()
replacements = {
    "as_root pacman -Rns --noconfirm cheese": "as_root pacman -R --noconfirm cheese",
    'as_root pacman -Rns --noconfirm "${selected_retired[@]}"': 'as_root pacman -R --noconfirm "${selected_retired[@]}"',
}

for old, new in replacements.items():
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one match for {old!r}, found {count}")
    text = text.replace(old, new, 1)

RECONCILER.write_text(text)
print("Switched retired package cleanup from recursive -Rns to package-only -R.")
