# Secure Awtarchy Polkit Agent Design

## Goal

Replace the visual-only PolicyKit concept with a real Awtarchy authentication agent that preserves the approved terminal-like UI while keeping the authentication implementation out of user-writable runtime code.

## User-facing behavior

- Authentication opens a dedicated fixed-size 900x520 window.
- The window is floating, centered, and restored to the intended geometry if Hyprland tiles or resizes it.
- The visual language stays close to the approved terminal prototype: monospace text, magenta `Authentication Required` and `Details:`, red `Cancel`, green `Authenticate`, dark background, and compact spacing.
- `Details:` starts collapsed for every new request.
- The prototype warning is absent from the real agent.
- The primary Polkit message is shown verbatim as plain text.
- Details show dynamic action ID, registered action description/vendor when available, and the selected authentication identity.
- The input label follows the current PAM/Polkit prompt. Password prompts are masked; visible-response prompts remain visible.
- Mouse and keyboard are both supported. Escape cancels. Enter submits when a response is requested.
- Authentication conversations may have multiple prompts, including second-factor prompts.

## Caller/application information

Polkit's `BeginAuthentication` D-Bus method includes a `details` dictionary. Known keys include `polkit.caller-pid` and `polkit.subject-pid`, which can be used by a full custom listener to identify the requesting mechanism/process.

Quickshell 0.3.1 receives that dictionary internally but intentionally omits it from the public `AuthFlow` object. Therefore the first Awtarchy implementation must not invent an application name. It shows the real Polkit message and action metadata. If Quickshell exposes the details dictionary later, or Awtarchy moves to its own libpolkit-agent listener, caller process/application information can be added safely.

## Authentication backend

Use Quickshell 0.3.1's native `Quickshell.Services.Polkit` implementation:

- `PolkitAgent` registers the agent with Polkit for the user session.
- `AuthFlow` supplies action/message/icon/identity/prompt state.
- `AuthFlow.submit()` sends responses into the libpolkit-agent/PAM conversation.
- `AuthFlow.cancelAuthenticationRequest()` cancels a user request.
- Quickshell queues simultaneous requests and supports multi-turn PAM conversations.

Do not implement password authentication with shell commands, temp files, custom sockets, terminal stdin, `sudo -S`, or `pkexec` wrappers.

## Security boundary

The real agent runs as the desktop user, because the authentication agent must register for that user's session. Its source/runtime configuration, however, is installed root-owned under:

`/usr/local/libexec/awtarchy/polkit-agent/`

The user-running process must not load executable QML, JavaScript, shell helpers, plugins, or QML import paths from the user's home directory. This prevents an ordinary same-user process from trivially rewriting the authentication UI/submit path and collecting a future password.

A root-owned launcher validates its own installed directory/files before starting Quickshell and constructs a minimal environment. It uses absolute executable paths and clears dangerous loader/import variables. In particular it must not trust user `PATH`, `QML2_IMPORT_PATH`, `QML_IMPORT_PATH`, `QT_PLUGIN_PATH`, `LD_PRELOAD`, `LD_LIBRARY_PATH`, or Polkit debug settings.

The root-owned UI uses a fixed Awtarchy authentication palette rather than dynamically loading user-writable theme code or colors. This intentionally trades live theme synchronization for stronger UI integrity.

All request-controlled strings are rendered as plain text, never rich text/HTML.

Passwords/responses are never logged, written to disk, copied to a custom IPC channel, or retained intentionally. The QML input is cleared immediately when submitted and when flows finish/cancel.

## Service ownership

Install a root-owned user unit at:

`/usr/local/lib/systemd/user/awtarchy-polkit-agent.service`

This location is in systemd's normal user-unit search path and keeps the service definition outside user-writable `$HOME`.

The service runs the root-owned launcher as the current user. The launcher starts a dedicated Quickshell process from the root-owned agent directory. The agent is separate from Awtarchy's main user-configured Quickshell process, so user shell configuration/reloads cannot rewrite the credential-handling code.

## Hyprland window handling

Use the dedicated title/app identity `awtarchy-polkit-agent` and a root-owned geometry helper/watch path that targets only the exact matching window. The intended geometry is 900x520, floating and centered. Geometry enforcement never receives or handles credentials.

## Test/rollback phase

Do not remove `polkit-gnome` or its Awtarchy autostart yet.

A testing controller installs the root-owned agent files, temporarily stops the exact GNOME PolicyKit agent process, starts the Awtarchy service, and allows a real harmless request such as `pkexec /usr/bin/true` to be tested. If the Awtarchy service cannot register/start, the controller stops it and restores GNOME.

The user may enter their real password only in the real root-owned agent path, not in the older visual prototype.

Permanent GNOME removal/autostart replacement is a separate integration step after live authentication, cancel, wrong-password, repeated-request, multi-prompt, focus, geometry, restart, and rollback behavior are verified.

## Threat boundaries

This design protects the agent implementation from trivial mutation by ordinary user-session programs and avoids custom password transport. It does not claim to defeat a fully compromised desktop session, compositor, kernel, root process, or arbitrary same-user input/screen spoofing. Those are broader session-compromise threats outside what a desktop authentication agent can solve by itself.
