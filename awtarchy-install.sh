#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# awtarchy-install.sh
# Install-only entrypoint for applying the Awtarchy overlay.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="${SCRIPT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
TARGET_USER=""
TARGET_HOME=""
REINSTALL=0
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

Options:
  --reinstall    Run the full installer even when the installed command exists
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

[[ -f "$RUNTIME" ]] || {
  printf 'ERROR: Missing installer runtime: %s\n' "$RUNTIME" >&2
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

if (( REINSTALL == 0 )) && [[ -x "${TARGET_HOME}/.local/bin/awtarchy" ]]; then
  show_existing_install_message
  exit 0
fi

exec bash "$RUNTIME" install "${ARGS[@]}"
