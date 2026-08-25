#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


bar = Path("config/quickshell/awtarchy/Bar.qml")
replace_once(
    bar,
    '        const ignored = ["tofi", "rofi", "hyprlock", "swaylock", "swww", "mpvpaper", "pulsemixer", "org.waytrogen.waytrogen", "org.pulseaudio.pavucontrol", "wiremix", "quickshell"];\n',
    '        const ignored = ["tofi", "rofi", "hyprlock", "swaylock", "swww", "mpvpaper", "pulsemixer", "org.waytrogen.waytrogen", "org.pulseaudio.pavucontrol", "wiremix", "quickshell", "awtarchy-polkit-agent"];\n',
)
replace_once(
    bar,
    '''    function scratchpadCount() {\n        return Hyprland.toplevels.values.filter(toplevel => toplevel.workspace && toplevel.workspace.id < 0).length;\n    }\n''',
    '''    function internalServiceWindow(toplevel) {\n        if (!toplevel)\n            return false;\n        const ipc = toplevel.lastIpcObject || {};\n        const cls = String(ipc.class || ipc.initialClass || "").toLowerCase();\n        return cls === "awtarchy-polkit-agent";\n    }\n\n    function scratchpadCount() {\n        return Hyprland.toplevels.values.filter(toplevel =>\n            toplevel.workspace && toplevel.workspace.id < 0 && !bar.internalServiceWindow(toplevel)).length;\n    }\n''',
)

hypr = Path("config/hypr/hyprland.lua")
needle = '''hl.window_rule({\n    name = "awtarchy-quickshell-launcher",\n    match = { title = "Awtarchy Application Search" },\n    float = true,\n    border_size = 0,\n    rounding = 0,\n    decorate = false,\n    no_shadow = true,\n    no_follow_mouse = true,\n})\n\n'''
insert = needle + '''-- Internal PolicyKit terminal: map directly to its private parking workspace.\n-- Quickshell intentionally excludes this service window from user scratchpad/task UI.\nhl.window_rule({\n    name = "awtarchy-polkit-agent-internal",\n    match = { class = "awtarchy-polkit-agent" },\n    float = true,\n    workspace = "special:awtarchy-polkit-agent silent",\n    no_initial_focus = true,\n    no_follow_mouse = true,\n    no_anim = true,\n})\n\n'''
replace_once(hypr, needle, insert)

theme = Path("config/hypr/scripts/quickshell_theme_apply.sh")
replace_once(
    theme,
    '''printf '%s\\n' "$name" >"$STATE_DIR/active-theme"\ncommand -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true\n''',
    '''printf '%s\\n' "$name" >"$STATE_DIR/active-theme"\n\n# The PolicyKit terminal uses a trusted root-owned base config plus sanitized\n# visual overrides from the user's current Alacritty config. Restart the hidden\n# agent after a theme change so its next prompt reflects the new theme.\nif command -v systemctl >/dev/null 2>&1 \\\n    && systemctl --user is-active --quiet awtarchy-polkit-agent.service 2>/dev/null;\nthen\n    systemctl --user try-restart awtarchy-polkit-agent.service >/dev/null 2>&1 || true\nfi\n\ncommand -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true\n''',
)
