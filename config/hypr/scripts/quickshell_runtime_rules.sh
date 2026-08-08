#!/usr/bin/env bash
# Register runtime-only Hyprland rules and binds needed by the Quickshell shell.

set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || exit 127

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

-- Route ALT + left-click by the surface under the pointer. The regular
-- window drag dispatcher can report success while the pointer is over a layer
-- surface, so auto_consuming is not sufficient here. Returning pass_event only
-- for Awtarchy bar layers gives Quickshell the complete pointer stream without
-- passing ALT-clicks through ordinary application windows.
local function pointer_is_on_awtarchy_bar()
    local cursor = hl.get_cursor_pos()
    if cursor == nil then
        return false
    end

    for _, layer in ipairs(hl.get_layers()) do
        local monitor = layer.monitor
        local namespace = layer.namespace
        local named_bar = namespace == "awtarchy-bar"
        local legacy_quickshell_bar = namespace == "quickshell"
            and ((layer.h >= 20 and layer.h <= 80 and layer.w > layer.h * 4)
                or (layer.w >= 20 and layer.w <= 80 and layer.h > layer.w * 4))

        if layer.mapped and monitor ~= nil and (named_bar or legacy_quickshell_bar)
            and cursor.x >= monitor.x + layer.x
            and cursor.x < monitor.x + layer.x + layer.w
            and cursor.y >= monitor.y + layer.y
            and cursor.y < monitor.y + layer.y + layer.h then
            return true
        end
    end

    return false
end

local drag_window = hl.dsp.window.drag()

hl.unbind("ALT + mouse:272")
hl.unbind("ALT + mouse:273")
hl.bind("ALT + mouse:272", function()
    if pointer_is_on_awtarchy_bar() then
        return { ok = true, pass_event = true }
    end

    -- Dispatcher factories return dispatcher objects. Lua callbacks must route
    -- those objects through hl.dispatch instead of calling them as functions.
    return hl.dispatch(drag_window)
end, { mouse = true })
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })
' >/dev/null; then
    printf '%s\n' 'quickshell_runtime_rules.sh: failed to register runtime rules' >&2
    exit 1
fi
