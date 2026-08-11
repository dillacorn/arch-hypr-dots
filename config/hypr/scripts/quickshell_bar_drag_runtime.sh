#!/usr/bin/env bash
# Harden Awtarchy bar dragging and make destination preview follow drag direction.

set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || exit 127

if ! hyprctl eval '
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

local function bar_under_pointer()
    local cursor = hl.get_cursor_pos()
    if cursor == nil then
        return nil
    end

    local cursor_monitor = hl.get_monitor_at_cursor()
    for _, layer in ipairs(hl.get_layers()) do
        local monitor = layer.monitor
        local namespace = layer.namespace
        local named_bar = namespace == "awtarchy-bar"
        local legacy_bar = namespace == "quickshell"
            and ((layer.h >= 20 and layer.h <= 80 and layer.w > layer.h * 4)
                or (layer.w >= 20 and layer.w <= 80 and layer.h > layer.w * 4))
        local same_monitor = monitor ~= nil and cursor_monitor ~= nil
            and monitor.name == cursor_monitor.name

        if layer.mapped ~= false and same_monitor
            and (named_bar or legacy_bar)
            and cursor_in_layer(cursor, layer) then
            return layer
        end
    end

    return nil
end

local function stop_drag_timer()
    if awtarchy_bar_drag_timer == nil then
        return
    end

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

local function movement_candidate(dx, dy)
    -- Give horizontal intent a small advantage so a left/right flick does not
    -- get trapped by the large vertical displacement caused by lifting a top or
    -- bottom bar into the screen first.
    if math.abs(dx) * 1.20 >= math.abs(dy) then
        return dx >= 0 and "right" or "left"
    end
    return dy >= 0 and "bottom" or "top"
end

local function drag_candidate(drag, cursor)
    local dx = cursor.x - drag.start_x
    local dy = cursor.y - drag.start_y
    local step_dx = cursor.x - (drag.last_x or drag.start_x)
    local step_dy = cursor.y - (drag.last_y or drag.start_y)
    drag.last_x = cursor.x
    drag.last_y = cursor.y

    if math.max(math.abs(dx), math.abs(dy)) < 24 then
        return "none"
    end

    local horizontal = math.abs(step_dx)
    local vertical = math.abs(step_dy)

    -- Recent pointer direction wins over total distance. This makes quick
    -- left/right flicks immediately move the destination preview without
    -- requiring the pointer to reach the physical side of the monitor.
    if horizontal >= 3 and horizontal * 1.45 >= vertical then
        return step_dx >= 0 and "right" or "left"
    end
    if vertical >= 3 and vertical * 1.15 >= horizontal then
        return step_dy >= 0 and "bottom" or "top"
    end

    -- When the pointer pauses, keep the last intentional destination instead
    -- of snapping back to top/bottom from the accumulated drag displacement.
    if drag.candidate ~= nil and drag.candidate ~= "none" then
        return drag.candidate
    end

    return movement_candidate(dx, dy)
end

local function finish_guarded_drag()
    local drag = awtarchy_bar_drag
    if drag == nil then
        return false
    end

    local monitor = tostring(drag.monitor or "")
    local cursor = hl.get_cursor_pos()
    local candidate = cursor ~= nil and drag_candidate(drag, cursor)
        or tostring(drag.candidate or "none")
    stop_drag_timer()
    awtarchy_bar_drag = nil

    if monitor == "" then
        exec_control("cancelBarDrag")
    else
        exec_control("finishBarDrag", monitor, candidate)
    end
    return true
end

local function begin_bar_drag(layer)
    local cursor = hl.get_cursor_pos()
    local monitor = layer ~= nil and layer.monitor or nil
    local monitor_name = monitor ~= nil and tostring(monitor.name or "") or ""
    if cursor == nil or monitor_name == "" then
        return false
    end

    stop_drag_timer()
    awtarchy_bar_drag = {
        monitor = monitor_name,
        start_x = cursor.x,
        start_y = cursor.y,
        last_x = cursor.x,
        last_y = cursor.y,
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

-- Disable the previous generic release guard if it was registered by an older
-- candidate. Its callback remains harmless because it checks this flag.
awtarchy_bar_drag_release_guard_v1_enabled = false

-- Clear stale state before replacing the ALT+left drag handlers.
stop_drag_timer()
awtarchy_bar_drag = nil
exec_control("cancelBarDrag")

local drag_window = hl.dsp.window.drag()
hl.unbind("ALT + mouse:272")

hl.bind("ALT + mouse:272", function()
    local layer = bar_under_pointer()
    if layer ~= nil and begin_bar_drag(layer) then
        return { ok = true }
    end
    return hl.dispatch(drag_window)
end, { mouse = true })

hl.bind("ALT + mouse:272", function()
    if finish_guarded_drag() then
        return { ok = true }
    end
    return { ok = false }
end, { mouse = true, release = true, auto_consuming = true })

awtarchy_bar_drag_release_guard_v2_enabled = true
if awtarchy_bar_drag_release_guard_v2_registered ~= true then
    awtarchy_bar_drag_release_guard_v2_registered = true

    -- Catch release even when ALT is released before the left mouse button.
    hl.bind("mouse:272", function()
        if awtarchy_bar_drag_release_guard_v2_enabled ~= true then
            return { ok = false }
        end
        if finish_guarded_drag() then
            return { ok = true }
        end
        return { ok = false }
    end, {
        mouse = true,
        release = true,
        ignore_mods = true,
        transparent = true,
        auto_consuming = true,
    })
end
' >/dev/null; then
    printf '%s\n' 'quickshell_bar_drag_runtime.sh: failed to register directional drag handlers' >&2
    exit 1
fi
