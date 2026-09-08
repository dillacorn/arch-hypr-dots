#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CURSOR = ROOT / "config/hypr/scripts/quickshell_cursor_theme.sh"
HYPR = ROOT / "config/hypr/hyprland.lua"
TEST = ROOT / "tests/test-bibata-cursor-migration.sh"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one marker, found {count}")
    path.write_text(text.replace(old, new, 1))


# Persist the compositor-facing hyprcursor variant alongside the XCursor
# fallback. The same directory intentionally contains both cursor formats.
replace_once(
    HYPR,
    'hl.env("XCURSOR_SIZE", "24")\nhl.env("GTK_THEME", "Materia-dark")\nhl.env("XCURSOR_THEME", "Bibata-Modern-Ice")\n',
    'hl.env("XCURSOR_SIZE", "24")\nhl.env("HYPRCURSOR_SIZE", "24")\nhl.env("GTK_THEME", "Materia-dark")\nhl.env("XCURSOR_THEME", "Bibata-Modern-Ice")\nhl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")\n',
    "stock Hyprland cursor environment",
)

write_old = '''def replace_required(path: Path, pattern: str, replacement: str, label: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one managed cursor setting in {path}")
    path.write_text(updated)


replace_required(
    hypr,
    r'^hl\\.env\\("XCURSOR_THEME",\\s*"[^"]+"\\)$',
    f'hl.env("XCURSOR_THEME", "{theme}")',
    "Hyprland",
)
'''
write_new = '''def replace_required(path: Path, pattern: str, replacement: str, label: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one managed cursor setting in {path}")
    path.write_text(updated)


def upsert_hypr_env(key: str, value: str, after_key: str) -> None:
    text = hypr.read_text()
    pattern = rf'^hl\\.env\\("{re.escape(key)}",\\s*"[^"]+"\\)$'
    replacement = f'hl.env("{key}", "{value}")'
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count == 1:
        hypr.write_text(updated)
        return
    if count != 0:
        raise SystemExit(f"Hyprland: multiple {key} cursor settings in {hypr}")

    anchor = rf'^(hl\\.env\\("{re.escape(after_key)}",\\s*"[^"]+"\\))$'
    updated, anchor_count = re.subn(
        anchor,
        rf'\\1\\n{replacement}',
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if anchor_count != 1:
        raise SystemExit(f"Hyprland: expected one {after_key} anchor in {hypr}")
    hypr.write_text(updated)


replace_required(
    hypr,
    r'^hl\\.env\\("XCURSOR_THEME",\\s*"[^"]+"\\)$',
    f'hl.env("XCURSOR_THEME", "{theme}")',
    "Hyprland XCursor",
)
upsert_hypr_env("HYPRCURSOR_THEME", theme, "XCURSOR_THEME")
upsert_hypr_env("HYPRCURSOR_SIZE", "24", "XCURSOR_SIZE")
'''
replace_once(CURSOR, write_old, write_new, "cursor Hyprland env writer")

replace_once(
    CURSOR,
    'systemctl --user set-environment "XCURSOR_THEME=${theme}" "XCURSOR_SIZE=${CURSOR_SIZE}" >/dev/null 2>&1 || true',
    'systemctl --user set-environment "XCURSOR_THEME=${theme}" "XCURSOR_SIZE=${CURSOR_SIZE}" "HYPRCURSOR_THEME=${theme}" "HYPRCURSOR_SIZE=${CURSOR_SIZE}" >/dev/null 2>&1 || true',
    "systemd cursor environment",
)

replace_once(
    CURSOR,
    '''        XCURSOR_THEME="$theme" XCURSOR_SIZE="$CURSOR_SIZE" \\
            dbus-update-activation-environment --systemd XCURSOR_THEME XCURSOR_SIZE >/dev/null 2>&1 || true
''',
    '''        XCURSOR_THEME="$theme" XCURSOR_SIZE="$CURSOR_SIZE" \\
            HYPRCURSOR_THEME="$theme" HYPRCURSOR_SIZE="$CURSOR_SIZE" \\
            dbus-update-activation-environment --systemd XCURSOR_THEME XCURSOR_SIZE HYPRCURSOR_THEME HYPRCURSOR_SIZE >/dev/null 2>&1 || true
''',
    "D-Bus cursor environment",
)

# Make the persistent compositor selection part of the focused contract.
replace_once(
    TEST,
    '''contains "$HYPR" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \\
  'Hyprland does not default to Bibata Modern Ice'
''',
    '''contains "$HYPR" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \\
  'Hyprland does not default to Bibata Modern Ice for XCursor'
contains "$HYPR" 'hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")' \\
  'Hyprland does not default to Bibata Modern Ice for hyprcursor'
contains "$HYPR" 'hl.env("HYPRCURSOR_SIZE", "24")' \\
  'Hyprland does not persist the hyprcursor size'
''',
    "stock hyprcursor assertions",
)

replace_once(
    TEST,
    '''printf '%s\\n' 'hl.env("XCURSOR_SIZE", "24")' 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \\
  >"$config_home/hypr/hyprland.lua"
''',
    '''printf '%s\\n' \\
  'hl.env("XCURSOR_SIZE", "24")' \\
  'hl.env("HYPRCURSOR_SIZE", "24")' \\
  'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \\
  'hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")' \\
  >"$config_home/hypr/hyprland.lua"
''',
    "initial cursor fixture",
)

replace_once(
    TEST,
    '''contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")' \\
  'Classic cursor was not persisted into Hyprland config'
''',
    '''contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")' \\
  'Classic XCursor was not persisted into Hyprland config'
contains "$config_home/hypr/hyprland.lua" 'hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")' \\
  'Classic hyprcursor was not persisted into Hyprland config'
contains "$config_home/hypr/hyprland.lua" 'hl.env("HYPRCURSOR_SIZE", "24")' \\
  'hyprcursor size was not persisted into Hyprland config'
''',
    "Classic persistent cursor assertions",
)

replace_once(
    TEST,
    '''printf '%s\\n' 'hl.env("XCURSOR_SIZE", "24")' 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \\
  >"$config_home/hypr/hyprland.lua"
''',
    '''printf '%s\\n' \\
  'hl.env("XCURSOR_SIZE", "24")' \\
  'hl.env("HYPRCURSOR_SIZE", "24")' \\
  'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \\
  'hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")' \\
  >"$config_home/hypr/hyprland.lua"
''',
    "reset cursor fixture",
)

replace_once(
    TEST,
    '''contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")' \\
  'persisted Classic cursor was not reapplied after a stock config reset'
''',
    '''contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")' \\
  'persisted Classic XCursor was not reapplied after a stock config reset'
contains "$config_home/hypr/hyprland.lua" 'hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")' \\
  'persisted Classic hyprcursor was not reapplied after a stock config reset'
''',
    "Classic reapply assertions",
)

replace_once(
    TEST,
    '''contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \\
  'Ice cursor was not reapplied to Hyprland config'
''',
    '''contains "$config_home/hypr/hyprland.lua" 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' \\
  'Ice XCursor was not reapplied to Hyprland config'
contains "$config_home/hypr/hyprland.lua" 'hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")' \\
  'Ice hyprcursor was not reapplied to Hyprland config'
''',
    "Ice reapply assertions",
)

# The cursor helper changed again, so append its exact current managed hash.
history_text = HISTORY.read_text()
digest = hashlib.sha256(CURSOR.read_bytes()).hexdigest()
line = f"{digest}\t.config/hypr/scripts/quickshell_cursor_theme.sh"
if line not in history_text.splitlines():
    if not history_text.endswith("\n"):
        history_text += "\n"
    history_text += "# 2026-09-08 Bibata hyprcursor login persistence follow-up.\n"
    history_text += line + "\n"
    HISTORY.write_text(history_text)

print("Applied Bibata hyprcursor environment persistence follow-up.")
