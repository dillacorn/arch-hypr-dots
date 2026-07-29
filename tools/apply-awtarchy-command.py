from pathlib import Path

root = Path.cwd()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


awtarchy = root / "awtarchy.sh"
text = awtarchy.read_text(encoding="utf-8")

text = replace_once(
    text,
    """Usage:
  awtarchy.sh
  awtarchy.sh dry-run
  awtarchy.sh install [--no-reboot] [--dry-run]
  awtarchy.sh update-reset-backup [--tag <tag>] [--mode preserve|clean] [--review-only]
  awtarchy.sh update-backup-cleaner [options]
  awtarchy.sh clean-backups [options]
  awtarchy.sh help

Top-level no-arg mode opens the built-in terminal menu.
No fzf/gum/dialog/whiptail dependency is used.""",
    """Usage:
  awtarchy
  awtarchy dry-run
  awtarchy install [--no-reboot] [--dry-run]
  awtarchy update [--tag <tag>] [--review-only]
  awtarchy reset [--tag <tag>] [--review-only]
  awtarchy review [--tag <tag>]
  awtarchy clean-backups [options]
  awtarchy version
  awtarchy check-update
  awtarchy self-update [--tag <tag>]

Legacy repository entrypoint:
  awtarchy.sh [command]

Top-level no-arg mode opens the built-in terminal menu.
No fzf/gum/dialog/whiptail dependency is used.""",
    "usage",
)

install_function = r'''install_awtarchy_command_stage() {
  local install_dir="${HOME_DIR}/.local/share/awtarchy"
  local bin_dir="${HOME_DIR}/.local/bin"
  local state_dir="${HOME_DIR}/.local/state/awtarchy"
  local version_file="${state_dir}/version"
  local tag="" revision=""

  [[ -f "${REPO_DIR}/awtarchy.sh" ]] || die "Missing ${REPO_DIR}/awtarchy.sh"
  [[ -f "${REPO_DIR}/local/bin/awtarchy" ]] || die "Missing ${REPO_DIR}/local/bin/awtarchy"

  create_directory "$install_dir"
  create_directory "$bin_dir"
  create_directory "$state_dir"

  retry_command install -m 0755 "${REPO_DIR}/awtarchy.sh" "${install_dir}/awtarchy.sh"
  retry_command install -m 0755 "${REPO_DIR}/local/bin/awtarchy" "${bin_dir}/awtarchy"
  retry_command chown "${TARGET_USER}:${TARGET_USER}" \
    "${install_dir}/awtarchy.sh" "${bin_dir}/awtarchy"

  if have git && git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tag="$(git -C "$REPO_DIR" describe --tags --abbrev=0 HEAD 2>/dev/null || true)"
    revision="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)"
  fi
  [[ -n "$tag" ]] || tag="unreleased"

  {
    printf 'tag=%s\n' "$tag"
    [[ -n "$revision" ]] && printf 'revision=%s\n' "$revision"
    printf 'installed_at=%s\n' "$(date -Iseconds)"
  } >"$version_file"
  chown "${TARGET_USER}:${TARGET_USER}" "$version_file"
  chmod 0644 "$version_file"

  ok "Installed Awtarchy command: ${bin_dir}/awtarchy"
}

'''
text = replace_once(
    text,
    "copy_awtarchy_configs_stage() {",
    install_function + "copy_awtarchy_configs_stage() {",
    "install command function",
)

text = replace_once(
    text,
    "  copy_awtarchy_configs_stage\n  apply_awtarchy_gsettings_defaults",
    "  copy_awtarchy_configs_stage\n  install_awtarchy_command_stage\n  apply_awtarchy_gsettings_defaults",
    "install command stage call",
)

text = replace_once(
    text,
    """  for rel in \\
    .config/hypr/scripts \\
    .config/hypr/themes \\
    .config/waybar/scripts""",
    """  for rel in \\
    .config/hypr/scripts \\
    .config/hypr/themes \\
    .config/waybar/scripts \\
    .local/bin \\
    .local/share/awtarchy""",
    "managed executable paths",
)

text = replace_once(
    text,
    """  copy_target "${repo_dir}/config/gamemode.ini" "${target_home}/.config/gamemode.ini"

  # Every directory under config/ is Awtarchy-managed.""",
    """  copy_target "${repo_dir}/config/gamemode.ini" "${target_home}/.config/gamemode.ini"
  copy_target "${repo_dir}/awtarchy.sh" \\
    "${target_home}/.local/share/awtarchy/awtarchy.sh"
  copy_target "${repo_dir}/local/bin/awtarchy" \\
    "${target_home}/.local/bin/awtarchy"

  # Every directory under config/ is Awtarchy-managed.""",
    "managed command staging",
)

text = replace_once(
    text,
    '  local tag="$1" dest="${HOME_DIR}/.cache/awtarchy/version"',
    '  local tag="$1" dest="${HOME_DIR}/.local/state/awtarchy/version"',
    "version state location",
)

self_update_entry = r'''run_awtarchy_self_update_entry() {
  local target_user="${USER:-$(id -un)}" target_home="${HOME:-}" launcher=""
  if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    target_user="${SUDO_USER}"
    target_home="$(getent passwd "$target_user" | cut -d: -f6 || true)"
  fi
  [[ -n "$target_home" ]] || die "Could not determine target home for Awtarchy self-update."
  launcher="${target_home}/.local/bin/awtarchy"
  [[ -x "$launcher" ]] || die "Installed Awtarchy launcher is missing: ${launcher}"

  if [[ "${EUID}" -eq 0 ]]; then
    runuser -u "$target_user" -- env \
      HOME="$target_home" USER="$target_user" LOGNAME="$target_user" \
      "$launcher" self-update
  else
    "$launcher" self-update
  fi
  press_any_key
}

'''
text = replace_once(
    text,
    "top_menu() {",
    self_update_entry + "top_menu() {",
    "self-update menu function",
)

text = replace_once(
    text,
    '''    choice="$(single_select_menu "Awtarchy" 0 \\
      "Install Awtarchy" \\
      "Dry-run Awtarchy install plan" \\
      "Update configs (preserve personal modifications)" \\
      "Reset configs (clean-slate managed files)" \\
      "Clean Awtarchy backup files" \\
      "Exit")" || exit 0''',
    '''    choice="$(single_select_menu "Awtarchy" 0 \\
      "Install Awtarchy" \\
      "Dry-run Awtarchy install plan" \\
      "Update Awtarchy command" \\
      "Update configs (preserve personal modifications)" \\
      "Reset configs (clean-slate managed files)" \\
      "Clean Awtarchy backup files" \\
      "Exit")" || exit 0''',
    "top menu items",
)

text = replace_once(
    text,
    """      2)
        update_reset_backup_main --mode preserve
        ;;
      3)
        update_reset_backup_main --mode clean
        ;;
      4)
        run_backup_cleaner_entry
        ;;""",
    """      2)
        run_awtarchy_self_update_entry
        ;;
      3)
        update_reset_backup_main --mode preserve
        ;;
      4)
        update_reset_backup_main --mode clean
        ;;
      5)
        run_backup_cleaner_entry
        ;;""",
    "top menu handlers",
)

text = replace_once(
    text,
    '''  "${HOME_DIR}/.config"
  "${HOME_DIR}/.local/share"
  "${HOME_DIR}/Pictures"''',
    '''  "${HOME_DIR}/.config"
  "${HOME_DIR}/.local/bin"
  "${HOME_DIR}/.local/share"
  "${HOME_DIR}/Pictures"''',
    "backup cleaner roots",
)

awtarchy.write_text(text, encoding="utf-8")

readme = root / "README.md"
text = readme.read_text(encoding="utf-8")
text = replace_once(
    text,
    "The script provides a built-in terminal menu without depending on `fzf`, `gum`, `dialog`, or `whiptail`.",
    "The installer adds a permanent `awtarchy` command to `~/.local/bin`. It provides a built-in terminal menu without depending on `fzf`, `gum`, `dialog`, or `whiptail`.",
    "README command description",
)
text = replace_once(
    text,
    "* clean old awtarchy backup files",
    "* update the installed Awtarchy command from GitHub releases\n* clean old awtarchy backup files",
    "README capability list",
)
text = replace_once(
    text,
    "sudo ./awtarchy.sh\n```\n\nDirect install command:",
    "sudo ./awtarchy.sh\n```\n\nThe installer creates `~/.local/bin/awtarchy`. Open a new shell after installation, then use `awtarchy` for future maintenance.\n\nDirect install command:",
    "README install note",
)
text = replace_once(
    text,
    "Running the script without arguments opens the main menu:\n\n```bash\n./awtarchy.sh\n```",
    "Running the installed command without arguments opens the main menu:\n\n```bash\nawtarchy\n```",
    "README menu command",
)
text = replace_once(
    text,
    "Dry-run Awtarchy install plan\nUpdate configs (preserve personal modifications)",
    "Dry-run Awtarchy install plan\nUpdate Awtarchy command\nUpdate configs (preserve personal modifications)",
    "README menu item",
)
text = replace_once(
    text,
    """Run the menu:

```bash
cd ~/awtarchy
chmod +x awtarchy.sh
./awtarchy.sh
```

Preview the preserve-mode update without changing files:

```bash
./awtarchy.sh update-reset-backup --mode preserve --review-only
```

Run preserve mode directly:

```bash
./awtarchy.sh update-reset-backup --mode preserve
```

Run clean-slate mode directly:

```bash
./awtarchy.sh update-reset-backup --mode clean
```

Update from a specific release tag:

```bash
./awtarchy.sh update-reset-backup --mode preserve --tag v1.0.0
```""",
    """Run the menu:

```bash
awtarchy
```

Check the installed and latest release versions:

```bash
awtarchy version
```

Update only the installed Awtarchy command:

```bash
awtarchy self-update
```

Preview the preserve-mode config update without changing files:

```bash
awtarchy review
```

Run preserve mode directly:

```bash
awtarchy update
```

Run clean-slate mode directly:

```bash
awtarchy reset
```

Update configs from a specific release tag:

```bash
awtarchy update --tag v1.0.0
```""",
    "README update commands",
)
text = replace_once(
    text,
    """Interactive cleaner:

```bash
cd ~/awtarchy
chmod +x awtarchy.sh
./awtarchy.sh update-backup-cleaner
```

Shortcut:

```bash
./awtarchy.sh clean-backups
```""",
    """Interactive cleaner:

```bash
awtarchy clean-backups
```""",
    "README cleaner commands",
)
text = text.replace("./awtarchy.sh clean-backups --dry-run", "awtarchy clean-backups --dry-run")
text = text.replace("./awtarchy.sh clean-backups --yes", "awtarchy clean-backups --yes")
text = text.replace("./awtarchy.sh clean-backups --older-than 14", "awtarchy clean-backups --older-than 14")
text = text.replace("./awtarchy.sh clean-backups --archive", "awtarchy clean-backups --archive")

migration = """## Existing installation migration

Existing installations need one final repository-based update to install the command:

```bash
cd ~/awtarchy
git pull --ff-only
sudo ./awtarchy.sh install
```

After that migration, use `awtarchy` instead of entering the repository directory. See [RELEASE_NOTES.md](RELEASE_NOTES.md) for command and version-state details.

"""
text = replace_once(
    text,
    "## 🧹 Clean Backup Files\n",
    migration + "## 🧹 Clean Backup Files\n",
    "README migration section",
)
readme.write_text(text, encoding="utf-8")

(root / ".github/workflows/apply-awtarchy-command.yml").unlink(missing_ok=True)
(root / "tools/apply-awtarchy-command.py").unlink(missing_ok=True)
