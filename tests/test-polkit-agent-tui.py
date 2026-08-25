#!/usr/bin/env python3
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TUI_PATH = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/tui.py"

spec = importlib.util.spec_from_file_location("awtarchy_polkit_tui", TUI_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("could not load terminal TUI module")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_sgr_mouse_press_release() -> None:
    press = module.parse_sgr_mouse(b"\x1b[<0;43;16M")
    release = module.parse_sgr_mouse(b"\x1b[<0;43;16m")

    assert press == (0, 43, 16, False), press
    assert release == (0, 43, 16, True), release


def test_sgr_mouse_rejects_invalid_input() -> None:
    assert module.parse_sgr_mouse(b"not-mouse") is None
    assert module.parse_sgr_mouse(b"\x1b[<0;43M") is None
    assert module.parse_sgr_mouse(b"\x1b[<x;43;16M") is None


def test_input_parser_keeps_split_sgr_event() -> None:
    parser = module.InputParser()
    assert parser.feed(b"\x1b[<0;43") == []
    events = parser.feed(b";16M")
    assert len(events) == 1
    event = events[0]
    assert event.kind == "mouse"
    assert event.mouse == (0, 43, 16, False)


def test_input_parser_keyboard_controls() -> None:
    parser = module.InputParser()
    events = parser.feed(b"\t\r\x1b[Z\x7f")
    assert [event.kind for event in events] == ["tab", "enter", "backtab", "backspace"]


def test_input_parser_password_text() -> None:
    parser = module.InputParser()
    events = parser.feed(b"abc123")
    assert [event.kind for event in events] == ["text"] * 6
    assert b"".join(event.data for event in events) == b"abc123"


if __name__ == "__main__":
    test_sgr_mouse_press_release()
    test_sgr_mouse_rejects_invalid_input()
    test_input_parser_keeps_split_sgr_event()
    test_input_parser_keyboard_controls()
    test_input_parser_password_text()
    print("terminal Polkit TUI parser tests passed")
