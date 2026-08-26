#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
HYPR="${ROOT_DIR}/config/hypr/hyprland.lua"
AGENT_DIR="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent"
LAUNCHER="${AGENT_DIR}/launcher.sh"
AGENT="${AGENT_DIR}/agent.py"
TUI="${AGENT_DIR}/tui.py"
SERVICE="${AGENT_DIR}/awtarchy-polkit-agent.service"

fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
reject_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 still contains: $2"; }
line_number() { grep -nF -- "$2" "$1" | head -n1 | cut -d: -f1; }
require_order() {
    local a b
    a="$(line_number "$1" "$2")" || fail "$1 missing ordered marker: $2" || return 1
    b="$(line_number "$1" "$3")" || fail "$1 missing ordered marker: $3" || return 1
    (( a < b )) || fail "$1 has unsafe ordering: $2 must precede $3"
}

for file in "$RUNTIME" "$HYPR" "$LAUNCHER" "$AGENT" "$TUI" "$SERVICE"; do
    [[ -f $file ]] || fail "missing $file"
done
bash -n "$RUNTIME"
bash -n "$LAUNCHER"
python3 -m py_compile "$AGENT" "$TUI"

# Session startup and packages.
require_contains "$HYPR" 'hl.exec_cmd("/usr/bin/systemctl --user restart awtarchy-polkit-agent.service")'
reject_contains "$HYPR" '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1'
reject_contains "$HYPR" 'special:awtarchy-polkit-agent'
require_contains "$RUNTIME" '"Utilities:upower polkit python-gobject gnome-keyring '
require_contains "$RUNTIME" 'local -a required=(quickshell upower playerctl hyprland-qt-support polkit python-gobject) missing=()'

# Root-owned runtime installation and exact GNOME migration/fallback.
require_contains "$RUNTIME" 'AWTARCHY_POLKIT_RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"'
require_contains "$RUNTIME" 'AWTARCHY_POLKIT_SERVICE_DEST="/usr/local/lib/systemd/user/awtarchy-polkit-agent.service"'
require_contains "$RUNTIME" 'install_awtarchy_polkit_agent_runtime()'
require_contains "$RUNTIME" 'install -m 0644 -o root -g root'
require_contains "$RUNTIME" 'install -m 0755 -o root -g root'
require_contains "$RUNTIME" 'migrate_awtarchy_polkit_autostart()'
require_contains "$RUNTIME" 'AWTARCHY_GNOME_POLKIT_BIN="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"'
require_contains "$RUNTIME" 'restore_legacy_polkit_gnome'

# Idle service is the isolated Python backend itself, not a parked terminal.
require_contains "$RUNTIME" 'awtarchy_polkit_verify_service_process()'
require_contains "$RUNTIME" 'expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)"'
require_contains "$RUNTIME" "mapfile -d '' -t argv <\"/proc/\${pid}/cmdline\""
require_contains "$RUNTIME" '"${AWTARCHY_POLKIT_RUNTIME_DIR}/agent.py"'
reject_contains "$RUNTIME" '[[ "$resolved" == "$expected_alacritty" ]] || return 1'

# Alacritty is transient and receives one anonymous inherited socket endpoint.
require_contains "$AGENT" 'socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)'
require_contains "$AGENT" 'pass_fds=(child_fd,)'
require_contains "$AGENT" 'frontend_process'
require_contains "$AGENT" 'frontend_socket'
require_contains "$AGENT" '"--class"'
require_contains "$AGENT" 'f"{APP_ID},{APP_ID}"'
require_contains "$LAUNCHER" 'AWTARCHY_POLKIT_ALACRITTY_OPTIONS="$appearance_text"'
require_contains "$LAUNCHER" '"$PYTHON" -I "$AGENT"'
reject_contains "$LAUNCHER" '-e "$SYSTEMD_CAT"'

# Preserve delayed, ownership-gated package removal ordering.
require_contains "$RUNTIME" 'managed_package_recorded polkit-gnome'
require_contains "$RUNTIME" 'pacman -Rns --noconfirm polkit-gnome'
require_contains "$RUNTIME" 'polkit_remove_legacy_ready=1'
require_order "$RUNTIME" '  remove_quickshell_update_legacy_packages' '    remove_legacy_polkit_gnome_package'
require_order "$RUNTIME" '    remove_legacy_polkit_gnome_package' '  commit_baseline "$target_home" "$source_label" "$active_theme"'

reject_contains "$SERVICE" 'WantedBy=default.target'
require_contains "$LAUNCHER" "IFS=' ' read -r uid mode type"

printf '%s\n' 'headless/transient terminal Polkit production integration contract passed'
