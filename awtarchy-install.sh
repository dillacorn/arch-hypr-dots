#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# awtarchy-install.sh
# Install-only entrypoint for applying the Awtarchy overlay.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_TEMPLATE="${SCRIPT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
RUNTIME_SOURCE="$RUNTIME_TEMPLATE"
LAUNCHER_SOURCE="${SCRIPT_DIR}/local/bin/awtarchy"
QUICKSHELL_LAUNCHER_SOURCE="${SCRIPT_DIR}/local/bin/awtarchy-quickshell"
SYSTEM_BIN_DIR="${AWTARCHY_SYSTEM_BIN_DIR:-/usr/local/bin}"
TARGET_USER=""
TARGET_HOME=""
REINSTALL=0
QUICKSHELL_COMMAND_ONLY=0
DRY_RUN_REQUESTED=0
ARGS=()
RUNTIME_TEMP=""

usage() {
  cat <<'EOF_USAGE'
Usage:
  sudo ./awtarchy-install.sh
  sudo ./awtarchy-install.sh --no-reboot
  sudo ./awtarchy-install.sh --quickshell-command
  ./awtarchy-install.sh --dry-run
  sudo ./awtarchy-install.sh --reinstall
  ./awtarchy-install.sh --help

This script only installs Awtarchy. After installation, use the `awtarchy`
command for updates, config resets, review mode, version checks, and backup cleanup.

Existing legacy installations are migrated to the new command without rerunning
package installation or replacing managed configs.

Options:
  --quickshell-command
                 Install only the temporary awtarchy-quickshell testing command
  --reinstall    Run the complete installer even when Awtarchy is already installed
EOF_USAGE
}

cleanup() {
  # Invoked indirectly by the EXIT trap below.
  # shellcheck disable=SC2317
  if [[ -n ${RUNTIME_TEMP:-} ]]; then
    rm -f -- "$RUNTIME_TEMP" 2>/dev/null || true
  fi
}
trap cleanup EXIT

prepare_runtime_source() {
  if [[ "${AWTARCHY_TEST_RUNTIME_PASSTHROUGH:-0}" == "1" ]]; then
    RUNTIME_SOURCE="$RUNTIME_TEMPLATE"
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || {
    printf 'ERROR: python3 is required to prepare the Quickshell conversion runtime.\n' >&2
    exit 1
  }

  RUNTIME_TEMP="$(mktemp "${TMPDIR:-/tmp}/awtarchy-runtime-quickshell.XXXXXX")"

  python3 - "$RUNTIME_TEMPLATE" "$RUNTIME_TEMP" <<'PY'
from pathlib import Path
import re
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
text = src.read_text(encoding="utf-8")

legacy = {"waybar", "waybar-git", "fuzzel", "wlogout", "mako", "wofi"}
legacy_connectivity = {"network-manager-applet", "blueman"}

# Arch package group: Quickshell replaces the old shell UI packages.
match = re.search(r'("Window Management:)([^"]+)(")', text)
if not match:
    raise SystemExit("ERROR: could not locate Window Management package group")
packages = match.group(2).split()
packages = [pkg for pkg in packages if pkg not in legacy]
if "quickshell" not in packages:
    insert_at = packages.index("hyprsunset") + 1 if "hyprsunset" in packages else 0
    packages.insert(insert_at, "quickshell")
text = text[:match.start()] + match.group(1) + " ".join(packages) + match.group(3) + text[match.end():]

# Quickshell battery integration requires the UPower daemon.
utility_match = re.search(r'("Utilities:)([^"]+)(")', text)
if not utility_match:
    raise SystemExit("ERROR: could not locate Utilities package group")
utility_packages = utility_match.group(2).split()
utility_packages = [pkg for pkg in utility_packages if pkg not in legacy_connectivity]
if "upower" not in utility_packages:
    insert_at = utility_packages.index("qt6ct") + 1 if "qt6ct" in utility_packages else 0
    utility_packages.insert(insert_at, "upower")
text = text[:utility_match.start()] + utility_match.group(1) + " ".join(utility_packages) + match.group(3) + text[utility_match.end():]

# AUR defaults: Waybar-git and wlogout are no longer part of Awtarchy.
aur = re.search(r'declare -a PACKAGES_AUR=\(\n(?P<body>.*?)\n\)', text, re.S)
if not aur:
    raise SystemExit("ERROR: could not locate PACKAGES_AUR")
body_lines = [line for line in aur.group("body").splitlines() if line.strip() not in legacy]
text = text[:aur.start("body")] + "\n".join(body_lines) + text[aur.end("body"):]

# Fresh config copy: Quickshell replaces legacy shell UI config trees.
config_dirs = re.search(r'local -a config_dirs=\(([^)]*)\)', text)
if not config_dirs:
    raise SystemExit("ERROR: could not locate config_dirs")
dirs = config_dirs.group(1).split()
dirs = [item for item in dirs if item not in {"waybar", "fuzzel", "mako", "wlogout", "wofi"}]
if "quickshell" not in dirs:
    insert_at = dirs.index("hypr") + 1 if "hypr" in dirs else 0
    dirs.insert(insert_at, "quickshell")
text = text[:config_dirs.start(1)] + " ".join(dirs) + text[config_dirs.end(1):]

# Install the exact transformed runtime used by this testing branch instead of
# copying the untransformed repository template back into ~/.local/share.
runtime_line = '  local runtime_src="${REPO_DIR}/local/share/awtarchy/awtarchy-runtime.sh"'
runtime_replacement = '  local runtime_src="${AWTARCHY_RUNTIME_SOURCE_OVERRIDE:-${REPO_DIR}/local/share/awtarchy/awtarchy-runtime.sh}"'
if runtime_line not in text:
    raise SystemExit("ERROR: could not locate install runtime source")
text = text.replace(runtime_line, runtime_replacement, 1)

# An unreleased testing branch must not replace itself with the latest stable
# release during install. Stable/tagged installers keep the existing behavior.
verify_block = '''  log "Verifying the installed Awtarchy command against GitHub's latest release..."
  if ! env -u XDG_DATA_HOME -u XDG_STATE_HOME \\
    HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \\
    "${bin_dir}/awtarchy" self-update
  then
    die "Could not verify the installed Awtarchy command against GitHub's latest release."
  fi
'''
verify_replacement = '''  if [[ "${AWTARCHY_SKIP_SELF_UPDATE:-0}" != "1" ]]; then
    log "Verifying the installed Awtarchy command against GitHub's latest release..."
    if ! env -u XDG_DATA_HOME -u XDG_STATE_HOME \\
      HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \\
      "${bin_dir}/awtarchy" self-update
    then
      die "Could not verify the installed Awtarchy command against GitHub's latest release."
    fi
  else
    log "Keeping the unreleased Quickshell conversion runtime installed for testing."
  fi
'''
if verify_block not in text:
    raise SystemExit("ERROR: could not locate install self-update verification block")
text = text.replace(verify_block, verify_replacement, 1)

# Updater theme application must use the Quickshell-aware theme helper instead
# of executing legacy theme scripts that mutate removed shell configs.
text = text.replace(
    'bash "$theme_script"',
    'bash "${repo_dir}/config/hypr/scripts/quickshell_theme_apply.sh" "$theme"'
)

# No notification reload should depend on makoctl after the conversion.
text = re.sub(
    r'(?m)^(?P<indent>[ \t]*)makoctl reload(?:[^\n]*)$',
    r'\g<indent>: # Quickshell owns notifications',
    text,
)

# These package names are the retired Awtarchy shell stack. Older Awtarchy
# installs may predate the managed-package ledger, so the Quickshell migration
# removes them even when they are absent from /var/lib/awtarchy/managed-packages.
cleanup_function = r'''
remove_legacy_shell_packages_stage() {
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
  local marker="${HOME_DIR}/.local/state/awtarchy/quickshell-connectivity-migration-complete"
  local pkg tmp cleanup_ok=1
  local -a obsolete=(waybar waybar-git fuzzel wlogout mako wofi network-manager-applet blueman)

  for pkg in "${obsolete[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || continue

    log "Removing retired Awtarchy shell package: ${pkg}"
    if pacman -Rns --noconfirm "$pkg"; then
      if [[ -f "$managed_file" ]]; then
        tmp="$(mktemp)"
        grep -Fxv "$pkg" "$managed_file" >"$tmp" || true
        cat "$tmp" >"$managed_file"
        rm -f "$tmp"
      fi
    else
      cleanup_ok=0
      warn "Could not remove retired package ${pkg}; continuing conversion."
    fi
  done

  if (( cleanup_ok == 1 )); then
    for pkg in "${obsolete[@]}"; do
      pacman -Q "$pkg" >/dev/null 2>&1 && cleanup_ok=0
    done
  fi

  if (( cleanup_ok == 1 )); then
    install -d -m 0755 "$(dirname "$marker")"
    : >"$marker"
    chown "${TARGET_USER}:${TARGET_USER}" "$marker" 2>/dev/null || true
  fi
}

'''
legacy_file_cleanup_function = r'''
remove_legacy_shell_path_stage() {
  local dest="$1" candidate

  for candidate in "$dest" "${dest}.backup" "${dest}.backup."*; do
    [[ -e "$candidate" || -L "$candidate" ]] || continue
    rm -rf -- "$candidate"
  done
}

remove_legacy_shell_files_stage() {
  local scripts_dir="${HOME_DIR}/.config/hypr/scripts"
  local applications_dir="${HOME_DIR}/.local/share/applications"
  local obsolete

  for obsolete in \
    "${HOME_DIR}/.config/waybar" \
    "${HOME_DIR}/.config/fuzzel" \
    "${HOME_DIR}/.config/mako" \
    "${HOME_DIR}/.config/wlogout" \
    "${HOME_DIR}/.config/wofi" \
    "${HOME_DIR}/.cache/waybar" \
    "${HOME_DIR}/.cache/fuzzel" \
    "${HOME_DIR}/.cache/wofi"
  do
    remove_legacy_shell_path_stage "$obsolete"
  done

  for obsolete in "${HOME_DIR}/.cache/wofi-"*; do
    [[ -e "$obsolete" || -L "$obsolete" ]] || continue
    remove_legacy_shell_path_stage "$obsolete"
  done

  for obsolete in \
    cliphist-fuzzel.sh \
    cliphist-wofi.sh \
    fuzzel_toggle.sh \
    mako_dismiss.sh \
    waybar.sh \
    waybar_flip.sh \
    waybar_ready_sound.sh \
    waybar_restore_resume.sh \
    waybar_rotate.sh \
    waybar_toggle.sh \
    waybar_toggle_idle.sh \
    wlogout_toggle.sh
  do
    remove_legacy_shell_path_stage "${scripts_dir}/${obsolete}"
  done

  for obsolete in \
    hypr_quicksettings.desktop \
    waybar_flip.desktop \
    waybar_rotate.desktop \
    waybar_toggle.desktop
  do
    remove_legacy_shell_path_stage "${applications_dir}/${obsolete}"
  done
}

'''

# The testing updater must perform the same one-time migration. This is explicit
# instead of relying only on old baseline reconstruction because legacy systems
# may not have a complete baseline or managed-package ledger.
update_cleanup_function = r'''
run_quickshell_update_pacman() {
  if [[ "${EUID}" -eq 0 ]]; then
    pacman "$@"
    return
  fi

  command -v sudo >/dev/null 2>&1 \
    || die "sudo is required to install the Quickshell migration packages"
  sudo -v || die "sudo authentication failed; no managed configs were changed"
  sudo pacman "$@"
}

record_quickshell_update_packages() {
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
  local tmp pkg
  local -a packages=("$@")
  (( ${#packages[@]} )) || return 0

  tmp="$(mktemp)"
  [[ -r "$managed_file" ]] && cat "$managed_file" >"$tmp" || : >"$tmp"
  for pkg in "${packages[@]}"; do
    printf '%s\n' "$pkg" >>"$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"

  if [[ "${EUID}" -eq 0 ]]; then
    install -d -m 0755 "$(dirname "$managed_file")"
    install -m 0644 "$tmp" "$managed_file"
  else
    sudo install -d -m 0755 "$(dirname "$managed_file")"
    sudo install -m 0644 "$tmp" "$managed_file"
  fi
  rm -f -- "$tmp"
}

ensure_quickshell_update_prerequisites() {
  command -v pacman >/dev/null 2>&1 \
    || die "pacman is required for the Quickshell migration"

  local pkg
  local -a required=(quickshell upower) missing=()
  for pkg in "${required[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  (( ${#missing[@]} )) || return 0

  log "Installing required Quickshell migration packages: ${missing[*]}"
  run_quickshell_update_pacman -S --needed --noconfirm "${missing[@]}" \
    || die "Could not install the Quickshell migration packages; no managed configs were changed"

  for pkg in "${missing[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 \
      || die "Required package is still missing after installation: ${pkg}"
  done
  record_quickshell_update_packages "${missing[@]}"
}

quickshell_update_legacy_paths() {
  printf '%s\n' \
    .config/waybar \
    .config/fuzzel \
    .config/mako \
    .config/wlogout \
    .config/wofi \
    .cache/waybar \
    .cache/fuzzel \
    .cache/wofi \
    .config/hypr/scripts/cliphist-fuzzel.sh \
    .config/hypr/scripts/cliphist-wofi.sh \
    .config/hypr/scripts/fuzzel_toggle.sh \
    .config/hypr/scripts/mako_dismiss.sh \
    .config/hypr/scripts/waybar.sh \
    .config/hypr/scripts/waybar_flip.sh \
    .config/hypr/scripts/waybar_ready_sound.sh \
    .config/hypr/scripts/waybar_restore_resume.sh \
    .config/hypr/scripts/waybar_rotate.sh \
    .config/hypr/scripts/waybar_toggle.sh \
    .config/hypr/scripts/waybar_toggle_idle.sh \
    .config/hypr/scripts/wlogout_toggle.sh \
    .local/share/applications/hypr_quicksettings.desktop \
    .local/share/applications/waybar_flip.desktop \
    .local/share/applications/waybar_rotate.desktop \
    .local/share/applications/waybar_toggle.desktop
}

quickshell_update_existing_legacy_paths() {
  local rel dest candidate

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    dest="${HOME_DIR}/${rel}"
    for candidate in "$dest" "${dest}.backup" "${dest}.backup."*; do
      [[ -e "$candidate" || -L "$candidate" ]] || continue
      printf '%s\n' "${candidate#"${HOME_DIR}/"}"
    done
  done < <(quickshell_update_legacy_paths)

  for candidate in "${HOME_DIR}/.cache/wofi-"*; do
    [[ -e "$candidate" || -L "$candidate" ]] || continue
    printf '%s\n' "${candidate#"${HOME_DIR}/"}"
  done
}

snapshot_quickshell_update_legacy_paths() {
  local rel dest
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    dest="${HOME_DIR}/${rel}"
    snapshot_for_rollback "$rel" "$dest"
    ROLLBACK_PATHS+=("$rel")
  done < <(quickshell_update_existing_legacy_paths)
}

remove_quickshell_update_legacy_files() {
  local rel dest
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    dest="${HOME_DIR}/${rel}"
    if ! rm -rf -- "$dest"; then
      FAILED+=("$rel")
      return 1
    fi
    CHANGED+=("$rel")
    REMOVED+=("$rel")
  done < <(quickshell_update_existing_legacy_paths)
}

reload_quickshell_update_hyprland() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
  run_target hyprctl reload >/dev/null 2>&1
}

start_quickshell_update_shell() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0

  local manager="${HOME_DIR}/.config/hypr/scripts/quickshell.sh"
  local status=""
  [[ -f "$manager" ]] || return 1
  # Descriptor 9 owns the updater lock. Keep it in this runtime, but do not
  # let the long-lived Quickshell process or its children inherit it.
  run_target bash "$manager" restart 9>&- || return 1
  status="$(run_target bash "$manager" status 9>&- 2>/dev/null || true)"
  [[ "$status" == "running" ]]
}

rollback_quickshell_update() {
  local manager="${HOME_DIR}/.config/hypr/scripts/quickshell.sh"
  if [[ -f "$manager" ]]; then
    run_target bash "$manager" stop 9>&- >/dev/null 2>&1 || true
  fi
  rollback_changes
  reload_quickshell_update_hyprland || true
  if [[ -f "$manager" ]] \
    && ! run_target bash "$manager" start 9>&-;
  then
    warn "User files were restored, but the restored Quickshell could not be restarted automatically."
  fi
}

remove_quickshell_update_legacy_packages() {
  local marker="${STATE_DIR}/quickshell-connectivity-migration-complete"
  local managed_file="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
  local pkg process tmp
  local -a obsolete_packages=(waybar waybar-git fuzzel wlogout mako wofi network-manager-applet blueman)
  local -a obsolete_processes=(waybar fuzzel wlogout mako wofi nm-applet blueman-applet blueman-manager)
  local -a installed=()

  [[ -e "$marker" ]] && return 0

  for pkg in "${obsolete_packages[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 && installed+=("$pkg")
  done

  for process in "${obsolete_processes[@]}"; do
    run_target pkill -x "$process" >/dev/null 2>&1 || true
  done

  if (( ${#installed[@]} )); then
    log "Removing retired Awtarchy shell packages: ${installed[*]}"
    if ! run_quickshell_update_pacman -Rns --noconfirm "${installed[@]}"; then
      warn "Could not remove all retired shell packages; the migration will retry later."
      return 0
    fi
  fi

  if [[ -f "$managed_file" ]]; then
    tmp="$(mktemp)"
    grep -Ev '^(waybar|waybar-git|fuzzel|wlogout|mako|wofi|network-manager-applet|blueman)$' "$managed_file" >"$tmp" || true
    if [[ "${EUID}" -eq 0 ]]; then
      install -m 0644 "$tmp" "$managed_file" \
        || warn "Retired packages were removed but the Awtarchy package ledger could not be updated."
    elif command -v sudo >/dev/null 2>&1 \
      && sudo -v \
      && sudo install -m 0644 "$tmp" "$managed_file";
    then
      :
    else
      warn "Retired packages were removed but the Awtarchy package ledger could not be updated."
    fi
    rm -f -- "$tmp"
  fi

  : >"$marker"
  [[ "${EUID}" -eq 0 ]] && chown "${TARGET_USER}:${TARGET_USER}" "$marker" 2>/dev/null || true
}

'''

run_install_marker = 'run_install() {\n'
if run_install_marker not in text:
    raise SystemExit("ERROR: could not locate run_install")
text = text.replace(run_install_marker, cleanup_function + legacy_file_cleanup_function + run_install_marker, 1)

install_sequence = '''  copy_awtarchy_configs_stage
  install_awtarchy_command_stage
'''
install_sequence_replacement = '''  copy_awtarchy_configs_stage
  remove_legacy_shell_files_stage
  install_awtarchy_command_stage
  remove_legacy_shell_packages_stage
'''
if install_sequence not in text:
    raise SystemExit("ERROR: could not locate install stage sequence")
text = text.replace(install_sequence, install_sequence_replacement, 1)

update_main_marker = '''main() {
  parse_args "$@" || return 0
'''
if update_main_marker not in text:
    raise SystemExit("ERROR: could not locate updater main")
text = text.replace(update_main_marker, update_cleanup_function + update_main_marker, 1)

update_apply_marker = '''  apply_plan "$plan_file" || die "Update failed and user files were rolled back."
  if [[ "$UPDATE_MODE" == "preserve" && -n "$fuzzel_anchor" ]]; then
    restore_fuzzel_anchor "$fuzzel_anchor"
  fi

  hardware_reconcile
'''
update_apply_replacement = '''  ensure_quickshell_update_prerequisites
  snapshot_quickshell_update_legacy_paths

  apply_plan "$plan_file" || die "Update failed and user files were rolled back."
  if [[ "$UPDATE_MODE" == "preserve" && -n "$fuzzel_anchor" ]]; then
    restore_fuzzel_anchor "$fuzzel_anchor"
  fi

  hardware_reconcile
'''
if update_apply_marker not in text:
    raise SystemExit("ERROR: could not locate updater apply sequence")
text = text.replace(update_apply_marker, update_apply_replacement, 1)

update_validate_marker = '''  if ! validate_live; then
    rollback_changes
    die "Live validation failed. User files were rolled back."
  fi
'''
update_validate_replacement = '''  if ! reload_quickshell_update_hyprland; then
    rollback_quickshell_update
    die "Hyprland reload failed. User files were rolled back."
  fi

  if ! validate_live; then
    rollback_quickshell_update
    die "Live validation failed. User files were rolled back."
  fi

  if ! start_quickshell_update_shell; then
    rollback_quickshell_update
    die "Quickshell did not start successfully. User files were rolled back."
  fi

  if ! remove_quickshell_update_legacy_files; then
    rollback_quickshell_update
    die "Legacy shell cleanup failed. User files were rolled back."
  fi

  remove_quickshell_update_legacy_packages
'''
if update_validate_marker not in text:
    raise SystemExit("ERROR: could not locate updater live validation sequence")
text = text.replace(update_validate_marker, update_validate_replacement, 1)

# The old Waybar script chmod block is obsolete because those helpers were moved
# under config/hypr/scripts.
text = re.sub(
    r'\n  if \[\[ -d "\$\{HOME_DIR\}/\.config/waybar/scripts" \]\]; then\n'
    r'    find "\$\{HOME_DIR\}/\.config/waybar/scripts" -type f -exec chmod \+x \{\} \+ 2>/dev/null \|\| true\n'
    r'  fi',
    '',
    text,
)

# Validate the effective install selections. Compatibility/migration code may
# still recognize old paths, but no legacy shell program may be selected.
window = re.search(r'"Window Management:([^"]+)"', text)
utilities = re.search(r'"Utilities:([^"]+)"', text)
aur = re.search(r'declare -a PACKAGES_AUR=\(\n(?P<body>.*?)\n\)', text, re.S)
config_dirs = re.search(r'local -a config_dirs=\(([^)]*)\)', text)
if not (window and utilities and aur and config_dirs):
    raise SystemExit("ERROR: transformed runtime validation anchors missing")
for old in legacy | legacy_connectivity:
    if (old in window.group(1).split() or old in utilities.group(1).split()
            or old in aur.group("body").split() or old in config_dirs.group(1).split()):
        raise SystemExit(f"ERROR: legacy shell dependency still selected: {old}")
if "quickshell" not in window.group(1).split() or "quickshell" not in config_dirs.group(1).split():
    raise SystemExit("ERROR: quickshell was not added to effective runtime")

dst.write_text(text, encoding="utf-8")
PY

  chmod 0755 "$RUNTIME_TEMP"
  bash -n "$RUNTIME_TEMP" || {
    printf 'ERROR: Generated Quickshell runtime failed Bash syntax validation.\n' >&2
    exit 1
  }
  RUNTIME_SOURCE="$RUNTIME_TEMP"
}

resolve_target() {
  if [[ ${EUID} -eq 0 && -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
    TARGET_USER="$SUDO_USER"
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
  else
    TARGET_USER="${USER:-$(id -un)}"
    TARGET_HOME="${HOME:-}"
  fi

  [[ -n $TARGET_USER ]] || {
    printf 'ERROR: Could not determine the target user.\n' >&2
    exit 1
  }
  [[ -n $TARGET_HOME && -d $TARGET_HOME ]] || {
    printf 'ERROR: Could not determine the home directory for %s.\n' "$TARGET_USER" >&2
    exit 1
  }
}

source_git() {
  local -a command=(git -C "$SCRIPT_DIR" "$@")

  if [[ ${EUID} -eq 0 && -n ${TARGET_USER:-} && $TARGET_USER != root ]]; then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$TARGET_USER" -- "${command[@]}"
    elif command -v sudo >/dev/null 2>&1; then
      sudo -u "$TARGET_USER" -H -- "${command[@]}"
    else
      return 1
    fi
  else
    "${command[@]}"
  fi
}

ensure_vpn_directory() {
  local vpn_dir="${TARGET_HOME}/vpn"
  install -d -m 0700 "$vpn_dir"
  if [[ ${EUID} -eq 0 ]]; then
    chown "$TARGET_USER:$TARGET_USER" "$vpn_dir"
  fi
}

state_value() {
  local key="$1" file="$2"
  [[ -r $file ]] || return 1
  sed -n "s/^${key}=//p" "$file" | head -n1
}

installed_command_exists() {
  [[ -x "${TARGET_HOME}/.local/bin/awtarchy" \
    && -f "${TARGET_HOME}/.local/share/awtarchy/awtarchy-runtime.sh" ]]
}

legacy_install_exists() {
  [[ -f "${TARGET_HOME}/.cache/awtarchy/version" ]] && return 0
  [[ -d "${TARGET_HOME}/.local/state/awtarchy/baseline" ]] && return 0
  [[ -f "${TARGET_HOME}/.local/state/awtarchy/hardware-state" ]] && return 0
  [[ -f /var/lib/awtarchy/managed-packages ]] && return 0

  if [[ -f "${TARGET_HOME}/.bashrc" \
    && -f "${TARGET_HOME}/.config/hypr/hyprland.lua" \
    && -f "${TARGET_HOME}/.config/waybar/config" ]] \
    && grep -Fq 'github.com/dillacorn/awtarchy' "${TARGET_HOME}/.bashrc";
  then
    return 0
  fi

  return 1
}

is_quickshell_testing_source() {
  local source_name="${SCRIPT_DIR##*/}" branch=""
  [[ ${AWTARCHY_INSTALL_BRANCH:-} == quickshell-conversion-testing ]] && return 0
  [[ ${AWTARCHY_TESTING_COMMIT:-} =~ ^[0-9a-fA-F]{40}$ ]] && return 0
  if command -v git >/dev/null 2>&1 \
    && source_git rev-parse --is-inside-work-tree >/dev/null 2>&1;
  then
    branch="$(source_git branch --show-current 2>/dev/null || true)"
    [[ $branch == quickshell-conversion-testing ]] && return 0
  fi
  [[ $source_name == awtarchy-quickshell-conversion-testing ]] && return 0
  return 1
}

source_release_tag() {
  local source_name="${SCRIPT_DIR##*/}" tag=""

  if is_quickshell_testing_source; then
    printf '%s\n' unreleased
    return 0
  fi

  if [[ -n ${AWTARCHY_INSTALL_TAG:-} ]]; then
    printf '%s\n' "$AWTARCHY_INSTALL_TAG"
    return 0
  fi

  if [[ $source_name == awtarchy-* ]]; then
    tag="${source_name#awtarchy-}"
    [[ -n $tag ]] && {
      printf '%s\n' "$tag"
      return 0
    }
  fi

  if command -v git >/dev/null 2>&1 \
    && source_git rev-parse --is-inside-work-tree >/dev/null 2>&1;
  then
    tag="$(source_git tag --points-at HEAD 2>/dev/null \
      | grep -E '^v[0-9]+([.][0-9]+)*([._+-].*)?$' \
      | head -n1 || true)"
    [[ -n $tag ]] && {
      printf '%s\n' "$tag"
      return 0
    }
  fi

  printf '%s\n' unreleased
}

source_revision() {
  if [[ ${AWTARCHY_TESTING_COMMIT:-} =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf '%s\n' "${AWTARCHY_TESTING_COMMIT,,}"
    return 0
  fi

  if command -v git >/dev/null 2>&1 \
    && source_git rev-parse --is-inside-work-tree >/dev/null 2>&1;
  then
    source_git rev-parse HEAD 2>/dev/null || true
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$RUNTIME_SOURCE" | awk '{print $1}'
  fi
}

legacy_config_tag() {
  local tag="" file=""
  for file in \
    "${TARGET_HOME}/.local/state/awtarchy/config-version" \
    "${TARGET_HOME}/.local/state/awtarchy/baseline/metadata" \
    "${TARGET_HOME}/.cache/awtarchy/version"
  do
    tag="$(state_value tag "$file" 2>/dev/null || true)"
    [[ -n $tag ]] && {
      printf '%s\n' "$tag"
      return 0
    }
  done
  printf '%s\n' unknown
}

write_version_file() {
  local destination="$1" tag="$2" revision="${3:-}" timestamp_key="$4"
  {
    printf 'tag=%s\n' "$tag"
    [[ -n $revision ]] && printf 'revision=%s\n' "$revision"
    printf '%s=%s\n' "$timestamp_key" "$(date -Iseconds)"
  } >"$destination"
  chmod 0644 "$destination"
}

install_system_launcher() {
  local destination="${SYSTEM_BIN_DIR}/awtarchy"
  local marker='# Awtarchy user-local command shim'
  local temporary=""

  if [[ ${EUID} -ne 0 && -z ${AWTARCHY_SYSTEM_BIN_DIR:-} ]]; then
    printf 'WARNING: Could not install the system command shim without sudo.\n' >&2
    printf 'Ensure %s is included in PATH.\n' "${TARGET_HOME}/.local/bin" >&2
    return 0
  fi

  if [[ -e $destination || -L $destination ]]; then
    if ! grep -Fq "$marker" "$destination" 2>/dev/null; then
      printf 'WARNING: Refusing to replace an existing non-Awtarchy command: %s\n' \
        "$destination" >&2
      printf 'Ensure %s is included in PATH.\n' "${TARGET_HOME}/.local/bin" >&2
      return 0
    fi
  fi

  install -d -m 0755 "$SYSTEM_BIN_DIR"
  temporary="$(mktemp "${SYSTEM_BIN_DIR}/.awtarchy.tmp.XXXXXX")"
  cat >"$temporary" <<'EOF_SHIM'
#!/usr/bin/env bash
# Awtarchy user-local command shim

set -Eeuo pipefail

target="${HOME}/.local/bin/awtarchy"

if [[ -x $target && $target != "${BASH_SOURCE[0]}" ]]; then
  exec "$target" "$@"
fi

printf 'ERROR: Awtarchy is not installed for %s: %s\n' \
  "${USER:-current user}" "$target" >&2
exit 127
EOF_SHIM
  chmod 0755 "$temporary"
  if [[ ${EUID} -eq 0 ]]; then
    chown root:root "$temporary"
  fi
  mv -Tf -- "$temporary" "$destination"
}

install_system_quickshell_launcher() {
  [[ ${AWTARCHY_SKIP_SYSTEM_SHIM:-0} == 1 ]] && return 0

  local destination="${SYSTEM_BIN_DIR}/awtarchy-quickshell"
  local marker='# Awtarchy Quickshell testing user-local command shim'
  local temporary=""

  if [[ ${EUID} -ne 0 && -z ${AWTARCHY_SYSTEM_BIN_DIR:-} ]]; then
    printf 'WARNING: Could not install the awtarchy-quickshell system shim without sudo.\n' >&2
    printf 'Ensure %s is included in PATH.\n' "${TARGET_HOME}/.local/bin" >&2
    return 0
  fi

  if [[ -e $destination || -L $destination ]]; then
    if ! grep -Fq "$marker" "$destination" 2>/dev/null; then
      printf 'WARNING: Refusing to replace an existing unrelated command: %s\n' \
        "$destination" >&2
      printf 'Ensure %s is included in PATH.\n' "${TARGET_HOME}/.local/bin" >&2
      return 0
    fi
  fi

  install -d -m 0755 "$SYSTEM_BIN_DIR"
  temporary="$(mktemp "${SYSTEM_BIN_DIR}/.awtarchy-quickshell.tmp.XXXXXX")"
  cat >"$temporary" <<'EOF_SHIM'
#!/usr/bin/env bash
# Awtarchy Quickshell testing user-local command shim

set -Eeuo pipefail

target="${HOME}/.local/bin/awtarchy-quickshell"

if [[ -x $target && $target != "${BASH_SOURCE[0]}" ]]; then
  exec "$target" "$@"
fi

printf 'ERROR: awtarchy-quickshell is not installed for %s: %s\n' \
  "${USER:-current user}" "$target" >&2
exit 127
EOF_SHIM
  chmod 0755 "$temporary"
  if [[ ${EUID} -eq 0 ]]; then
    chown root:root "$temporary"
  fi
  mv -Tf -- "$temporary" "$destination"
}

repair_quickshell_command_ownership() {
  [[ ${EUID} -eq 0 ]] || return 0

  local path
  for path in \
    "${TARGET_HOME}/.local/bin" \
    "${TARGET_HOME}/.local/bin/awtarchy-quickshell" \
    "${TARGET_HOME}/.local/share/awtarchy-quickshell" \
    "${TARGET_HOME}/.local/share/awtarchy-quickshell/awtarchy-runtime.sh" \
    "${TARGET_HOME}/.local/state/awtarchy-quickshell" \
    "${TARGET_HOME}/.local/state/awtarchy-quickshell/command-version"
  do
    [[ -e $path || -L $path ]] || continue
    chown -h "${TARGET_USER}:${TARGET_USER}" "$path"
  done
}

install_quickshell_testing_command() {
  local bin_dir="${TARGET_HOME}/.local/bin"
  local data_dir="${TARGET_HOME}/.local/share/awtarchy-quickshell"
  local state_dir="${TARGET_HOME}/.local/state/awtarchy-quickshell"
  local command_version="${state_dir}/command-version"
  local revision

  is_quickshell_testing_source || {
    printf 'ERROR: awtarchy-quickshell can only be installed from quickshell-conversion-testing.\n' >&2
    exit 1
  }
  [[ -f $QUICKSHELL_LAUNCHER_SOURCE ]] || {
    printf 'ERROR: Missing testing command: %s\n' "$QUICKSHELL_LAUNCHER_SOURCE" >&2
    exit 1
  }
  bash -n "$RUNTIME_SOURCE" || {
    printf 'ERROR: Quickshell testing runtime failed Bash syntax validation.\n' >&2
    exit 1
  }
  bash -n "$QUICKSHELL_LAUNCHER_SOURCE" || {
    printf 'ERROR: awtarchy-quickshell failed Bash syntax validation.\n' >&2
    exit 1
  }

  revision="$(source_revision)"
  [[ $revision =~ ^[0-9a-fA-F]{40}$ ]] || {
    printf 'ERROR: Could not resolve the exact quickshell-conversion-testing commit.\n' >&2
    exit 1
  }
  revision="${revision,,}"

  install -d -m 0755 "$bin_dir" "$data_dir" "$state_dir"
  install -m 0755 "$QUICKSHELL_LAUNCHER_SOURCE" \
    "${bin_dir}/awtarchy-quickshell"
  install -m 0755 "$RUNTIME_SOURCE" "${data_dir}/awtarchy-runtime.sh"
  write_version_file "$command_version" quickshell-conversion-testing \
    "$revision" installed_at
  repair_quickshell_command_ownership

  if [[ ${AWTARCHY_QUIET_TEST_COMMAND_INSTALL:-0} == 1 ]]; then
    return 0
  fi

  cat <<EOF_MESSAGE
Installed the temporary Quickshell testing command at commit:

  ${revision}

The stable awtarchy launcher, runtime, and command-version state were not changed.

  awtarchy-quickshell review
  awtarchy-quickshell update
  awtarchy-quickshell version
EOF_MESSAGE
}

repair_target_ownership() {
  [[ ${EUID} -eq 0 ]] || return 0

  local path
  for path in \
    "${TARGET_HOME}/.local/bin" \
    "${TARGET_HOME}/.local/bin/awtarchy" \
    "${TARGET_HOME}/.local/share/awtarchy" \
    "${TARGET_HOME}/.local/share/awtarchy/awtarchy-runtime.sh" \
    "${TARGET_HOME}/.local/state/awtarchy" \
    "${TARGET_HOME}/.local/state/awtarchy/command-version" \
    "${TARGET_HOME}/.local/state/awtarchy/config-version"
  do
    [[ -e $path || -L $path ]] || continue
    chown -h "${TARGET_USER}:${TARGET_USER}" "$path"
  done
}

refresh_existing_command() {
  local bin_dir="${TARGET_HOME}/.local/bin"
  local data_dir="${TARGET_HOME}/.local/share/awtarchy"
  local state_dir="${TARGET_HOME}/.local/state/awtarchy"
  local command_version="${state_dir}/command-version"
  local command_tag revision

  bash -n "$RUNTIME_SOURCE" || {
    printf 'ERROR: Awtarchy runtime failed Bash syntax validation.\n' >&2
    exit 1
  }
  bash -n "$LAUNCHER_SOURCE" || {
    printf 'ERROR: Awtarchy command failed Bash syntax validation.\n' >&2
    exit 1
  }

  install -d -m 0755 "$bin_dir" "$data_dir" "$state_dir"
  install -m 0755 "$LAUNCHER_SOURCE" "${bin_dir}/awtarchy"
  install -m 0755 "$RUNTIME_SOURCE" "${data_dir}/awtarchy-runtime.sh"

  command_tag="$(source_release_tag)"
  revision="$(source_revision)"
  write_version_file "$command_version" "$command_tag" "$revision" installed_at
  repair_target_ownership

  if [[ $command_tag == unreleased ]]; then
    printf '%s\n' "Installed the unreleased Quickshell conversion runtime without replacing it from stable."
  else
    printf '%s\n' "Verifying the Awtarchy command against GitHub's latest release..."
    if ! env -u XDG_DATA_HOME -u XDG_STATE_HOME \
      HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
      "${bin_dir}/awtarchy" self-update
    then
      printf '%s\n' "ERROR: Could not verify the Awtarchy command against GitHub's latest release." >&2
      exit 1
    fi
    repair_target_ownership
  fi
}

show_existing_install_message() {
  local testing_commit
  testing_commit="$(source_revision)"
  [[ "$testing_commit" =~ ^[0-9a-fA-F]{40}$ ]] \
    || testing_commit="<full quickshell-conversion-testing commit SHA>"

  cat <<EOF_MESSAGE
Awtarchy is already installed for ${TARGET_USER}.

The installed launcher/runtime were refreshed from this installer. For this
unreleased Quickshell branch, the runtime is intentionally not replaced by the
latest stable GitHub release. No packages or managed configs were changed.

  awtarchy                 Open the maintenance menu
  awtarchy review --testing-commit ${testing_commit}
  awtarchy update --testing-commit ${testing_commit}
  awtarchy version         Show installed and latest releases

Do not run awtarchy self-update during branch testing. That explicitly returns
the installed command/runtime to the latest stable release.

To intentionally run the complete Quickshell conversion installer:

  sudo ./awtarchy-install.sh --reinstall
EOF_MESSAGE
}

show_legacy_dry_run_message() {
  cat <<EOF_MESSAGE
An existing legacy Awtarchy installation was detected for ${TARGET_USER}.

No files were changed because --dry-run was used. Run this once to install the
new maintenance command without changing packages or managed configs:

  sudo ./awtarchy-install.sh

Future updates will then use:

  awtarchy
EOF_MESSAGE
}

migrate_legacy_install() {
  local bin_dir="${TARGET_HOME}/.local/bin"
  local data_dir="${TARGET_HOME}/.local/share/awtarchy"
  local state_dir="${TARGET_HOME}/.local/state/awtarchy"
  local command_version="${state_dir}/command-version"
  local config_version="${state_dir}/config-version"
  local command_tag config_tag revision

  bash -n "$RUNTIME_SOURCE" || {
    printf 'ERROR: Awtarchy runtime failed Bash syntax validation.\n' >&2
    exit 1
  }
  bash -n "$LAUNCHER_SOURCE" || {
    printf 'ERROR: Awtarchy command failed Bash syntax validation.\n' >&2
    exit 1
  }

  install -d -m 0755 "$bin_dir" "$data_dir" "$state_dir"
  install -m 0755 "$LAUNCHER_SOURCE" "${bin_dir}/awtarchy"
  install -m 0755 "$RUNTIME_SOURCE" "${data_dir}/awtarchy-runtime.sh"

  command_tag="$(source_release_tag)"
  revision="$(source_revision)"
  write_version_file "$command_version" "$command_tag" "$revision" installed_at

  if [[ ! -f $config_version ]]; then
    config_tag="$(legacy_config_tag)"
    write_version_file "$config_version" "$config_tag" "" migrated_at
  fi

  repair_target_ownership
  refresh_existing_command

  cat <<EOF_MESSAGE
Existing legacy Awtarchy installation detected for ${TARGET_USER}.

Installed the new maintenance command:

  ${bin_dir}/awtarchy

No packages or managed configs were changed. Use --reinstall when you are ready
to apply the actual Quickshell conversion.
EOF_MESSAGE
}

[[ -f $RUNTIME_TEMPLATE ]] || {
  printf 'ERROR: Missing installer runtime template: %s\n' "$RUNTIME_TEMPLATE" >&2
  exit 1
}
[[ -f $LAUNCHER_SOURCE ]] || {
  printf 'ERROR: Missing maintenance command: %s\n' "$LAUNCHER_SOURCE" >&2
  exit 1
}

while (( $# )); do
  case "$1" in
    -h|--help|help)
      usage
      exit 0
      ;;
    install)
      shift
      ;;
    --reinstall)
      REINSTALL=1
      shift
      ;;
    --quickshell-command)
      QUICKSHELL_COMMAND_ONLY=1
      shift
      ;;
    --dry-run|--test)
      DRY_RUN_REQUESTED=1
      ARGS+=("$1")
      shift
      ;;
    update|reset|review|clean-backups|version|check-update|self-update|update-reset-backup|update-backup-cleaner)
      printf 'ERROR: %s is a maintenance command. Run it through: awtarchy %s\n' "$1" "$1" >&2
      exit 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

prepare_runtime_source
resolve_target

if (( REINSTALL == 0 && QUICKSHELL_COMMAND_ONLY == 0 )) \
  && is_quickshell_testing_source \
  && { installed_command_exists || legacy_install_exists; };
then
  QUICKSHELL_COMMAND_ONLY=1
fi

if (( QUICKSHELL_COMMAND_ONLY == 1 )); then
  if (( DRY_RUN_REQUESTED == 1 )); then
    printf 'awtarchy-quickshell would be installed for %s. No files were changed because --dry-run was used.\n' \
      "$TARGET_USER"
  else
    install_system_quickshell_launcher
    install_quickshell_testing_command
  fi
  exit 0
fi

if (( DRY_RUN_REQUESTED == 0 )); then
  ensure_vpn_directory
  install_system_launcher
fi

if (( REINSTALL == 0 )); then
  if installed_command_exists; then
    if (( DRY_RUN_REQUESTED == 1 )); then
      printf 'Awtarchy is already installed for %s. No files were changed because --dry-run was used.\n' \
        "$TARGET_USER"
    else
      refresh_existing_command
      show_existing_install_message
    fi
    exit 0
  fi

  if legacy_install_exists; then
    if (( DRY_RUN_REQUESTED == 1 )); then
      show_legacy_dry_run_message
    else
      migrate_legacy_install
    fi
    exit 0
  fi
fi

set +e
env \
  AWTARCHY_REPO_DIR="$SCRIPT_DIR" \
  AWTARCHY_RUNTIME_SOURCE_OVERRIDE="$RUNTIME_SOURCE" \
  AWTARCHY_SKIP_SELF_UPDATE=1 \
  AWTARCHY_INSTALL_BRANCH=quickshell-conversion-testing \
  bash "$RUNTIME_SOURCE" install "${ARGS[@]}"
status=$?
set -e
exit "$status"
