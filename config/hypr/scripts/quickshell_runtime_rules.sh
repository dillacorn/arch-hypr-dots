#!/usr/bin/env bash
# Register runtime-only Hyprland rules and binds needed by the Quickshell shell.

set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || exit 127

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"

# Privacy is fail-closed: absent, invalid, or unreadable state means that the
# sensitive surface stays masked in screenshots and screen recordings.
capture_allowed() {
    local surface="$1"
    command -v jq >/dev/null 2>&1 \
        && [[ -s "$STATE_FILE" ]] \
        && jq -e --arg surface "$surface" \
            '((.capture_allowed? // {})[$surface] == true)' \
            "$STATE_FILE" >/dev/null 2>&1
}

launcher_protected=true
clipboard_protected=true
notifications_protected=true
quick_settings_protected=true
network_protected=true
bluetooth_protected=true
capture_allowed launcher && launcher_protected=false
capture_allowed clipboard && clipboard_protected=false
capture_allowed notifications && notifications_protected=false
capture_allowed quick_settings && quick_settings_protected=false
capture_allowed network && network_protected=false
capture_allowed bluetooth && bluetooth_protected=false

if ! hyprctl eval "
if awtarchy_launcher_privacy_rule == nil then
    awtarchy_launcher_privacy_rule = hl.window_rule({
        name = \"awtarchy-launcher-capture-privacy\",
        match = { title = \"^Awtarchy Application Search$\" },
        no_screen_share = true,
    })
end

local function disable_superseded_rule(rule)
    if rule ~= nil then
        pcall(function() rule:set_enabled(false) end)
    end
end

disable_superseded_rule(awtarchy_clipboard_privacy_rule)
disable_superseded_rule(awtarchy_notifications_privacy_rule)
disable_superseded_rule(awtarchy_notifications_popup_privacy_rule)
disable_superseded_rule(awtarchy_notifications_center_privacy_rule)
disable_superseded_rule(awtarchy_quick_settings_privacy_rule)
disable_superseded_rule(awtarchy_connectivity_privacy_rule)
disable_superseded_rule(awtarchy_connectivity_window_privacy_rule_v2)

if awtarchy_clipboard_window_privacy_rule_v2 == nil then
    awtarchy_clipboard_window_privacy_rule_v2 = hl.window_rule({
        name = \"awtarchy-clipboard-window-capture-privacy-v2\",
        match = { title = \"^Awtarchy Clipboard History$\" },
        no_screen_share = true,
    })
end

if awtarchy_notifications_popup_privacy_rule_v2 == nil then
    awtarchy_notifications_popup_privacy_rule_v2 = hl.layer_rule({
        name = \"awtarchy-notification-popup-capture-privacy-v2\",
        match = { namespace = \"^awtarchy-notification-popup$\" },
        no_screen_share = true,
    })
end

if awtarchy_notifications_center_window_privacy_rule_v2 == nil then
    awtarchy_notifications_center_window_privacy_rule_v2 = hl.window_rule({
        name = \"awtarchy-notification-center-window-capture-privacy-v2\",
        match = { title = \"^Awtarchy Notification Center$\" },
        no_screen_share = true,
    })
end

if awtarchy_quick_settings_window_privacy_rule_v2 == nil then
    awtarchy_quick_settings_window_privacy_rule_v2 = hl.window_rule({
        name = \"awtarchy-quick-settings-window-capture-privacy-v2\",
        match = { title = \"^Awtarchy Quick Settings$\" },
        no_screen_share = true,
    })
end

if awtarchy_network_window_privacy_rule_v3 == nil then
    awtarchy_network_window_privacy_rule_v3 = hl.window_rule({
        name = \"awtarchy-network-window-capture-privacy-v3\",
        match = { title = \"^Awtarchy Network$\" },
        no_screen_share = true,
    })
end

if awtarchy_bluetooth_window_privacy_rule_v3 == nil then
    awtarchy_bluetooth_window_privacy_rule_v3 = hl.window_rule({
        name = \"awtarchy-bluetooth-window-capture-privacy-v3\",
        match = { title = \"^Awtarchy Bluetooth$\" },
        no_screen_share = true,
    })
end

if awtarchy_vpn_editor_privacy_rule_v1 == nil then
    awtarchy_vpn_editor_privacy_rule_v1 = hl.window_rule({
        name = \"awtarchy-vpn-editor-capture-privacy-v1\",
        match = { class = \"^awtarchy-vpn-editor$\" },
        no_screen_share = true,
    })
end

if awtarchy_public_ip_privacy_rule_v1 == nil then
    awtarchy_public_ip_privacy_rule_v1 = hl.window_rule({
        name = \"awtarchy-public-ip-capture-privacy-v1\",
        match = { class = \"^awtarchy-public-ip$\" },
        no_screen_share = true,
    })
end

awtarchy_launcher_privacy_rule:set_enabled(${launcher_protected})
awtarchy_clipboard_window_privacy_rule_v2:set_enabled(${clipboard_protected})
awtarchy_notifications_popup_privacy_rule_v2:set_enabled(${notifications_protected})
awtarchy_notifications_center_window_privacy_rule_v2:set_enabled(${notifications_protected})
awtarchy_quick_settings_window_privacy_rule_v2:set_enabled(${quick_settings_protected})
awtarchy_network_window_privacy_rule_v3:set_enabled(${network_protected})
awtarchy_bluetooth_window_privacy_rule_v3:set_enabled(${bluetooth_protected})
awtarchy_vpn_editor_privacy_rule_v1:set_enabled(${network_protected})
awtarchy_public_ip_privacy_rule_v1:set_enabled(${network_protected})
hl.exec_scheduled_prop_refresh_immediately()
" >/dev/null; then
    printf '%s\n' 'quickshell_runtime_rules.sh: failed to register capture privacy rules' >&2
    exit 1
fi

if ! hyprctl eval '
if awtarchy_quickshell_launcher_rule ~= nil then
    pcall(function() awtarchy_quickshell_launcher_rule:set_enabled(false) end)
end
if awtarchy_quickshell_launcher_rule_v2 == nil then
    awtarchy_quickshell_launcher_rule_v2 = hl.window_rule({
        name = "awtarchy-quickshell-launcher-runtime-v2",
        match = { title = "Awtarchy Application Search" },
        float = true,
        border_size = 0,
        rounding = 0,
        decorate = false,
        no_shadow = true,
        no_follow_mouse = true,
        no_anim = true,
        opacity = "0 override 0 override 0 override",
    })
end
awtarchy_quickshell_launcher_rule_v2:set_enabled(true)

if awtarchy_quickshell_flyout_rule ~= nil then
    pcall(function() awtarchy_quickshell_flyout_rule:set_enabled(false) end)
end
if awtarchy_quickshell_flyout_rule_v2 ~= nil then
    pcall(function() awtarchy_quickshell_flyout_rule_v2:set_enabled(false) end)
end

if awtarchy_quickshell_flyout_rule_v3 == nil then
    awtarchy_quickshell_flyout_rule_v3 = hl.window_rule({
        name = "awtarchy-quickshell-floating-flyouts-v3",
        match = { title = "^Awtarchy (Clipboard History|Notification Center|Quick Settings|Network|Bluetooth)$" },
        float = true,
        border_size = 0,
        rounding = 0,
        decorate = false,
        no_shadow = true,
        no_anim = true,
        opacity = "0 override 0 override 0 override",
    })
end
awtarchy_quickshell_flyout_rule_v3:set_enabled(true)

local function shell_quote(value)
    local quote = string.char(39)
    local slash = string.char(92)
    local escaped = tostring(value):gsub(quote, quote .. slash .. quote .. quote)
    return quote .. escaped .. quote
end

local function exec_control(method, ...)
    local command = { "qs", "-c", "awtarchy", "ipc", "call", "control", method }
    for _, value in ipairs({ ... }) do
        table.insert(command, shell_quote(value))
    end
    return hl.dispatch(hl.dsp.exec_cmd(table.concat(command, " ") .. " >/dev/null 2>&1"))
end

local function cursor_in_layer(cursor, layer)
    local lx = tonumber(layer.x)
    local ly = tonumber(layer.y)
    local lw = tonumber(layer.w)
    local lh = tonumber(layer.h)
    if lx == nil or ly == nil or lw == nil or lh == nil then
        return false
    end

    local function inside(x, y)
        return cursor.x >= x and cursor.x < x + lw
            and cursor.y >= y and cursor.y < y + lh
    end

    if inside(lx, ly) then
        return true
    end

    local monitor = layer.monitor
    if monitor == nil then
        return false
    end
    local mx = tonumber(monitor.x) or 0
    local my = tonumber(monitor.y) or 0
    return inside(mx + lx, my + ly)
end

local function awtarchy_bar_under_pointer()
    local cursor = hl.get_cursor_pos()
    if cursor == nil then
        return nil
    end

    local cursor_monitor = hl.get_monitor_at_cursor()

    for _, layer in ipairs(hl.get_layers()) do
        local monitor = layer.monitor
        local namespace = layer.namespace
        local named_bar = namespace == "awtarchy-bar"
        local legacy_quickshell_bar = namespace == "quickshell"
            and ((layer.h >= 20 and layer.h <= 80 and layer.w > layer.h * 4)
                or (layer.w >= 20 and layer.w <= 80 and layer.h > layer.w * 4))

        local same_monitor = monitor ~= nil and cursor_monitor ~= nil
            and monitor.name == cursor_monitor.name

        if layer.mapped ~= false and same_monitor
            and (named_bar or legacy_quickshell_bar)
            and cursor_in_layer(cursor, layer) then
            return layer
        end
    end

    return nil
end

awtarchy_flyout_spawn_hooks_v1_enabled = false
if awtarchy_flyout_spawn_rules_v1 ~= nil then
    for title, rule in pairs(awtarchy_flyout_spawn_rules_v1) do
        if rule ~= nil then
            pcall(function() rule:set_enabled(false) end)
        end
        awtarchy_flyout_spawn_rules_v1[title] = nil
    end
end

local awtarchy_flyout_spawn_layouts = {
    ["Awtarchy Clipboard History"] = "centered",
    ["Awtarchy Notification Center"] = "notification",
    ["Awtarchy Quick Settings"] = "centered",
    ["Awtarchy Network"] = "corner",
    ["Awtarchy Bluetooth"] = "corner",
}

local function awtarchy_bar_placement(layer)
    if layer == nil or layer.monitor == nil then
        return nil, nil
    end

    local lx = tonumber(layer.x)
    local ly = tonumber(layer.y)
    local lw = tonumber(layer.w)
    local lh = tonumber(layer.h)
    if lx == nil or ly == nil or lw == nil or lh == nil or lw <= 0 or lh <= 0 then
        return nil, nil
    end

    local mx = tonumber(layer.monitor.x) or 0
    local my = tonumber(layer.monitor.y) or 0
    if lw > lh * 4 then
        local at_top = math.abs(ly) <= 2 or math.abs(ly - my) <= 2
        return at_top and "top" or "bottom", math.max(1, math.floor(lh + 0.5))
    end

    if lh > lw * 4 then
        local at_left = math.abs(lx) <= 2 or math.abs(lx - mx) <= 2
        return at_left and "left" or "right", math.max(1, math.floor(lw + 0.5))
    end

    return nil, nil
end

local function awtarchy_flyout_spawn_move(layout, placement, bar_size)
    local bar = tostring(math.max(1, tonumber(bar_size) or 1))
    local half_bar = tostring(math.max(4, math.floor((tonumber(bar_size) or 8) / 2 + 0.5)))

    if layout == "centered" then
        if placement == "top" then
            return { "((monitor_w-window_w)/2)", bar }
        elseif placement == "bottom" then
            return { "((monitor_w-window_w)/2)", "(monitor_h-window_h-" .. bar .. ")" }
        elseif placement == "left" then
            return { bar, "((monitor_h-window_h)/2)" }
        elseif placement == "right" then
            return { "(monitor_w-window_w-" .. bar .. ")", "((monitor_h-window_h)/2)" }
        end
    elseif layout == "corner" then
        if placement == "top" then
            return { "(monitor_w-window_w-8)", bar }
        elseif placement == "bottom" then
            return { "(monitor_w-window_w-8)", "(monitor_h-window_h-" .. bar .. ")" }
        elseif placement == "left" then
            return { bar, "(monitor_h-window_h-8)" }
        elseif placement == "right" then
            return { "(monitor_w-window_w-" .. bar .. ")", "(monitor_h-window_h-8)" }
        end
    elseif layout == "notification" then
        if placement == "top" then
            return { "(cursor_x-window_w+" .. half_bar .. ")", bar }
        elseif placement == "bottom" then
            return { "(cursor_x-window_w+" .. half_bar .. ")", "(monitor_h-window_h-" .. bar .. ")" }
        elseif placement == "left" then
            return { bar, "(cursor_y-window_h+" .. half_bar .. ")" }
        elseif placement == "right" then
            return { "(monitor_w-window_w-" .. bar .. ")", "(cursor_y-window_h+" .. half_bar .. ")" }
        end
    end

    return nil
end

local function awtarchy_disable_spawn_rule(title)
    if awtarchy_flyout_spawn_rules_v1 == nil then
        return
    end
    local rule = awtarchy_flyout_spawn_rules_v1[title]
    if rule ~= nil then
        pcall(function() rule:set_enabled(false) end)
        awtarchy_flyout_spawn_rules_v1[title] = nil
    end
end

if awtarchy_flyout_spawn_hooks_v1_registered ~= true then
    awtarchy_flyout_spawn_hooks_v1_registered = true
    awtarchy_flyout_spawn_rules_v1 = awtarchy_flyout_spawn_rules_v1 or {}
    awtarchy_flyout_spawn_rule_counter_v1 = awtarchy_flyout_spawn_rule_counter_v1 or 0

    hl.on("window.open_early", function(window)
        if awtarchy_flyout_spawn_hooks_v1_enabled ~= true or window == nil then
            return
        end

        local title = tostring(window.title or "")
        local layout = awtarchy_flyout_spawn_layouts[title]
        if layout == nil then
            return
        end

        local layer = awtarchy_bar_under_pointer()
        if layer == nil or layer.monitor == nil then
            return
        end

        local monitor_name = tostring(layer.monitor.name or "")
        local placement, bar_size = awtarchy_bar_placement(layer)
        local move = awtarchy_flyout_spawn_move(layout, placement, bar_size)
        if monitor_name == "" or move == nil then
            return
        end

        awtarchy_disable_spawn_rule(title)
        awtarchy_flyout_spawn_rule_counter_v1 = awtarchy_flyout_spawn_rule_counter_v1 + 1
        local rule_name = "awtarchy-flyout-spawn-v1-"
            .. tostring(awtarchy_flyout_spawn_rule_counter_v1)

        awtarchy_flyout_spawn_rules_v1[title] = hl.window_rule({
            name = rule_name,
            match = { title = title },
            float = true,
            monitor = monitor_name,
            move = move,
            no_anim = true,
        })

        hl.exec_scheduled_prop_refresh_immediately()
    end)

    hl.on("window.open", function(window)
        if awtarchy_flyout_spawn_hooks_v1_enabled ~= true or window == nil then
            return
        end
        local title = tostring(window.title or "")
        if awtarchy_flyout_spawn_layouts[title] ~= nil then
            awtarchy_disable_spawn_rule(title)
        end
    end)
end

local function movement_candidate(dx, dy)
    if math.abs(dx) > math.abs(dy) then
        return dx >= 0 and "right" or "left"
    end
    return dy >= 0 and "bottom" or "top"
end

local function drag_candidate(drag, cursor)
    local dx = cursor.x - drag.start_x
    local dy = cursor.y - drag.start_y
    if math.max(math.abs(dx), math.abs(dy)) < 32 then
        return "none"
    end

    if dy < 0 then
        local vertical = math.abs(dy)
        local horizontal = math.abs(dx)
        local top = tonumber(drag.monitor_y)

        if top ~= nil and vertical >= 16 and math.abs(cursor.y - top) <= 64 then
            return "top"
        end

        local upward_bias = drag.candidate == "top" and 1.75 or 1.5
        if vertical * upward_bias >= horizontal then
            return "top"
        end
    end

    return movement_candidate(dx, dy)
end

local function stop_bar_drag_timer()
    if awtarchy_bar_drag_timer ~= nil then
        local stopped = pcall(function()
            awtarchy_bar_drag_timer:set_enabled(false)
        end)
        if not stopped then
            pcall(function()
                awtarchy_bar_drag_timer:cancel()
            end)
        end
        awtarchy_bar_drag_timer = nil
    end
end

local function begin_bar_drag(layer)
    local cursor = hl.get_cursor_pos()
    local monitor = layer.monitor
    local monitor_name = monitor ~= nil and tostring(monitor.name or "") or ""
    if cursor == nil or monitor_name == "" then
        return false
    end

    stop_bar_drag_timer()
    awtarchy_bar_drag = {
        monitor = monitor_name,
        start_x = cursor.x,
        start_y = cursor.y,
        monitor_y = tonumber(monitor.y) or 0,
        candidate = "none",
    }
    exec_control("beginBarDrag", monitor_name)

    awtarchy_bar_drag_timer = hl.timer(function()
        local drag = awtarchy_bar_drag
        local current = hl.get_cursor_pos()
        if drag == nil or current == nil then
            return
        end

        local candidate = drag_candidate(drag, current)
        if candidate ~= drag.candidate then
            drag.candidate = candidate
            exec_control("previewBarDrag", drag.monitor, candidate)
        end
    end, { timeout = 16, type = "repeat" })

    return true
end

local drag_window = hl.dsp.window.drag()
local resize_window = hl.dsp.window.resize()

stop_bar_drag_timer()
awtarchy_bar_drag = nil
exec_control("cancelBarDrag")

hl.unbind("ALT + mouse:272")
hl.unbind("ALT + mouse:273")
hl.bind("ALT + mouse:272", function()
    local layer = awtarchy_bar_under_pointer()
    if layer ~= nil and begin_bar_drag(layer) then
        return { ok = true }
    end

    return hl.dispatch(drag_window)
end, { mouse = true })
hl.bind("ALT + mouse:272", function()
    local drag = awtarchy_bar_drag
    if drag == nil then
        return { ok = false }
    end

    local cursor = hl.get_cursor_pos()
    local candidate = cursor ~= nil and drag_candidate(drag, cursor) or "none"
    stop_bar_drag_timer()
    awtarchy_bar_drag = nil
    exec_control("finishBarDrag", drag.monitor, candidate)
    return { ok = true }
end, { mouse = true, release = true, auto_consuming = true })
hl.bind("ALT + mouse:273", function()
    return hl.dispatch(resize_window)
end, { mouse = true })
' >/dev/null; then
    printf '%s\n' 'quickshell_runtime_rules.sh: failed to register runtime rules' >&2
    exit 1
fi
