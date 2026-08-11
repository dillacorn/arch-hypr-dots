#!/usr/bin/env bash
# Harden Awtarchy bar dragging against missed modifier/button release ordering.

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

local function finish_guarded_drag()
    local drag = awtarchy_bar_drag
    if drag == nil then
        return false
    end

    local monitor = tostring(drag.monitor or "")
    local candidate = tostring(drag.candidate or "none")
    stop_drag_timer()
    awtarchy_bar_drag = nil

    if monitor == "" then
        exec_control("cancelBarDrag")
    else
        exec_control("finishBarDrag", monitor, candidate)
    end
    return true
end

-- Clear any stale visual state left behind by a previously missed release.
stop_drag_timer()
awtarchy_bar_drag = nil
exec_control("cancelBarDrag")
awtarchy_bar_drag_release_guard_v1_enabled = true

if awtarchy_bar_drag_release_guard_v1_registered ~= true then
    awtarchy_bar_drag_release_guard_v1_registered = true

    -- Catch left-button release even if ALT was released before the mouse.
    -- transparent prevents the more-specific ALT release bind from shadowing
    -- this fail-safe; auto_consuming passes normal clicks through when idle.
    hl.bind("mouse:272", function()
        if awtarchy_bar_drag_release_guard_v1_enabled ~= true then
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
    printf '%s\n' 'quickshell_bar_drag_runtime.sh: failed to register drag release guard' >&2
    exit 1
fi
