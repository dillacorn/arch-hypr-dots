#!/usr/bin/env python3
from pathlib import Path
import re

path = Path("AGENTS.md")
text = path.read_text(encoding="utf-8")

replacement = r'''### PolicyKit authentication

Awtarchy owns its desktop PolicyKit authentication agent instead of delegating that role to `polkit-gnome`.

Repository sources:

- `config/hypr/scripts/awtarchy-polkit-agent/agent.py`: system-bus registration and the PolicyKit/PAM authentication conversation.
- `config/hypr/scripts/awtarchy-polkit-agent/tui.py`: the real terminal authentication UI, keyboard/mouse handling, and exact-window Hyprland lifecycle.
- `config/hypr/scripts/awtarchy-polkit-agent/launcher.sh`: validates the trusted runtime and starts the dedicated Alacritty terminal with isolated Python.
- `config/hypr/scripts/awtarchy-polkit-agent/alacritty.toml`: root-owned terminal configuration for the authentication window.
- `config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service`: supervised user service.

Installed trusted runtime:

- `/usr/local/libexec/awtarchy/polkit-agent/`
- `/usr/local/lib/systemd/user/awtarchy-polkit-agent.service`

Important invariants:

- `polkit` and `python-gobject` are explicit Arch package dependencies. `polkit-gnome` is retired and may exist only as a controlled migration/testing fallback.
- The real authentication frontend is the dedicated Alacritty terminal. Quickshell/QML does not participate in the authentication process and must not be reintroduced as an authentication backend/frontend without an explicit architecture change.
- The Python agent exports `org.freedesktop.PolicyKit1.AuthenticationAgent` on the system bus and uses `PolkitAgent.Session` for the PAM conversation. Password responses must travel only through `PolkitAgent.Session.response()`.
- Hyprland starts/restarts `awtarchy-polkit-agent.service` after the Wayland/Hyprland session environment exists. Do not globally enable the unit at `default.target` where it can race `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` setup.
- Authentication Python, launcher code, and the dedicated Alacritty configuration must run from the root-owned, non-user-writable runtime under `/usr/local`. Do not execute the live agent from `~/.config`, and do not add user-controlled Python/library/plugin search paths to the agent process.
- Never log, persist, shell-expand, write to temporary files, pass in argv, or transport credentials through `sudo -S`, `pkexec` arguments, sockets, helper-process stdin, or any custom IPC channel.
- The terminal stays registered while idle and is hidden on the private Hyprland special workspace `special:awtarchy-polkit-agent`. During authentication, move/focus/resize only the exact `awtarchy-polkit-agent` window; never target arbitrary windows.
- Preserve the approved terminal behavior: fixed 900x520 geometry, Details collapsed initially, targeted password-field redraw without full-screen typing flicker, SGR mouse support, keyboard navigation, and real PAM status/error messages.
- Migration must stop only the exact retired GNOME agent binary, verify both the supervised Alacritty process and its isolated `python3 -I .../agent.py` descendant, and restore GNOME when activation fails.
- Automatic `polkit-gnome` package removal is allowed only when Awtarchy recorded ownership of that package, live activation succeeded, and every rollback-capable update validation/cleanup step has already completed.
- Changes to this architecture require `tests/test-polkit-agent-production-integration.sh`, `tests/test-polkit-agent-secure.sh`, `tests/test-polkit-agent-runtime-rebuild.sh`, and `tests/test-polkit-agent-tui.py` to remain aligned with the implementation.
'''

pattern = re.compile(
    r"### PolicyKit authentication\n.*?(?=\n### Runtime and integration helpers\n)",
    re.S,
)
text, count = pattern.subn(replacement.rstrip(), text, count=1)
if count != 1:
    raise SystemExit(f"PolicyKit AGENTS section: expected exactly one match, found {count}")

path.write_text(text, encoding="utf-8")
