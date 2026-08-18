#!/usr/bin/env bash
# ~/.config/hypr/scripts/hyprbars_toggle.sh
#
# Safer hyprbars toggle.
# - Enabling can be applied immediately with hyprpm reload.
# - Disabling is staged for next Hyprland restart to avoid hot-unloading hyprbars and crashing Hyprland.
# - Routine status/toggle operations are unprivileged. hyprpm itself handles any
#   authentication it needs during the one-time repository/header setup path.

set -euo pipefail

TERM_CLASS="hyprbars"
TERM_TITLE="hyprbars"
PLUGIN="hyprbars"
REPO_URL="https://github.com/hyprwm/hyprland-plugins"
TRUSTED_HELPER="/usr/local/libexec/awtarchy/scxctl-helper"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCKFILE="${RUNTIME_DIR}/hyprbars-toggle.lockfile"
SCRIPT_PATH="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"

HYPRPM_BIN="$(command -v hyprpm || true)"
HYPRCTL_BIN="$(command -v hyprctl || true)"

require_hyprpm() {
  [[ -n "$HYPRPM_BIN" ]] || {
    printf 'hyprbars-toggle: hyprpm not found\n' >&2
    return 127
  }
}

acquire_lock() {
  command -v flock >/dev/null 2>&1 || return 0
  exec 9>"$LOCKFILE"
  flock -n 9
}

have_hyprbars_in_hyprpm() {
  require_hyprpm
  "$HYPRPM_BIN" list 2>/dev/null \
    | grep -qiE '(^|[^a-zA-Z0-9_])hyprbars([^a-zA-Z0-9_]|$)'
}

hyprbars_enabled_in_hyprpm() {
  require_hyprpm
  "$HYPRPM_BIN" list 2>/dev/null \
    | grep -iEA1 '(^|[^a-zA-Z0-9_])hyprbars([^a-zA-Z0-9_]|$)' \
    | grep -qiE 'enabled:[[:space:]]*true'
}

repo_already_added() {
  require_hyprpm
  "$HYPRPM_BIN" list 2>/dev/null \
    | grep -qiE '(Repository[[:space:]]+hyprland-plugins:|hyprwm/hyprland-plugins|https://github.com/hyprwm/hyprland-plugins)'
}

hyprbars_loaded() {
  [[ -n "$HYPRCTL_BIN" ]] || return 1
  "$HYPRCTL_BIN" plugin list 2>/dev/null \
    | grep -qiE '(^|[^a-zA-Z0-9_])hyprbars([^a-zA-Z0-9_]|$)'
}

reload_hyprbars() {
  require_hyprpm
  "$HYPRPM_BIN" reload
  if [[ -n "$HYPRCTL_BIN" ]]; then
    "$HYPRCTL_BIN" reload >/dev/null 2>&1 || true
  fi
}

machine_status() {
  if [[ -x $TRUSTED_HELPER ]]; then
    "$TRUSTED_HELPER" hyprbars-status
    return
  fi

  require_hyprpm || {
    printf '%s\n' 'unavailable'
    return 0
  }

  if ! have_hyprbars_in_hyprpm; then
    if hyprbars_loaded; then
      printf '%s\n' 'enabled'
    else
      printf '%s\n' 'unavailable'
    fi
  elif hyprbars_enabled_in_hyprpm; then
    if hyprbars_loaded; then
      printf '%s\n' 'enabled'
    else
      printf '%s\n' 'not-loaded'
    fi
  elif hyprbars_loaded; then
    printf '%s\n' 'disabled-pending'
  else
    printf '%s\n' 'disabled'
  fi
}

machine_toggle() {
  require_hyprpm
  acquire_lock || return 0

  if ! have_hyprbars_in_hyprpm; then
    printf 'hyprbars-toggle: setup required; run the interactive toggle once\n' >&2
    return 3
  fi

  if hyprbars_enabled_in_hyprpm; then
    "$HYPRPM_BIN" disable "$PLUGIN"
    if hyprbars_loaded; then
      printf '%s\n' 'disabled-pending'
    else
      printf '%s\n' 'disabled'
    fi
    return 0
  fi

  "$HYPRPM_BIN" enable "$PLUGIN"
  reload_hyprbars
  printf '%s\n' 'enabled'
}

pause_exit() {
  printf '\nPress ENTER to close...'
  read -r _ || true
}

install_official_plugins_repo() {
  printf '\n%s is not available yet.\n' "$PLUGIN"
  printf 'The Hyprland plugins repo is probably not added to hyprpm.\n\n'
  printf 'This will run:\n'
  printf '  hyprpm update\n'
  printf '  hyprpm add %s\n' "$REPO_URL"
  printf '  hyprpm enable %s\n' "$PLUGIN"
  printf '  hyprpm reload\n\n'

  local ans=""
  read -r -p "Install Hyprland plugins now? [y/N] " ans
  case "${ans,,}" in
    y|yes) ;;
    *) printf 'Cancelled. No changes made.\n'; pause_exit; exit 0 ;;
  esac

  # Do not pre-authenticate with sudo here. hyprpm requests elevation only when
  # its header/update work actually needs it, instead of every title-bar toggle.
  "$HYPRPM_BIN" update

  if ! "$HYPRPM_BIN" add "$REPO_URL"; then
    if repo_already_added; then
      printf '(repo already added)\n'
    else
      printf 'ERROR: failed to add plugins repo.\n' >&2
      pause_exit
      exit 1
    fi
  fi
}

interactive_main() {
  require_hyprpm || { pause_exit; exit 1; }

  printf '\nChecking hyprbars...\n\n'

  if hyprbars_loaded; then
    printf 'hyprbars is currently loaded.\n'
    printf 'Not hot-unloading it. Hot-unloading hyprbars can crash Hyprland.\n\n'
    printf 'This will run:\n'
    printf '  hyprpm disable hyprbars\n\n'
    printf 'It will take effect after you log out and back in.\n\n'

    local ans=""
    read -r -p "Disable hyprbars for next session? [y/N] " ans
    case "${ans,,}" in
      y|yes) ;;
      *) printf 'Cancelled. No changes made.\n'; pause_exit; exit 0 ;;
    esac

    "$HYPRPM_BIN" disable "$PLUGIN"

    printf '\nHyprbars disabled for next session.\n'
    printf 'Log out and back in. Do not run hyprpm reload to hot-unload it.\n'
    pause_exit
    exit 0
  fi

  printf 'hyprbars is not currently loaded.\n'

  if ! have_hyprbars_in_hyprpm; then
    install_official_plugins_repo
  fi

  printf '\nhyprpm enable %s\n' "$PLUGIN"
  "$HYPRPM_BIN" enable "$PLUGIN"

  printf '\nhyprpm reload\n'
  reload_hyprbars

  if [[ -n "$HYPRCTL_BIN" ]]; then
    printf '\nLoaded plugins:\n\n'
    "$HYPRCTL_BIN" plugin list 2>/dev/null || true

    printf '\nConfig errors:\n\n'
    "$HYPRCTL_BIN" configerrors || true
  fi

  printf '\nHyprbars enabled.\n'
  pause_exit
}

case "${1:-}" in
  --status)
    [[ $# -eq 1 ]] || { printf 'hyprbars-toggle: --status takes no arguments\n' >&2; exit 2; }
    machine_status
    ;;
  --toggle)
    [[ $# -eq 1 ]] || { printf 'hyprbars-toggle: --toggle takes no arguments\n' >&2; exit 2; }
    machine_toggle
    ;;
  --interactive)
    [[ $# -eq 1 ]] || { printf 'hyprbars-toggle: --interactive takes no arguments\n' >&2; exit 2; }
    interactive_main
    ;;
  "")
    [[ $# -eq 0 ]] || exit 2
    ALACRITTY="$(command -v alacritty || true)"
    [[ -n "$ALACRITTY" ]] || { printf 'hyprbars-toggle: alacritty not found\n' >&2; exit 1; }
    require_hyprpm
    acquire_lock || exit 0
    exec "$ALACRITTY" \
      --class "${TERM_CLASS},${TERM_CLASS}" \
      -T "$TERM_TITLE" \
      -e bash --noprofile --norc "$SCRIPT_PATH" --interactive
    ;;
  *)
    printf 'usage: hyprbars_toggle.sh [--status|--toggle]\n' >&2
    exit 2
    ;;
esac
