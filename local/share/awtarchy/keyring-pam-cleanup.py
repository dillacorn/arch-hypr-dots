#!/usr/bin/env python3
from pathlib import Path
import sys

MARKERS = (
    "# GNOME Keyring Integration",
    "# Unlock GNOME Keyring (added by dotfiles setup)",
)
DATED_PREFIX = "# GNOME Keyring Integration (added "
AUTH_LINE = "auth       optional     pam_gnome_keyring.so"
SESSION_LINE = "session    optional     pam_gnome_keyring.so auto_start"


def is_marker(line: str) -> bool:
    return line in MARKERS or line.startswith(DATED_PREFIX)


def clean_legacy_keyring_block(text: str) -> tuple[str, bool]:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    changed = False
    index = 0

    while index < len(lines):
        marker = lines[index].rstrip("\r\n")
        if is_marker(marker) and index + 2 < len(lines):
            auth = lines[index + 1].strip()
            session = lines[index + 2].strip()
            if auth == AUTH_LINE and session == SESSION_LINE:
                index += 3
                changed = True
                continue

        output.append(lines[index])
        index += 1

    return "".join(output), changed


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: keyring-pam-cleanup.py INPUT OUTPUT", file=sys.stderr)
        return 64

    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    cleaned, changed = clean_legacy_keyring_block(source.read_text(encoding="utf-8"))
    destination.write_text(cleaned, encoding="utf-8")
    return 0 if changed else 3


if __name__ == "__main__":
    raise SystemExit(main())
