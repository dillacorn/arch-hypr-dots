#!/usr/bin/env bash
set -euo pipefail

# ~/.config/hypr/scripts/portal_fixup.sh
#
# Ensures graphical-session.target is active before restarting the portal stack.
# This protects plain Hyprland sessions from xdg-desktop-portal units using:
#
#   Requisite=graphical-session.target
#
# The compatibility service is installed proactively, so systems remain
# protected before and after xdg-desktop-portal package upgrades.

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
user_unit_dir="$config_home/systemd/user"

helper_unit_name="awtarchy-graphical-session.service"
helper_unit_file="$user_unit_dir/$helper_unit_name"

legacy_dropin_dir="$user_unit_dir/xdg-desktop-portal.service.d"
legacy_dropin_file="$legacy_dropin_dir/90-awtarchy-non-uwsm.conf"

export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Hyprland}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"

command -v systemctl >/dev/null 2>&1 || exit 0
systemctl --user show-environment >/dev/null 2>&1 || exit 0

unit_exists() {
    local state

    state="$(
        systemctl --user show "$1" \
            --property=LoadState \
            --value 2>/dev/null || true
    )"

    [[ -n "$state" && "$state" != "not-found" ]]
}

restart_if_present() {
    if unit_exists "$1"; then
        systemctl --user restart "$1" >/dev/null 2>&1 || true
    fi
}

# Advertise the Awtarchy dark appearance preference through desktop settings.
# Applications remain free to use their own supported toolkit style.
if command -v gsettings >/dev/null 2>&1; then
    if gsettings writable org.gnome.desktop.interface color-scheme 2>/dev/null | grep -qx 'true'; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark >/dev/null 2>&1 || true
    fi
fi

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd \
        WAYLAND_DISPLAY \
        XDG_CURRENT_DESKTOP \
        XDG_SESSION_DESKTOP \
        XDG_SESSION_TYPE \
        HYPRLAND_INSTANCE_SIGNATURE >/dev/null 2>&1 || true
fi

systemctl --user import-environment \
    WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_DESKTOP \
    XDG_SESSION_TYPE \
    HYPRLAND_INSTANCE_SIGNATURE >/dev/null 2>&1 || true

if unit_exists graphical-session.target; then
    mkdir -p "$user_unit_dir"

    true_path="$(type -P true || true)"
    true_path="${true_path:-/usr/bin/true}"

    helper_content="$(
        printf '%s\n' \
            '[Unit]' \
            'Description=Awtarchy graphical session compatibility' \
            'Requires=graphical-session.target' \
            'After=graphical-session.target' \
            'Before=xdg-desktop-portal.service' \
            'PartOf=graphical-session.target' \
            '' \
            '[Service]' \
            'Type=oneshot' \
            "ExecStart=$true_path" \
            'RemainAfterExit=yes'
    )"

    if [[ ! -f "$helper_unit_file" ]] ||
        ! cmp -s "$helper_unit_file" <(printf '%s\n' "$helper_content"); then
        printf '%s\n' "$helper_content" > "$helper_unit_file"
        chmod 644 "$helper_unit_file"
    fi
fi

# Remove the older Awtarchy workaround after replacing it with the independent
# graphical-session activator. Never remove any other user portal overrides.
if [[ -f "$legacy_dropin_file" ]]; then
    rm -f "$legacy_dropin_file"
    rmdir --ignore-fail-on-non-empty "$legacy_dropin_dir" 2>/dev/null || true
fi

# Always reload. This also handles files installed or updated before the current
# systemd user manager noticed them.
systemctl --user daemon-reload >/dev/null 2>&1 || true

# Starting this service pulls in graphical-session.target as a dependency.
# This works even though graphical-session.target refuses direct manual starts.
if unit_exists "$helper_unit_name"; then
    systemctl --user reset-failed \
        "$helper_unit_name" >/dev/null 2>&1 || true

    systemctl --user start \
        "$helper_unit_name" >/dev/null 2>&1 || true
fi

systemctl --user reset-failed \
    graphical-session.target \
    xdg-desktop-portal.service \
    xdg-desktop-portal-hyprland.service \
    xdg-desktop-portal-gtk.service >/dev/null 2>&1 || true

restart_if_present xdg-desktop-portal-hyprland.service
restart_if_present xdg-desktop-portal-gtk.service
restart_if_present xdg-desktop-portal.service

exit 0
