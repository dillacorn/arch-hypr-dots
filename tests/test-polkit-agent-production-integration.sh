#!/usr/bin/env bash
# Production integration contract for replacing polkit-gnome with Awtarchy's agent.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="${ROOT_DIR}/local/share/awtarchy/awtarchy-runtime.sh"
HYPR="${ROOT_DIR}/config/hypr/hyprland.lua"
LAUNCHER="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"
SERVICE="${ROOT_DIR}/config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service"

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

for file in "$RUNTIME" "$HYPR" "$LAUNCHER" "$SERVICE"; do
    [[ -f $file ]] || fail "missing $file"
done

bash -n "$RUNTIME"
bash -n "$LAUNCHER"

# Hyprland owns session timing: import the Wayland/Hyprland environment first,
# then restart the supervised Awtarchy agent. GNOME must not also autostart.
require_contains "$HYPR" 'hl.exec_cmd("/usr/bin/systemctl --user restart awtarchy-polkit-agent.service")'
reject_contains "$HYPR" '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1'

# Fresh installs must not pull the retired GNOME authentication agent.
reject_contains "$RUNTIME" 'Utilities:upower polkit-gnome '

# The real runtime/service are installed root-owned outside HOME from the
# immutable release/git-testing source tree, not from ~/.config.
require_contains "$RUNTIME" 'install_awtarchy_polkit_agent_runtime()'
require_contains "$RUNTIME" 'AWTARCHY_POLKIT_RUNTIME_DIR="/usr/local/libexec/awtarchy/polkit-agent"'
require_contains "$RUNTIME" 'AWTARCHY_POLKIT_SERVICE_DEST="/usr/local/lib/systemd/user/awtarchy-polkit-agent.service"'
require_contains "$RUNTIME" 'install -m 0644 -o root -g root'
require_contains "$RUNTIME" 'install -m 0755 -o root -g root'
require_contains "$RUNTIME" 'install_awtarchy_polkit_agent_runtime "$REPO_DIR"'
require_contains "$RUNTIME" 'install_awtarchy_polkit_agent_runtime "$repo_dir"'
reject_contains "$RUNTIME" '${HOME_DIR}/.config/hypr/scripts/awtarchy-polkit-agent/shell.qml'

# Preserve customized Hyprland configs by migrating only the exact retired
# Awtarchy GNOME line when the normal three-way update keeps the local file.
require_contains "$RUNTIME" 'migrate_awtarchy_polkit_autostart()'
require_contains "$RUNTIME" '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1'
require_contains "$RUNTIME" '/usr/bin/systemctl --user restart awtarchy-polkit-agent.service'

# Activation must stop only the exact GNOME binary, start the supervised agent,
# verify Quickshell is the service MainPID, and restore GNOME on activation failure.
require_contains "$RUNTIME" 'activate_awtarchy_polkit_agent()'
require_contains "$RUNTIME" 'AWTARCHY_GNOME_POLKIT_BIN="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"'
require_contains "$RUNTIME" '/proc/${pid}/exe'
require_contains "$RUNTIME" 'systemctl --user start "$AWTARCHY_POLKIT_SERVICE_NAME"'
require_contains "$RUNTIME" 'restore_legacy_polkit_gnome'

# Only remove polkit-gnome when Awtarchy recorded ownership of the package.
require_contains "$RUNTIME" 'remove_legacy_polkit_gnome_package()'
require_contains "$RUNTIME" 'managed_package_recorded polkit-gnome'
require_contains "$RUNTIME" 'pacman -Rns --noconfirm polkit-gnome'

# This unit is started explicitly after Hyprland imports its environment. Do not
# globally enable it at default.target where it can race WAYLAND_DISPLAY setup.
reject_contains "$SERVICE" 'WantedBy=default.target'

# Runtime trust checks must parse stat output independently of the global IFS.
require_contains "$LAUNCHER" "IFS=' ' read -r uid mode type"

printf '%s\n' 'Polkit production integration contract passed'
