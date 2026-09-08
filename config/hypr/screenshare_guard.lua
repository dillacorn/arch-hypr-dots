local guard = {
    rules = {},
    stock = {},
    order = {},
    metadata = {},
}

local function window_rule(name, match)
    return hl.window_rule({ name = name, match = match, no_screen_share = true })
end

local function safe_field(value, name)
    if type(value) ~= "string" or value == "" then
        error("Screen Share Guard " .. name .. " must be a non-empty string")
    end
    if value:find("[\t\r\n]") then
        error("Screen Share Guard " .. name .. " cannot contain tabs or newlines")
    end
    return value
end

local function validate_id(id)
    safe_field(id, "id")
    if not id:match("^[a-z0-9][a-z0-9._-]*$") then
        error("Screen Share Guard id must match ^[a-z0-9][a-z0-9._-]*$")
    end
    return id
end

local function validate_match(match)
    if type(match) ~= "table" then
        error("Screen Share Guard match must be a table")
    end
    for key, _ in pairs(match) do
        if key ~= "class" and key ~= "title" then
            error("custom Screen Share Guard matches support only class and optional title")
        end
    end
    safe_field(match.class, "match.class")
    if match.title ~= nil then
        safe_field(match.title, "match.title")
    end
    return match
end

local function add_target(spec, definitions)
    local id = validate_id(spec.id)
    if guard.rules[id] ~= nil then
        error("duplicate Screen Share Guard id: " .. id)
    end

    local label = safe_field(spec.label, "label")
    local section = spec.section
    if section ~= "protected" and section ~= "optional" then
        error("Screen Share Guard section must be protected or optional")
    end
    if type(spec.default_protected) ~= "boolean" then
        error("Screen Share Guard default_protected must be boolean")
    end
    if type(definitions) ~= "table" or #definitions == 0 then
        error("Screen Share Guard target requires at least one rule")
    end

    local rules = {}
    local matches = {}
    for _, definition in ipairs(definitions) do
        local name = safe_field(definition.name, "rule name")
        local match = validate_match(definition.match)
        rules[#rules + 1] = window_rule(name, match)
        matches[#matches + 1] = match
    end

    guard.rules[id] = rules
    guard.stock[id] = spec.default_protected
    guard.metadata[id] = {
        id = id,
        label = label,
        section = section,
        default_protected = spec.default_protected,
        matches = matches,
    }
    guard.order[#guard.order + 1] = id

    for _, rule in ipairs(rules) do
        rule:set_enabled(spec.default_protected)
    end
end

local function builtin(id, label, section, default_protected, definitions)
    add_target({
        id = id,
        label = label,
        section = section,
        default_protected = default_protected,
    }, definitions)
end

builtin("security", "Passwords & Security", "protected", true, {
    { name = "awtarchy-screenshare-security-apps-v1", match = { class = "^(Bitwarden|com\\.bitwarden\\.desktop|KeePassXC|org\\.keepassxc\\.KeePassXC|1Password|com\\.1password\\.1password|Enpass|org\\.gnome\\.Secrets|org\\.gnome\\.seahorse\\.Application|OTPClient|otpclient|org\\.rasalminen\\.OTPClient)$" } },
    { name = "awtarchy-screenshare-bitwarden-firefox-v1", match = { class = "^(firefox)$", title = "^(Extension: \\(Bitwarden Password Manager\\).*)$" } },
    { name = "awtarchy-screenshare-bitwarden-chromium-v1", match = { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^(Bitwarden Password Manager.*)$" } },
})

builtin("mullvad-browser", "Mullvad Browser", "protected", true, {
    { name = "awtarchy-screenshare-mullvad-browser-v1", match = { class = "^(Mullvad Browser|mullvad-browser|com\\.mullvad\\.Browser)$" } },
})

builtin("localsend", "LocalSend", "protected", true, {
    { name = "awtarchy-screenshare-localsend-v1", match = { class = "^(localsend|LocalSend|org\\.localsend\\.localsend|io\\.github\\.localsend\\.localsend)$" } },
})

builtin("telegram", "Telegram", "protected", true, {
    { name = "awtarchy-screenshare-telegram-desktop-v1", match = { class = "^(org\\.telegram\\.desktop|TelegramDesktop|telegram-desktop|telegram|Telegram)$" } },
    { name = "awtarchy-screenshare-telegram-browser-v1", match = { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^.*Telegram.*$" } },
})

builtin("matrix", "Element / Matrix", "protected", true, {
    { name = "awtarchy-screenshare-matrix-v1", match = { class = "^(Element|io\\.element\\.Element|im\\.riot\\.Riot|chat\\.element\\.desktop|SchildiChat|im\\.fluffychat\\.Fluffychat|Fractal|org\\.gnome\\.Fractal|nheko)$" } },
})

builtin("discord", "Discord / Vesktop / Fluxer", "protected", true, {
    { name = "awtarchy-screenshare-discord-v1", match = { class = "^(discord|com\\.discordapp\\.Discord|vesktop|dev\\.vencord\\.Vesktop|Fluxer|fluxer)$" } },
})

builtin("teams", "Teams", "protected", true, {
    { name = "awtarchy-screenshare-teams-v1", match = { class = "^(com\\.github\\.IsmaelMartinez\\.teams_for_linux)$" } },
})

builtin("messages", "Messages", "protected", true, {
    { name = "awtarchy-screenshare-messages-v1", match = { class = "^(messages|Messages)$" } },
})

builtin("obs", "OBS", "optional", false, {
    { name = "awtarchy-screenshare-obs-v1", match = { class = "^(obs|com\\.obsproject\\.Studio|obs-studio|com\\.obsproject\\.Studio\\.obs)$" } },
})

builtin("steam", "Steam", "optional", false, {
    { name = "awtarchy-screenshare-steam-v1", match = { class = "^(steam|com\\.valvesoftware\\.Steam|steam-chat|SteamChat)$" } },
})

builtin("rustdesk", "RustDesk", "optional", false, {
    { name = "awtarchy-screenshare-rustdesk-v1", match = { class = "^(rustdesk|com\\.rustdesk\\.RustDesk)$" } },
})

builtin("files", "Files", "optional", false, {
    { name = "awtarchy-screenshare-files-v1", match = { class = "^(pcmanfm-qt|Pcmanfm-qt|pcmanfm)$" } },
})

builtin("wallpicker", "Wallpicker", "optional", false, {
    { name = "awtarchy-screenshare-wallpicker-v1", match = { class = "^(wallpicker)$" } },
})

builtin("virt-manager", "Virtual Machine Manager", "optional", false, {
    { name = "awtarchy-screenshare-virt-manager-v1", match = { class = "^(virt-manager)$" } },
})

builtin("alacritty", "Alacritty", "optional", false, {
    { name = "awtarchy-screenshare-alacritty-v1", match = { class = "^(Alacritty)$" } },
})

builtin("mpv", "mpv", "optional", false, {
    { name = "awtarchy-screenshare-mpv-v1", match = { class = "^(mpv)$" } },
})

function guard.register(spec)
    if type(spec) ~= "table" then
        error("Screen Share Guard registration must be a table")
    end
    local id = validate_id(spec.id)
    add_target({
        id = id,
        label = spec.label,
        section = spec.section or "protected",
        default_protected = spec.default_protected ~= false,
    }, {
        {
            name = "awtarchy-screenshare-user-" .. id .. "-v1",
            match = validate_match(spec.match),
        },
    })
    return true
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

function guard.registry()
    local rows = {}
    for _, target in ipairs(guard.order) do
        local metadata = guard.metadata[target]
        for _, match in ipairs(metadata.matches) do
            rows[#rows + 1] = table.concat({
                metadata.id,
                metadata.label,
                metadata.section,
                tostring(metadata.default_protected),
                match.class or "",
                match.title or "",
            }, "\t")
        end
    end
    return table.concat(rows, "\n")
end

_G.awtarchy_screenshare_guard_set_group_v1 = function(target, enabled)
    return guard.set_group(target, enabled)
end

_G.awtarchy_screenshare_guard_status_v1 = function()
    return guard.status()
end

_G.awtarchy_screenshare_guard_register_v1 = function(spec)
    return guard.register(spec)
end

_G.awtarchy_screenshare_guard_registry_v1 = function()
    return guard.registry()
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
