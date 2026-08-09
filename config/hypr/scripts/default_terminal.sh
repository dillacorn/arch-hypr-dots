#!/usr/bin/env bash
# Open a command in the user's preferred terminal without assuming Alacritty.

set -euo pipefail

window_class="terminal-command"
hold_open=0

while (( $# > 0 )); do
  case "$1" in
    --class)
      [[ -n ${2:-} ]] || { printf '%s\n' '--class requires a value' >&2; exit 2; }
      window_class="$2"
      shift 2
      ;;
    --hold)
      hold_open=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

(( $# > 0 )) || {
  printf 'usage: %s [--class NAME] [--hold] -- COMMAND [ARG...]\n' "${0##*/}" >&2
  exit 2
}

command_args=("$@")
if (( hold_open )); then
  printf -v command_line '%q ' "${command_args[@]}"
  command_args=(bash -lc "${command_line}status=\$?; printf '\\n[command finished: %s]\\nPress ENTER to close...' \"\$status\"; IFS= read -r _; exit \"\$status\"")
fi

terminal_args=()
if [[ -n ${TERMINAL:-} ]]; then
  # Respect the conventional user preference. Simple arguments are supported;
  # shell evaluation is deliberately avoided.
  read -r -a terminal_args <<<"$TERMINAL"
  if (( ${#terminal_args[@]} == 0 )) || ! command -v "${terminal_args[0]}" >/dev/null 2>&1; then
    terminal_args=()
  fi
fi

if (( ${#terminal_args[@]} == 0 )); then
  for candidate in footclient foot kitty alacritty wezterm konsole gnome-terminal xfce4-terminal xterm; do
    if command -v "$candidate" >/dev/null 2>&1; then
      terminal_args=("$candidate")
      break
    fi
  done
fi

(( ${#terminal_args[@]} > 0 )) || {
  printf '%s\n' 'No supported terminal emulator was found.' >&2
  exit 127
}

terminal_name="${terminal_args[0]##*/}"
case "$terminal_name" in
  foot|footclient)
    exec "${terminal_args[@]}" --app-id="$window_class" "${command_args[@]}"
    ;;
  kitty)
    exec "${terminal_args[@]}" --class "$window_class" "${command_args[@]}"
    ;;
  alacritty)
    exec "${terminal_args[@]}" --class "$window_class" -T "$window_class" -e "${command_args[@]}"
    ;;
  wezterm)
    exec "${terminal_args[@]}" start --class "$window_class" -- "${command_args[@]}"
    ;;
  konsole)
    exec "${terminal_args[@]}" --appname "$window_class" -e "${command_args[@]}"
    ;;
  gnome-terminal)
    exec "${terminal_args[@]}" --title="$window_class" -- "${command_args[@]}"
    ;;
  xfce4-terminal)
    exec "${terminal_args[@]}" --title="$window_class" --execute "${command_args[@]}"
    ;;
  xterm)
    exec "${terminal_args[@]}" -class "$window_class" -T "$window_class" -e "${command_args[@]}"
    ;;
  *)
    exec "${terminal_args[@]}" -e "${command_args[@]}"
    ;;
esac
