#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def write(rel: str, text: str) -> None:
    (ROOT / rel).write_text(text, encoding="utf-8")


def replace_exact(rel: str, old: str, new: str) -> None:
    text = read(rel)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{rel}: expected exactly one match, found {count}: {old!r}")
    write(rel, text.replace(old, new, 1))


def reject(rel: str, needle: str) -> None:
    if needle in read(rel):
        raise SystemExit(f"{rel}: unexpected remaining text: {needle!r}")


# Hyprland production entrypoint and obsolete Hyprlock screencopy permission.
replace_exact(
    "config/hypr/hyprland.lua",
    'hl.permission("/usr/bin/hyprlock", "screencopy", "allow")\n',
    "",
)
hyprland = read("config/hypr/hyprland.lua")
old_lock_bind = 'hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), {})'
new_lock_bind = 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})'
if hyprland.count(old_lock_bind) != 2:
    raise SystemExit(
        "config/hypr/hyprland.lua: expected both default/noalt Hyprlock binds before cutover"
    )
write("config/hypr/hyprland.lua", hyprland.replace(old_lock_bind, new_lock_bind))

# Hypridle uses the same lock authority for idle locks and sleep preparation.
replace_exact(
    "config/hypr/hypridle.conf",
    "    lock_cmd = pidof hyprlock || hyprlock",
    "    lock_cmd = ~/.config/hypr/scripts/awtarchy_lock.sh lock",
)
replace_exact(
    "config/hypr/hypridle.conf",
    "    # Clear the temporary all-bar idle hide after a successful hyprlock unlock.",
    "    # Clear the temporary all-bar idle hide after a successful session unlock.",
)

replace_exact(
    "config/hypr/scripts/hypridle_action.sh",
    'SCRIPTS_DIR="${CONF}/hypr/scripts"\n',
    'SCRIPTS_DIR="${CONF}/hypr/scripts"\nLOCK_MANAGER="${LOCK_MANAGER:-${SCRIPTS_DIR}/awtarchy_lock.sh}"\n',
)
replace_exact(
    "config/hypr/scripts/hypridle_action.sh",
    '        log "sleep transition: inhibitor reset before sleep"\n        exec loginctl lock-session',
    '        log "sleep transition: inhibitor reset before sleep"\n        "$LOCK_MANAGER" lock\n        exec "$LOCK_MANAGER" wait-secure 5',
)
replace_exact(
    "config/hypr/scripts/hypridle_action.sh",
    '    lock)\n        exec loginctl lock-session\n        ;;',
    '    lock)\n        exec "$LOCK_MANAGER" lock\n        ;;',
)

# Power menu delegates lock/power sequencing to the lock manager.
replace_exact(
    "config/quickshell/awtarchy/PowerMenu.qml",
    '        { label: "", text: "Lock (L)", key: "l", command: "hyprlock" },\n'
    '        { label: "", text: "Hibernate (H)", key: "h", command: "hyprlock & sleep 1; systemctl hibernate || loginctl hibernate" },',
    '        { label: "", text: "Lock (L)", key: "l", command: "~/.config/hypr/scripts/awtarchy_lock.sh lock" },\n'
    '        { label: "", text: "Hibernate (H)", key: "h", command: "~/.config/hypr/scripts/awtarchy_lock.sh hibernate" },',
)
replace_exact(
    "config/quickshell/awtarchy/PowerMenu.qml",
    '        { label: "", text: "Suspend (Z)", key: "z", command: "hyprlock & sleep 1; systemctl suspend -i" }',
    '        { label: "", text: "Suspend (Z)", key: "z", command: "~/.config/hypr/scripts/awtarchy_lock.sh suspend" }',
)

# Retire stale UI/process/config assumptions.
replace_exact(
    "config/quickshell/awtarchy/Bar.qml",
    '"tofi", "rofi", "hyprlock", "swaylock"',
    '"tofi", "rofi", "swaylock"',
)

animations_path = ROOT / "config/hypr/scripts/toggle_animations.sh"
animations = animations_path.read_text(encoding="utf-8")
animations = animations.replace('HYPRLOCK_CONF="${HYPRLOCK_CONF:-$HOME/.config/hypr/hyprlock.conf}"\n', "")
animations, count = re.subn(
    r'\nupdate_hyprlock_animations_enabled\(\) \{.*?\n\}\n\nstate="\$\(read_state\)"',
    '\nstate="$(read_state)"',
    animations,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit("toggle_animations.sh: could not remove Hyprlock animation helper")
animations = animations.replace('  hyprlock_enabled="false"\n', "")
animations = animations.replace('  hyprlock_enabled="true"\n', "")
animations = animations.replace('\nupdate_hyprlock_animations_enabled "$hyprlock_enabled" "$HYPRLOCK_CONF" || true\n', "\n")
animations_path.write_text(animations, encoding="utf-8")
reject("config/hypr/scripts/toggle_animations.sh", "hyprlock")

# Installer/runtime target no longer depends on Hyprlock, and Git testing now
# exercises the exact same ownership-safe retirement stage as a future stable target.
replace_exact(
    "local/share/awtarchy/awtarchy-runtime.sh",
    "hyprland hyprpaper hyprlock hypridle hyprpicker",
    "hyprland hyprpaper hypridle hyprpicker",
)
replace_exact(
    "local/share/awtarchy/awtarchy-runtime.sh",
    '  if [[ -n "${TESTING_BRANCH:-}" ]]; then\n'
    '    log "Git testing keeps Hyprlock installed as an emergency lock fallback."\n'
    '    return 0\n'
    '  fi\n\n',
    "",
)

# Lock manager owns secure-before-power sequencing.
replace_exact(
    "config/hypr/scripts/awtarchy_lock.sh",
    'QS_BIN="${QS_BIN:-qs}"\n',
    'QS_BIN="${QS_BIN:-qs}"\nSYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"\nLOGINCTL_BIN="${LOGINCTL_BIN:-loginctl}"\n',
)
replace_exact(
    "config/hypr/scripts/awtarchy_lock.sh",
    '  wait-secure [secs]   Wait until the compositor confirms the lock is secure.\n'
    '  stop-test            Stop only a non-secure development lock instance.\n',
    '  wait-secure [secs]   Wait until the compositor confirms the lock is secure.\n'
    '  hibernate            Lock securely, then hibernate.\n'
    '  suspend              Lock securely, then suspend.\n'
    '  stop-test            Stop only a non-secure development lock instance.\n',
)
manager = read("config/hypr/scripts/awtarchy_lock.sh")
needle = '''stop_test() {\n    local state response\n'''
insert = '''secure_then_power() {\n    local action="$1"\n\n    start_lock || return $?\n    wait_secure 5 || return $?\n\n    case "$action" in\n        hibernate)\n            "$SYSTEMCTL_BIN" hibernate || "$LOGINCTL_BIN" hibernate\n            ;;\n        suspend)\n            "$SYSTEMCTL_BIN" suspend -i\n            ;;\n        *)\n            return 2\n            ;;\n    esac\n}\n\nstop_test() {\n    local state response\n'''
if manager.count(needle) != 1:
    raise SystemExit("awtarchy_lock.sh: could not place secure power helper")
manager = manager.replace(needle, insert, 1)
manager = manager.replace(
    '''    wait-secure)\n        [[ $# -le 2 ]] || { usage >&2; exit 2; }\n        wait_secure "${2:-5}"\n        ;;\n    stop-test)''',
    '''    wait-secure)\n        [[ $# -le 2 ]] || { usage >&2; exit 2; }\n        wait_secure "${2:-5}"\n        ;;\n    hibernate)\n        [[ $# -eq 1 ]] || { usage >&2; exit 2; }\n        secure_then_power hibernate\n        ;;\n    suspend)\n        [[ $# -eq 1 ]] || { usage >&2; exit 2; }\n        secure_then_power suspend\n        ;;\n    stop-test)''',
    1,
)
write("config/hypr/scripts/awtarchy_lock.sh", manager)

# The managed Hyprlock config is retired from the target. The runtime migration
# preserves a live remaining copy before ownership-safe package removal.
hyprlock_conf = ROOT / "config/hypr/hyprlock.conf"
if not hyprlock_conf.is_file():
    raise SystemExit("expected managed hyprlock.conf before cutover")
hyprlock_conf.unlink()

# Foundation test no longer asserts the intentionally removed fallback.
foundation_path = ROOT / "tests/test-quickshell-lockscreen-foundation.sh"
foundation = foundation_path.read_text(encoding="utf-8")
foundation, count = re.subn(
    r'\n# Foundation safety boundary: no production entrypoint switches away from Hyprlock\n.*?\n    \'foundation slice unexpectedly changed Power Menu Lock\'\n',
    "\n",
    foundation,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit("foundation test: could not retire Hyprlock fallback assertions")
foundation_path.write_text(foundation, encoding="utf-8")

# Migration test now describes the active cutover instead of the dormant foundation.
migration_path = ROOT / "tests/test-quickshell-lockscreen-migration.sh"
migration = migration_path.read_text(encoding="utf-8")
old_block = '''# This branch still uses Hyprlock in production. The migration plumbing must be\n# dormant until the later production switch actually removes these requirements.\n[[ -f "$HYPRLOCK_CONF" ]] || fail "foundation branch unexpectedly retired hyprlock.conf"\nrequire_text "$RUNTIME" 'hyprpaper hyprlock hypridle' \\\n    'foundation branch unexpectedly removed hyprlock from the installer catalog'\nrequire_text "$HYPRIDLE" 'lock_cmd = pidof hyprlock || hyprlock' \\\n    'foundation branch unexpectedly switched Hypridle'\nrequire_text "$HYPRLAND" 'hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), {})' \\\n    'foundation branch unexpectedly switched SUPER + L'\nrequire_text "$POWER_MENU" 'command: "hyprlock"' \\\n    'foundation branch unexpectedly switched Power Menu Lock'\n'''
new_block = '''# This target performs the real Hyprlock -> native Quickshell cutover.\n[[ ! -e "$HYPRLOCK_CONF" && ! -L "$HYPRLOCK_CONF" ]] \\\n    || fail "cutover target still ships hyprlock.conf"\nif grep -Fq 'hyprpaper hyprlock hypridle' "$RUNTIME"; then\n    fail 'cutover target still catalogs hyprlock'\nfi\nrequire_text "$HYPRIDLE" 'lock_cmd = ~/.config/hypr/scripts/awtarchy_lock.sh lock' \\\n    'cutover target did not switch Hypridle'\nrequire_text "$HYPRLAND" 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' \\\n    'cutover target did not switch SUPER + L'\nrequire_text "$POWER_MENU" 'command: "~/.config/hypr/scripts/awtarchy_lock.sh lock"' \\\n    'cutover target did not switch Power Menu Lock'\n'''
if migration.count(old_block) != 1:
    raise SystemExit("migration test: could not replace dormant-target assertions")
migration = migration.replace(old_block, new_block, 1)
migration = migration.replace(
    '''require_text "$RUNTIME" 'Git testing keeps Hyprlock installed as an emergency lock fallback.' \\\n    'Git-testing fallback contract is missing'\n''',
    '''if grep -Fq 'Git testing keeps Hyprlock installed as an emergency lock fallback.' "$RUNTIME"; then\n    fail 'Git testing still suppresses Hyprlock retirement'\nfi\n''',
    1,
)
migration_path.write_text(migration, encoding="utf-8")

# Config target must contain no functional Hyprlock references after cutover.
for rel in [
    "config/hypr/hyprland.lua",
    "config/hypr/hypridle.conf",
    "config/hypr/scripts/toggle_animations.sh",
    "config/quickshell/awtarchy/PowerMenu.qml",
    "config/quickshell/awtarchy/Bar.qml",
]:
    reject(rel, "hyprlock")
