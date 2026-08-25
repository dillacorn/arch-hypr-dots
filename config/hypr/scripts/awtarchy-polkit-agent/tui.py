#!/usr/bin/env python3
"""Terminal UI and Hyprland window control for Awtarchy's PolicyKit agent."""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
import re
import subprocess
import termios
import textwrap
from typing import Callable, Optional

APP_ID = "awtarchy-polkit-agent"
WINDOW_WIDTH = 900
WINDOW_HEIGHT = 520
HIDDEN_WORKSPACE = "special:awtarchy-polkit-agent"
HYPRCTL = "/usr/bin/hyprctl"

ESC = b"\x1b"
ALT_ENTER = b"\x1b[?1049h\x1b[2J\x1b[H\x1b[?25l"
ALT_LEAVE = b"\x1b[?25h\x1b[0m\x1b[?1049l"
MOUSE_ENABLE = b"\x1b[?1000h\x1b[?1006h"
MOUSE_DISABLE = b"\x1b[?1000l\x1b[?1006l"
NORMAL_CLEAR = b"\x1b[3J\x1b[2J\x1b[H"
SPINNER_FRAMES = ("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")

def spinner_text(index: int) -> str:
    return f"Authenticating {SPINNER_FRAMES[index % len(SPINNER_FRAMES)]}"


C_RESET = "\x1b[0m"
C_BOLD = "\x1b[1m"
C_DIM = "\x1b[2m"
C_ACCENT = "\x1b[1;35m"
C_GREEN = "\x1b[1;32m"
C_RED = "\x1b[1;31m"
C_YELLOW = "\x1b[1;33m"
C_REVERSE = "\x1b[7m"

_SGR_MOUSE = re.compile(rb"^\x1b\[<(\d+);(\d+);(\d+)([Mm])$")
_SGR_MOUSE_PREFIX = re.compile(rb"^\x1b\[<[0-9;]*$")


@dataclass(frozen=True)
class InputEvent:
    kind: str
    data: bytes = b""
    mouse: Optional[tuple[int, int, int, bool]] = None


def parse_sgr_mouse(data: bytes) -> Optional[tuple[int, int, int, bool]]:
    """Parse xterm SGR mouse input as (button, x, y, release)."""
    match = _SGR_MOUSE.fullmatch(data)
    if match is None:
        return None
    button = int(match.group(1))
    x = int(match.group(2))
    y = int(match.group(3))
    release = match.group(4) == b"m"
    return button, x, y, release


class InputParser:
    """Incremental parser for keyboard and xterm SGR mouse input."""

    def __init__(self) -> None:
        self._buffer = bytearray()

    def feed(self, data: bytes) -> list[InputEvent]:
        if data:
            self._buffer.extend(data)
        events: list[InputEvent] = []

        while self._buffer:
            buf = bytes(self._buffer)

            if buf.startswith(b"\x1b[<"):
                end = None
                for index, value in enumerate(self._buffer):
                    if index >= 3 and value in (ord("M"), ord("m")):
                        end = index + 1
                        break
                if end is None:
                    if _SGR_MOUSE_PREFIX.match(buf):
                        break
                    del self._buffer[0]
                    events.append(InputEvent("escape"))
                    continue
                sequence = bytes(self._buffer[:end])
                parsed = parse_sgr_mouse(sequence)
                if parsed is not None:
                    del self._buffer[:end]
                    events.append(InputEvent("mouse", mouse=parsed))
                    continue
                del self._buffer[0]
                events.append(InputEvent("escape"))
                continue

            known = (
                (b"\x1b[Z", "backtab"),
                (b"\x1b[A", "up"),
                (b"\x1b[B", "down"),
                (b"\x1b[C", "right"),
                (b"\x1b[D", "left"),
            )
            matched = False
            for sequence, kind in known:
                if buf.startswith(sequence):
                    del self._buffer[: len(sequence)]
                    events.append(InputEvent(kind))
                    matched = True
                    break
                if sequence.startswith(buf):
                    return events
            if matched:
                continue

            first = self._buffer[0]
            if first == 0x1B:
                if len(self._buffer) == 1:
                    break
                del self._buffer[0]
                events.append(InputEvent("escape"))
            elif first == 0x09:
                del self._buffer[0]
                events.append(InputEvent("tab"))
            elif first in (0x0A, 0x0D):
                del self._buffer[0]
                events.append(InputEvent("enter"))
            elif first in (0x08, 0x7F):
                del self._buffer[0]
                events.append(InputEvent("backspace"))
            elif first in (0x03, 0x04):
                del self._buffer[0]
                events.append(InputEvent("escape"))
            else:
                del self._buffer[0]
                events.append(InputEvent("text", data=bytes((first,))))

        return events

    def flush_escape(self) -> list[InputEvent]:
        if self._buffer == bytearray(b"\x1b"):
            self._buffer.clear()
            return [InputEvent("escape")]
        return []


class TerminalUI:
    """Approved terminal authentication UI plus exact-window Hyprland control."""

    def __init__(
        self,
        on_submit: Callable[[str], None],
        on_cancel: Callable[[], None],
        on_identity_cycle: Callable[[int], None],
    ) -> None:
        self.on_submit = on_submit
        self.on_cancel = on_cancel
        self.on_identity_cycle = on_identity_cycle
        self.tty_fd = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
        self._saved_termios = termios.tcgetattr(self.tty_fd)
        self.parser = InputParser()
        self.visible = False
        self.raw_active = False
        self.focus = 0
        self.details_expanded = False
        self.action_id = ""
        self.message = "Authentication is required."
        self.vendor = "Unavailable"
        self.description = "Unavailable"
        self.identities: list[str] = []
        self.identity_index = 0
        self.prompt = "Password:"
        self.echo_on = False
        self.status = ""
        self.status_error = False
        self.authenticating = False
        self.spinner_index = 0
        self._response = bytearray()
        self.password_row = 0
        self.status_row = 0
        self.details_row = 0
        self.identity_row = 0
        self.button_row = 0
        self.cancel_x1 = self.cancel_x2 = 0
        self.auth_x1 = self.auth_x2 = 0
        self._last_workspace = "1"

    def close(self) -> None:
        try:
            self.hide()
        finally:
            try:
                termios.tcsetattr(self.tty_fd, termios.TCSANOW, self._saved_termios)
            except termios.error:
                pass
            os.close(self.tty_fd)

    def _write(self, data: bytes | str) -> None:
        payload = data.encode("utf-8", "replace") if isinstance(data, str) else data
        os.write(self.tty_fd, payload)

    def _enter_raw(self) -> None:
        if self.raw_active:
            return
        attrs = termios.tcgetattr(self.tty_fd)
        attrs[3] &= ~(termios.ECHO | termios.ICANON)
        attrs[6][termios.VMIN] = 1
        attrs[6][termios.VTIME] = 0
        termios.tcsetattr(self.tty_fd, termios.TCSANOW, attrs)
        self._write(ALT_ENTER + MOUSE_ENABLE)
        self.raw_active = True

    def _leave_raw(self) -> None:
        if not self.raw_active:
            return
        self._write(MOUSE_DISABLE + ALT_LEAVE + NORMAL_CLEAR)
        termios.tcsetattr(self.tty_fd, termios.TCSANOW, self._saved_termios)
        self.raw_active = False

    def _hypr(self, *args: str, capture: bool = False) -> str:
        result = subprocess.run(
            [HYPRCTL, *args],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=2.0,
        )
        if result.returncode != 0:
            raise RuntimeError(f"hyprctl failed: {' '.join(args)}")
        return result.stdout if capture else ""

    def _window(self) -> Optional[dict]:
        try:
            clients = json.loads(self._hypr("-j", "clients", capture=True))
        except (RuntimeError, json.JSONDecodeError):
            return None
        matches = []
        for client in clients if isinstance(clients, list) else []:
            if not isinstance(client, dict) or not client.get("mapped", True):
                continue
            identities = {
                str(client.get("class") or ""),
                str(client.get("initialClass") or ""),
                str(client.get("title") or ""),
                str(client.get("initialTitle") or ""),
            }
            if APP_ID not in identities:
                continue
            address = str(client.get("address") or "")
            if re.fullmatch(r"0x[0-9a-fA-F]+", address):
                matches.append(client)
        if not matches:
            return None
        matches.sort(key=lambda item: int(item.get("focusHistoryID", 999999)))
        return matches[0]

    def _active_workspace(self) -> str:
        try:
            payload = json.loads(self._hypr("-j", "activeworkspace", capture=True))
        except (RuntimeError, json.JSONDecodeError):
            return self._last_workspace
        name = str(payload.get("name") or "") if isinstance(payload, dict) else ""
        if name and not name.startswith("special:"):
            self._last_workspace = name
        return self._last_workspace

    @staticmethod
    def _lua_string(value: str) -> str:
        return (
            value.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\n", "\\n")
            .replace("\r", "\\r")
        )

    def _move_window(self, workspace: str, focus: bool) -> None:
        client = self._window()
        if client is None:
            raise RuntimeError("Awtarchy PolicyKit terminal window not found")
        address = str(client["address"])
        selector = self._lua_string(f"address:{address}")
        workspace_value = self._lua_string(workspace)
        commands = [
            f'local w="{selector}"',
            f'local workspace="{workspace_value}"',
            'hl.dispatch(hl.dsp.window.move({ workspace = workspace, follow = false, window = w }))',
        ]
        if focus:
            commands.extend(
                [
                    'hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))',
                    f'hl.dispatch(hl.dsp.window.resize({{ x = {WINDOW_WIDTH}, y = {WINDOW_HEIGHT}, relative = false, window = w }}))',
                    'hl.dispatch(hl.dsp.window.center({ window = w }))',
                    'hl.dispatch(hl.dsp.focus({ window = w }))',
                ]
            )
        self._hypr("eval", "; ".join(commands))

    def prime_hidden(self) -> None:
        """Hide the service terminal after Alacritty maps it."""
        for _ in range(50):
            if self._window() is not None:
                self._move_window(HIDDEN_WORKSPACE, focus=False)
                return
            import time
            time.sleep(0.04)
        raise RuntimeError("Awtarchy PolicyKit terminal did not appear")

    def show_request(
        self,
        *,
        action_id: str,
        message: str,
        vendor: str,
        description: str,
        identities: list[str],
        identity_index: int,
    ) -> None:
        self.clear_secret()
        self.action_id = action_id
        self.message = message or "Authentication is required."
        self.vendor = vendor or "Unavailable"
        self.description = description or "Unavailable"
        self.identities = list(identities)
        self.identity_index = max(0, min(identity_index, max(0, len(self.identities) - 1)))
        self.prompt = "Password:"
        self.echo_on = False
        self.status = ""
        self.status_error = False
        self.authenticating = False
        self.spinner_index = 0
        self.focus = 0
        self.details_expanded = False
        workspace = self._active_workspace()
        self._move_window(workspace, focus=True)
        self._enter_raw()
        self.visible = True
        self.render()

    def hide(self) -> None:
        self.clear_secret()
        self.authenticating = False
        self.spinner_index = 0
        self.visible = False
        self._leave_raw()
        try:
            if self._window() is not None:
                self._move_window(HIDDEN_WORKSPACE, focus=False)
        except RuntimeError:
            pass

    def set_prompt(self, prompt: str, echo_on: bool) -> None:
        self.clear_secret()
        self.prompt = (prompt or "Password:").strip() or "Password:"
        self.echo_on = bool(echo_on)
        self.status = ""
        self.status_error = False
        self.focus = 0
        if self.visible:
            self.render()

    def set_status(self, message: str) -> None:
        self.status = message or ""
        self.status_error = False
        if self.visible:
            self.render()

    def set_error(self, message: str) -> None:
        self.clear_secret()
        self.status = message or "Authentication failed."
        self.status_error = True
        self.focus = 0
        if self.visible:
            self.render()

    def set_authenticating(self, active: bool) -> None:
        active = bool(active)
        if active:
            self.clear_secret()
            self.authenticating = True
            self.spinner_index = 0
            self.status = spinner_text(0)
            self.status_error = False
            self.focus = 2
        else:
            self.authenticating = False
            self.spinner_index = 0
            if self.status.startswith("Authenticating "):
                self.status = ""
                self.status_error = False
        if self.visible:
            self.render()

    def advance_spinner(self) -> None:
        if not self.authenticating:
            return
        self.spinner_index = (self.spinner_index + 1) % len(SPINNER_FRAMES)
        self.status = spinner_text(self.spinner_index)
        if self.visible:
            self.render_status_only()

    def set_identity_index(self, index: int) -> None:
        if not self.identities:
            self.identity_index = 0
            return
        self.identity_index = index % len(self.identities)
        if self.visible:
            self.render()

    def clear_secret(self) -> None:
        for index in range(len(self._response)):
            self._response[index] = 0
        self._response.clear()
        if self.visible and self.password_row:
            self.render_password_field_only()

    def _columns_lines(self) -> tuple[int, int]:
        try:
            size = os.get_terminal_size(self.tty_fd)
            return size.columns, size.lines
        except OSError:
            return 100, 28

    def _goto(self, row: int, column: int) -> None:
        self._write(f"\x1b[{row};{column}H")

    def _print_at(self, row: int, column: int, text: str) -> None:
        self._goto(row, column)
        self._write(text)

    def _focus(self, index: int, text: str, color: str) -> str:
        if self.focus == index:
            return f"{C_REVERSE}{color}{text}{C_RESET}"
        return f"{color}{text}{C_RESET}"

    def _field_text(self, columns: int) -> str:
        width = 40
        if columns < 72:
            width = 28
        elif columns > 100:
            width = 46
        if self.echo_on:
            shown = bytes(self._response[-width:]).decode("utf-8", "replace")
            shown = shown[-width:]
        else:
            shown = "•" * min(len(self._response), width)
        content = shown + (" " * max(0, width - len(shown)))
        if self.focus == 0:
            return f"{C_REVERSE}[{content}]{C_RESET}"
        return f"[{content}]"

    def render_password_field_only(self) -> None:
        if not self.visible or self.password_row <= 0:
            return
        columns, _ = self._columns_lines()
        label = self.prompt if self.prompt.endswith(":") else f"{self.prompt}:"
        self._print_at(self.password_row, 3, " " * max(1, columns - 4))
        self._print_at(self.password_row, 3, f"{label:<10} {self._field_text(columns)}")

    def render_status_only(self) -> None:
        if not self.visible or self.status_row <= 0:
            return
        columns, _ = self._columns_lines()
        left = 3
        self._print_at(self.status_row, left, " " * max(1, columns - left - 1))
        if self.status:
            color = C_RED if self.status_error else C_YELLOW
            self._print_at(self.status_row, left, f"{color}{self.status}{C_RESET}"[: max(1, columns - left)])

    def render(self) -> None:
        if not self.visible:
            return
        columns, lines = self._columns_lines()
        self._write(b"\x1b[H\x1b[2J")
        if columns < 64 or lines < 20:
            self._print_at(2, 2, f"{C_YELLOW}{C_BOLD}Authentication window is below the minimum terminal cell size.{C_RESET}")
            self._print_at(4, 2, f"Awtarchy will keep the window at {WINDOW_WIDTH}x{WINDOW_HEIGHT}.")
            self._print_at(6, 2, "Esc cancels authentication.")
            return

        left = 3
        row = 2
        self._print_at(row, left, f"{C_ACCENT}{C_BOLD}Authentication Required{C_RESET}")
        row += 2

        wrapped = textwrap.wrap(self.message, width=max(40, columns - 6)) or ["Authentication is required."]
        for line in wrapped[:3]:
            self._print_at(row, left, line)
            row += 1
        row += 1

        self.password_row = row
        label = self.prompt if self.prompt.endswith(":") else f"{self.prompt}:"
        self._print_at(row, left, f"{label:<10} {self._field_text(columns)}")
        row += 2

        self.details_row = row
        marker = "▼ Details:" if self.details_expanded else "▶ Details:"
        self._print_at(row, left, self._focus(1, marker, C_ACCENT))
        row += 1
        self.identity_row = 0

        if self.details_expanded:
            details = [
                ("Action:", self.action_id or "Unavailable"),
                ("Vendor:", self.vendor or "Unavailable"),
                ("Description:", self.description or "Unavailable"),
                ("Identity:", self.identities[self.identity_index] if self.identities else "Unavailable"),
            ]
            for label_text, value in details:
                if label_text == "Identity:":
                    self.identity_row = row
                    if len(self.identities) > 1:
                        value = f"{value}   (Left/Right to change)"
                self._print_at(row, left + 2, f"{C_DIM}{label_text:<13}{C_RESET}{value}"[: max(1, columns - left - 2)])
                row += 1
            row += 1
        else:
            row += 1

        cancel = "[ Cancel ]"
        authenticate = "[ Authenticate ]"
        gap = 6
        total = len(cancel) + gap + len(authenticate)
        start = max(left, (columns - total) // 2 + 1)
        self.button_row = row
        self.cancel_x1 = start
        self.cancel_x2 = start + len(cancel) - 1
        self.auth_x1 = self.cancel_x2 + gap + 1
        self.auth_x2 = self.auth_x1 + len(authenticate) - 1
        self._print_at(row, self.cancel_x1, self._focus(2, cancel, C_RED))
        self._print_at(row, self.auth_x1, self._focus(3, authenticate, C_GREEN))
        row += 2

        self.status_row = row
        if self.status:
            color = C_RED if self.status_error else C_YELLOW
            self._print_at(row, left, f"{color}{self.status}{C_RESET}"[: max(1, columns - left)])
        row += 2
        hint = "Tab/Shift+Tab: move   Enter: activate   Mouse: click   Esc: cancel"
        self._print_at(row, left, f"{C_DIM}{hint}{C_RESET}")

    def read_input(self) -> list[InputEvent]:
        try:
            data = os.read(self.tty_fd, 4096)
        except BlockingIOError:
            return []
        return self.parser.feed(data)

    def flush_pending_input(self) -> None:
        for event in self.parser.flush_escape():
            self.handle_event(event)

    def _submit(self) -> None:
        if self.authenticating:
            return
        if not self._response:
            self.status = "Password not entered."
            self.status_error = False
            self.render()
            return
        raw = bytes(self._response)
        try:
            response = raw.decode("utf-8")
        except UnicodeDecodeError:
            self.set_error("Input is not valid UTF-8.")
            return
        self.clear_secret()
        self.on_submit(response)
        response = ""

    def handle_event(self, event: InputEvent) -> None:
        if not self.visible:
            return
        if self.authenticating:
            if event.kind == "escape":
                self.on_cancel()
                return
            if event.kind == "mouse" and event.mouse is not None:
                button, x, y, release = event.mouse
                if not release and button == 0 and y == self.button_row and self.cancel_x1 <= x <= self.cancel_x2:
                    self.on_cancel()
            return
        if event.kind == "escape":
            self.on_cancel()
            return
        if event.kind == "tab":
            self.focus = (self.focus + 1) % 4
            self.render()
            return
        if event.kind == "backtab":
            self.focus = (self.focus - 1) % 4
            self.render()
            return
        if event.kind in ("left", "right") and self.focus == 1 and len(self.identities) > 1:
            delta = -1 if event.kind == "left" else 1
            self.on_identity_cycle(delta)
            return
        if event.kind == "backspace" and self.focus == 0:
            if self._response:
                self._response[-1] = 0
                self._response.pop()
                self.render_password_field_only()
            return
        if event.kind == "enter":
            if self.focus == 1:
                self.details_expanded = not self.details_expanded
                self.render()
            elif self.focus == 2:
                self.on_cancel()
            else:
                self._submit()
            return
        if event.kind == "text":
            if self.focus == 0:
                if len(self._response) < 512:
                    self._response.extend(event.data)
                    self.render_password_field_only()
            elif event.data == b" ":
                if self.focus == 1:
                    self.details_expanded = not self.details_expanded
                    self.render()
                elif self.focus == 2:
                    self.on_cancel()
                elif self.focus == 3:
                    self._submit()
            return
        if event.kind != "mouse" or event.mouse is None:
            return
        button, x, y, release = event.mouse
        if release or button != 0:
            return
        if y == self.password_row:
            self.focus = 0
            self.render()
        elif y == self.details_row:
            self.focus = 1
            self.details_expanded = not self.details_expanded
            self.render()
        elif self.identity_row and y == self.identity_row and len(self.identities) > 1:
            self.focus = 1
            self.on_identity_cycle(1)
        elif y == self.button_row and self.cancel_x1 <= x <= self.cancel_x2:
            self.focus = 2
            self.on_cancel()
        elif y == self.button_row and self.auth_x1 <= x <= self.auth_x2:
            self.focus = 3
            self._submit()
