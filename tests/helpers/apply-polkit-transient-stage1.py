#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


launcher = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"
replace_once(
    launcher,
    '    local lang_value="${LANG:-C.UTF-8}"\n    local -a appearance_args=()\n',
    '    local lang_value="${LANG:-C.UTF-8}"\n',
)
replace_once(
    launcher,
    '''    if [[ -n $appearance_text ]]; then
        while IFS= read -r option; do
            [[ -n $option ]] || continue
            appearance_args+=(--option "$option")
        done <<<"$appearance_text"
    fi

''',
    '',
)
replace_once(
    launcher,
    '''    # Fail before Alacritty owns stderr so missing PyGObject/PolicyKit bindings
    # are visible in the systemd journal instead of flashing in a closing PTY.
''',
    '''    # Fail before the persistent backend starts so missing PyGObject/PolicyKit
    # bindings are visible immediately in the systemd user journal.
''',
)
replace_once(
    launcher,
    '''    exec /usr/bin/env -i \\
        HOME="$home_dir" \\
        USER="$account" \\
        LOGNAME="$account" \\
        PATH=/usr/bin:/bin \\
        LANG="$lang_value" \\
        LC_ALL=C.UTF-8 \\
        XDG_RUNTIME_DIR="$expected_runtime" \\
        DBUS_SESSION_BUS_ADDRESS="unix:path=${expected_runtime}/bus" \\
        WAYLAND_DISPLAY="$wayland_display" \\
        HYPRLAND_INSTANCE_SIGNATURE="$hypr_signature" \\
        XDG_SESSION_ID="$session_id" \\
        XDG_CURRENT_DESKTOP=Hyprland \\
        XDG_SESSION_DESKTOP=Hyprland \\
        XDG_SESSION_TYPE=wayland \\
        "$ALACRITTY" \\
        --config-file "$TERMINAL_CONFIG" \\
        "${appearance_args[@]}" \\
        --class "$APP_ID,$APP_ID" \\
        --title "$APP_ID" \\
        -e "$SYSTEMD_CAT" \\
        --identifier=awtarchy-polkit-agent \\
        "$PYTHON" -I "$AGENT"
''',
    '''    exec /usr/bin/env -i \\
        HOME="$home_dir" \\
        USER="$account" \\
        LOGNAME="$account" \\
        PATH=/usr/bin:/bin \\
        LANG="$lang_value" \\
        LC_ALL=C.UTF-8 \\
        XDG_RUNTIME_DIR="$expected_runtime" \\
        DBUS_SESSION_BUS_ADDRESS="unix:path=${expected_runtime}/bus" \\
        WAYLAND_DISPLAY="$wayland_display" \\
        HYPRLAND_INSTANCE_SIGNATURE="$hypr_signature" \\
        XDG_SESSION_ID="$session_id" \\
        XDG_CURRENT_DESKTOP=Hyprland \\
        XDG_SESSION_DESKTOP=Hyprland \\
        XDG_SESSION_TYPE=wayland \\
        AWTARCHY_POLKIT_ALACRITTY_OPTIONS="$appearance_text" \\
        "$PYTHON" -I "$AGENT"
''',
)

hypr = ROOT / "config/hypr/hyprland.lua"
replace_once(
    hypr,
    '''-- Quickshell intentionally excludes this service window from user scratchpad/task UI.
hl.window_rule({
    name = "awtarchy-polkit-agent-internal",
    match = { class = "awtarchy-polkit-agent" },
    float = true,
    workspace = "special:awtarchy-polkit-agent silent",
    no_initial_focus = true,
    no_follow_mouse = true,
    no_anim = true,
})
''',
    '''-- The PolicyKit terminal exists only while an authentication request is active.
hl.window_rule({
    name = "awtarchy-polkit-agent-auth",
    match = { class = "awtarchy-polkit-agent" },
    float = true,
})
''',
)
