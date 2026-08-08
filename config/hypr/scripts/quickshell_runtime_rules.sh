#!/usr/bin/env bash
# Register runtime-only Hyprland rules needed by the Quickshell shell.

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
' >/dev/null 2>&1 || true
