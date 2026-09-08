local guard = {}

local function window_rule(name, match)
    return hl.window_rule({ name = name, match = match, no_screen_share = true })
end

local function layer_rule(name, match)
    return hl.layer_rule({ name = name, match = match, no_screen_share = true })
end

guard.rules = {
    security = {
        window_rule("awtarchy-screenshare-security-apps-v1", { class = "^(Bitwarden|com\\.bitwarden\\.desktop|KeePassXC|org\\.keepassxc\\.KeePassXC|1Password|com\\.1password\\.1password|Enpass|org\\.gnome\\.Secrets|org\\.gnome\\.seahorse\\.Application|OTPClient|otpclient|org\\.rasalminen\\.OTPClient)$" }),
        window_rule("awtarchy-screenshare-bitwarden-firefox-v1", { class = "^(firefox)$", title = "^(Extension: \\(Bitwarden Password Manager\\).*)$" }),
        window_rule("awtarchy-screenshare-bitwarden-chromium-v1", { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^(Bitwarden Password Manager.*)$" }),
    },
    ["mullvad-browser"] = {
        window_rule("awtarchy-screenshare-mullvad-browser-v1", { class = "^(Mullvad Browser|mullvad-browser|com\\.mullvad\\.Browser)$" }),
    },
    localsend = {
        window_rule("awtarchy-screenshare-localsend-v1", { class = "^(localsend|LocalSend|org\\.localsend\\.localsend|io\\.github\\.localsend\\.localsend)$" }),
    },
    telegram = {
        window_rule("awtarchy-screenshare-telegram-desktop-v1", { class = "^(org\\.telegram\\.desktop|TelegramDesktop|telegram-desktop|Telegram)$" }),
        window_rule("awtarchy-screenshare-telegram-browser-v1", { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^.*Telegram.*$" }),
    },
    matrix = {
        window_rule("awtarchy-screenshare-matrix-v1", { class = "^(Element|io\\.element\\.Element|im\\.riot\\.Riot|chat\\.element\\.desktop|SchildiChat|im\\.fluffychat\\.Fluffychat|Fractal|org\\.gnome\\.Fractal|nheko)$" }),
    },
    discord = {
        window_rule("awtarchy-screenshare-discord-v1", { class = "^(discord|com\\.discordapp\\.Discord|vesktop|dev\\.vencord\\.Vesktop|Fluxer|fluxer)$" }),
    },
    teams = {
        window_rule("awtarchy-screenshare-teams-v1", { class = "^(com\\.github\\.IsmaelMartinez\\.teams_for_linux)$" }),
    },
    messages = {
        window_rule("awtarchy-screenshare-messages-v1", { class = "^(Messages)$" }),
    },
    notifications = {
        layer_rule("awtarchy-screenshare-notifications-v1", { namespace = "^(notifications|swaync.*)$" }),
    },
    obs = {
        window_rule("awtarchy-screenshare-obs-v1", { class = "^(obs|com\\.obsproject\\.Studio|obs-studio|com\\.obsproject\\.Studio\\.obs)$" }),
    },
    steam = {
        window_rule("awtarchy-screenshare-steam-v1", { class = "^(steam|com\\.valvesoftware\\.Steam)$" }),
    },
    rustdesk = {
        window_rule("awtarchy-screenshare-rustdesk-v1", { class = "^(rustdesk|com\\.rustdesk\\.RustDesk)$" }),
    },
    files = {
        window_rule("awtarchy-screenshare-files-v1", { class = "^(pcmanfm-qt|Pcmanfm-qt|pcmanfm)$" }),
    },
    wallpicker = {
        window_rule("awtarchy-screenshare-wallpicker-v1", { class = "^(wallpicker)$" }),
    },
    ["virt-manager"] = {
        window_rule("awtarchy-screenshare-virt-manager-v1", { class = "^(virt-manager)$" }),
    },
    alacritty = {
        window_rule("awtarchy-screenshare-alacritty-v1", { class = "^(Alacritty)$" }),
    },
    mpv = {
        window_rule("awtarchy-screenshare-mpv-v1", { class = "^(mpv)$" }),
    },
    ags = {
        layer_rule("awtarchy-screenshare-ags-v1", { namespace = "^(ags)$" }),
    },
    ["logout-dialog"] = {
        layer_rule("awtarchy-screenshare-logout-dialog-v1", { namespace = "^(logout_dialog)$" }),
    },
    waybar = {
        layer_rule("awtarchy-screenshare-waybar-v1", { namespace = "^(waybar)$" }),
    },
}

guard.stock = {
    security = true,
    ["mullvad-browser"] = true,
    localsend = true,
    telegram = true,
    matrix = true,
    discord = true,
    teams = true,
    messages = true,
    notifications = true,
    obs = false,
    steam = false,
    rustdesk = false,
    files = false,
    wallpicker = false,
    ["virt-manager"] = false,
    alacritty = false,
    mpv = false,
    ags = false,
    ["logout-dialog"] = false,
    waybar = false,
}

guard.order = {
    "security", "mullvad-browser", "localsend", "telegram", "matrix",
    "discord", "teams", "messages", "notifications", "obs", "steam",
    "rustdesk", "files", "wallpicker", "virt-manager", "alacritty", "mpv",
    "ags", "logout-dialog", "waybar",
}

for target, rules in pairs(guard.rules) do
    local enabled = guard.stock[target] == true
    for _, rule in ipairs(rules) do
        rule:set_enabled(enabled)
    end
end

function guard.set_group(target, enabled)
    local rules = guard.rules[target]
    if rules == nil then return false end
    for _, rule in ipairs(rules) do
        rule:set_enabled(enabled == true)
    end
    return true
end

function guard.group_enabled(target)
    local rules = guard.rules[target]
    if rules == nil or #rules == 0 then return nil end
    for _, rule in ipairs(rules) do
        if not rule:is_enabled() then return false end
    end
    return true
end

function guard.status()
    local status = {}
    for _, target in ipairs(guard.order) do
        status[#status + 1] = target .. "=" .. tostring(guard.group_enabled(target))
    end
    return table.concat(status, "\n")
end

local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then
    config_home = assert(os.getenv("HOME")) .. "/.config"
end
local helper = config_home .. "/hypr/scripts/screenshare_guard.sh"

local function apply_saved_state()
    hl.exec_cmd(string.format("%q", helper) .. " apply >/dev/null 2>&1")
end

hl.on("hyprland.start", apply_saved_state)
hl.on("config.reloaded", apply_saved_state)

return guard
