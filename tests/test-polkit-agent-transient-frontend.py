#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import socket
import sys

ROOT = Path(__file__).resolve().parents[1]
AGENT_PATH = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/agent.py"
TUI_PATH = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/tui.py"
LAUNCHER_PATH = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"
HYPR_PATH = ROOT / "config/hypr/hyprland.lua"

MODULE_NAME = "awtarchy_polkit_transient_tui"
spec = importlib.util.spec_from_file_location(MODULE_NAME, TUI_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("could not load terminal TUI module")
tui = importlib.util.module_from_spec(spec)
sys.modules[MODULE_NAME] = tui
spec.loader.exec_module(tui)


def test_seqpacket_protocol_round_trip() -> None:
    assert hasattr(tui, "send_packet"), "TUI protocol must provide send_packet"
    assert hasattr(tui, "recv_packet"), "TUI protocol must provide recv_packet"

    left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    try:
        tui.send_packet(left, {"type": "status", "message": "ok"})
        assert tui.recv_packet(right) == {"type": "status", "message": "ok"}
    finally:
        left.close()
        right.close()


def test_backend_is_headless_until_authentication() -> None:
    source = AGENT_PATH.read_text(encoding="utf-8")
    assert "from tui import TerminalUI" not in source
    assert "self.ui = TerminalUI(" not in source
    assert "socket.socketpair(" in source
    assert "socket.SOCK_SEQPACKET" in source
    assert "pass_fds=" in source
    assert "frontend_process" in source
    assert "frontend_socket" in source


def test_idle_terminal_is_not_parked_in_a_special_workspace() -> None:
    tui_source = TUI_PATH.read_text(encoding="utf-8")
    hypr_source = HYPR_PATH.read_text(encoding="utf-8")
    assert "HIDDEN_WORKSPACE" not in tui_source
    assert "special:awtarchy-polkit-agent" not in tui_source
    assert "special:awtarchy-polkit-agent" not in hypr_source


def test_launcher_starts_python_backend_not_alacritty() -> None:
    source = LAUNCHER_PATH.read_text(encoding="utf-8")
    assert 'AWTARCHY_POLKIT_ALACRITTY_OPTIONS="$appearance_text"' in source
    assert '"$PYTHON" -I "$AGENT"' in source
    tail = source[source.rfind("exec /usr/bin/env -i") :]
    assert '"$ALACRITTY"' not in tail


if __name__ == "__main__":
    test_seqpacket_protocol_round_trip()
    test_backend_is_headless_until_authentication()
    test_idle_terminal_is_not_parked_in_a_special_workspace()
    test_launcher_starts_python_backend_not_alacritty()
    print("transient PolicyKit frontend contract passed")
