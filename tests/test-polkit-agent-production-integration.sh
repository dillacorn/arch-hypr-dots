#!/usr/bin/env bash
# Production integration contract for replacing polkit-gnome with Awtarchy's terminal agent.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
HYPR="${ROOT_DIR}/config/hypr/hyprland.lua"
AGENT_DIR="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent"
LAUNCHER="${AGENT_DIR}/launcher.sh"
AGENT="${AGENT_DIR}/agent.py"
TUI="${AGENT_DIR}/tui.py"
TERMINAL_CONFIG="${AGENT_DIR}/alacritty.toml"
SERVICE="${AGENT_DIR}/awtarchy-polkit-agent.service"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

require_contains() {
    local file="$1" pattern="$2"
    grep -Fq -- "$pattern" "$file" || fail "$file missing: $pattern"
}

reject_contains() {
    local file="$1" pattern="$2"
    if grep -Fq -- "$pattern" "$file"; then
        fail "$file still contains: $pattern"
    fi
}

line_number() {
    local file="$1" pattern="$2" line
    line="$(grep -nF -- "$pattern" "$file" | head -n1 | cut -d: -f1 || true)"
    [[ $line =~ ^[1-9][0-9]*$ ]] || fail "$file missing ordered marker: $pattern" || return 1
    printf '%s\n' "$line"
}

require_order() {
    local file="$1" first="$2" second="$3" first_line second_line
    first_line="$(line_number "$file" "$first")" || return 1
    second_line="$(line_number "$file" "$second")" || return 1
    (( first_line < second_line )) || fail "$file has unsafe ordering: $first must precede $second"
}

for file in "$RUNTIME" "$HYPR" "$LAUNCHER" "$AGENT" "$TUI" "$TERMINAL_CONFIG" "$SERVICE"; do
    [[ -f $file ]] || fail "missing $file"
done

bash -n "$RUNTIME"
bash -n "$LAUNCHER"
/usr/bin/python3 -m py_compile "$AGENT" "$TUI"

# Hyprland owns session timing: import the Wayland/Hyprland environment first,
# then restart the supervised headless Awtarchy agent. GNOME must not also autostart.
require_contains "$HYPR" 'hl.exec_cmd("/usr/bin/systemctl --user restart awtarchy-polkit-agent.service")'
reject_contains "$HYPR" '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1'
reject_contains "$HYPR" 'special:awtarchy-polkit-agent'

# Fresh installs must explicitly install both PolicyKit and PyGObject rather
# than rely on unrelated transitive dependencies. GNOME is retired.
require_contains "$RUNTIME" '"Utilities:upower polkit python-gobject gnome-keyring '
reject_contains "$RUNTIME" 'Utilities:upower polkit-gnome '

# Existing installs entering the migration must also receive the dependencies
# before the new agent is activated; fresh-install package ownership is not enough.
require_contains "$RUNTIME" 'local -a required=(quickshell upower playerctl hyprland-qt-support polkit python-gobject) missing=()'

# The real runtime/service are installed root-owned outside HOME from the
# immutable release/git-testing source tree, not from ~/.config.
require_contains "$RUNTIME" 'install_awtarchy_polkit_agent_runtime()'
require_contains "$RUNTIME" 'AWTARCHY_POLKIT_RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"'
require_contains "$RUNTIME" 'AWTARCHY_POLKIT_SERVICE_DEST="/usr/local/lib/systemd/user/awtarchy-polkit-agent.service"'
require_contains "$RUNTIME" 'install -m 0644 -o root -g root'
require_contains "$RUNTIME" 'install -m 0755 -o root -g root'
require_contains "$RUNTIME" 'install_awtarchy_polkit_agent_runtime "$REPO_DIR"'
require_contains "$RUNTIME" 'install_awtarchy_polkit_agent_runtime "$repo_dir"'
require_contains "$RUNTIME" 'agent.py'
require_contains "$RUNTIME" 'tui.py'
require_contains "$RUNTIME" 'alacritty.toml'
reject_contains "$RUNTIME" 'shell.qml'
reject_contains "$RUNTIME" 'window-guard.sh'

# Preserve customized Hyprland configs by migrating only the exact retired
# Awtarchy GNOME line when the normal three-way update keeps the local file.
require_contains "$RUNTIME" 'migrate_awtarchy_polkit_autostart()'
require_contains "$RUNTIME" '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1'
require_contains "$RUNTIME" '/usr/bin/systemctl --user restart awtarchy-polkit-agent.service'

# Activation must stop only the exact GNOME binary, start the supervised agent,
# verify the isolated Python backend itself is MainPID, and restore GNOME on failure.
require_contains "$RUNTIME" 'activate_awtarchy_polkit_agent()'
require_contains "$RUNTIME" 'AWTARCHY_GNOME_POLKIT_BIN="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"'
require_contains "$RUNTIME" '/proc/${pid}/exe'
require_contains "$RUNTIME" 'expected_python="$(/usr/bin/readlink -f -- /usr/bin/python3 2>/dev/null)"'
require_contains "$RUNTIME" 'mapfile -d '\''\'\''' -t argv'
require_contains "$RUNTIME" '"${AWTARCHY_POLKIT_RUNTIME_DIR}/agent.py"'
require_contains "$RUNTIME" 'systemctl --user start "$AWTARCHY_POLKIT_SERVICE_NAME"'
require_contains "$RUNTIME" 'restore_legacy_polkit_gnome'

# The backend owns PolicyKit registration while idle; Alacritty is created only
# for an active request over an anonymous inherited socketpair.
require_contains "$AGENT" 'socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)'
require_contains "$AGENT" 'pass_fds=(child_fd,)'
require_contains "$AGENT" 'frontend_process'
require_contains "$AGENT" 'frontend_socket'
require_contains "$LAUNCHER" 'AWTARCHY_POLKIT_ALACRITTY_OPTIONS="$appearance_text"'
reject_contains "$LAUNCHER" '-e "$SYSTEMD_CAT"'

# Only remove polkit-gnome when Awtarchy recorded ownership of the package.
require_contains "$RUNTIME" 'remove_legacy_polkit_gnome_package()'
require_contains "$RUNTIME" 'managed_package_recorded polkit-gnome'
require_contains "$RUNTIME" 'pacman -Rns --noconfirm polkit-gnome'

# Package removal is irreversible by the user-file rollback transaction. It must
# happen only after every rollback-capable live/config validation and cleanup has
# succeeded, only if live activation actually succeeded, and before the new
# baseline is committed.
require_contains "$RUNTIME" 'local polkit_migration_rc=0 polkit_activation_rc=0 polkit_remove_legacy_ready=0'
require_contains "$RUNTIME" 'polkit_remove_legacy_ready=1'
require_contains "$RUNTIME" 'if (( polkit_remove_legacy_ready == 1 )); then'
require_order "$RUNTIME" '  remove_quickshell_update_legacy_packages' '    remove_legacy_polkit_gnome_package'
require_order "$RUNTIME" '    remove_legacy_polkit_gnome_package' '  commit_baseline "$target_home" "$source_label" "$active_theme"'

# This unit is started explicitly after Hyprland imports its environment. Do not
# globally enable it at default.target where it can race WAYLAND_DISPLAY setup.
reject_contains "$SERVICE" 'WantedBy=default.target'

# Runtime trust checks must parse stat output independently of the global IFS.
require_contains "$LAUNCHER" "IFS=' ' read -r uid mode type"

printf '%s\n' 'headless/transient terminal Polkit production integration contract passed'
