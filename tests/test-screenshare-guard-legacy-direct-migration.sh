#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
MANAGED="${ROOT}/config/hypr/hyprland.lua"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

HOME_DIR="${TMP}/home"
target_home="${TMP}/target-home"
mkdir -p "$HOME_DIR/.config/hypr" "$target_home/.config/hypr"
cp -- "$MANAGED" "$target_home/.config/hypr/hyprland.lua"
live="$HOME_DIR/.config/hypr/hyprland.lua"

cat >"$live" <<'EOF'
-- Personal rule unrelated to Screen Share Guard must survive.
hl.window_rule({ match = { class = "^(pcmanfm-qt|localsend|wallpicker)$" }, opacity = "0.95 0.95" })

-- Retired direct Awtarchy Screen Share Guard rules from before PR #170.
hl.window_rule({ match = { class = "^(Bitwarden|com\\.bitwarden\\.desktop|KeePassXC|org\\.keepassxc\\.KeePassXC|1Password|com\\.1password\\.1password|Enpass|org\\.gnome\\.Secrets|org\\.gnome\\.seahorse\\.Application|OTPClient|otpclient|org\\.rasalminen\\.OTPClient|Mullvad Browser|mullvad-browser|com\\.mullvad\\.Browser|localsend|LocalSend|org\\.localsend\\.localsend|io\\.github\\.localsend\\.localsend)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(firefox)$", title = "^(Extension: \\(Bitwarden Password Manager\\).*)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^(Bitwarden Password Manager.*)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(org\\.telegram\\.desktop|TelegramDesktop|telegram-desktop|Telegram)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^.*Telegram.*$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(Element|io\\.element\\.Element|im\\.riot\\.Riot|chat\\.element\\.desktop|SchildiChat|im\\.fluffychat\\.Fluffychat|Fractal|org\\.gnome\\.Fractal|nheko)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(discord|com\\.discordapp\\.Discord|vesktop|dev\\.vencord\\.Vesktop|Fluxer|fluxer)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(com\\.github\\.IsmaelMartinez\\.teams_for_linux)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(Messages)$" }, no_screen_share = true })

-- This layer rule and optional examples are not part of the retired direct-window cleanup.
hl.layer_rule({ match = { namespace = "^(notifications|swaync.*)$" }, no_screen_share = true })
-- hl.window_rule({ match = { class = "^(obs|com\\.obsproject\\.Studio|obs-studio|com\\.obsproject\\.Studio\\.obs)$" }, no_screen_share = true })

-- The newer integration was already migrated on a previous update.
local awtarchy_config_home = os.getenv("XDG_CONFIG_HOME")
if not awtarchy_config_home or awtarchy_config_home == "" then
    awtarchy_config_home = assert(os.getenv("HOME")) .. "/.config"
end

local awtarchy_screenshare_guard_v1 = dofile(awtarchy_config_home .. "/hypr/screenshare_guard.lua")

function awtarchy_screenshare_guard_set_group_v1(target, enabled)
    return awtarchy_screenshare_guard_v1.set_group(target, enabled)
end

function awtarchy_screenshare_guard_status_v1()
    return awtarchy_screenshare_guard_v1.status()
end

hl.env("AWTARCHY_TEST_PERSONAL_AFTER", "1")
EOF

# Exercise the updater stage itself so an early return cannot hide stale direct rules.
stage="$(awk '
    /^migrate_screenshare_guard_hyprland_stage\(\)/ { capture=1 }
    capture { print }
    capture && /^}/ { exit }
' "$RUNTIME")"
[[ -n "$stage" ]] || fail 'could not extract Screen Share Guard updater migration stage'

eval "$stage"
run_as_target() { "$@"; }
retry_command() { "$@"; }
die() { printf 'ERROR: %s\n' "$*" >&2; return 1; }

migrate_screenshare_guard_hyprland_stage "$ROOT" "$target_home"

legacy_security='hl.window_rule({ match = { class = "^(Bitwarden|com\\.bitwarden\\.desktop|KeePassXC|org\\.keepassxc\\.KeePassXC|1Password|com\\.1password\\.1password|Enpass|org\\.gnome\\.Secrets|org\\.gnome\\.seahorse\\.Application|OTPClient|otpclient|org\\.rasalminen\\.OTPClient|Mullvad Browser|mullvad-browser|com\\.mullvad\\.Browser|localsend|LocalSend|org\\.localsend\\.localsend|io\\.github\\.localsend\\.localsend)$" }, no_screen_share = true })'
legacy_localsend='localsend|LocalSend|org\\.localsend\\.localsend|io\\.github\\.localsend\\.localsend'
legacy_telegram='hl.window_rule({ match = { class = "^(org\\.telegram\\.desktop|TelegramDesktop|telegram-desktop|Telegram)$" }, no_screen_share = true })'

! grep -Fq -- "$legacy_security" "$live" || fail 'retired combined security/LocalSend direct rule remains after updater migration'
! grep -Fq -- "$legacy_localsend" "$live" || fail 'retired direct LocalSend Screen Share Guard match remains after updater migration'
! grep -Fq -- "$legacy_telegram" "$live" || fail 'retired Telegram direct Screen Share Guard rule remains after updater migration'

grep -Fq -- 'opacity = "0.95 0.95"' "$live" || fail 'migration removed unrelated personal window rule'
grep -Fq -- 'hl.layer_rule({ match = { namespace = "^(notifications|swaync.*)$" }, no_screen_share = true })' "$live" \
    || fail 'migration removed preserved notification layer protection'
grep -Fq -- '-- hl.window_rule({ match = { class = "^(obs|' "$live" \
    || fail 'migration removed preserved optional commented Screen Share Guard example'
grep -Fq -- 'AWTARCHY_TEST_PERSONAL_AFTER' "$live" || fail 'migration removed unrelated personal content after Screen Share Guard'

[[ "$(grep -Foc -- 'function awtarchy_screenshare_guard_set_group_v1' "$live")" == 1 ]] \
    || fail 'migration duplicated or removed Screen Share Guard setter integration'
[[ "$(grep -Foc -- 'function awtarchy_screenshare_guard_status_v1' "$live")" == 1 ]] \
    || fail 'migration duplicated or removed Screen Share Guard status integration'

backup="$(find "$HOME_DIR/.config/hypr" -maxdepth 1 -type f -name 'hyprland.lua.backup.*' -print -quit)"
[[ -n "$backup" && -f "$backup" ]] || fail 'legacy direct-rule cleanup did not create a personalized hyprland.lua backup'
grep -Fq -- "$legacy_security" "$backup" || fail 'backup does not retain the retired direct Screen Share Guard rules'

before_hash="$(sha256sum "$live" | awk '{print $1}')"
migrate_screenshare_guard_hyprland_stage "$ROOT" "$target_home"
[[ "$(sha256sum "$live" | awk '{print $1}')" == "$before_hash" ]] || fail 'second updater migration changed an already-clean integrated config'

printf '%s\n' 'Screen Share Guard legacy direct-rule migration regression passed.'
