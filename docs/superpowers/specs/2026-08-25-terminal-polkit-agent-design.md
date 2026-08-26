# Terminal PolicyKit Agent Design

## Status

Approved replacement design for the Awtarchy PolicyKit authentication agent. This supersedes the Quickshell-rendered authentication frontend described by `docs/superpowers/specs/2026-08-25-secure-polkit-agent-design.md` while preserving its root-owned runtime and migration safety requirements.

## Goal

Replace `polkit-gnome` with an Awtarchy-owned PolicyKit authentication agent whose real authentication interface is the approved terminal TUI, not a Quickshell window.

## Architecture

A root-owned launcher starts a dedicated Alacritty window with an explicit command pointing at the root-owned Python agent. The Python process registers `org.freedesktop.PolicyKit1.AuthenticationAgent` for the current desktop session, receives `BeginAuthentication`/`CancelAuthentication` requests on the system bus, and uses `PolkitAgent.Session` for the trusted PAM/polkit-agent-helper conversation.

The terminal remains alive for the lifetime of the user service. While idle it is moved to a private Hyprland special workspace. When authentication begins, the agent moves its own terminal to the currently active workspace, forces floating 900x520 geometry, centers/focuses it, and renders the approved TUI. When the request completes or is cancelled, credentials and request state are cleared and the terminal is returned to the hidden workspace.

No Quickshell process participates in authentication.

## Runtime files

Repository source:

- `config/hypr/scripts/awtarchy-polkit-agent/agent.py`: D-Bus registration, PolicyKit/PAM conversation, request lifecycle.
- `config/hypr/scripts/awtarchy-polkit-agent/tui.py`: terminal rendering, keyboard/mouse input, password-field redraw, Hyprland show/hide/geometry control.
- `config/hypr/scripts/awtarchy-polkit-agent/launcher.sh`: validates trusted runtime and launches Alacritty with the root-owned agent command.
- `config/hypr/scripts/awtarchy-polkit-agent/alacritty.toml`: root-owned minimal terminal config used only by the authentication terminal.
- `config/hypr/scripts/awtarchy-polkit-agent/awtarchy-polkit-agent.service`: user service for the terminal agent.

Installed trusted runtime:

- `/usr/local/libexec/awtarchy/polkit-agent/agent.py`
- `/usr/local/libexec/awtarchy/polkit-agent/tui.py`
- `/usr/local/libexec/awtarchy/polkit-agent/launcher`
- `/usr/local/libexec/awtarchy/polkit-agent/alacritty.toml`
- `/usr/local/lib/systemd/user/awtarchy-polkit-agent.service`

All executable/authentication source remains root-owned, non-symlink, and not group/world writable.

## PolicyKit registration

The agent uses `gi.repository` with `Polkit`, `PolkitAgent`, `Gio`, and `GLib`.

Startup sequence:

1. Validate `/dev/tty`, Hyprland session variables, and required binaries.
2. Connect to the system bus.
3. Export `/org/awtarchy/PolkitAgent` implementing `org.freedesktop.PolicyKit1.AuthenticationAgent`.
4. Resolve the current Unix session using `Polkit.UnixSession.new_for_process_sync(os.getpid(), None)`.
5. Obtain `Polkit.Authority` and synchronously register the object path for that session and current locale.
6. Enter the GLib main loop.

`BeginAuthentication` retains the D-Bus method invocation until authentication completes, as required by PolicyKit. `CancelAuthentication(cookie)` cancels only the matching active request.

Only one authentication request is active at a time. A second request received while one is active is rejected rather than corrupting the current PAM conversation.

## Identity handling

The D-Bus request supplies one or more allowed identities. The agent converts supported `unix-user` identities into `Polkit.UnixUser` objects.

Selection order:

1. Current real UID when present.
2. First supported Unix user identity.

If multiple identities are available, the Details area shows the selected identity and the TUI exposes identity cycling before authentication begins. Unsupported non-Unix-user identities are not passed to `PolkitAgent.Session`.

## PAM conversation

For the selected identity and request cookie, the agent creates `PolkitAgent.Session` and connects:

- `request`: update the prompt and whether the response may be echoed.
- `show-info`: show supplementary informational text.
- `show-error`: show supplementary error text.
- `completed`: finish the D-Bus request and hide/clear the terminal.

The user response is sent only with `PolkitAgent.Session.response()`. The agent never logs or persists the response and never passes it through command-line arguments, temporary files, sockets, shell expansion, `sudo -S`, or `pkexec` stdin.

Cancellation calls `PolkitAgent.Session.cancel()` and returns the PolicyKit cancelled D-Bus error.

## TUI behavior

The terminal interface preserves the approved concept behavior:

- fixed floating 900x520 window;
- magenta `Authentication Required` header;
- request message plus real PolicyKit message;
- password/input field with targeted redraw so typing does not clear/flicker the screen;
- Details collapsed initially;
- Details contains Action, Vendor/Description when available, and selected Identity;
- red `[ Cancel ]` and green `[ Authenticate ]` controls;
- SGR mouse input (`1000` + `1006`) using the event-reading pattern already proven by Awtarchy's terminal UI;
- Tab/Shift+Tab navigation, Enter/Space activation, Esc cancellation;
- empty Authenticate displays `Password not entered.` instead of submitting an empty response;
- PAM errors such as incorrect password are shown from the real session rather than simulated text.

The password buffer is cleared immediately after submission, cancellation, failure, or completion. Rendering stores only the display length/bullets, not a second copy of the password.

## Window lifecycle

The terminal is identified by exact class/title `awtarchy-polkit-agent`.

Idle state:

- moved silently to `special:awtarchy-polkit-agent`;
- not focused;
- service and agent remain registered.

Authentication state:

- determine the currently focused normal workspace before moving the agent;
- move the exact agent window to that workspace;
- force floating 900x520 geometry;
- center and focus it;
- render the request.

Completion/cancellation returns the window to the private special workspace.

The agent never moves arbitrary windows; Hyprland actions are constrained to the exact window address found by class/title matching.

## Dependencies

Fresh Awtarchy installs explicitly require:

- `polkit`
- `python-gobject`
- an Awtarchy-provided `/usr/bin/alacritty` (currently supplied by the existing Alacritty package path)

The implementation must fail closed if `PolkitAgent-1.0` GI bindings, `/usr/bin/alacritty`, `/usr/bin/python3`, `/usr/bin/hyprctl`, or `/dev/tty` are unavailable.

## Migration

Hyprland continues to start/restart `awtarchy-polkit-agent.service` after its session environment exists. The service is not globally enabled at `default.target`.

Existing migration safety remains:

- stop only the exact retired GNOME PolicyKit agent binary;
- install/replace runtime through a root-owned staging directory;
- verify ownership/modes before activation;
- keep `polkit-gnome` as fallback during Git testing;
- restore GNOME automatically if the new agent fails registration/stability/live authentication testing;
- stable automatic `polkit-gnome` package removal is allowed only when Awtarchy recorded package ownership, live activation succeeded, and all rollback-capable update stages have completed.

## Testing

Static tests must verify:

- no Quickshell/QML runtime remains in the production agent;
- `polkit` and `python-gobject` are explicit dependencies;
- trusted runtime install includes agent, TUI, launcher, terminal config, and service;
- launcher rejects unsafe ownership/symlinks and uses explicit absolute binaries;
- Python source imports PolicyKit GI modules and registers the D-Bus authentication interface;
- passwords are not logged/persisted or routed through forbidden mechanisms;
- terminal SGR mouse parsing accepts the live-proven `ESC[<0;43;16M/m` events;
- targeted password redraw remains separate from full-screen structural redraw;
- updater fallback/removal ordering remains intact.

The mandatory live test remains `/usr/bin/pkexec --disable-internal-agent /usr/bin/true`, with GNOME rollback available until the terminal agent succeeds on a real Arch/Hyprland session.
