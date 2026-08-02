#!/usr/bin/env python3
from pathlib import Path

path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = path.read_text(encoding="utf-8")

old = "      grep -Fqx '[Desktop Entry]' \"$file\"         && grep -Eq '^Type=(Application|Link|Directory)$' \"$file\"         && grep -Eq '^Name=.+$' \"$file\""
new = "\n".join(
    [
        "      grep -Fqx '[Desktop Entry]' \"$file\" \\",
        "        && grep -Eq '^Type=(Application|Link|Directory)$' \"$file\" \\",
        "        && grep -Eq '^Name=.+$' \"$file\"",
    ]
)

count = text.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one collapsed desktop validator, found {count}")

path.write_text(text.replace(old, new, 1), encoding="utf-8")
