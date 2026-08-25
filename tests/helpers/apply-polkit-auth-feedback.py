#!/usr/bin/env python3
from pathlib import Path

ROOT = Path.cwd()
TUI = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/tui.py"
AGENT = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/agent.py"
LAUNCHER = ROOT / "config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:80]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# --- Terminal TUI spinner + clean normal buffer ---
replace_once(
    TUI,
    'MOUSE_DISABLE = b"\\x1b[?1000l\\x1b[?1006l"\n\nC_RESET =',
    'MOUSE_DISABLE = b"\\x1b[?1000l\\x1b[?1006l"\n'
    'NORMAL_CLEAR = b"\\x1b[3J\\x1b[2J\\x1b[H"\n'
    'SPINNER_FRAMES = ("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")\n\n'
    'def spinner_text(index: int) -> str:\n'
    '    return f"Authenticating {SPINNER_FRAMES[index % len(SPINNER_FRAMES)]}"\n\n\n'
    'C_RESET =',
)

replace_once(
    TUI,
    '        self.status = ""\n        self.status_error = False\n        self._response = bytearray()\n'
    '        self.password_row = 0\n',
    '        self.status = ""\n        self.status_error = False\n'
    '        self.authenticating = False\n        self.spinner_index = 0\n'
    '        self._response = bytearray()\n        self.password_row = 0\n'
    '        self.status_row = 0\n',
)

replace_once(
    TUI,
    '        self._write(MOUSE_DISABLE + ALT_LEAVE)\n'
    '        termios.tcsetattr(self.tty_fd, termios.TCSANOW, self._saved_termios)\n',
    '        self._write(MOUSE_DISABLE + ALT_LEAVE + NORMAL_CLEAR)\n'
    '        termios.tcsetattr(self.tty_fd, termios.TCSANOW, self._saved_termios)\n',
)

replace_once(
    TUI,
    '        self.status = ""\n        self.status_error = False\n        self.focus = 0\n'
    '        self.details_expanded = False\n',
    '        self.status = ""\n        self.status_error = False\n'
    '        self.authenticating = False\n        self.spinner_index = 0\n'
    '        self.focus = 0\n        self.details_expanded = False\n',
)

replace_once(
    TUI,
    '    def hide(self) -> None:\n        self.clear_secret()\n        self.visible = False\n',
    '    def hide(self) -> None:\n        self.clear_secret()\n'
    '        self.authenticating = False\n        self.spinner_index = 0\n'
    '        self.visible = False\n',
)

replace_once(
    TUI,
    '    def set_identity_index(self, index: int) -> None:\n',
    '    def set_authenticating(self, active: bool) -> None:\n'
    '        active = bool(active)\n'
    '        if active:\n'
    '            self.clear_secret()\n'
    '            self.authenticating = True\n'
    '            self.spinner_index = 0\n'
    '            self.status = spinner_text(0)\n'
    '            self.status_error = False\n'
    '            self.focus = 2\n'
    '        else:\n'
    '            self.authenticating = False\n'
    '            self.spinner_index = 0\n'
    '            if self.status.startswith("Authenticating "):\n'
    '                self.status = ""\n'
    '                self.status_error = False\n'
    '        if self.visible:\n'
    '            self.render()\n\n'
    '    def advance_spinner(self) -> None:\n'
    '        if not self.authenticating:\n'
    '            return\n'
    '        self.spinner_index = (self.spinner_index + 1) % len(SPINNER_FRAMES)\n'
    '        self.status = spinner_text(self.spinner_index)\n'
    '        if self.visible:\n'
    '            self.render_status_only()\n\n'
    '    def set_identity_index(self, index: int) -> None:\n',
)

replace_once(
    TUI,
    '    def render(self) -> None:\n',
    '    def render_status_only(self) -> None:\n'
    '        if not self.visible or self.status_row <= 0:\n'
    '            return\n'
    '        columns, _ = self._columns_lines()\n'
    '        left = 3\n'
    '        self._print_at(self.status_row, left, " " * max(1, columns - left - 1))\n'
    '        if self.status:\n'
    '            color = C_RED if self.status_error else C_YELLOW\n'
    '            self._print_at(self.status_row, left, f"{color}{self.status}{C_RESET}"[: max(1, columns - left)])\n\n'
    '    def render(self) -> None:\n',
)

replace_once(
    TUI,
    '        if self.status:\n            color = C_RED if self.status_error else C_YELLOW\n'
    '            self._print_at(row, left, f"{color}{self.status}{C_RESET}"[: max(1, columns - left)])\n'
    '        row += 2\n',
    '        self.status_row = row\n'
    '        if self.status:\n            color = C_RED if self.status_error else C_YELLOW\n'
    '            self._print_at(row, left, f"{color}{self.status}{C_RESET}"[: max(1, columns - left)])\n'
    '        row += 2\n',
)

replace_once(
    TUI,
    '    def _submit(self) -> None:\n        if not self._response:\n',
    '    def _submit(self) -> None:\n        if self.authenticating:\n            return\n'
    '        if not self._response:\n',
)

replace_once(
    TUI,
    '    def handle_event(self, event: InputEvent) -> None:\n        if not self.visible:\n            return\n'
    '        if event.kind == "escape":\n',
    '    def handle_event(self, event: InputEvent) -> None:\n        if not self.visible:\n            return\n'
    '        if self.authenticating:\n'
    '            if event.kind == "escape":\n'
    '                self.on_cancel()\n'
    '                return\n'
    '            if event.kind == "mouse" and event.mouse is not None:\n'
    '                button, x, y, release = event.mouse\n'
    '                if not release and button == 0 and y == self.button_row and self.cancel_x1 <= x <= self.cancel_x2:\n'
    '                    self.on_cancel()\n'
    '            return\n'
    '        if event.kind == "escape":\n',
)

# --- Agent drives spinner around the real PAM response ---
replace_once(
    AGENT,
    '        self.retry_limit_reached = False\n\n        self.ui = TerminalUI(\n',
    '        self.retry_limit_reached = False\n'
    '        self.auth_feedback_source = 0\n\n'
    '        self.ui = TerminalUI(\n',
)

replace_once(
    AGENT,
    '    def _submit_response(self, response: str) -> None:\n'
    '        if self.begin_invocation is None or self.cancel_requested or self.retry_limit_reached:\n'
    '            return\n'
    '        if self.active_session is None:\n',
    '    def _advance_auth_feedback(self) -> bool:\n'
    '        if self.begin_invocation is None or self.cancel_requested or not self.ui.authenticating:\n'
    '            self.auth_feedback_source = 0\n'
    '            return GLib.SOURCE_REMOVE\n'
    '        self.ui.advance_spinner()\n'
    '        return GLib.SOURCE_CONTINUE\n\n'
    '    def _start_auth_feedback(self) -> None:\n'
    '        self.ui.set_authenticating(True)\n'
    '        if not self.auth_feedback_source:\n'
    '            self.auth_feedback_source = GLib.timeout_add(90, self._advance_auth_feedback)\n\n'
    '    def _stop_auth_feedback(self) -> None:\n'
    '        if self.auth_feedback_source:\n'
    '            GLib.source_remove(self.auth_feedback_source)\n'
    '            self.auth_feedback_source = 0\n'
    '        self.ui.set_authenticating(False)\n\n'
    '    def _submit_response(self, response: str) -> None:\n'
    '        if self.begin_invocation is None or self.cancel_requested or self.retry_limit_reached:\n'
    '            return\n'
    '        self._start_auth_feedback()\n'
    '        if self.active_session is None:\n',
)

replace_once(
    AGENT,
    '        self.ui.set_prompt(str(request), bool(echo_on))\n'
    '        if self.pending_response is not None:\n'
    '            response = self.pending_response\n'
    '            self.pending_response = None\n'
    '            session.response(response)\n',
    '        self.ui.set_prompt(str(request), bool(echo_on))\n'
    '        if self.pending_response is not None:\n'
    '            response = self.pending_response\n'
    '            self.pending_response = None\n'
    '            self._start_auth_feedback()\n'
    '            session.response(response)\n',
)

replace_once(
    AGENT,
    '    def _on_session_info(self, session: PolkitAgent.Session, text: str) -> None:\n'
    '        if session is self.active_session:\n'
    '            self.ui.set_status(str(text))\n\n'
    '    def _on_session_error(self, session: PolkitAgent.Session, text: str) -> None:\n'
    '        if session is self.active_session:\n'
    '            self.last_session_error = str(text).strip()\n'
    '            self.ui.set_error(self._friendly_auth_error())\n',
    '    def _on_session_info(self, session: PolkitAgent.Session, text: str) -> None:\n'
    '        if session is self.active_session:\n'
    '            self._stop_auth_feedback()\n'
    '            self.ui.set_status(str(text))\n\n'
    '    def _on_session_error(self, session: PolkitAgent.Session, text: str) -> None:\n'
    '        if session is self.active_session:\n'
    '            self._stop_auth_feedback()\n'
    '            self.last_session_error = str(text).strip()\n'
    '            self.ui.set_error(self._friendly_auth_error())\n',
)

replace_once(
    AGENT,
    '    def _on_session_completed(self, session: PolkitAgent.Session, gained_authorization: bool) -> None:\n'
    '        if session is not self.active_session:\n'
    '            return\n'
    '        self.active_session = None\n',
    '    def _on_session_completed(self, session: PolkitAgent.Session, gained_authorization: bool) -> None:\n'
    '        if session is not self.active_session:\n'
    '            return\n'
    '        self._stop_auth_feedback()\n'
    '        self.active_session = None\n',
)

replace_once(
    AGENT,
    '        self.cancel_requested = True\n        self.pending_response = None\n        self.ui.clear_secret()\n',
    '        self.cancel_requested = True\n        self.pending_response = None\n'
    '        self._stop_auth_feedback()\n        self.ui.clear_secret()\n',
)

replace_once(
    AGENT,
    '    def _finish_request(self, *, cancelled: bool, error: str = "") -> None:\n'
    '        invocation = self.begin_invocation\n',
    '    def _finish_request(self, *, cancelled: bool, error: str = "") -> None:\n'
    '        self._stop_auth_feedback()\n'
    '        invocation = self.begin_invocation\n',
)

# --- Keep Python warnings/errors out of the Alacritty normal buffer ---
replace_once(
    LAUNCHER,
    'HYPRCTL="/usr/bin/hyprctl"\nAPP_ID="awtarchy-polkit-agent"\n',
    'HYPRCTL="/usr/bin/hyprctl"\nSYSTEMD_CAT="/usr/bin/systemd-cat"\nAPP_ID="awtarchy-polkit-agent"\n',
)

replace_once(
    LAUNCHER,
    '    verify_system_binary "$HYPRCTL" || return 1\n\n'
    '    verify_root_owned_directory "$RUNTIME_DIR" || return 1\n',
    '    verify_system_binary "$HYPRCTL" || return 1\n'
    '    verify_system_binary "$SYSTEMD_CAT" || return 1\n\n'
    '    verify_root_owned_directory "$RUNTIME_DIR" || return 1\n',
)

replace_once(
    LAUNCHER,
    '        --title "$APP_ID" \\\n        -e "$PYTHON" -I "$AGENT"\n',
    '        --title "$APP_ID" \\\n'
    '        -e "$SYSTEMD_CAT" \\\n'
    '        --identifier=awtarchy-polkit-agent \\\n'
    '        "$PYTHON" -I "$AGENT"\n',
)

print("applied Polkit authentication feedback implementation")
