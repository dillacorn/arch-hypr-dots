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
capture_allowed launcher && launcher_protected=false
capture_allowed clipboard && clipboard_protected=false
capture_allowed notifications && notifications_protected=false

if ! hyprctl eval "
if awtarchy_launcher_privacy_rule == nil then
    awtarchy_launcher_privacy_rule = hl.window_rule({
        name = \"awtarchy-launcher-capture-privacy\",
        match = { title = \"^Awtarchy Application Search$\" },
        no_screen_share = true,
    })
end

if awtarchy_clipboard_privacy_rule == nil then
    awtarchy_clipboard_privacy_rule = hl.layer_rule({
        name = \"awtarchy-clipboard-capture-privacy\",
        match = { namespace = \"^awtarchy-clipboard$\" },
        no_screen_share = true,
    })
end

if awtarchy_notifications_privacy_rule == nil then
    awtarchy_notifications_privacy_rule = hl.layer_rule({
        name = \"awtarchy-notifications-capture-privacy\",
        match = { namespace = \"^awtarchy-notification-(popup|center)$\" },
        no_screen_share = true,
    })
end

awtarchy_launcher_privacy_rule:set_enabled(${launcher_protected})
awtarchy_clipboard_privacy_rule:set_enabled(${clipboard_protected})
awtarchy_notifications_privacy_rule:set_enabled(${notifications_protected})
" >/dev/null; then
    printf '%s\n' 'quickshell_runtime_rules.sh: failed to register capture privacy rules' >&2
    exit 1
fi

if ! hyprctl eval '
if awtarchy_quickshell_launcher_rule == nil then
    awtarchy_quickshell_launcher_rule = hl.window_rule({
        name = "awtarchy-quickshell-launcher-runtime",
        match = { title = "Awtarchy Application Search" },
        float = true,
        border_size = 0,
        rounding = 0,
        decorate = false,
        no_shadow = true,
        no_follow_mouse = true,
        no_anim = true,
    })
end

-- Current Hyprland releases can synthesize an immediate button release while
-- passing a mouse bind to another surface. Track bar drags in compositor Lua
-- instead, then send only drag state changes to Quickshell IPC.
local function shell_quote(value)
    local quote = string.char(39)
    local slash = string.char(92)
    local escaped = tostring(value):gsub(quote, quote .. slash .. quote .. quote)
    return quote .. escaped .. quote
end

local function exec_bar_control(method, arg1, arg2)
    local command = { "qs", "-c", "awtarchy", "ipc", "call", "control", method }
    if arg1 ~= nil then
        table.insert(command, shell_quote(arg1))
    end
    if arg2 ~= nil then
        table.insert(command, shell_quote(arg2))
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

    -- Layer coordinates have changed representation across compositor code
    -- paths. Accept compositor-global coordinates and monitor-local ones, but
    -- only after matching the monitor under the cursor.
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

        -- A pointer that reaches the top snap zone is unambiguously aiming
        -- upward even when the drag began close to that edge and accumulated
        -- more sideways movement than vertical movement.
        if top ~= nil and vertical >= 16 and math.abs(cursor.y - top) <= 64 then
            return "top"
        end

        -- Give upward movement a wider cone and a little hysteresis once the
        -- top preview is active. Left/right still win for clearly horizontal
        -- movement, while small diagonal drift no longer steals the target.
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
    exec_bar_control("beginBarDrag", monitor_name)

    awtarchy_bar_drag_timer = hl.timer(function()
        local drag = awtarchy_bar_drag
        local current = hl.get_cursor_pos()
        if drag == nil or current == nil then
            return
        end

        local candidate = drag_candidate(drag, current)
        if candidate ~= drag.candidate then
            drag.candidate = candidate
            exec_bar_control("previewBarDrag", drag.monitor, candidate)
        end
    end, { timeout = 16, type = "repeat" })

    return true
end

local drag_window = hl.dsp.window.drag()

stop_bar_drag_timer()
awtarchy_bar_drag = nil
exec_bar_control("cancelBarDrag")

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
    exec_bar_control("finishBarDrag", drag.monitor, candidate)
    return { ok = true }
end, { mouse = true, release = true, auto_consuming = true })
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })
' >/dev/null; then
    printf '%s\n' 'quickshell_runtime_rules.sh: failed to register runtime rules' >&2
    exit 1
fi
