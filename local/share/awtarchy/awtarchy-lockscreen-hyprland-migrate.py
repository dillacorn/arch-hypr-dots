#!/usr/bin/env python3
"""Safely migrate known Awtarchy lock lines in a personalized hyprland.lua."""

from pathlib import Path
import sys

OLD_BIND = 'hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), {})'
INTERMEDIATE_BIND = (
    'hl.bind("SUPER + L", '
    'hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})'
)
OLD_PERMISSION = 'hl.permission("/usr/bin/hyprlock", "screencopy", "allow")'


def fail(message: str) -> "NoReturn":
    print(f"awtarchy-lockscreen-hyprland-migrate: {message}", file=sys.stderr)
    raise SystemExit(3)


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: awtarchy-lockscreen-hyprland-migrate.py INPUT OUTPUT",
            file=sys.stderr,
        )
        return 2

    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])

    try:
        text = source.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        fail(f"could not read {source}: {exc}")

    migrated = text.replace(OLD_BIND + "\n", "")
    migrated = migrated.replace(OLD_BIND, "")
    migrated = migrated.replace(INTERMEDIATE_BIND + "\n", "")
    migrated = migrated.replace(INTERMEDIATE_BIND, "")
    migrated = migrated.replace(OLD_PERMISSION + "\n", "")
    migrated = migrated.replace(OLD_PERMISSION, "")

    if "hyprlock" in migrated.lower() or INTERMEDIATE_BIND in migrated:
        fail(
            "unknown Hyprlock reference remains in personalized hyprland.lua; "
            "automatic retirement refused"
        )

    try:
        destination.write_text(migrated, encoding="utf-8")
    except OSError as exc:
        fail(f"could not write {destination}: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
