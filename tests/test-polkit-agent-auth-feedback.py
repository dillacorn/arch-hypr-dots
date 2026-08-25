#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TUI_PATH = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/tui.py"
AGENT_PATH = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/agent.py"
LAUNCHER_PATH = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"
MODULE_NAME = "awtarchy_polkit_feedback_tui"

spec = importlib.util.spec_from_file_location(MODULE_NAME, TUI_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("could not load terminal TUI module")
module = importlib.util.module_from_spec(spec)
sys.modules[MODULE_NAME] = module
spec.loader.exec_module(module)


def test_spinner_frames_wrap() -> None:
    frames = module.SPINNER_FRAMES
    assert len(frames) >= 6
    assert module.spinner_text(0).startswith("Authenticating ")
    assert module.spinner_text(len(frames)) == module.spinner_text(0)
    assert module.spinner_text(1) != module.spinner_text(0)


def test_authenticating_state_clears_secret_and_animates() -> None:
    ui = module.TerminalUI.__new__(module.TerminalUI)
    ui.visible = False
    ui.password_row = 0
    ui.focus = 3
    ui.status = ""
    ui.status_error = False
    ui.authenticating = False
    ui.spinner_index = 0
    ui._response = bytearray(b"secret")

    ui.set_authenticating(True)
    assert ui.authenticating is True
    assert ui._response == bytearray()
    assert ui.focus == 2
    first = ui.status
    assert first == module.spinner_text(0)

    ui.advance_spinner()
    assert ui.status != first
    assert ui.status == module.spinner_text(1)

    ui.set_authenticating(False)
    assert ui.authenticating is False


def test_runtime_output_is_not_attached_to_auth_tty() -> None:
    launcher = LAUNCHER_PATH.read_text(encoding="utf-8")
    assert 'SYSTEMD_CAT="/usr/bin/systemd-cat"' in launcher
    assert 'verify_system_binary "$SYSTEMD_CAT"' in launcher
    assert '-e "$SYSTEMD_CAT"' in launcher
    assert '--identifier=awtarchy-polkit-agent' in launcher
    assert '"$PYTHON" -I "$AGENT"' in launcher


def test_agent_drives_spinner_around_pam_response() -> None:
    agent = AGENT_PATH.read_text(encoding="utf-8")
    assert "def _start_auth_feedback(self)" in agent
    assert "def _stop_auth_feedback(self)" in agent
    assert "GLib.timeout_add(" in agent
    assert "self.ui.set_authenticating(True)" in agent
    assert "self.ui.advance_spinner()" in agent
    assert "self.ui.set_authenticating(False)" in agent


if __name__ == "__main__":
    test_spinner_frames_wrap()
    test_authenticating_state_clears_secret_and_animates()
    test_runtime_output_is_not_attached_to_auth_tty()
    test_agent_drives_spinner_around_pam_response()
    print("Polkit authentication feedback tests passed")
