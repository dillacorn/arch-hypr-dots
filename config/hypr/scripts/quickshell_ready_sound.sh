#!/usr/bin/env bash
# Compatibility name retained for Hyprland autostart.
# Wait for Awtarchy Quickshell, recover an early NetworkManager startup race,
# optionally wait for USB audio refresh, then play the login sound.

set -euo pipefail

WAIT_SHELL_SECS="${WAIT_SHELL_SECS:-30}"
SHELL_POLL_SECS="${SHELL_POLL_SECS:-0.05}"
NETWORK_WAIT_SECS="${NETWORK_WAIT_SECS:-15}"
REFRESH_DETECT_WINDOW_SECS="${REFRESH_DETECT_WINDOW_SECS:-8}"
WAIT_AUDIO_SECS="${WAIT_AUDIO_SECS:-20}"
AUDIO_POLL_SECS="${AUDIO_POLL_SECS:-0.10}"
QUIET_POLLS="${QUIET_POLLS:-2}"
SOUND_FILE="${SOUND_FILE:-$HOME/.config/hypr/sounds/awtarchy-login.mp3}"
QUICKSHELL_MANAGER="${QUICKSHELL_MANAGER:-$HOME/.config/hypr/scripts/quickshell.sh}"
USB_REFRESH_LOCK_FILE="${USB_REFRESH_LOCK_FILE:-/run/awtarchy/usb-refresh/$(id -u).active}"
SCRIPT_LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/quickshell_ready_sound.lock"

have() { command -v "$1" >/dev/null 2>&1; }

shell_ready() {
    qs -c awtarchy ipc call control ping >/dev/null 2>&1
}

wait_for_shell() {
    local end
    end=$(( $(date +%s) + WAIT_SHELL_SECS ))
    while (( $(date +%s) < end )); do
        shell_ready && return 0
        sleep "$SHELL_POLL_SECS"
    done
    return 1
}

network_manager_installed() {
    have systemctl && systemctl cat --no-pager NetworkManager.service >/dev/null 2>&1
}

network_manager_active() {
    have systemctl && systemctl is-active --quiet NetworkManager.service
}

wait_for_network_manager() {
    local end
    network_manager_installed || return 1
    end=$(( $(date +%s) + NETWORK_WAIT_SECS ))
    while (( $(date +%s) < end )); do
        network_manager_active && return 0
        sleep "$SHELL_POLL_SECS"
    done
    return 1
}

default_sink_name() {
    have wpctl || return 1
    wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '
        /node\.name =/        { print $2; found=1; exit }
        /node\.nick =/        { if (nick == "") nick=$2 }
        /node\.description =/ { if (desc == "") desc=$2 }
        END {
            if (!found) {
                if (nick != "") print nick
                else if (desc != "") print desc
            }
        }
    '
}

default_sink_is_real() {
    local sink
    sink="$(default_sink_name || true)"
    [[ -n "$sink" && "$sink" != "auto_null" ]]
}

refresh_lock_active() {
    local pid
    [[ -r "$USB_REFRESH_LOCK_FILE" ]] || return 1
    pid="$(tr -dc '0-9' <"$USB_REFRESH_LOCK_FILE" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ && -d "/proc/$pid" ]]
}

wait_for_optional_refresh_cycle() {
    local detect_end settle_end quiet=0 seen=0
    detect_end=$(( $(date +%s) + REFRESH_DETECT_WINDOW_SECS ))
    while (( $(date +%s) < detect_end )); do
        if refresh_lock_active; then seen=1; break; fi
        sleep "$AUDIO_POLL_SECS"
    done
    (( seen == 1 )) || return 0

    settle_end=$(( $(date +%s) + WAIT_AUDIO_SECS ))
    while (( $(date +%s) < settle_end )); do
        if refresh_lock_active; then
            quiet=0
        else
            ((quiet += 1)) || true
            (( quiet >= QUIET_POLLS )) && return 0
        fi
        sleep "$AUDIO_POLL_SECS"
    done
    return 1
}

play_with_retry() {
    local end
    [[ -f "$SOUND_FILE" ]] || return 1
    have pw-play || return 1
    end=$(( $(date +%s) + WAIT_AUDIO_SECS ))
    while (( $(date +%s) < end )); do
        if default_sink_is_real && pw-play "$SOUND_FILE" >/dev/null 2>&1; then return 0; fi
        sleep "$AUDIO_POLL_SECS"
    done
    return 1
}

if have flock; then
    exec 9>"$SCRIPT_LOCK_FILE"
    flock -n 9 || exit 0
fi

network_backend_may_need_restart=0
if network_manager_installed && ! network_manager_active; then
    network_backend_may_need_restart=1
fi

wait_for_shell || exit 0

if (( network_backend_may_need_restart == 1 )); then
    if wait_for_network_manager && [[ -x "$QUICKSHELL_MANAGER" ]]; then
        "$QUICKSHELL_MANAGER" restart >/dev/null 2>&1 || exit 0
        wait_for_shell || exit 0
    fi
fi

wait_for_optional_refresh_cycle || exit 0
play_with_retry || exit 0
