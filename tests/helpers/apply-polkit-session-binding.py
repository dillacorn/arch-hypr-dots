#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


hypr = Path("config/hypr/hyprland.lua")
controller = Path("config/hypr/scripts/awtarchy-polkit-agent-live-test.sh")
runtime = Path("local/share/awtarchy/awtarchy-runtime.sh")

replace_once(
    hypr,
    '    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE")\n'
    '    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE")',
    '    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_ID XDG_SESSION_TYPE")\n'
    '    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_ID XDG_SESSION_TYPE")',
    "Hyprland graphical-session export",
)

replace_once(
    controller,
    '    [[ -n ${WAYLAND_DISPLAY:-} && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \\\n'
    "        || fail 'this command must run inside the active Hyprland desktop session' || return 1",
    '    [[ -n ${WAYLAND_DISPLAY:-} && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -n ${XDG_SESSION_ID:-} ]] \\\n'
    "        || fail 'this command must run inside the active Hyprland/logind desktop session' || return 1",
    "live-test graphical-session requirement",
)

replace_once(
    controller,
    '        HYPRLAND_INSTANCE_SIGNATURE \\\n'
    '        XDG_CURRENT_DESKTOP \\\n',
    '        HYPRLAND_INSTANCE_SIGNATURE \\\n'
    '        XDG_SESSION_ID \\\n'
    '        XDG_CURRENT_DESKTOP \\\n',
    "live-test systemd session import",
)

replace_once(
    runtime,
    '  [[ -S "${runtime_dir}/bus" && -n "${WAYLAND_DISPLAY:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 2',
    '  [[ -S "${runtime_dir}/bus" && -n "${WAYLAND_DISPLAY:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -n "${XDG_SESSION_ID:-}" ]] || return 2',
    "production activation graphical-session requirement",
)

replace_once(
    runtime,
    '    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" \\\n'
    '    XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}" \\\n'
    '    XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}" \\\n'
    '    /usr/bin/systemctl --user import-environment \\\n'
    '    WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE >/dev/null || return 1',
    '    HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" \\\n'
    '    XDG_SESSION_ID="$XDG_SESSION_ID" \\\n'
    '    XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}" \\\n'
    '    XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}" \\\n'
    '    /usr/bin/systemctl --user import-environment \\\n'
    '    WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_ID XDG_CURRENT_DESKTOP XDG_SESSION_TYPE >/dev/null || return 1',
    "production systemd session import",
)
