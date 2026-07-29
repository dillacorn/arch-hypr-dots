from pathlib import Path
import shutil

root = Path.cwd()
runtime = root / "local/share/awtarchy/awtarchy-runtime.sh"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


text = runtime.read_text(encoding="utf-8")

text = replace_once(
    text,
    "# awtarchy.sh\n# Single-file Awtarchy installer / updater / backup cleaner.",
    "# awtarchy-runtime.sh\n# Internal Awtarchy install and maintenance runtime.",
    "runtime header",
)

text = replace_once(
    text,
    '  REPO_DIR="${HOME_DIR}/awtarchy"',
    '  REPO_DIR="${AWTARCHY_REPO_DIR:-${HOME_DIR}/awtarchy}"',
    "installer source directory override",
)

install_function = r'''detect_installed_release_tag() {
  local latest="" release_commit="" head_commit=""

  if have curl && have python3; then
    latest="$(
      curl -fsSL --connect-timeout 5 --max-time 10 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: awtarchy-installer' \
        'https://api.github.com/repos/dillacorn/awtarchy/releases/latest' 2>/dev/null \
      | python3 -c '
import json, sys
try:
    value = json.load(sys.stdin).get("tag_name", "")
except Exception:
    value = ""
print(str(value).strip())
' 2>/dev/null
    )" || true
  fi

  if [[ -n "$latest" ]] && have git \
    && git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    release_commit="$(git -C "$REPO_DIR" rev-parse "${latest}^{commit}" 2>/dev/null || true)"
    head_commit="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$release_commit" && -n "$head_commit" ]] \
      && git -C "$REPO_DIR" merge-base --is-ancestor "$release_commit" "$head_commit" 2>/dev/null; then
      printf '%s\n' "$latest"
      return 0
    fi
  fi

  printf '%s\n' unreleased
}

install_awtarchy_command_stage() {
  local install_dir="${HOME_DIR}/.local/share/awtarchy"
  local bin_dir="${HOME_DIR}/.local/bin"
  local state_dir="${HOME_DIR}/.local/state/awtarchy"
  local command_version_file="${state_dir}/command-version"
  local config_version_file="${state_dir}/config-version"
  local runtime_src="${REPO_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
  local launcher_src="${REPO_DIR}/local/bin/awtarchy"
  local tag="" revision=""

  [[ -f "$runtime_src" ]] || die "Missing Awtarchy runtime: ${runtime_src}"
  [[ -f "$launcher_src" ]] || die "Missing Awtarchy command: ${launcher_src}"
  bash -n "$runtime_src" || die "Awtarchy runtime failed Bash syntax validation."
  bash -n "$launcher_src" || die "Awtarchy command failed Bash syntax validation."

  create_directory "$install_dir"
  create_directory "$bin_dir"
  create_directory "$state_dir"

  retry_command install -m 0755 "$runtime_src" "${install_dir}/awtarchy-runtime.sh"
  retry_command install -m 0755 "$launcher_src" "${bin_dir}/awtarchy"
  retry_command chown "${TARGET_USER}:${TARGET_USER}" \
    "${install_dir}/awtarchy-runtime.sh" "${bin_dir}/awtarchy"

  tag="$(detect_installed_release_tag)"
  if have git && git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    revision="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)"
  fi

  {
    printf 'tag=%s\n' "$tag"
    [[ -n "$revision" ]] && printf 'revision=%s\n' "$revision"
    printf 'installed_at=%s\n' "$(date -Iseconds)"
  } >"$command_version_file"
  cp -- "$command_version_file" "$config_version_file"
  chown "${TARGET_USER}:${TARGET_USER}" "$command_version_file" "$config_version_file"
  chmod 0644 "$command_version_file" "$config_version_file"

  ok "Installed Awtarchy command: ${bin_dir}/awtarchy"
}

'''

text = replace_once(
    text,
    "copy_awtarchy_configs_stage() {",
    install_function + "copy_awtarchy_configs_stage() {",
    "command installation stage",
)

text = replace_once(
    text,
    "  copy_awtarchy_configs_stage\n  apply_awtarchy_gsettings_defaults",
    "  copy_awtarchy_configs_stage\n  install_awtarchy_command_stage\n  apply_awtarchy_gsettings_defaults",
    "command installation stage call",
)

text = replace_once(
    text,
    '  local tag="$1" dest="${HOME_DIR}/.cache/awtarchy/version"',
    '  local tag="$1" dest="${HOME_DIR}/.local/state/awtarchy/config-version"',
    "persistent config version state",
)

text = replace_once(
    text,
    """Usage:
  update-backup-cleaner.sh [options]

IMPORTANT:
  - Do NOT run with sudo. This scans under your $HOME. Running with sudo usually makes $HOME=/root.

Default (interactive TTY):
  - Scans common awtarchy-managed paths under $HOME for:
      *.backup
      *.backup.YYYYMMDD-HHMMSS
  - Shows a paged list (default 20 items/page)
  - Press a number to toggle KEEP immediately (no Enter)
  - Press [D] to delete everything NOT marked KEEP

Options:
  --dry-run              Print full list and exit (no menu, no deletes)
  --yes                  Delete ALL matches without prompts (ignores KEEP UI)
  --older-than <days>    Only match files with mtime strictly greater than <days> (integer)
  --archive <tar.gz>     Create a tar.gz archive (relative to $HOME if not absolute)
  --help                 Show help

Paging config:
  - Default page size: 20
  - Change via:
      AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_DEFAULT=40 ./update-backup-cleaner.sh
    or press [G] in the menu (saved in ~/.config/awtarchy/backup_clean_page_size)

Examples:
  cd ~/awtarchy
  chmod +x ./update-backup-cleaner.sh
  ./update-backup-cleaner.sh

  ./update-backup-cleaner.sh --dry-run""",
    """Usage:
  awtarchy clean-backups [options]

IMPORTANT:
  - Do NOT run with sudo. This scans backups under your home directory.

Default (interactive TTY):
  - Scans common awtarchy-managed paths under $HOME for:
      *.backup
      *.backup.YYYYMMDD-HHMMSS
  - Shows a paged list (default 20 items/page)
  - Press a number to toggle KEEP immediately (no Enter)
  - Press [D] to delete everything NOT marked KEEP

Options:
  --dry-run              Print full list and exit (no menu, no deletes)
  --yes                  Delete ALL matches without prompts (ignores KEEP UI)
  --older-than <days>    Only match files with mtime strictly greater than <days> (integer)
  --archive <tar.gz>     Create a tar.gz archive (relative to $HOME if not absolute)
  --help                 Show help

Paging config:
  - Default page size: 20
  - Change via:
      AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_DEFAULT=40 awtarchy clean-backups
    or press [G] in the menu (saved in ~/.config/awtarchy/backup_clean_page_size)

Examples:
  awtarchy clean-backups
  awtarchy clean-backups --dry-run""",
    "backup cleaner help",
)

text = replace_once(
    text,
    """  die "Do not run this with sudo. Run as your normal user.
Example:
  cd ~/awtarchy
  chmod +x ./update-backup-cleaner.sh
  ./update-backup-cleaner.sh""",
    """  die "Do not run this with sudo. Run as your normal user.
Example:
  awtarchy clean-backups""",
    "backup cleaner root message",
)

runtime.write_text(text, encoding="utf-8")

apply_workflow = root / ".github/workflows/apply-awtarchy-command.yml"
apply_workflow.unlink(missing_ok=True)
(root / "tools/apply-awtarchy-command.py").unlink(missing_ok=True)
shutil.rmtree(root / "tools/__pycache__", ignore_errors=True)
