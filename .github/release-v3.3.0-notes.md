# Awtarchy v3.3.0 Quickshell

Awtarchy v3.3.0 replaces the GNOME PolicyKit authentication agent with an Awtarchy-owned terminal authentication flow. The trusted authentication backend stays headless while idle and opens a transient Alacritty TUI only when authorization is actually required.

## Getting started

Awtarchy is an Arch Linux overlay/environment, not a Linux distribution or an Arch Linux installer. Install it onto a working minimal Arch Linux system.

If you are starting from zero:

1. Download the official Arch Linux ISO from the [Arch Linux download page](https://archlinux.org/download/).
2. Boot the Arch Linux ISO.
3. Install a working minimal Arch Linux system first.
   - For most users, Awtarchy recommends the official `archinstall` guided installer included with the Arch ISO as the easiest path. Run `archinstall` from the live environment and complete a minimal Arch installation.
   - A normal manual Arch installation using the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide) is also fine.
4. Boot into the installed Arch system.

Once you have a working minimal Arch installation, install Awtarchy:

```bash
sudo pacman -S git --noconfirm
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

Existing Awtarchy users:

```bash
awtarchy update
```

## Awtarchy terminal PolicyKit authentication

- Replaces `polkit-gnome` with an Awtarchy-owned PolicyKit authentication agent.
- Keeps the trusted Python authentication backend headless while idle instead of parking a hidden authentication window on a special workspace.
- Opens a transient real Alacritty terminal only while an authentication request is active.
- Uses the current sanitized Alacritty appearance without loading arbitrary user terminal commands, key bindings, environment settings, or plugins into the trusted authentication runtime.
- Supports keyboard and mouse controls, clear password retry feedback, and an animated `Authenticating` status while PAM/PolicyKit is processing.
- Successful authentication closes immediately without adding an artificial delay.

## Credential and runtime security

- The backend and terminal frontend communicate through an inherited anonymous `AF_UNIX`/`SOCK_SEQPACKET` socketpair instead of a filesystem IPC path.
- Passwords travel only from the terminal frontend into `PolkitAgent.Session.response()` and are not persisted, logged, stored in temporary files, placed in command-line arguments or environment variables, or passed through `sudo -S`.
- The installed authentication runtime is root-owned under `/usr/local/libexec/awtarchy/polkit-agent` with a dedicated user service under `/usr/local/lib/systemd/user/awtarchy-polkit-agent.service`.
- Runtime startup validates ownership, file types and modes, Python/PyGObject/PolicyKit prerequisites, and the graphical login session before activation.
- Agent diagnostics are sent to the journal rather than leaking warnings or tracebacks into the authentication terminal.

## Migration and rollback safety

- `polkit` and `python-gobject` are explicit installation/update dependencies.
- The PolicyKit runtime is installed through a staged root-owned transaction and verified before it becomes active.
- If the privileged PolicyKit runtime installation fails during an update, Awtarchy's user-file transaction is rolled back instead of leaving a partially migrated desktop configuration.
- Existing `polkit-gnome` is retained as a controlled fallback while activation of the new agent is being validated.
- Removal of `polkit-gnome` is delayed and ownership-gated rather than happening before the replacement agent is proven live.

## Validation

- End-to-end authorization was live-tested with the installed root-owned runtime using both `pkexec` and a real systemd-generated PolicyKit request.
- Password retries, successful authorization, terminal theming, transient-window behavior, and authentication feedback were live-tested on the desktop.
- Permanent PolicyKit CI covers TUI parsing, authentication feedback, transient frontend lifecycle, headless idle behavior, retry handling, sanitized Alacritty appearance, GLib socket watching, Hyprland integration, graphical-session binding, startup diagnostics, secure credential transport, production migration integration, and runtime rebuild behavior.
- Bash syntax, ShellCheck, desktop validation, command/updater integration, managed-history migration, anonymous failure-reporting, and the dedicated PolicyKit suite all passed on the exact `v3.3.0` release target before publication.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.3.0._