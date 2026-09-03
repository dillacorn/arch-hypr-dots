#!/usr/bin/env python3
"""Safely add Hyprmoncfg integration to a preserved Awtarchy hyprland.lua.

This is a one-time compatibility migration for users whose local hyprland.lua
wins a three-way update conflict. It never replaces the file and refuses to
claim SUPER+CTRL+M when that shortcut is already user-owned.
"""

from __future__ import annotations

import os
from pathlib import Path
import stat
import sys
import tempfile

HOME = Path(os.environ.get("HOME", "~")).expanduser()
CONFIG = Path(
    os.environ.get("HYPRLAND_CONFIG", str(HOME / ".config/hypr/hyprland.lua"))
).expanduser()
STATE_ROOT = Path(
    os.environ.get("XDG_STATE_HOME", str(HOME / ".local/state"))
).expanduser()
MARKER = STATE_ROOT / "awtarchy/migrations/hyprmoncfg-config-v1"

KEY = "SUPER + CTRL + M"
MACCEL_ENTRY = '{ "SUPER + SHIFT + M", maccel },'
HYPRMONCFG_ENTRY = '{ "SUPER + CTRL + M", hyprmoncfg },'
LAUNCHER = (
    'local hyprmoncfg = "APP_NO_LAUNCH_IF_TILED=1 '
    '~/.config/hypr/scripts/launch_handler.sh hyprmoncfg '
    '\\"~/.config/hypr/scripts/default_terminal.sh --class hyprmoncfg -- hyprmoncfg\\""'
)
RULES = (
    'hl.window_rule({ match = { class = "^(hyprmoncfg)$" }, float = true })',
    'hl.window_rule({ match = { class = "^(hyprmoncfg)$" }, '
    'size = { "(monitor_w*0.85)", "(monitor_h*0.90)" } })',
    'hl.window_rule({ match = { class = "^(hyprmoncfg)$" }, center = true })',
)


def warn(message: str) -> None:
    print(f"WARN: {message}", file=sys.stderr)


def mark_done() -> None:
    MARKER.parent.mkdir(parents=True, exist_ok=True)
    MARKER.write_text("done\n", encoding="utf-8")


def write_atomic(path: Path, text: str) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.awtarchy-",
        delete=False,
    ) as tmp:
        tmp.write(text)
        tmp_path = Path(tmp.name)
    os.chmod(tmp_path, mode)
    os.replace(tmp_path, path)


def main() -> int:
    if MARKER.exists():
        return 0
    if not CONFIG.is_file() or CONFIG.is_symlink():
        return 0

    original = CONFIG.read_text(encoding="utf-8")
    lines = original.splitlines()

    shortcut_lines = [line for line in lines if KEY in line]
    if shortcut_lines and any("hyprmoncfg" not in line for line in shortcut_lines):
        warn("hyprland.lua already uses SUPER+CTRL+M; preserving the user-owned binding.")
        mark_done()
        return 0

    changed = False

    if LAUNCHER not in original:
        maccel_indices = [i for i, line in enumerate(lines) if line.startswith("local maccel = ")]
        if len(maccel_indices) != 1:
            warn("could not locate the unique maccel launcher anchor; Hyprmoncfg config migration was skipped.")
            return 1
        lines.insert(maccel_indices[0] + 1, LAUNCHER)
        changed = True

    current = "\n".join(lines)
    shortcut_lines = [line for line in lines if KEY in line]
    if not shortcut_lines:
        anchors = [i for i, line in enumerate(lines) if MACCEL_ENTRY in line]
        if len(anchors) != 2:
            warn("could not locate both normal/noalt maccel bind anchors; Hyprmoncfg shortcut migration was skipped.")
            return 1
        offset = 0
        for index in anchors:
            indent = lines[index + offset][: len(lines[index + offset]) - len(lines[index + offset].lstrip())]
            lines.insert(index + offset + 1, f"{indent}{HYPRMONCFG_ENTRY}")
            offset += 1
        changed = True

    current = "\n".join(lines)
    missing_rules = [rule for rule in RULES if rule not in current]
    if missing_rules:
        lines.extend(
            [
                "",
                "-- Awtarchy Hyprmoncfg integration retained across preserved-config updates.",
                *missing_rules,
            ]
        )
        changed = True

    if changed:
        newline = "\n" if original.endswith("\n") else ""
        write_atomic(CONFIG, "\n".join(lines) + newline)
        print("Applied preserved Hyprland Hyprmoncfg integration.")

    mark_done()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
