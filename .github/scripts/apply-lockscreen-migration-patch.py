#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER = ROOT / "local/share/awtarchy/awtarchy-package-reconcile.sh"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one anchor in {path}: {old!r}; found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


runtime_helpers = r'''runtime_catalog_has_exact_package() {
  local runtime_source="$1" package="$2"
  awk -v package="$package" '
    /^declare -a PKG_GROUPS=\(/ {
      in_groups=1
      next
    }
    in_groups && /^[[:space:]]*\)[[:space:]]*$/ { exit }
    in_groups {
      line=$0
      sub(/^[[:space:]]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      sub(/^[^:]*:/, "", line)
      count=split(line, fields, /[[:space:]]+/)
      for (i=1; i<=count; i++) {
        if (fields[i] == package)
          found=1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$runtime_source"
}

lockscreen_target_retires_hyprlock() {
  local repo_dir="$1"
  local runtime_source="${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh"
  local config_root="${repo_dir}/config"

  [[ -f "${repo_dir}/config/quickshell/awtarchy-lock/shell.qml" \
    && ! -L "${repo_dir}/config/quickshell/awtarchy-lock/shell.qml" ]] || return 1
  [[ -f "${repo_dir}/config/hypr/scripts/awtarchy_lock.sh" \
    && ! -L "${repo_dir}/config/hypr/scripts/awtarchy_lock.sh" ]] || return 1
  [[ ! -e "${repo_dir}/config/hypr/hyprlock.conf" \
    && ! -L "${repo_dir}/config/hypr/hyprlock.conf" ]] || return 1
  [[ -r "$runtime_source" && ! -L "$runtime_source" ]] || return 1
  [[ -d "$config_root" && ! -L "$config_root" ]] || return 1

  runtime_catalog_has_exact_package "$runtime_source" hyprlock && return 1
  if grep -R -I -w -q -- hyprlock "$config_root"; then
    return 1
  fi
  return 0
}

retired_hyprlock_backup_path() {
  local live="$1" stamp candidate suffix=0
  stamp="$(date '+%Y%m%d-%H%M%S')"
  candidate="${live}.backup.${stamp}"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    ((suffix += 1))
    candidate="${live}.backup.${stamp}.${suffix}"
  done
  printf '%s\n' "$candidate"
}

migrate_retired_hyprlock_stage() {
  local repo_dir="$1"
  local reconciler="${repo_dir}/local/share/awtarchy/awtarchy-package-reconcile.sh"
  local runtime_source="${repo_dir}/local/share/awtarchy/awtarchy-runtime.sh"
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
  local live="${HOME_DIR}/.config/hypr/hyprlock.conf" backup=""

  lockscreen_target_retires_hyprlock "$repo_dir" || return 0

  if [[ -n "${TESTING_BRANCH:-}" ]]; then
    log "Git testing keeps Hyprlock installed as an emergency lock fallback."
    return 0
  fi

  [[ -f "$reconciler" && ! -L "$reconciler" ]] \
    || die "Lockscreen package migration helper is unavailable or unsafe: ${reconciler}"
  [[ -r "$runtime_source" && ! -L "$runtime_source" ]] \
    || die "Lockscreen package migration runtime is unavailable or unsafe: ${runtime_source}"

  if [[ -e "$live" || -L "$live" ]]; then
    backup="$(retired_hyprlock_backup_path "$live")"
    retry_command run_as_target mv -- "$live" "$backup" \
      || die "Could not preserve retired Hyprlock config: ${live}"
    log "Preserved retired Hyprlock config: ${backup}"
  fi

  AWTARCHY_RUNTIME="$runtime_source" \
    AWTARCHY_MANAGED_PACKAGES_FILE="$managed_file" \
    AWTARCHY_LOCKSCREEN_RETIRE_CONFIRMED=1 \
    bash "$reconciler" --migrate-lockscreen-retirement \
      || die "Could not complete the ownership-safe Hyprlock package migration."
}

'''

runtime_marker = "# ──────────────────────────────────────────────────────────────────────────────\n# Built-in raw-key terminal UI\n# ──────────────────────────────────────────────────────────────────────────────"
replace_once(RUNTIME, runtime_marker, runtime_helpers + runtime_marker)

replace_once(
    RUNTIME,
    '  install_awtarchy_command_stage\n  remove_legacy_shell_packages_stage\n\n  ok "Setup complete. Rebooting now."',
    '  install_awtarchy_command_stage\n  remove_legacy_shell_packages_stage\n  migrate_retired_hyprlock_stage "$REPO_DIR"\n\n  ok "Setup complete. Rebooting now."',
)

replace_once(
    RUNTIME,
    '  persist_quickshell_hyprland_user_patch\n  remove_quickshell_update_legacy_packages\n\n  if (( polkit_remove_legacy_ready == 1 )); then',
    '  persist_quickshell_hyprland_user_patch\n  remove_quickshell_update_legacy_packages\n  migrate_retired_hyprlock_stage "$repo_dir"\n\n  if (( polkit_remove_legacy_ready == 1 )); then',
)

replace_once(
    RECONCILER,
    'REVIEW_ONLY=0\nMIGRATE_REPLACEMENTS_ONLY=0\nNEEDS_ACTION_ONLY=0',
    'REVIEW_ONLY=0\nMIGRATE_REPLACEMENTS_ONLY=0\nMIGRATE_LOCKSCREEN_RETIREMENT_ONLY=0\nNEEDS_ACTION_ONLY=0',
)

replace_once(
    RECONCILER,
    '    --migrate-replacements)\n      MIGRATE_REPLACEMENTS_ONLY=1\n      ;;\n    --needs-action)',
    '    --migrate-replacements)\n      MIGRATE_REPLACEMENTS_ONLY=1\n      ;;\n    --migrate-lockscreen-retirement)\n      MIGRATE_LOCKSCREEN_RETIREMENT_ONLY=1\n      ;;\n    --needs-action)',
)

reconciler_helper = r'''migrate_lockscreen_retirement() {
  [[ "${AWTARCHY_LOCKSCREEN_RETIRE_CONFIRMED:-0}" == 1 ]] \
    || die "Lockscreen retirement requires an explicitly confirmed target."

  if array_contains hyprlock "${ARCH_CATALOG[@]}"; then
    die "Target runtime still requires Hyprlock; refusing package retirement."
  fi

  package_installed hyprlock || return 0
  if ! managed_package hyprlock; then
    log "Hyprlock is installed but is not recorded as Awtarchy-owned; leaving it installed."
    return 0
  fi

  log "Removing retired Awtarchy-owned Hyprlock package..."
  if ! as_root pacman -Rns --noconfirm hyprlock; then
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
}

'''

replace_once(RECONCILER, "flatpak_scope() {", reconciler_helper + "flatpak_scope() {")

replace_once(
    RECONCILER,
    'if (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then\n  apply_cheese_snapshot_replacement\n  exit 0\nfi\n\nif (( REVIEW_ONLY == 1 )); then',
    'if (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then\n  apply_cheese_snapshot_replacement\n  exit 0\nfi\n\nif (( MIGRATE_LOCKSCREEN_RETIREMENT_ONLY == 1 )); then\n  migrate_lockscreen_retirement\n  exit 0\nfi\n\nif (( REVIEW_ONLY == 1 )); then',
)
