#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATOR="${ROOT}/local/share/awtarchy/migrate-screenshare-guard-hyprland.sh"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
MANAGED="${ROOT}/config/hypr/hyprland.lua"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_count() {
    local file="$1" needle="$2" expected="$3" actual
    actual="$(grep -Foc -- "$needle" "$file" || true)"
    [[ "$actual" == "$expected" ]] || fail "expected ${expected} occurrence(s) of ${needle@Q} in ${file}, found ${actual}"
}

[[ -f "$MIGRATOR" ]] || fail "missing preserved-hyprland Screen Share Guard migrator"
grep -Fq 'migrate-screenshare-guard-hyprland.sh' "$RUNTIME" \
    || fail "updater runtime does not invoke the preserved-hyprland Screen Share Guard migrator"

live="${TMP}/hyprland.lua"
backup="${TMP}/hyprland.lua.awtarchy-screenshare-guard-test"

cat >"$live" <<'EOF'
-- personal edit before Awtarchy's retired block
hl.env("AWTARCHY_TEST_PERSONAL_BEFORE", "1")

local screenshot_hide_window = function(class, title)
    local match = { class = class }
    if title ~= nil then
        match.title = title
    end
    hl.window_rule({
        match = match,
        no_screen_share = true,
    })
end

screenshot_hide_window("^(Bitwarden|com\\.bitwarden\\.desktop|KeePassXC|org\\.keepassxc\\.KeePassXC|1Password|com\\.1password\\.1password|Enpass|org\\.gnome\\.Secrets|org\\.gnome\\.seahorse\\.Application|OTPClient|otpclient|org\\.rasalminen\\.OTPClient)$")
screenshot_hide_window("^(firefox)$", "^(Extension: \\(Bitwarden Password Manager\\).*)$")
screenshot_hide_window("^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", "^(Bitwarden Password Manager.*)$")
screenshot_hide_window("^(Mullvad Browser|mullvad-browser|com\\.mullvad\\.Browser)$")
screenshot_hide_window("^(localsend|LocalSend|org\\.localsend\\.localsend|io\\.github\\.localsend\\.localsend)$")
screenshot_hide_window("^(org\\.telegram\\.desktop|TelegramDesktop|telegram-desktop|telegram|Telegram)$")
screenshot_hide_window("^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", "^.*Telegram.*$")
screenshot_hide_window("^(Element|io\\.element\\.Element|im\\.riot\\.Riot|chat\\.element\\.desktop|SchildiChat|im\\.fluffychat\\.Fluffychat|Fractal|org\\.gnome\\.Fractal|nheko)$")
screenshot_hide_window("^(discord|com\\.discordapp\\.Discord|vesktop|dev\\.vencord\\.Vesktop|Fluxer|fluxer)$")
screenshot_hide_window("^(com\\.github\\.IsmaelMartinez\\.teams_for_linux)$")
screenshot_hide_window("^(messages|Messages)$")

-- personal edit after Awtarchy's retired block
hl.env("AWTARCHY_TEST_PERSONAL_AFTER", "1")
EOF

bash "$MIGRATOR" "$live" "$MANAGED" "$backup"

grep -Fq 'AWTARCHY_TEST_PERSONAL_BEFORE' "$live" || fail "migration removed personal content before retired block"
grep -Fq 'AWTARCHY_TEST_PERSONAL_AFTER' "$live" || fail "migration removed personal content after retired block"
! grep -Fq 'local screenshot_hide_window = function' "$live" || fail "retired anonymous Screen Share Guard helper remains"
! grep -Fq 'screenshot_hide_window("^(localsend|LocalSend|' "$live" || fail "retired LocalSend protection remains"
require_count "$live" 'local awtarchy_screenshare_guard_v1 = dofile' 1
require_count "$live" 'function awtarchy_screenshare_guard_set_group_v1' 1
require_count "$live" 'function awtarchy_screenshare_guard_status_v1' 1

[[ -f "$backup" ]] || fail "migration did not preserve the original personalized hyprland.lua"
grep -Fq 'AWTARCHY_TEST_PERSONAL_BEFORE' "$backup" || fail "backup lost personal content"
grep -Fq 'local screenshot_hide_window = function' "$backup" || fail "backup does not contain retired Screen Share Guard block"

before_hash="$(sha256sum "$live" | awk '{print $1}')"
backup_hash="$(sha256sum "$backup" | awk '{print $1}')"
bash "$MIGRATOR" "$live" "$MANAGED" "$backup"
[[ "$(sha256sum "$live" | awk '{print $1}')" == "$before_hash" ]] || fail "migration is not idempotent"
[[ "$(sha256sum "$backup" | awk '{print $1}')" == "$backup_hash" ]] || fail "idempotent migration rewrote the original backup"

plain="${TMP}/plain-personal.lua"
plain_backup="${TMP}/plain-personal.lua.backup"
cat >"$plain" <<'EOF'
-- personalized config from before Screen Share Guard existed
hl.env("AWTARCHY_TEST_PLAIN_PERSONAL", "1")
EOF
bash "$MIGRATOR" "$plain" "$MANAGED" "$plain_backup"
grep -Fq 'AWTARCHY_TEST_PLAIN_PERSONAL' "$plain" || fail "migration removed unrelated personal config"
require_count "$plain" 'function awtarchy_screenshare_guard_set_group_v1' 1
require_count "$plain" 'function awtarchy_screenshare_guard_status_v1' 1
[[ -f "$plain_backup" ]] || fail "plain personalized config was not backed up"

partial="${TMP}/partial.lua"
partial_backup="${TMP}/partial.lua.backup"
cat >"$partial" <<'EOF'
-- malformed/partially hand-merged integration must not be guessed through
function awtarchy_screenshare_guard_set_group_v1(target, enabled)
    return false
end
EOF
if bash "$MIGRATOR" "$partial" "$MANAGED" "$partial_backup" >/dev/null 2>&1; then
    fail "partial Screen Share Guard integration was accepted for automatic migration"
fi
[[ ! -e "$partial_backup" ]] || fail "failed partial migration created a backup despite making no safe change"
require_count "$partial" 'function awtarchy_screenshare_guard_set_group_v1' 1
require_count "$partial" 'function awtarchy_screenshare_guard_status_v1' 0

printf 'Screen Share Guard preserved hyprland.lua migration regression passed.\n'
