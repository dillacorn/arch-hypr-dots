#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# awtarchy-install.sh
# Install-only entrypoint for applying the Awtarchy overlay.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="${SCRIPT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"

usage() {
  cat <<'EOF'
Usage:
  sudo ./awtarchy-install.sh
  sudo ./awtarchy-install.sh --no-reboot
  ./awtarchy-install.sh --dry-run
  ./awtarchy-install.sh --help

This script only installs Awtarchy. After installation, use the `awtarchy`
command for updates, config resets, review mode, version checks, and backup cleanup.
EOF
}

[[ -f "$RUNTIME" ]] || {
  printf 'ERROR: Missing installer runtime: %s\n' "$RUNTIME" >&2
  exit 1
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
  install)
    shift
    ;;
  update|reset|review|clean-backups|version|check-update|self-update|update-reset-backup|update-backup-cleaner)
    printf 'ERROR: %s is a maintenance command. Run it through: awtarchy %s\n' "$1" "$1" >&2
    exit 2
    ;;
esac

exec bash "$RUNTIME" install "$@"
