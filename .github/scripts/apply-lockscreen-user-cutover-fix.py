#!/usr/bin/env python3
from pathlib import Path


def replace_exact(path: str, old: str, new: str, expected: int = 1) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} exact match(es), found {count}")
    p.write_text(text.replace(old, new), encoding="utf-8")


# SUPER+L belongs to Awtarchy's normal movement bindings. Manual locking stays
# in the existing SUPER+P power menu, then L.
bind = 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})\n'
replace_exact("config/hypr/hyprland.lua", bind, "", expected=2)

# Personalized configs from either the old Hyprlock state or the first partial
# cutover are normalized by removing the dedicated SUPER+L lock bind while
# preserving unrelated user configuration.
migrator = Path("local/share/awtarchy/awtarchy-lockscreen-hyprland-migrate.py")
migrator_lines = [
    "#!/usr/bin/env python3",
    "from pathlib import Path",
    "import sys",
    "",
    "OLD_PERMISSION = 'hl.permission({ match = { path = \"/usr/bin/hyprlock\" }, screencopy = true })'",
    "OLD_BIND = 'hl.bind(\"SUPER + L\", hl.dsp.exec_cmd(\"hyprlock\"), {})'",
    "INTERMEDIATE_BIND = 'hl.bind(\"SUPER + L\", hl.dsp.exec_cmd(\"~/.config/hypr/scripts/awtarchy_lock.sh lock\"), {})'",
    "",
    "",
    "def fail() -> None:",
    "    raise SystemExit(3)",
    "",
    "",
    "if len(sys.argv) != 3:",
    "    raise SystemExit(2)",
    "",
    "source = Path(sys.argv[1])",
    "destination = Path(sys.argv[2])",
    "text = source.read_text(encoding=\"utf-8\")",
    "",
    "if \"hyprlock\" not in text.lower() and INTERMEDIATE_BIND not in text:",
    "    destination.write_text(text, encoding=\"utf-8\")",
    "    raise SystemExit(0)",
    "",
    "old_bind_count = text.count(OLD_BIND)",
    "intermediate_bind_count = text.count(INTERMEDIATE_BIND)",
    "old_permission_count = text.count(OLD_PERMISSION)",
    "lower_count = text.lower().count(\"hyprlock\")",
    "known_bind_count = old_bind_count + intermediate_bind_count",
    "",
    "if (",
    "    known_bind_count not in {1, 2}",
    "    or old_permission_count not in {0, 1}",
    "    or lower_count != old_bind_count + old_permission_count",
    "):",
    "    fail()",
    "",
    "text = text.replace(OLD_BIND + \"\\n\", \"\")",
    "text = text.replace(INTERMEDIATE_BIND + \"\\n\", \"\")",
    "if old_permission_count:",
    "    text = text.replace(OLD_PERMISSION + \"\\n\", \"\", 1)",
    "",
    "if \"hyprlock\" in text.lower() or INTERMEDIATE_BIND in text:",
    "    fail()",
    "",
    "destination.write_text(text, encoding=\"utf-8\")",
]
migrator.write_text("\n".join(migrator_lines) + "\n", encoding="utf-8")

# The runtime must invoke the helper for a machine which already ran the first
# partial migration and contains the temporary Awtarchy SUPER+L lock bind but
# no literal "hyprlock" string.
old_runtime = '  grep -Fqi -- hyprlock "$live" || return 0\n'
new_runtime = '''  if ! grep -Fqi -- hyprlock "$live" \\
    && ! grep -Fq -- 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' "$live"; then
    return 0
  fi
'''
replace_exact("local/share/awtarchy/awtarchy-runtime.sh", old_runtime, new_runtime)

# Keep automatic package retirement ownership-safe. An installation absent
# from Awtarchy's ledger is removable only after explicit one-time confirmation.
old_pkg = '''  package_installed hyprlock || return 0
  if ! managed_package hyprlock; then
    log "Hyprlock is installed but is not recorded as Awtarchy-owned; leaving it installed."
    return 0
  fi

  log "Removing retired Awtarchy-owned Hyprlock package..."
  if ! as_root pacman -R --noconfirm hyprlock; then
    warn "Could not remove retired Awtarchy-owned Hyprlock; leaving package ownership recorded for a later retry."
    return 0
  fi
  if package_installed hyprlock; then
    warn "Hyprlock is still detected after package removal; leaving package ownership recorded for a later retry."
    return 0
  fi
  if ! forget_managed_packages hyprlock; then
    warn "Hyprlock was removed, but Awtarchy could not update its managed-package ledger."
    return 0
  fi
  log "Removed retired Awtarchy-owned Hyprlock package."
'''
new_pkg = '''  package_installed hyprlock || return 0
  local ownership_recorded=0
  if managed_package hyprlock; then
    ownership_recorded=1
    log "Removing retired Awtarchy-owned Hyprlock package..."
  elif [[ "${AWTARCHY_LOCKSCREEN_RETIRE_UNOWNED_CONFIRMED:-0}" == 1 ]]; then
    log "Removing retired Hyprlock package after explicit confirmation..."
  elif [[ -r /dev/tty && -w /dev/tty ]] \\
    && confirm_yes_no 'Hyprlock is no longer used by Awtarchy but was not recorded as Awtarchy-owned. Remove it now?' 0; then
    log "Removing retired Hyprlock package after explicit confirmation..."
  else
    log "Hyprlock is installed but is not recorded as Awtarchy-owned; leaving it installed."
    return 0
  fi

  if ! as_root pacman -R --noconfirm hyprlock; then
    warn "Could not remove retired Hyprlock; leaving it installed for a later retry."
    return 0
  fi
  if package_installed hyprlock; then
    warn "Hyprlock is still detected after package removal."
    return 0
  fi
  if (( ownership_recorded == 1 )); then
    if ! forget_managed_packages hyprlock; then
      warn "Hyprlock was removed, but Awtarchy could not update its managed-package ledger."
      return 0
    fi
    log "Removed retired Awtarchy-owned Hyprlock package."
  else
    log "Removed retired Hyprlock package after explicit confirmation."
  fi
'''
replace_exact("local/share/awtarchy/awtarchy-package-reconcile.sh", old_pkg, new_pkg)

# Existing contracts now encode the intended manual power-menu path.
old_cutover = '''require_text "$HYPRLAND" 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' \\
    'SUPER + L does not use the native Awtarchy locker'
'''
new_cutover = '''reject_text "$HYPRLAND" 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' \\
    'native locker steals SUPER + L from normal movement bindings'
require_text "$HYPRLAND" 'hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})' \\
    'SUPER + P no longer opens the power menu'
'''
replace_exact("tests/test-quickshell-lockscreen-cutover.sh", old_cutover, new_cutover)

old_migration = '''require_text "$HYPRLAND" 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' \\
    'cutover target did not switch SUPER + L'
'''
new_migration = '''if grep -Fq 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' "$HYPRLAND"; then
    fail 'cutover target still steals SUPER + L instead of using the power menu'
fi
require_text "$HYPRLAND" 'hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})' \\
    'cutover target lost the SUPER + P power-menu bind'
'''
replace_exact("tests/test-quickshell-lockscreen-migration.sh", old_migration, new_migration)

live_test = Path("tests/test-quickshell-lockscreen-live-hyprland-migration.sh")
text = live_test.read_text(encoding="utf-8")
old_expect = '''[[ "$(grep -Fc 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' "$out")" == 2 ]] \\
    || fail 'both default/noalt lock bindings were not migrated'
'''
new_expect = '''if grep -Fq 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' "$out"; then
    fail 'direct SUPER + L lock binding remained after migration'
fi
'''
if text.count(old_expect) != 1:
    raise SystemExit("live migration test: expected old bind assertion once")
text = text.replace(old_expect, new_expect)
marker = '''grep -Fq 'hl.bind("SUPER + F11", hl.dsp.exec_cmd("notify-send custom"), {})' "$out" \\
    || fail 'unrelated personal bind was lost'
'''
addition = marker + '''
# A machine that already ran the first cutover may contain the temporary native
# SUPER+L lock bindings but no literal Hyprlock reference. Those known Awtarchy
# lines are also removed without touching unrelated personal configuration.
intermediate="${TMP}/hyprland-intermediate.lua"
intermediate_out="${TMP}/hyprland-intermediate.new.lua"
cat >"$intermediate" <<'EOF'
hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})
hl.bind("SUPER + F11", hl.dsp.exec_cmd("notify-send custom"), {})
hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})
EOF
python3 "$HELPER" "$intermediate" "$intermediate_out" \\
    || fail 'intermediate Awtarchy SUPER+L lock bindings could not be retired'
if grep -Fq 'awtarchy_lock.sh lock' "$intermediate_out"; then
    fail 'intermediate direct SUPER+L lock binding remained after migration'
fi
grep -Fq 'notify-send custom' "$intermediate_out" \\
    || fail 'intermediate migration lost unrelated personal configuration'
'''
if text.count(marker) != 1:
    raise SystemExit("live migration test: insertion marker not unique")
live_test.write_text(text.replace(marker, addition), encoding="utf-8")
