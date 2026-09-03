# shellcheck shell=bash
# github.com/dillacorn/awtarchy
# ~/.bashrc - User-specific Bash configuration

# Only run if shell is interactive
[[ $- != *i* ]] && return

# --- Aliases ---
# Colorize common commands for better visibility
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Flatpak alias to always use --user flag on non-Btrfs systems
alias flatpak='flatpak --user'

# Shortcut to launch Hyprland under Wayland session
alias hypr='XDG_SESSION_TYPE=wayland exec start-hyprland'

# --- Environment Variables ---
# Default editor for command line text editing
export EDITOR=/usr/bin/micro

# GTK theme for graphical apps
export GTK_THEME=Materia-dark

# --- Prompt ---
# PS1 defines the command prompt appearance
# \w = full current working directory path
# \$ = shows '#' for root, '$' for normal user
# Icon can be customized, examples: 󰞷 (penguin), , λ, etc.
PS1='󰞷 \w\$ '

# --- Functions ---

# Run a command in the background, redirecting output to a log file
background() {
  if [ $# -lt 1 ]; then
    echo "Usage: background <command> [args...]"
    return 1
  fi

  # Sanitize command name for log filename (replace '/' with '_')
  local cmd_name="${1//\//_}"

  # Run command detached from terminal, log output in ~/.cache/
  nohup "$@" > ~/.cache/"$cmd_name".log 2>&1 < /dev/null &

  echo "$1 started in background. Logs: ~/.cache/$cmd_name.log"
}

dryrun() {
    # Check if file exists and is readable
    if [[ ! -f "$1" || ! -r "$1" ]]; then
        echo -e "\033[1;31m✘ Error: '$1' is not a readable script file\033[0m" >&2
        return 1
    fi

    local script_name
    script_name=$(basename "$1")
    echo -e "\n\033[1;33m🏗️  DRY RUN: \033[1;37m${script_name}\033[0m"

    # Syntax & lint check using ShellCheck
    echo -e "\n\033[1;34m🔎 ShellCheck Analysis:\033[0m"
    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck "$1"; then
            echo -e "\033[1;32m✓ ShellCheck passed (no issues)\033[0m"
        else
            echo -e "\n\033[1;31m✘ ShellCheck found issues\033[0m" >&2
            return 1
        fi
    else
        echo -e "\033[1;31m✘ ShellCheck is not installed. Install it first:\033[0m"
        echo "  pacman -S shellcheck   # Arch"
        echo "  apt install shellcheck # Debian/Ubuntu"
        return 1
    fi

    # Command analysis with improved detection
    echo -e "\n\033[1;34m📊 Operations Analysis:\033[0m"

    declare -A categories=(
        ["🔧 System Modifications"]='sudo|install|ch(mod|own)|ufw|mount'
        ["📦 Package Management"]='yay|pacman|makepkg|flatpak|dnf|apt'
        ["🗂️  File Operations"]='rm\>|mv\>|cp\>|mkdir|ln\>'
        ["🔄 Git Operations"]='git\s+(clone|push|pull|reset|checkout)'
        ["🌐 Network Operations"]='curl\>|wget\>|ssh\>|scp\>'
    )

    local found_operations=false
    for category in "${!categories[@]}"; do
        local matches
        matches=$(grep -E --color=always -n "${categories[$category]}" "$1")
        if [[ -n "$matches" ]]; then
            found_operations=true
            echo -e "\n\033[1;35m${category}:\033[0m"
            echo "$matches" | while read -r line; do
                echo -e "  \033[1;36mLine ${line%%:*}\033[0m: ${line#*:}"
            done
        fi
    done

    if ! $found_operations; then
        echo -e "\033[1;37mNo potentially impactful operations found\033[0m"
    fi

    echo -e "\n\033[1;33m💡 Dry run complete. To execute:\033[0m\n\033[1;32m./${script_name}\033[0m"
}

# Retire public AurGuard commands from shells that source this file after an update.
unset -f \
  aurguard aurguardtest aurverify aurinstall aurup aurunsafe aurcheck \
  aurremove auruninstall yay paru 2>/dev/null

# --- AUR helper policy ---
# Upstream aur-scanner owns AUR scanning and installation. Keep yay/paru useful
# for read-only inspection while preventing accidental package transactions.
_awtarchy_aur_helper_is_read_only() {
  (( $# > 0 )) || return 1

  local first="$1"
  local arg

  case "$first" in
    -Q*|--query|--query=*|-P*|--show-stats|--help|-h|--version|-V|\
    -Ss|-Si|-Sl|-Sg)
      ;;
    *)
      return 1
      ;;
  esac

  for arg in "$@"; do
    case "$arg" in
      -Ss|-Si|-Sl|-Sg)
        ;;
      -S*|-R*|-U*|-D*|-F*|-G*|-Y*|\
      --sync|--sync=*|--remove|--remove=*|--upgrade|--upgrade=*|\
      --database|--database=*|--files|--files=*|--getpkgbuild|--getpkgbuild=*|\
      --yay|--yay=*|--clean|--clean=*|--gendb|--save)
        return 1
        ;;
    esac
  done

  return 0
}

_awtarchy_run_aur_helper() {
  local helper="$1"
  shift || true

  if ! type -P "$helper" >/dev/null 2>&1; then
    printf '%s is not installed or not in PATH.\n' "$helper" >&2
    return 127
  fi

  if _awtarchy_aur_helper_is_read_only "$@"; then
    command "$helper" "$@"
    return $?
  fi

  printf 'Awtarchy blocks package-changing %s transactions.\n' "$helper" >&2
  printf 'Install AUR packages with upstream aur-scanner instead:\n' >&2
  printf '  aur-scan install <package>\n' >&2
  printf 'Run aur-scan -h for upstream options.\n' >&2
  return 2
}

yay() {
  _awtarchy_run_aur_helper yay "$@"
}

paru() {
  _awtarchy_run_aur_helper paru "$@"
}

aurhelp() {
  if ! type -P aur-scan >/dev/null 2>&1; then
    printf 'aur-scan is unavailable. Install the aur-scanner package first.\n' >&2
    return 127
  fi
  command aur-scan -h
}

aur() {
  if (( $# != 0 )); then
    printf 'Usage: aur\n' >&2
    printf 'Use aur-scan directly for scanner commands.\n' >&2
    return 1
  fi
  aurhelp
}

aurinstalled() {
  local output

  if ! output=$(command pacman -Qm 2>/dev/null); then
    printf 'Unable to query installed foreign packages with pacman.\n' >&2
    return 1
  fi

  if [[ -z "$output" ]]; then
    printf 'No foreign/AUR packages are currently installed.\n'
    return 0
  fi

  printf 'Installed foreign/AUR packages and versions:\n'
  printf '%s\n' "$output"
}

sysupdate() {
  sudo pacman -Syu
}
