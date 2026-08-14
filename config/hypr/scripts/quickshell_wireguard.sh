#!/usr/bin/env bash
# WireGuard helper for the Awtarchy Quickshell Network flyout.

set -euo pipefail
export LC_ALL=C.UTF-8

VPN_DIR="${AWTARCHY_VPN_DIR:-${HOME}/vpn}"
EDITOR_TITLE="Awtarchy VPN Config Editor"
EDITOR_CLASS="awtarchy-vpn-editor"
FIREFOX="/usr/bin/firefox"
WG_QUICK="/usr/bin/wg-quick"
WTFISMYIP_URL="https://myip.wtf/"
WTFISMYIP_TEXT_URL="https://myip.wtf/text"

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
    [[ ! -L "$conf" ]] || fail "WireGuard profile must not be a symbolic link: $conf"
    [[ -f "$conf" ]] || fail "WireGuard profile not found: $conf"
    [[ -r "$conf" ]] || fail "WireGuard profile is not readable: $conf"
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

reject_privileged_hooks() {
    local conf="$1" rc=0

    grep -Eiq '^[[:space:]]*(PreUp|PostUp|PreDown|PostDown)[[:space:]]*=' "$conf" || rc=$?
    case "$rc" in
        0)
            fail "WireGuard profile contains PreUp/PostUp/PreDown/PostDown hooks. Awtarchy refuses to run imported command hooks as root."
            ;;
        1)
            return 0
            ;;
        *)
            fail "Could not safely inspect WireGuard profile before privilege escalation: $conf"
            ;;
    esac
}

run_privileged_wg_quick() {
    local action="$1" conf="$2"

    reject_privileged_hooks "$conf"
    [[ -x "$WG_QUICK" ]] || fail "wg-quick is unavailable at ${WG_QUICK}. Install wireguard-tools."

    if command -v pkexec >/dev/null 2>&1; then
        exec pkexec "$WG_QUICK" "$action" "$conf"
    fi

    if command -v alacritty >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        exec alacritty --title "Awtarchy WireGuard" -e sudo "$WG_QUICK" "$action" "$conf"
    fi

    fail "A privilege prompt is required but neither pkexec nor an Alacritty+sudo fallback is available."
}

edit_profile() {
    local conf="$1"
    command -v alacritty >/dev/null 2>&1 || fail "Alacritty is required for the protected VPN editor."
    command -v micro >/dev/null 2>&1 || fail "micro is required for the protected VPN editor."
    exec alacritty --class "${EDITOR_CLASS},${EDITOR_CLASS}" --title "$EDITOR_TITLE" -e micro "$conf"
}

local_info() {
    command -v ip >/dev/null 2>&1 || fail "ip is required"
    command -v jq >/dev/null 2>&1 || fail "jq is required"

    local route interface gateway local_ipv4 connection_type
    route="$(
        ip -j -4 route show default table main 2>/dev/null |
            jq -c '[.[] | select((.dev // "") != "lo")][0] // {}'
    )"

    interface="$(jq -r '.dev // empty' <<<"$route")"
    gateway="$(jq -r '.gateway // empty' <<<"$route")"
    local_ipv4=""
    connection_type=""

    if [[ -n "$interface" ]]; then
        local_ipv4="$(
            ip -j -4 addr show dev "$interface" scope global 2>/dev/null |
                jq -r '[.[].addr_info[]? | select(.family == "inet") | .local][0] // empty'
        )"

        if [[ -d "/sys/class/net/${interface}/wireless" ]]; then
            connection_type="Wi-Fi"
        else
            connection_type="Ethernet"
        fi
    fi

    jq -cn \
        --arg interface "$interface" \
        --arg connectionType "$connection_type" \
        --arg localIpv4 "$local_ipv4" \
        --arg gateway "$gateway" \
        '{interface:$interface,connectionType:$connectionType,localIpv4:$localIpv4,gateway:$gateway}'
}

validated_public_ip() {
    local family="$1"
    command -v curl >/dev/null 2>&1 || return 0
    command -v python3 >/dev/null 2>&1 || return 0

    curl "-${family}" -fsS --connect-timeout 4 --max-time 8 "$WTFISMYIP_TEXT_URL" 2>/dev/null |
        python3 -c '
import ipaddress
import sys
family = int(sys.argv[1])
value = sys.stdin.read().strip()
try:
    address = ipaddress.ip_address(value)
except ValueError:
    raise SystemExit(1)
if address.version != family:
    raise SystemExit(1)
print(address)
' "$family" 2>/dev/null || true
}

public_ips() {
    command -v jq >/dev/null 2>&1 || fail "jq is required"

    local ipv4 ipv6
    ipv4="$(validated_public_ip 4)"
    ipv6="$(validated_public_ip 6)"

    jq -cn \
        --arg ipv4 "$ipv4" \
        --arg ipv6 "$ipv6" \
        '{ipv4:$ipv4,ipv6:$ipv6}'
}

open_ip_site() {
    [[ -x "$FIREFOX" ]] || fail "Firefox is unavailable: $FIREFOX"
    exec "$FIREFOX" --new-tab "$WTFISMYIP_URL"
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
    local-info)
        local_info
        ;;
    public-ips)
        public_ips
        ;;
    open-ip-site)
        open_ip_site
        ;;
    *)
        printf 'Usage: %s {list|up PROFILE|down PROFILE|edit PROFILE|open-dir|local-info|public-ips|open-ip-site}\n' "$0" >&2
        exit 2
        ;;
esac
