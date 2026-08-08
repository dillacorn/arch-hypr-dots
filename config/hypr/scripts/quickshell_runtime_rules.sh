#!/usr/bin/env bash
# Register runtime-only Hyprland rules and binds needed by the Quickshell shell.

set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || exit 127

hyprctl eval '
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

-- The normal ALT mouse binds should continue moving/resizing regular windows,
-- but must pass through when their dispatcher cannot act on a layer surface.
-- This is what allows ALT + left-drag directly on the Quickshell bar.
hl.unbind("ALT + mouse:272")
hl.unbind("ALT + mouse:273")
hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true, auto_consuming = true })
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true, auto_consuming = true })
' >/dev/null 2>&1 || true
