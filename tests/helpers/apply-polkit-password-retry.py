#!/usr/bin/env python3
from pathlib import Path

path = Path("config/hypr/scripts/awtarchy-polkit-agent/agent.py")
text = path.read_text(encoding="utf-8")

replacements = [
    (
        'SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")\n',
        'SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")\nMAX_AUTH_ATTEMPTS = 3\n',
    ),
    (
        '        self.active_session: Optional[PolkitAgent.Session] = None\n'
        '        self.pending_response: Optional[str] = None\n'
        '        self.cancel_requested = False\n',
        '        self.active_session: Optional[PolkitAgent.Session] = None\n'
        '        self.pending_response: Optional[str] = None\n'
        '        self.cancel_requested = False\n'
        '        self.auth_attempts = 0\n'
        '        self.last_session_error = ""\n'
        '        self.retry_limit_reached = False\n',
    ),
    (
        '        self.active_session = None\n'
        '        self.pending_response = None\n'
        '        self.cancel_requested = False\n\n'
        '        try:\n'
        '            self.ui.show_request(\n',
        '        self.active_session = None\n'
        '        self.pending_response = None\n'
        '        self.cancel_requested = False\n'
        '        self.auth_attempts = 0\n'
        '        self.last_session_error = ""\n'
        '        self.retry_limit_reached = False\n\n'
        '        try:\n'
        '            self.ui.show_request(\n',
    ),
    (
        '    def _submit_response(self, response: str) -> None:\n'
        '        if self.begin_invocation is None or self.cancel_requested:\n'
        '            return\n',
        '    def _submit_response(self, response: str) -> None:\n'
        '        if self.begin_invocation is None or self.cancel_requested or self.retry_limit_reached:\n'
        '            return\n',
    ),
    (
        '    def _start_session(self) -> None:\n'
        '        if self.begin_invocation is None or self.active_session is not None:\n'
        '            return\n'
        '        identity = self.identity_objects[self.identity_index]\n',
        '    def _start_session(self) -> None:\n'
        '        if self.begin_invocation is None or self.active_session is not None or self.retry_limit_reached:\n'
        '            return\n'
        '        self.auth_attempts += 1\n'
        '        self.last_session_error = ""\n'
        '        identity = self.identity_objects[self.identity_index]\n',
    ),
    (
        '    def _on_session_error(self, session: PolkitAgent.Session, text: str) -> None:\n'
        '        if session is self.active_session:\n'
        '            self.ui.set_error(str(text))\n\n'
        '    def _on_session_completed(self, session: PolkitAgent.Session, gained_authorization: bool) -> None:\n'
        '        if session is not self.active_session:\n'
        '            return\n'
        '        # The helper tells polkitd about successful authorization itself. The\n'
        '        # D-Bus method simply remains outstanding until this conversation ends.\n'
        '        # Only explicit cancellation is returned as Request dismissed.\n'
        '        del gained_authorization\n'
        '        self._finish_request(cancelled=self.cancel_requested)\n',
        '    def _on_session_error(self, session: PolkitAgent.Session, text: str) -> None:\n'
        '        if session is self.active_session:\n'
        '            self.last_session_error = str(text).strip()\n'
        '            self.ui.set_error(self._friendly_auth_error())\n\n'
        '    def _friendly_auth_error(self) -> str:\n'
        '        message = self.last_session_error.strip()\n'
        '        normalized = message.casefold()\n'
        '        password_failure_markers = (\n'
        '            "authentication failure",\n'
        '            "authentication failed",\n'
        '            "incorrect password",\n'
        '            "password incorrect",\n'
        '            "sorry, try again",\n'
        '        )\n'
        '        if any(marker in normalized for marker in password_failure_markers):\n'
        '            return "Incorrect password. Try again."\n'
        '        if message:\n'
        '            return message\n'
        '        if not self.ui.echo_on and "password" in self.ui.prompt.casefold():\n'
        '            return "Incorrect password. Try again."\n'
        '        return "Authentication failed. Try again."\n\n'
        '    def _on_session_completed(self, session: PolkitAgent.Session, gained_authorization: bool) -> None:\n'
        '        if session is not self.active_session:\n'
        '            return\n'
        '        self.active_session = None\n'
        '        self.pending_response = None\n\n'
        '        # The helper reports successful authorization to polkitd itself. Keep\n'
        '        # BeginAuthentication outstanding across failed PAM sessions so a typo\n'
        '        # can be retried with the same PolicyKit cookie.\n'
        '        if gained_authorization:\n'
        '            self._finish_request(cancelled=False)\n'
        '            return\n'
        '        if self.cancel_requested:\n'
        '            self._finish_request(cancelled=True)\n'
        '            return\n\n'
        '        self.ui.clear_secret()\n'
        '        if self.auth_attempts < MAX_AUTH_ATTEMPTS:\n'
        '            self.ui.set_error(self._friendly_auth_error())\n'
        '            return\n\n'
        '        self.retry_limit_reached = True\n'
        '        self.ui.set_error(f"Authentication failed after {MAX_AUTH_ATTEMPTS} attempts.")\n'
        '        GLib.timeout_add(1200, self._finish_denied_after_retry_limit)\n\n'
        '    def _finish_denied_after_retry_limit(self) -> bool:\n'
        '        if self.begin_invocation is not None and not self.cancel_requested:\n'
        '            self._finish_request(cancelled=False)\n'
        '        return GLib.SOURCE_REMOVE\n',
    ),
    (
        '        self.identity_labels = []\n'
        '        self.identity_index = 0\n'
        '        self.cancel_requested = False\n'
        '        self.ui.hide()\n',
        '        self.identity_labels = []\n'
        '        self.identity_index = 0\n'
        '        self.cancel_requested = False\n'
        '        self.auth_attempts = 0\n'
        '        self.last_session_error = ""\n'
        '        self.retry_limit_reached = False\n'
        '        self.ui.hide()\n',
    ),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one match, found {count}: {old[:80]!r}")
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
