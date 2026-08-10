#!/usr/bin/env bash
# Hide Awtarchy floating flyouts until their bar-aware positioning pass completes.

set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || exit 127

hyprctl eval '
awtarchy_flyout_spawn_hooks_v1_enabled = false

if awtarchy_flyout_spawn_rules_v1 ~= nil then
    for _, rule in pairs(awtarchy_flyout_spawn_rules_v1) do
        if rule ~= nil then
            pcall(function() rule:set_enabled(false) end)
        end
    end
    awtarchy_flyout_spawn_rules_v1 = {}
end

if awtarchy_flyout_hidden_until_positioned_rule_v1 == nil then
    awtarchy_flyout_hidden_until_positioned_rule_v1 = hl.window_rule({
        name = "awtarchy-flyout-hidden-until-positioned-v1",
        match = {
            title = "^Awtarchy (Clipboard History|Notification Center|Quick Settings|Network|Bluetooth)$",
        },
        opacity = "0 override 0 override 0 override",
        no_anim = true,
    })
end

awtarchy_flyout_hidden_until_positioned_rule_v1:set_enabled(true)
' >/dev/null
