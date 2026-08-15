#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# Reconcile Quickshell UI files that preserve mode could not classify safely.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

HOME_DIR="${HOME:-}"
[[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || {
  printf 'ERROR: Could not determine HOME for Quickshell UI reconciliation.\n' >&2
  exit 1
}

BASELINE_ROOT="${HOME_DIR}/.local/state/awtarchy/baseline/home"
LIVE_ROOT="$HOME_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"

# These are Awtarchy shell plumbing files, not personal Hyprland configuration.
# They are deliberately narrow so preserve mode never turns into a broad reset.
UI_FILES=(
  ".config/quickshell/awtarchy/AudioLimitState.qml"
  ".config/quickshell/awtarchy/Bar.qml"
  ".config/quickshell/awtarchy/BarSettingsSection.qml"
  ".config/quickshell/awtarchy/CaptureEyeButton.qml"
  ".config/quickshell/awtarchy/FlyoutSettings.qml"
  ".config/quickshell/awtarchy/Launcher.qml"
  ".config/quickshell/awtarchy/Notifications.qml"
  ".config/quickshell/awtarchy/QuickSettings.qml"
)

differences=()
for rel in "${UI_FILES[@]}"; do
  baseline="${BASELINE_ROOT}/${rel}"
  live="${LIVE_ROOT}/${rel}"
  [[ -f "$baseline" && ! -L "$baseline" ]] || continue
  if [[ ! -f "$live" || -L "$live" ]] || ! cmp -s -- "$baseline" "$live"; then
    differences+=("$rel")
  fi
done

(( ${#differences[@]} > 0 )) || exit 0

printf '\nAwtarchy preserved local Quickshell UI files that differ from the current managed version:\n' >&2
printf '  %s\n' "${differences[@]}" >&2
printf '\nThese stale UI files can hide new Awtarchy controls even when the update itself succeeds.\n' >&2
printf 'Your personalized hyprland.lua is NOT part of this repair.\n\n' >&2

if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
  printf 'WARN: No interactive terminal is available; keeping all local Quickshell UI files unchanged.\n' >&2
  exit 0
fi

printf '  1. Keep all local UI files\n' >/dev/tty
printf '  2. Use current Awtarchy versions for all files above and create backups\n' >/dev/tty
printf '  3. Review each file individually\n' >/dev/tty
printf 'Choose [1]: ' >/dev/tty
IFS= read -r choice </dev/tty || choice=1

replace_one() {
  local rel="$1" baseline="${BASELINE_ROOT}/${rel}" live="${LIVE_ROOT}/${rel}"
  local backup="${live}.backup.${STAMP}" tmp=""

  [[ -f "$baseline" && ! -L "$baseline" ]] || return 0
  mkdir -p -- "$(dirname -- "$live")"

  if [[ -e "$live" || -L "$live" ]]; then
    cp -a -- "$live" "$backup"
    printf 'Backup: %s\n' "$backup"
  fi

  tmp="$(mktemp --tmpdir="$(dirname -- "$live")" '.awtarchy-ui.tmp.XXXXXX')"
  install -m "$(stat -c '%a' "$baseline")" -- "$baseline" "$tmp"
  mv -Tf -- "$tmp" "$live"
  printf 'Updated: %s\n' "$rel"
}

replaced=0
case "$choice" in
  2)
    for rel in "${differences[@]}"; do
      replace_one "$rel"
      replaced=1
    done
    ;;
  3)
    for rel in "${differences[@]}"; do
      printf '\n%s\n' "$rel" >/dev/tty
      printf '  1. Keep local\n' >/dev/tty
      printf '  2. Use current Awtarchy version and create backup\n' >/dev/tty
      printf 'Choose [1]: ' >/dev/tty
      IFS= read -r per_file </dev/tty || per_file=1
      if [[ "$per_file" == 2 ]]; then
        replace_one "$rel"
        replaced=1
      fi
    done
    ;;
  *)
    printf 'Kept local Quickshell UI files.\n'
    exit 0
    ;;
esac

if (( replaced == 1 )); then
  manager="${HOME_DIR}/.config/hypr/scripts/quickshell.sh"
  if [[ -f "$manager" ]]; then
    bash "$manager" restart || {
      printf 'WARN: Quickshell UI files were updated, but Quickshell could not be restarted automatically.\n' >&2
      exit 1
    }
  fi
fi
