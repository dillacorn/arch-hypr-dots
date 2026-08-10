#!/usr/bin/env bash
# WireGuard helper for the Awtarchy Quickshell Network flyout.

set -euo pipefail
export LC_ALL=C.UTF-8

VPN_DIR="${AWTARCHY_VPN_DIR:-${HOME}/vpn}"
EDITOR_TITLE="Awtarchy VPN Config Editor"
EDITOR_CLASS="awtarchy-vpn-editor"

mkdir -p -- "$VPN_DIR"
chmod 0700 "$VPN_DIR" 2>/dev/null || true

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

valid_profile_name() {
    local name="$1"
    [[ "$name" =~ ^[A-Za-z0-9_=+.-]{1,15}$ ]]
}

profile_conf() {
    local name="$1"
    valid_profile_name "$name" || fail "Invalid WireGuard profile name: $name"
    local conf="${VPN_DIR}/${name}.conf"
    [[ -f "$conf" ]] || fail "WireGuard profile not found: $conf"
    printf '%s\n' "$conf"
}

profile_active() {
    local name="$1"
    command -v ip >/dev/null 2>&1 || return 1
    ip -d link show dev "$name" 2>/dev/null | grep -q 'wireguard'
}

list_profiles() {
    command -v jq >/dev/null 2>&1 || fail "jq is required"

    local json='[]' conf name active
    shopt -s nullglob
    for conf in "$VPN_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        name="$(basename -- "$conf" .conf)"
        valid_profile_name "$name" || continue
        active=false
        profile_active "$name" && active=true
        json="$(
            jq -cn \
                --argjson current "$json" \
                --arg name "$name" \
                --arg path "$conf" \
                --argjson active "$active" \
                '$current + [{name:$name,path:$path,active:$active}]'
        )"
    done
    printf '%s\n' "$json"
}

run_privileged_wg_quick() {
    local action="$1" conf="$2"
    local wg_quick
    wg_quick="$(command -v wg-quick || true)"
    [[ -n "$wg_quick" ]] || fail "wg-quick is unavailable. Install wireguard-tools."

    if command -v pkexec >/dev/null 2>&1; then
        exec pkexec "$wg_quick" "$action" "$conf"
    fi

    if command -v alacritty >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        exec alacritty --title "Awtarchy WireGuard" -e sudo "$wg_quick" "$action" "$conf"
    fi

    fail "A privilege prompt is required but neither pkexec nor an Alacritty+sudo fallback is available."
}

edit_profile() {
    local conf="$1"
    command -v alacritty >/dev/null 2>&1 || fail "Alacritty is required for the protected VPN editor."
    command -v micro >/dev/null 2>&1 || fail "micro is required for the protected VPN editor."
    exec alacritty --class "${EDITOR_CLASS},${EDITOR_CLASS}" --title "$EDITOR_TITLE" -e micro "$conf"
}

public_ip() {
    command -v curl >/dev/null 2>&1 || fail "curl is required"
    command -v python3 >/dev/null 2>&1 || fail "python3 is required"

    curl -fsS --connect-timeout 4 --max-time 8 https://wtfismyip.com/text |
        python3 -c '
import ipaddress
import sys
value = sys.stdin.read().strip()
try:
    print(ipaddress.ip_address(value))
except ValueError:
    raise SystemExit(1)
' || fail "Could not determine the public IP address from wtfismyip.com."
}

case "${1:-}" in
    list)
        list_profiles
        ;;
    up|down)
        action="$1"
        name="${2:-}"
        [[ -n "$name" ]] || fail "Profile name is required"
        conf="$(profile_conf "$name")"
        run_privileged_wg_quick "$action" "$conf"
        ;;
    edit)
        name="${2:-}"
        [[ -n "$name" ]] || fail "Profile name is required"
        conf="$(profile_conf "$name")"
        edit_profile "$conf"
        ;;
    open-dir)
        command -v xdg-open >/dev/null 2>&1 || fail "xdg-open is required"
        exec xdg-open "$VPN_DIR"
        ;;
    public-ip)
        public_ip
        ;;
    open-ip-site)
        command -v xdg-open >/dev/null 2>&1 || fail "xdg-open is required"
        exec xdg-open https://wtfismyip.com/
        ;;
    *)
        printf 'Usage: %s {list|up PROFILE|down PROFILE|edit PROFILE|open-dir|public-ip|open-ip-site}\n' "$0" >&2
        exit 2
        ;;
esac
