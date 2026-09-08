#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

if (( $# != 3 )); then
    printf 'usage: %s LIVE_HYPRLAND MANAGED_HYPRLAND BACKUP\n' "${0##*/}" >&2
    exit 2
fi

live="$1"
managed="$2"
backup="$3"

python3 - "$live" "$managed" "$backup" <<'PY'
from pathlib import Path
import os
import shutil
import sys
import tempfile

live = Path(sys.argv[1])
managed = Path(sys.argv[2])
backup = Path(sys.argv[3])

START = 'local screenshot_hide_window = function(class, title)'
END = 'screenshot_hide_window("^(messages|Messages)$")'
INTEGRATION_START = 'local awtarchy_config_home = os.getenv("XDG_CONFIG_HOME")'
SET_FN = 'function awtarchy_screenshare_guard_set_group_v1(target, enabled)'
STATUS_FN = 'function awtarchy_screenshare_guard_status_v1()'
EXPECTED_LEGACY = (
    'Bitwarden',
    'Mullvad Browser',
    'localsend|LocalSend',
    'telegram-desktop',
    'Element|',
    'discord|',
    'teams_for_linux',
    'messages|Messages',
)


def fail(message: str) -> None:
    print(f'screenshare-guard-hyprland-migrate: {message}', file=sys.stderr)
    raise SystemExit(3)


def read(path: Path, label: str) -> str:
    if path.is_symlink() or not path.is_file():
        fail(f'{label} is unavailable or unsafe: {path}')
    try:
        return path.read_text(encoding='utf-8')
    except (OSError, UnicodeError) as exc:
        fail(f'could not read {path}: {exc}')


live_text = read(live, 'live hyprland.lua')
managed_text = read(managed, 'managed hyprland.lua')

has_set = SET_FN in live_text
has_status = STATUS_FN in live_text
if has_set and has_status:
    raise SystemExit(0)
if has_set or has_status:
    fail('partial Screen Share Guard integration found; automatic migration refused')

start = managed_text.find(INTEGRATION_START)
if start < 0:
    fail('managed hyprland.lua is missing the Screen Share Guard integration start')
status = managed_text.find(STATUS_FN, start)
if status < 0:
    fail('managed hyprland.lua is missing the Screen Share Guard status function')
end = managed_text.find('\nend', status)
if end < 0:
    fail('managed hyprland.lua has an incomplete Screen Share Guard status function')
end += len('\nend')
integration = managed_text[start:end]
if SET_FN not in integration or STATUS_FN not in integration:
    fail('managed Screen Share Guard integration is incomplete')

legacy_start_count = live_text.count(START)
legacy_end_count = live_text.count(END)

if legacy_start_count == 0 and legacy_end_count == 0:
    separator = '' if live_text.endswith('\n\n') else ('\n' if live_text.endswith('\n') else '\n\n')
    migrated = live_text + separator + integration + '\n'
elif legacy_start_count == 1 and legacy_end_count == 1:
    old_start = live_text.find(START)
    old_end = live_text.find(END, old_start)
    if old_end < old_start:
        fail('retired Screen Share Guard block markers are out of order')
    old_end += len(END)
    legacy = live_text[old_start:old_end]
    missing = [needle for needle in EXPECTED_LEGACY if needle not in legacy]
    if missing:
        fail(
            'retired Screen Share Guard block was customized; automatic replacement refused; '
            + 'missing known marker(s): '
            + ', '.join(missing)
        )
    migrated = live_text[:old_start] + integration + live_text[old_end:]
else:
    fail('ambiguous retired Screen Share Guard block; automatic replacement refused')

if SET_FN not in migrated or STATUS_FN not in migrated:
    fail('migration did not install required Screen Share Guard runtime functions')
if START in migrated or END in migrated:
    fail('retired Screen Share Guard block remains after migration')

if backup.exists() or backup.is_symlink():
    fail(f'backup path already exists: {backup}')

try:
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(live, backup)
    fd, tmp_name = tempfile.mkstemp(prefix='.awtarchy-screenshare-guard.', dir=live.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            handle.write(migrated)
            handle.flush()
            os.fsync(handle.fileno())
        shutil.copymode(live, tmp_name)
        os.replace(tmp_name, live)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise
except OSError as exc:
    fail(f'could not install migration: {exc}')

print(f'Migrated Screen Share Guard integration in personalized hyprland.lua; backup: {backup}')
PY
