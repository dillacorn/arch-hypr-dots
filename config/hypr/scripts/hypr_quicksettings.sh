#!/usr/bin/env bash
# Awtarchy Quick Settings entrypoint.
# The existing UI implementation is kept in hypr_quicksettings_core.sh while
# this entrypoint wires Quickshell-specific nested controls into it.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="${SCRIPT_DIR}/hypr_quicksettings_core.sh"
APPLICATION_SETTINGS_SCRIPT="${SCRIPT_DIR}/quickshell_application_settings.sh"
STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/quickshell-state.json"

[[ -r "$CORE_SCRIPT" ]] || {
  printf 'missing: %s\n' "$CORE_SCRIPT" >&2
  exit 1
}

# Load the established Quick Settings implementation without executing its
# final main call. Overrides below remain small and isolated.
# shellcheck disable=SC1090
source <(sed '/^main "\$@"$/d' "$CORE_SCRIPT")

# Keep the established core behavior while inserting Quickshell-specific
# nested editors into the visible menu.
MENU_ITEMS=(
  "Brightness"
  "Display"
  "Bar"
  "Application View - Edit spawn dimensions"
  "Night Light"
  "Vibrance"
  "Submap"
  "Wallpaper Picker"
  "sched-ext"
  "Stop sched-ext"
)

eval "$(declare -f do_action | sed '1s/^do_action /core_do_action /')"

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
  if ! "$QUICKSHELL_SCRIPT" start >/dev/null 2>&1; then
    MSG='bar settings: Quickshell failed to start'
    return 1
  fi

  if qs -c awtarchy ipc call barsettings open >/dev/null 2>&1; then
    MSG='bar settings opened'
  else
    MSG='bar settings: native editor unavailable'
    return 1
  fi
}

prepare_application_view_state() {
  local tmp

  "$QUICKSHELL_SCRIPT" dump-state >/dev/null 2>&1 || return 1
  [[ -s "$STATE_FILE" ]] || return 1

  if jq -e '.application_view.customized == true' "$STATE_FILE" >/dev/null 2>&1; then
    return 0
  fi

  tmp="${STATE_FILE}.tmp.$$"
  jq '
    .application_view = {
      width: 520,
      height: 604,
      text_size: 14,
      icon_size: 18,
      customized: true
    }
    | .monitors = (.monitors // {})
    | .monitors |= with_entries(.value |= del(.application_view))
  ' "$STATE_FILE" >"$tmp"
  mv -f "$tmp" "$STATE_FILE"
}

select_application_view() {
  if [[ ! -x "$APPLICATION_SETTINGS_SCRIPT" ]]; then
    MSG='Application View settings: helper not found'
    return 1
  fi

  prepare_application_view_state || true
  "$APPLICATION_SETTINGS_SCRIPT" --embedded || true
  mouse_enable
  printf '\033[?25l'
  MSG='Application View settings updated'
}

do_action() {
  if [[ "${MENU_ITEMS[$SEL]}" == Application\ View* ]]; then
    select_application_view
    return
  fi
  core_do_action
}

main "$@"
