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

# Exact Awtarchy direct window rules retired by PR #170. The combined first
# rule is the fingerprint: if it is present, require the complete known set
# before deleting anything. Layer rules and commented optional examples are
# intentionally not part of this cleanup.
LEGACY_DIRECT_RULES = (
    'hl.window_rule({ match = { class = "^(Bitwarden|com\\\\.bitwarden\\\\.desktop|KeePassXC|org\\\\.keepassxc\\\\.KeePassXC|1Password|com\\\\.1password\\\\.1password|Enpass|org\\\\.gnome\\\\.Secrets|org\\\\.gnome\\\\.seahorse\\\\.Application|OTPClient|otpclient|org\\\\.rasalminen\\\\.OTPClient|Mullvad Browser|mullvad-browser|com\\\\.mullvad\\\\.Browser|localsend|LocalSend|org\\\\.localsend\\\\.localsend|io\\\\.github\\\\.localsend\\\\.localsend)$" }, no_screen_share = true })',
    'hl.window_rule({ match = { class = "^(firefox)$", title = "^(Extension: \\\\(Bitwarden Password Manager\\\\).*)$" }, no_screen_share = true })',
    'hl.window_rule({ match = { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^(Bitwarden Password Manager.*)$" }, no_screen_share = true })',
    'hl.window_rule({ match = { class = "^(org\\\\.telegram\\\\.desktop|TelegramDesktop|telegram-desktop|Telegram)$" }, no_screen_share = true })',
    'hl.window_rule({ match = { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^.*Telegram.*$" }, no_screen_share = true })',
    'hl.window_rule({ match = { class = "^(Element|io\\\\.element\\\\.Element|im\\\\.riot\\\\.Riot|chat\\\\.element\\\\.desktop|SchildiChat|im\\\\.fluffychat\\\\.Fluffychat|Fractal|org\\\\.gnome\\\\.Fractal|nheko)$" }, no_screen_share = true })',
    'hl.window_rule({ match = { class = "^(discord|com\\\\.discordapp\\\\.Discord|vesktop|dev\\\\.vencord\\\\.Vesktop|Fluxer|fluxer)$" }, no_screen_share = true })',
    'hl.window_rule({ match = { class = "^(com\\\\.github\\\\.IsmaelMartinez\\\\.teams_for_linux)$" }, no_screen_share = true })',
    'hl.window_rule({ match = { class = "^(Messages)$" }, no_screen_share = true })',
)
LEGACY_DIRECT_ANCHOR = LEGACY_DIRECT_RULES[0]


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


def extract_integration(managed_text: str) -> str:
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
    return integration


def remove_direct_legacy(text: str) -> tuple[str, bool]:
    lines = text.splitlines(keepends=True)
    stripped = [line.rstrip('\r\n').strip() for line in lines]
    anchor_count = stripped.count(LEGACY_DIRECT_ANCHOR)
    if anchor_count == 0:
        return text, False
    if anchor_count != 1:
        fail('ambiguous retired direct Screen Share Guard anchor count')

    missing = []
    duplicate = []
    for rule in LEGACY_DIRECT_RULES:
        count = stripped.count(rule)
        if count == 0:
            missing.append(rule)
        elif count != 1:
            duplicate.append(rule)
    if missing or duplicate:
        details = []
        if missing:
            details.append(f'missing {len(missing)} known direct rule(s)')
        if duplicate:
            details.append(f'duplicated {len(duplicate)} known direct rule(s)')
        fail('retired direct Screen Share Guard block was customized; automatic cleanup refused; ' + ', '.join(details))

    retired = set(LEGACY_DIRECT_RULES)
    kept = [line for line, normalized in zip(lines, stripped) if normalized not in retired]
    return ''.join(kept), True


live_text = read(live, 'live hyprland.lua')
managed_text = read(managed, 'managed hyprland.lua')
integration = extract_integration(managed_text)

has_set = SET_FN in live_text
has_status = STATUS_FN in live_text
if has_set != has_status:
    fail('partial Screen Share Guard integration found; automatic migration refused')

migrated = live_text
changed = False
has_integration = has_set and has_status

legacy_start_count = migrated.count(START)
legacy_end_count = migrated.count(END)
if legacy_start_count == 0 and legacy_end_count == 0:
    pass
elif legacy_start_count == 1 and legacy_end_count == 1:
    old_start = migrated.find(START)
    old_end = migrated.find(END, old_start)
    if old_end < old_start:
        fail('retired Screen Share Guard block markers are out of order')
    old_end += len(END)
    legacy = migrated[old_start:old_end]
    missing = [needle for needle in EXPECTED_LEGACY if needle not in legacy]
    if missing:
        fail(
            'retired Screen Share Guard block was customized; automatic replacement refused; '
            + 'missing known marker(s): '
            + ', '.join(missing)
        )
    replacement = '' if has_integration else integration
    migrated = migrated[:old_start] + replacement + migrated[old_end:]
    has_integration = True
    changed = True
else:
    fail('ambiguous retired Screen Share Guard block; automatic replacement refused')

migrated, direct_changed = remove_direct_legacy(migrated)
changed = changed or direct_changed

if not has_integration:
    separator = '' if migrated.endswith('\n\n') else ('\n' if migrated.endswith('\n') else '\n\n')
    migrated = migrated + separator + integration + '\n'
    has_integration = True
    changed = True

if SET_FN not in migrated or STATUS_FN not in migrated:
    fail('migration did not install required Screen Share Guard runtime functions')
if START in migrated or END in migrated:
    fail('retired Screen Share Guard helper block remains after migration')
if LEGACY_DIRECT_ANCHOR in [line.rstrip('\r\n').strip() for line in migrated.splitlines(keepends=True)]:
    fail('retired direct Screen Share Guard rules remain after migration')

if not changed:
    raise SystemExit(0)

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
