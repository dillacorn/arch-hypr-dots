# Transient PolicyKit Terminal Design

## Goal

Keep Awtarchy's PolicyKit authentication agent registered while idle without keeping any Alacritty window alive. Spawn the authentication terminal only for an active PolicyKit request, then close it completely on success, cancellation, or final failure.

## Architecture

`awtarchy-polkit-agent.service` supervises the root-owned isolated Python PolicyKit backend directly. The backend owns system-bus registration, the `PolkitAgent.Session` PAM conversation, retry state, and the outstanding D-Bus invocation. It has no TTY and creates no window while idle.

For each `BeginAuthentication`, the backend creates an anonymous `AF_UNIX` `SOCK_SEQPACKET` socketpair and starts a dedicated Alacritty process. One socket endpoint stays in the backend; the other is explicitly inherited by Alacritty and its root-owned `python3 -I .../tui.py` child. The socket has no filesystem path and exists only for that authentication request.

The TUI owns `/dev/tty`, rendering, keyboard/mouse input, the authentication spinner, and exact-window Hyprland positioning. It sends only structured request events (`submit`, `cancel`, `identity-cycle`) over the inherited socket. Password data exists only in TUI memory, the anonymous socket kernel buffers, backend memory, and `PolkitAgent.Session.response()`; it is never written to disk, logged, passed in argv/environment, or sent through a named socket.

## Lifecycle

Idle:
- systemd user service and headless Python backend remain active;
- no Alacritty process exists;
- no Hyprland client/special workspace/scratchpad entry exists.

Authentication start:
- backend receives `BeginAuthentication`;
- backend creates socketpair and spawns Alacritty with trusted config plus sanitized current-theme overrides;
- TUI maps on the active workspace, floats/resizes/centers/focuses only its exact `awtarchy-polkit-agent` window;
- backend sends request metadata and identities.

Authentication interaction:
- submit immediately switches the TUI into the existing `Authenticating` spinner state;
- backend starts/responds to `PolkitAgent.Session`;
- failed PAM authentication keeps the same PolicyKit cookie and TUI alive for up to three attempts;
- error/info/prompt/identity state returns to the TUI as structured messages;
- success closes immediately with no artificial delay.

Authentication end:
- backend sends `close` and closes its socket endpoint;
- TUI restores terminal state and exits;
- Alacritty exits when its child exits;
- backend remains registered and ready for the next request.

If the frontend exits unexpectedly while an authentication request is active, the backend cancels that request rather than leaving it outstanding. A bounded termination fallback may kill only the exact Alacritty process spawned for that request if it does not exit after the TUI is told to close.

## IPC contract

Transport: anonymous Unix-domain `SOCK_SEQPACKET` socketpair, inherited by file descriptor only. No pathname, abstract namespace name, listening socket, port, or discoverable endpoint.

Messages are UTF-8 JSON objects, one object per packet. Maximum packet size is bounded. Unknown/oversized/malformed packets cancel the active request and close the frontend.

Frontend to backend:
- `{"type":"submit","response":"..."}`
- `{"type":"cancel"}`
- `{"type":"identity-cycle","delta":-1|1}`
- `{"type":"ready"}`

Backend to frontend:
- `show-request` with action/message/vendor/description/identities/current index
- `prompt` with prompt text and `echo_on`
- `status`
- `error`
- `identity-index`
- `close`

The password is allowed only in the `submit.response` field and must never be included in diagnostics.

## Security constraints

- Backend, TUI, launcher, service, and Alacritty config execute from `/usr/local/libexec/awtarchy/polkit-agent` and remain root-owned/non-user-writable.
- Backend stays `python3 -I`; no user Python/plugin/library search paths are introduced.
- Current Alacritty appearance is still sanitized to a visual-only whitelist before being passed to the backend for later terminal spawning.
- The inherited IPC descriptor number is not secret; credential contents are never placed in argv or environment.
- Frontend stdout/stderr must not expose runtime diagnostics in the authentication terminal. TUI diagnostics go to journald; UI rendering uses `/dev/tty` directly.
- Only one authentication request/frontend may be active at a time.
- GNOME Polkit remains the testing/migration fallback until production activation is fully validated.

## Hyprland / Quickshell behavior

Remove the private special-workspace parking rule. The transient auth window may retain an exact-class float rule, but it must not be mapped to `special:awtarchy-polkit-agent` and must not remain after authentication.

Quickshell may continue ignoring the auth class in the normal task strip while the prompt is active. Scratchpad-specific exclusion is no longer required for correctness because no idle auth window exists.

## Verification

Focused tests must prove:
- backend startup does not instantiate/open `TerminalUI` or `/dev/tty`;
- service MainPID resolves to isolated Python backend, not Alacritty;
- no special-workspace parking contract remains;
- socketpair is anonymous and child-FD inherited only for the spawned frontend;
- malformed frontend packets fail closed;
- password submit reaches only `PolkitAgent.Session.response()` after IPC decoding and is never logged/persisted/argv/env;
- spinner/retry behavior remains intact;
- frontend closes on success/cancel/final failure and backend remains alive;
- runtime/live-test process verification expects headless Python at idle and transient Alacritty only during a request;
- full production integration/security/runtime rebuild tests remain green.
