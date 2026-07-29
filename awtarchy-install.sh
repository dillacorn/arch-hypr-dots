#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# awtarchy-install.sh
# Install-only entrypoint for applying the Awtarchy overlay.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_SOURCE="${SCRIPT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
LAUNCHER_SOURCE="${SCRIPT_DIR}/local/bin/awtarchy"
TARGET_USER=""
TARGET_HOME=""
REINSTALL=0
DRY_RUN_REQUESTED=0
ARGS=()

usage() {
  cat <<'EOF'
Usage:
  sudo ./awtarchy-install.sh
  sudo ./awtarchy-install.sh --no-reboot
  ./awtarchy-install.sh --dry-run
  sudo ./awtarchy-install.sh --reinstall
  ./awtarchy-install.sh --help

This script only installs Awtarchy. After installation, use the `awtarchy`
command for updates, config resets, review mode, version checks, and backup cleanup.

Existing legacy installations are migrated to the new command without rerunning
package installation or replacing managed configs.

Options:
  --reinstall    Run the complete installer even when Awtarchy is already installed
EOF
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

source_release_tag() {
  local source_name="${SCRIPT_DIR##*/}" tag=""

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
    && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1;
  then
    tag="$(git -C "$SCRIPT_DIR" tag --points-at HEAD 2>/dev/null \
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
  if command -v git >/dev/null 2>&1 \
    && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1;
  then
    git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || true
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

show_existing_install_message() {
  cat <<EOF
Awtarchy is already installed for ${TARGET_USER}.

Do not rerun the installer to update Awtarchy. Use the installed command:

  awtarchy                 Open the maintenance menu
  awtarchy self-update     Update the Awtarchy command
  awtarchy update          Update configs and preserve personal changes
  awtarchy reset           Reset managed configs to release defaults
  awtarchy version         Show installed and latest releases

To intentionally run the complete installer again:

  sudo ./awtarchy-install.sh --reinstall
EOF
}

show_legacy_dry_run_message() {
  cat <<EOF
An existing legacy Awtarchy installation was detected for ${TARGET_USER}.

No files were changed because --dry-run was used. Run this once to install the
new maintenance command without changing packages or managed configs:

  sudo ./awtarchy-install.sh

Future updates will then use:

  awtarchy
EOF
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

  cat <<EOF
Existing legacy Awtarchy installation detected for ${TARGET_USER}.

Installed the new maintenance command:

  ${bin_dir}/awtarchy

No packages or managed configs were changed. Future maintenance now uses:

  awtarchy                 Open the maintenance menu
  awtarchy self-update     Update the Awtarchy command
  awtarchy update          Update configs and preserve personal changes
  awtarchy reset           Reset managed configs to release defaults
  awtarchy version         Show installed and latest releases
EOF
}

[[ -f $RUNTIME_SOURCE ]] || {
  printf 'ERROR: Missing installer runtime: %s\n' "$RUNTIME_SOURCE" >&2
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

resolve_target

if (( REINSTALL == 0 )); then
  if installed_command_exists; then
    show_existing_install_message
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

exec env AWTARCHY_REPO_DIR="$SCRIPT_DIR" bash "$RUNTIME_SOURCE" install "${ARGS[@]}"
