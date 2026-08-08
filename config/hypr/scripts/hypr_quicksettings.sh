#!/usr/bin/env bash
# Awtarchy Quick Settings entrypoint.
# The existing UI implementation is kept in hypr_quicksettings_core.sh while
# this entrypoint wires Quickshell-specific nested controls into it.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/hypr_quicksettings_core.sh"
BAR_SETTINGS_SCRIPT="${SCRIPT_DIR}/quickshell_bar_settings.sh"

[[ -r "$CORE_SCRIPT" ]] || {
  printf 'missing: %s\n' "$CORE_SCRIPT" >&2
  exit 1
}

# Load the established Quick Settings implementation without executing its
# final main call. Overrides below remain small and isolated.
# shellcheck disable=SC1090
source <(sed '/^main "\$@"$/d' "$CORE_SCRIPT")

launch_terminal() {
  local self
  self="$(readlink -f "${BASH_SOURCE[0]}")"

  if close_existing_quicksettings; then
    return 0
  fi

  if [[ -t 1 ]]; then
    exec "$self" --ui
  fi

  if have_cmd kitty; then
    exec kitty --class "$TERM_CLASS" -e "$self" --ui
  fi
  if have_cmd foot; then
    exec foot --app-id="$TERM_CLASS" "$self" --ui
  fi
  if have_cmd alacritty; then
    exec alacritty --class "$TERM_CLASS" -e "$self" --ui
  fi
  if have_cmd wezterm; then
    exec wezterm start --class "$TERM_CLASS" -- "$self" --ui
  fi
  if have_cmd konsole; then
    exec konsole --appname "$TERM_CLASS" -e "$self" --ui
  fi
  if have_cmd gnome-terminal; then
    exec gnome-terminal --title="$TERM_CLASS" -- "$self" --ui
  fi

  exec xterm -T "$TERM_CLASS" -e "$self" --ui
}

select_bar() {
  if [[ ! -x "$BAR_SETTINGS_SCRIPT" ]]; then
    MSG='bar settings: helper not found'
    return 1
  fi

  "$BAR_SETTINGS_SCRIPT" --embedded || true
  mouse_enable
  printf '\033[?25l'
  refresh_bar
  MSG="bar: $(format_bar)"
}

main "$@"
