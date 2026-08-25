#!/usr/bin/env python3
"""Awtarchy terminal PolicyKit authentication agent."""

from __future__ import annotations

import locale
import os
import pwd
import re
import signal
import subprocess
import sys
from typing import Any, Optional

import gi

gi.require_version("Polkit", "1.0")
gi.require_version("PolkitAgent", "1.0")
from gi.repository import Gio, GLib, Polkit, PolkitAgent

RUNTIME_DIR = os.path.dirname(os.path.realpath(__file__))
if RUNTIME_DIR not in sys.path:
    # python -I intentionally removes the script directory from sys.path. The
    # only path restored here is the verified root-owned Awtarchy runtime.
    sys.path.insert(0, RUNTIME_DIR)

from tui import TerminalUI

OBJECT_PATH = "/org/awtarchy/PolkitAgent"
INTERFACE_NAME = "org.freedesktop.PolicyKit1.AuthenticationAgent"
ERROR_FAILED = "org.freedesktop.PolicyKit1.Error.Failed"
ERROR_CANCELLED = "org.freedesktop.PolicyKit1.Error.Cancelled"
PKACTION = "/usr/bin/pkaction"
SYSTEMD_CAT = "/usr/bin/systemd-cat"
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")
MAX_AUTH_ATTEMPTS = 3

INTROSPECTION_XML = """
<node>
  <interface name="org.freedesktop.PolicyKit1.AuthenticationAgent">
    <method name="BeginAuthentication">
      <arg type="s" name="action_id" direction="in"/>
      <arg type="s" name="message" direction="in"/>
      <arg type="s" name="icon_name" direction="in"/>
      <arg type="a{ss}" name="details" direction="in"/>
      <arg type="s" name="cookie" direction="in"/>
      <arg type="a(sa{sv})" name="identities" direction="in"/>
    </method>
    <method name="CancelAuthentication">
      <arg type="s" name="cookie" direction="in"/>
    </method>
  </interface>
</node>
"""


def journal_message(priority: str, message: str) -> None:
    """Write non-secret startup diagnostics to the user journal."""
    try:
        subprocess.run(
            [
                SYSTEMD_CAT,
                "--identifier=awtarchy-polkit-agent",
                f"--priority={priority}",
            ],
            input=f"{message}\n",
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},
            timeout=2.0,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


class TerminalPolkitAgent:
    def __init__(self) -> None:
        self.loop = GLib.MainLoop()
        self.connection: Optional[Gio.DBusConnection] = None
        self.registration_id = 0
        self.authority: Optional[Polkit.Authority] = None
        self.subject: Optional[Polkit.Subject] = None
        self.registered = False
        self.shutting_down = False

        self.begin_invocation: Optional[Gio.DBusMethodInvocation] = None
        self.active_cookie = ""
        self.active_action_id = ""
        self.identity_objects: list[Polkit.Identity] = []
        self.identity_labels: list[str] = []
        self.identity_index = 0
        self.active_session: Optional[PolkitAgent.Session] = None
        self.pending_response: Optional[str] = None
        self.cancel_requested = False
        self.auth_attempts = 0
        self.last_session_error = ""
        self.retry_limit_reached = False

        self.ui = TerminalUI(
            on_submit=self._submit_response,
            on_cancel=self._cancel_from_ui,
            on_identity_cycle=self._cycle_identity,
        )

    @staticmethod
    def _agent_locale() -> str:
        try:
            locale.setlocale(locale.LC_ALL, "")
        except locale.Error:
            pass
        return (
            os.environ.get("LC_ALL")
            or os.environ.get("LC_MESSAGES")
            or os.environ.get("LANG")
            or "C.UTF-8"
        )

    @staticmethod
    def _variant_value(value: Any) -> Any:
        return value.unpack() if hasattr(value, "unpack") else value

    @staticmethod
    def _identity_label(uid: int) -> str:
        try:
            name = pwd.getpwuid(uid).pw_name
        except KeyError:
            name = str(uid)
        return f"unix-user:{name}"

    def _decode_identities(self, raw_identities: Any) -> tuple[list[Polkit.Identity], list[str], int]:
        objects: list[Polkit.Identity] = []
        labels: list[str] = []
        current_uid = os.getuid()
        preferred = 0

        for raw_identity in raw_identities:
            try:
                kind, properties = raw_identity
            except (TypeError, ValueError):
                continue
            if str(kind) != "unix-user" or not isinstance(properties, dict):
                continue
            uid_value = self._variant_value(properties.get("uid"))
            try:
                uid = int(uid_value)
            except (TypeError, ValueError):
                continue
            if uid < 0:
                continue
            try:
                identity = Polkit.UnixUser.new(uid)
            except (TypeError, GLib.Error):
                continue
            if identity is None:
                continue
            if uid == current_uid:
                preferred = len(objects)
            objects.append(identity)
            labels.append(self._identity_label(uid))

        return objects, labels, preferred

    @staticmethod
    def _action_metadata(action_id: str) -> tuple[str, str]:
        if not action_id:
            return "Unavailable", "Unavailable"
        try:
            result = subprocess.run(
                [PKACTION, "--action-id", action_id, "--verbose"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                encoding="utf-8",
                errors="replace",
                env={"PATH": "/usr/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},
                timeout=2.0,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            return "Unavailable", "Unavailable"

        vendor = "Unavailable"
        description = "Unavailable"
        fallback_message = ""
        for raw_line in result.stdout.splitlines():
            line = raw_line.strip()
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            key = key.strip().lower()
            value = value.strip()
            if not value:
                continue
            if key == "vendor":
                vendor = value
            elif key == "description":
                description = value
            elif key == "message":
                fallback_message = value
        if description == "Unavailable" and fallback_message:
            description = fallback_message
        return vendor, description

    def start(self) -> None:
        node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
        interface_info = node.interfaces[0]

        self.connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.registration_id = self.connection.register_object(
            OBJECT_PATH,
            interface_info,
            self._on_method_call,
            None,
            None,
        )
        if not self.registration_id:
            raise RuntimeError("could not export PolicyKit authentication agent object")

        # This process is supervised by systemd --user and may therefore live
        # outside the graphical session's session-*.scope. Register against the
        # explicit logind session inherited from Hyprland instead of asking
        # PolicyKit to infer a session from this service process PID.
        session_id = os.environ.get("XDG_SESSION_ID", "")
        if not SESSION_ID_RE.fullmatch(session_id):
            raise RuntimeError("XDG_SESSION_ID is unavailable or invalid")
        self.subject = Polkit.UnixSession.new(session_id)
        if self.subject is None:
            raise RuntimeError("could not construct the graphical PolicyKit session subject")

        self.authority = Polkit.Authority.get_sync(None)
        self.authority.register_authentication_agent_sync(
            self.subject,
            self._agent_locale(),
            OBJECT_PATH,
            None,
        )
        self.registered = True
        journal_message("info", "startup: PolicyKit authentication agent registered")

        # Alacritty is already mapped by the time this child is running. Keep the
        # registered agent alive but put its terminal on a private special
        # workspace until PolicyKit starts a request.
        self.ui.prime_hidden()
        journal_message("info", "startup: authentication terminal hidden and ready")

        conditions = GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR
        self.tty_channel = GLib.IOChannel.unix_new(self.ui.tty_fd)
        self.tty_channel.set_close_on_unref(False)
        self.tty_channel.add_watch(conditions, self._on_tty_ready)
        GLib.timeout_add(45, self._flush_pending_escape)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self._on_signal)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, self._on_signal)

        self.loop.run()

    def _on_tty_ready(self, channel: GLib.IOChannel, condition: GLib.IOCondition) -> bool:
        del channel
        if condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
            self.shutdown()
            return False
        for event in self.ui.read_input():
            self.ui.handle_event(event)
        return not self.shutting_down

    def _flush_pending_escape(self) -> bool:
        if self.shutting_down:
            return False
        self.ui.flush_pending_input()
        return True

    def _on_signal(self) -> bool:
        self.shutdown()
        return GLib.SOURCE_REMOVE

    def _on_method_call(
        self,
        connection: Gio.DBusConnection,
        sender: str,
        object_path: str,
        interface_name: str,
        method_name: str,
        parameters: GLib.Variant,
        invocation: Gio.DBusMethodInvocation,
    ) -> None:
        del connection, sender, object_path
        if interface_name != INTERFACE_NAME:
            invocation.return_dbus_error(ERROR_FAILED, "Unsupported PolicyKit interface")
            return
        if method_name == "BeginAuthentication":
            self._begin_authentication(parameters, invocation)
        elif method_name == "CancelAuthentication":
            self._cancel_authentication(parameters, invocation)
        else:
            invocation.return_dbus_error(ERROR_FAILED, "Unsupported PolicyKit method")

    def _begin_authentication(
        self,
        parameters: GLib.Variant,
        invocation: Gio.DBusMethodInvocation,
    ) -> None:
        if self.begin_invocation is not None:
            invocation.return_dbus_error(ERROR_FAILED, "Another authentication request is already active")
            return

        try:
            action_id, message, _icon_name, _details, cookie, raw_identities = parameters.unpack()
        except (TypeError, ValueError) as exc:
            invocation.return_dbus_error(ERROR_FAILED, f"Invalid authentication request: {exc}")
            return

        identities, labels, preferred = self._decode_identities(raw_identities)
        if not identities:
            invocation.return_dbus_error(ERROR_FAILED, "No supported Unix user identity is available")
            return

        vendor, description = self._action_metadata(str(action_id))
        self.begin_invocation = invocation
        self.active_cookie = str(cookie)
        self.active_action_id = str(action_id)
        self.identity_objects = identities
        self.identity_labels = labels
        self.identity_index = preferred
        self.active_session = None
        self.pending_response = None
        self.cancel_requested = False
        self.auth_attempts = 0
        self.last_session_error = ""
        self.retry_limit_reached = False

        try:
            self.ui.show_request(
                action_id=self.active_action_id,
                message=str(message or "Authentication is required."),
                vendor=vendor,
                description=description,
                identities=self.identity_labels,
                identity_index=self.identity_index,
            )
        except Exception as exc:
            self._finish_request(cancelled=False, error=f"Could not show authentication terminal: {exc}")

    def _cancel_authentication(
        self,
        parameters: GLib.Variant,
        invocation: Gio.DBusMethodInvocation,
    ) -> None:
        try:
            (cookie,) = parameters.unpack()
        except (TypeError, ValueError):
            invocation.return_dbus_error(ERROR_FAILED, "Invalid cancellation request")
            return

        if self.begin_invocation is not None and str(cookie) == self.active_cookie:
            self._request_cancel()
        invocation.return_value(None)

    def _cycle_identity(self, delta: int) -> None:
        if self.begin_invocation is None or self.active_session is not None:
            return
        if len(self.identity_objects) <= 1:
            return
        self.identity_index = (self.identity_index + delta) % len(self.identity_objects)
        self.ui.set_identity_index(self.identity_index)

    def _submit_response(self, response: str) -> None:
        if self.begin_invocation is None or self.cancel_requested or self.retry_limit_reached:
            return
        if self.active_session is None:
            self.pending_response = response
            self._start_session()
            return
        self.active_session.response(response)
        response = ""

    def _start_session(self) -> None:
        if self.begin_invocation is None or self.active_session is not None or self.retry_limit_reached:
            return
        self.auth_attempts += 1
        self.last_session_error = ""
        identity = self.identity_objects[self.identity_index]
        session = PolkitAgent.Session.new(identity, self.active_cookie)
        session.connect("request", self._on_session_request)
        session.connect("show-info", self._on_session_info)
        session.connect("show-error", self._on_session_error)
        session.connect("completed", self._on_session_completed)
        self.active_session = session
        try:
            session.initiate()
        except GLib.Error as exc:
            self._finish_request(cancelled=False, error=f"Authentication could not start: {exc.message}")

    def _on_session_request(self, session: PolkitAgent.Session, request: str, echo_on: bool) -> None:
        if session is not self.active_session:
            return
        self.ui.set_prompt(str(request), bool(echo_on))
        if self.pending_response is not None:
            response = self.pending_response
            self.pending_response = None
            session.response(response)
            response = ""

    def _on_session_info(self, session: PolkitAgent.Session, text: str) -> None:
        if session is self.active_session:
            self.ui.set_status(str(text))

    def _on_session_error(self, session: PolkitAgent.Session, text: str) -> None:
        if session is self.active_session:
            self.last_session_error = str(text).strip()
            self.ui.set_error(self._friendly_auth_error())

    def _friendly_auth_error(self) -> str:
        message = self.last_session_error.strip()
        normalized = message.casefold()
        password_failure_markers = (
            "authentication failure",
            "authentication failed",
            "incorrect password",
            "password incorrect",
            "sorry, try again",
        )
        if any(marker in normalized for marker in password_failure_markers):
            return "Incorrect password. Try again."
        if message:
            return message
        if not self.ui.echo_on and "password" in self.ui.prompt.casefold():
            return "Incorrect password. Try again."
        return "Authentication failed. Try again."

    def _on_session_completed(self, session: PolkitAgent.Session, gained_authorization: bool) -> None:
        if session is not self.active_session:
            return
        self.active_session = None
        self.pending_response = None

        # The helper reports successful authorization to polkitd itself. Keep
        # BeginAuthentication outstanding across failed PAM sessions so a typo
        # can be retried with the same PolicyKit cookie.
        if gained_authorization:
            self._finish_request(cancelled=False)
            return
        if self.cancel_requested:
            self._finish_request(cancelled=True)
            return

        self.ui.clear_secret()
        if self.auth_attempts < MAX_AUTH_ATTEMPTS:
            self.ui.set_error(self._friendly_auth_error())
            return

        self.retry_limit_reached = True
        self.ui.set_error(f"Authentication failed after {MAX_AUTH_ATTEMPTS} attempts.")
        GLib.timeout_add(1200, self._finish_denied_after_retry_limit)

    def _finish_denied_after_retry_limit(self) -> bool:
        if self.begin_invocation is not None and not self.cancel_requested:
            self._finish_request(cancelled=False)
        return GLib.SOURCE_REMOVE

    def _cancel_from_ui(self) -> None:
        self._request_cancel()

    def _request_cancel(self) -> None:
        if self.begin_invocation is None or self.cancel_requested:
            return
        self.cancel_requested = True
        self.pending_response = None
        self.ui.clear_secret()
        if self.active_session is not None:
            self.active_session.cancel()
        else:
            self._finish_request(cancelled=True)

    def _finish_request(self, *, cancelled: bool, error: str = "") -> None:
        invocation = self.begin_invocation
        self.begin_invocation = None
        self.pending_response = None
        self.active_session = None
        self.active_cookie = ""
        self.active_action_id = ""
        self.identity_objects = []
        self.identity_labels = []
        self.identity_index = 0
        self.cancel_requested = False
        self.auth_attempts = 0
        self.last_session_error = ""
        self.retry_limit_reached = False
        self.ui.hide()

        if invocation is None:
            return
        if error:
            invocation.return_dbus_error(ERROR_FAILED, error)
        elif cancelled:
            invocation.return_dbus_error(ERROR_CANCELLED, "Authentication request cancelled")
        else:
            invocation.return_value(None)

    def shutdown(self) -> None:
        if self.shutting_down:
            return
        self.shutting_down = True

        if self.begin_invocation is not None:
            if self.active_session is not None:
                try:
                    self.active_session.cancel()
                except GLib.Error:
                    pass
            self._finish_request(cancelled=True)

        if self.registered and self.authority is not None and self.subject is not None:
            try:
                self.authority.unregister_authentication_agent_sync(self.subject, OBJECT_PATH, None)
            except GLib.Error:
                pass
            self.registered = False

        if self.connection is not None and self.registration_id:
            self.connection.unregister_object(self.registration_id)
            self.registration_id = 0

        self.ui.close()
        if self.loop.is_running():
            self.loop.quit()


def main() -> int:
    try:
        agent = TerminalPolkitAgent()
        agent.start()
        return 0
    except Exception as exc:
        message = f"fatal startup: {type(exc).__name__}: {exc}"
        journal_message("err", message)
        print(f"awtarchy-polkit-agent: {message}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
