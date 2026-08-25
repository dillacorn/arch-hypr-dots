#!/usr/bin/env python3
from pathlib import Path

# One-shot branch patch helper. Deleted by the gated workflow after use.
path = Path("AGENTS.md")
text = path.read_text(encoding="utf-8")
marker = "### Runtime and integration helpers\n"
section = """### PolicyKit authentication

Awtarchy owns its desktop PolicyKit authentication agent instead of delegating that role to `polkit-gnome`.

Repository sources:

- `config/hypr/scripts/awtarchy-polkit-agent/shell.qml`
- `config/hypr/scripts/awtarchy-polkit-agent/launcher.sh`
- `config/hypr/scripts/awtarchy-polkit-agent/window-guard.sh`
- `config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service`

Installed trusted runtime:

- `/usr/local/libexec/awtarchy/polkit-agent/`
- `/usr/local/lib/systemd/user/awtarchy-polkit-agent.service`

Important invariants:

- `polkit` is an explicit Arch package dependency. `polkit-gnome` is retired and may exist only as a controlled migration/testing fallback.
- Hyprland starts/restarts `awtarchy-polkit-agent.service` after the Wayland/Hyprland session environment exists. Do not globally enable the unit at `default.target` where it can race `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` setup.
- Authentication QML and executable launcher code must run from the root-owned, non-user-writable runtime under `/usr/local`. Do not execute the live authentication agent from `~/.config`, and do not reintroduce user-controlled QML/plugin/library search paths into the agent process.
- Password responses must travel only through Quickshell `AuthFlow`. Never log, persist, shell-expand, write to temporary files, or transport credentials through `sudo -S`, `pkexec` arguments, sockets, or helper-process stdin.
- Migration must stop only the exact retired GNOME agent binary, verify the supervised Quickshell process, and restore the GNOME fallback when activation fails.
- Automatic `polkit-gnome` package removal is allowed only when Awtarchy recorded ownership of that package, live activation succeeded, and every rollback-capable update validation/cleanup step has already completed.
- Changes to this architecture require the focused production/security/runtime-rebuild tests to remain aligned with the implementation.

"""

if text.count(marker) != 1:
    raise SystemExit(f"expected exactly one AGENTS insertion marker, found {text.count(marker)}")
if "### PolicyKit authentication\n" in text:
    raise SystemExit("PolicyKit AGENTS section already exists")

path.write_text(text.replace(marker, section + marker, 1), encoding="utf-8")
