#!/usr/bin/env bash
# Emit Awtarchy theme palettes as read-only JSON for the Quickshell theme browser.

set -Eeuo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_DIR="${CONFIG_HOME}/hypr/themes"

python3 - "$THEME_DIR" <<'PY'
from __future__ import annotations

from pathlib import Path
import fnmatch
import json
import os
import re
import sys


theme_dir = Path(sys.argv[1])
if not theme_dir.is_dir():
    raise SystemExit(f"theme catalog: directory unavailable: {theme_dir}")

assignment_re = re.compile(r'^([A-Z0-9_]+)="([^"\n]*)"$')
hex_color_re = re.compile(r'^#[0-9a-fA-F]{6}$')
hex_border_re = re.compile(r'^[0-9a-fA-F]{8}$')

palette_keys = {
    "background": "QS_BACKGROUND",
    "foreground": "QS_FOREGROUND",
    "hover": "QS_HOVER",
    "focus": "QS_FOCUS",
    "active": "QS_ACTIVE",
    "urgent": "QS_URGENT",
    "dark": "QS_DARK",
    "charging": "QS_CHARGING",
    "critical": "QS_CRITICAL",
    "muted": "QS_MUTED",
}


def display_name(name: str) -> str:
    words = re.sub(r"[_-]+", " ", name).strip()
    return words.title() if words else name


def parse_assignments(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8", errors="strict")
    except (OSError, UnicodeError) as error:
        raise SystemExit(f"theme catalog: could not read {path.name}: {error}") from error

    for raw_line in text.splitlines():
        match = assignment_re.fullmatch(raw_line.strip())
        if match:
            values[match.group(1)] = match.group(2)
    return values


def parse_theme(path: Path) -> dict[str, object]:
    values = parse_assignments(path)
    palette: dict[str, str] = {}

    for output_key, source_key in palette_keys.items():
        value = values.get(source_key, "")
        if not hex_color_re.fullmatch(value):
            raise SystemExit(
                f"theme catalog: {path.name} has invalid or missing {source_key}: {value!r}"
            )
        palette[output_key] = value

    active_border = values.get("NEW_ACTIVE_BORDER", "a0a0a0ff")
    inactive_border = values.get("NEW_INACTIVE_BORDER", "4b4b4bff")
    if not hex_border_re.fullmatch(active_border):
        raise SystemExit(
            f"theme catalog: {path.name} has invalid NEW_ACTIVE_BORDER: {active_border!r}"
        )
    if not hex_border_re.fullmatch(inactive_border):
        raise SystemExit(
            f"theme catalog: {path.name} has invalid NEW_INACTIVE_BORDER: {inactive_border!r}"
        )

    return {
        "name": path.name,
        "display_name": display_name(path.name),
        "palette": palette,
        "borders": {
            "active": active_border,
            "inactive": inactive_border,
        },
        "apps": {
            "micro": values.get("MICRO_COLORSCHEME", "geany"),
            "alacritty": values.get("ALACRITTY_THEME", "wombat.toml"),
            "speedcrunch": values.get("SPEEDCRUNCH_COLORSCHEME", path.name),
        },
    }


paths = [
    path
    for path in theme_dir.iterdir()
    if path.is_file() and not fnmatch.fnmatch(path.name, "*.backup*")
]
paths.sort(key=lambda path: os.fsencode(path.name))

catalog = [parse_theme(path) for path in paths]
json.dump(catalog, sys.stdout, ensure_ascii=False, separators=(",", ":"))
sys.stdout.write("\n")
PY
