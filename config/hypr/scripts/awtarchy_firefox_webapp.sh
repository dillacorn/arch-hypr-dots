#!/usr/bin/env bash
# Launch Awtarchy Firefox web apps in dedicated, isolated profiles.

set -euo pipefail

firefox=/usr/bin/firefox
[[ -x "$firefox" ]] || {
    printf 'awtarchy_firefox_webapp.sh: Firefox not found: %s\n' "$firefox" >&2
    exit 127
}

app="${1:-}"
case "$app" in
    google-messages)
        profile_name='messages'
        profile_dir='messages-profile'
        wm_class='messages'
        window_name='Messages'
        url='https://messages.google.com/web'
        ;;
    telegram)
        profile_name='telegram'
        profile_dir='telegram-profile'
        wm_class='telegram'
        window_name='Telegram'
        url='https://web.telegram.org/a/'
        ;;
    fluxer)
        profile_name='fluxer-profile'
        profile_dir='fluxer-profile'
        wm_class='fluxer'
        window_name='Fluxer'
        url='https://web.fluxer.app'
        ;;
    steam-chat)
        profile_name='steam-chat'
        profile_dir='steam-chat'
        wm_class='steam-chat'
        window_name='SteamChat'
        url='https://steamcommunity.com/chat'
        ;;
    public-ip)
        profile_name='awtarchy-public-ip'
        profile_dir='awtarchy-public-ip-profile'
        wm_class='awtarchy-public-ip'
        window_name='AwtarchyPublicIP'
        url='https://wtfismyip.com/'
        ;;
    *)
        printf 'Usage: %s {google-messages|telegram|fluxer|steam-chat|public-ip}\n' "${0##*/}" >&2
        exit 2
        ;;
esac

profile_root="${HOME}/.mozilla/firefox"
profile="${profile_root}/${profile_dir}"
mkdir -p "$profile_root"

if [[ ! -d "$profile" ]]; then
    "$firefox" --no-remote -CreateProfile "${profile_name} ${profile}"
fi

exec env \
    MOZ_ENABLE_WAYLAND=1 \
    MOZ_USE_XINPUT2=1 \
    "$firefox" \
    --no-remote \
    --class="$wm_class" \
    --name="$window_name" \
    --profile "$profile" \
    --new-window "$url"
