#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
HYPRLOCK_CONF="${ROOT}/config/hypr/hyprlock.conf"
HYPRIDLE="${ROOT}/config/hypr/hypridle.conf"
HYPRLAND="${ROOT}/config/hypr/hyprland.lua"
HYPRIDLE_ACTION="${ROOT}/config/hypr/scripts/hypridle_action.sh"
ANIMATIONS="${ROOT}/config/hypr/scripts/toggle_animations.sh"
POWER_MENU="${ROOT}/config/quickshell/awtarchy/PowerMenu.qml"
BAR="${ROOT}/config/quickshell/awtarchy/Bar.qml"
MANAGER="${ROOT}/config/hypr/scripts/awtarchy_lock.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

[[ ! -e "$HYPRLOCK_CONF" && ! -L "$HYPRLOCK_CONF" ]] \
    || fail 'retired managed hyprlock.conf still exists in the target'

if awk '
    /^declare -a PKG_GROUPS=\(/ { in_groups=1; next }
    in_groups && /^[[:space:]]*\)[[:space:]]*$/ { exit }
    in_groups && /(^|[[:space:]])hyprlock([[:space:]"$]|$)/ { found=1 }
    END { exit(found ? 0 : 1) }
' "$RUNTIME"; then
    fail 'Hyprlock remains in the installer package catalog'
fi

require_text "$HYPRIDLE" 'lock_cmd = ~/.config/hypr/scripts/awtarchy_lock.sh lock' \
    'Hypridle does not use the native Awtarchy locker'
reject_text "$HYPRIDLE" 'hyprlock' \
    'Hypridle still references Hyprlock'

reject_text "$HYPRLAND" 'hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/awtarchy_lock.sh lock"), {})' \
    'native locker steals SUPER + L from normal movement bindings'
require_text "$HYPRLAND" 'hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})' \
    'SUPER + P no longer opens the power menu'
reject_text "$HYPRLAND" '/usr/bin/hyprlock' \
    'Hyprland still grants a Hyprlock permission'
reject_text "$HYPRLAND" 'exec_cmd("hyprlock")' \
    'Hyprland still launches Hyprlock'

require_text "$POWER_MENU" 'command: "~/.config/hypr/scripts/awtarchy_lock.sh lock && ~/.config/hypr/scripts/awtarchy_lock.sh wait-secure 5"' \
    'Power Menu Lock does not keep the overlay until native lock secure confirmation'
require_text "$POWER_MENU" 'command: "~/.config/hypr/scripts/awtarchy_lock.sh hibernate"' \
    'Power Menu Hibernate does not use secure lock-then-hibernate'
require_text "$POWER_MENU" 'command: "~/.config/hypr/scripts/awtarchy_lock.sh suspend"' \
    'Power Menu Suspend does not use secure lock-then-suspend'
reject_text "$POWER_MENU" 'hyprlock' \
    'Power Menu still references Hyprlock'
reject_text "$POWER_MENU" 'sleep 1' \
    'Power Menu still uses a timing guess before a power transition'

require_text "$MANAGER" 'hibernate)' \
    'lock manager has no hibernate operation'
require_text "$MANAGER" 'suspend)' \
    'lock manager has no suspend operation'
require_text "$MANAGER" 'wait_secure 5' \
    'power operations do not require compositor-secure lock confirmation'

require_text "$HYPRIDLE_ACTION" 'awtarchy_lock.sh' \
    'Hypridle sleep actions do not use the native lock manager'
reject_text "$ANIMATIONS" 'hyprlock' \
    'animation toggle still edits retired Hyprlock configuration'
reject_text "$BAR" '"hyprlock"' \
    'bar task filtering still contains the retired Hyprlock class'

reject_text "$RUNTIME" 'Git testing keeps Hyprlock installed as an emergency lock fallback.' \
    'Git-testing still suppresses the Hyprlock migration'

printf 'PASS: native Quickshell lockscreen production cutover contracts\n'
