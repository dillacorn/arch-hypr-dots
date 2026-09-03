#!/usr/bin/env python3
from pathlib import Path

path = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = path.read_text(encoding="utf-8")
old = '''  write_audit "$source_label" "$active_theme"
  [[ "${EUID}" -eq 0 ]] && chown -R "${TARGET_USER}:${TARGET_USER}" "$STATE_DIR" 2>/dev/null || true
  command -v hyprctl >/dev/null 2>&1 && run_target hyprctl reload >/dev/null 2>&1 || true
  restart_hypridle_after_update
'''
new = '''  write_audit "$source_label" "$active_theme"
  [[ "${EUID}" -eq 0 ]] && chown -R "${TARGET_USER}:${TARGET_USER}" "$STATE_DIR" 2>/dev/null || true

  # A preserved hyprland.lua may have intentionally won a three-way merge
  # conflict. Apply only the one-time, conflict-safe Hyprmoncfg integration;
  # never replace the user's file or take an already-owned shortcut.
  if [[ "$UPDATE_MODE" == "preserve" ]]; then
    hyprmoncfg_migrator="${HOME_DIR}/.config/hypr/scripts/hyprmoncfg_config_migrate.py"
    if [[ -f "$hyprmoncfg_migrator" ]]; then
      if command -v python3 >/dev/null 2>&1; then
        run_target env \\
          "HOME=${HOME_DIR}" \\
          "HYPRLAND_CONFIG=${HOME_DIR}/.config/hypr/hyprland.lua" \\
          python3 "$hyprmoncfg_migrator" \\
          || warn "Hyprmoncfg integration could not be added to the preserved hyprland.lua; local configuration was left intact."
      else
        warn "python3 is unavailable; skipped preserved Hyprmoncfg config migration."
      fi
    fi
  fi

  command -v hyprctl >/dev/null 2>&1 && run_target hyprctl reload >/dev/null 2>&1 || true
  restart_hypridle_after_update
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f"expected one updater tail anchor, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Applied Hyprmoncfg preserved-config updater hook.")
