# Awtarchy v3.3.1 Quickshell

Awtarchy v3.3.1 is a focused bug-fix release for update notifications. It keeps the v3.3.0 Quickshell and terminal PolicyKit changes while fixing a login-check bug that could prevent users from being notified about a newly published Awtarchy release.

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

## Update notification reliability

- The 30-second graphical startup check now uses an explicit login mode and is no longer suppressed just because the previous periodic check happened less than six hours earlier.
- Periodic update checks remain rate-limited to every six hours.
- A stable release is recorded as announced only after `notify-send` returns a valid notification ID, so a failed notification attempt does not permanently consume that release notification.
- Successful notifications still suppress duplicate alerts for the same release.
- Git-testing mode continues to suppress stable-release notifications as intended.

## v3.3.0 baseline retained

- Keeps the Awtarchy-owned terminal PolicyKit authentication agent introduced in v3.3.0.
- Keeps the headless trusted authentication backend and transient Alacritty TUI behavior.
- Keeps the root-owned PolicyKit runtime, migration safeguards, credential-transport protections, and rollback behavior from v3.3.0.

## Validation

- The original bug was reproduced on a real Awtarchy laptop: a simulated login one hour after the previous check produced no notification, while the same state seven hours after the previous check did.
- The fixed branch was live-tested on the same laptop with a temporary `v3.2.2` state and `last_check` set to the current second; login mode still displayed the expected `v3.2.2 → v3.3.0` update notification.
- Permanent regression coverage verifies that login checks bypass only the normal six-hour throttle, periodic checks remain throttled, and failed notification delivery does not consume the stable release target.
- Bash syntax, ShellCheck, desktop validation, command/updater integration, managed-history migration, anonymous failure-reporting, the dedicated update-notification regression, and the PolicyKit suite all passed on the exact `v3.3.1` release target before publication.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.3.1._
