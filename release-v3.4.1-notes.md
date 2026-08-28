# Awtarchy v3.4.1 Quickshell

Awtarchy v3.4.1 is a focused patch release improving Awtarchy's anonymous failure-reporting experience. Pending reports now use a normal Awtarchy command instead of exposing an internal helper script, the notification explains exactly what to run, and duplicate notices from concurrent Quickshell startup paths are suppressed without changing the existing user-review and consent model.

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

## Failure reporting usability

- Pending sanitized failure reports now have a first-class `awtarchy report` command.
- The desktop notification tells the user to run `awtarchy report` instead of exposing `~/.config/hypr/scripts/awtarchy_report_failure.sh` as a user-facing command.
- `awtarchy report` opens the existing Review / Send / Don't send flow, so the report can be inspected before anything is submitted.
- The notification explicitly tells the user that reviewing the report does not commit them to sending it.
- An unchanged pending-report state is notified only once rather than once per Quickshell startup path.
- Concurrent Quickshell startup paths are serialized around pending-report notification delivery so they cannot race into duplicate notices.
- Sending or discarding a pending report clears the notification state, allowing a genuinely new future failure to notify normally.
- Running plain `awtarchy` continues to surface pending reports before the maintenance menu.

## Privacy and report behavior

- This patch does not broaden the report schema or add telemetry.
- Sanitized reports still exclude usernames, hostnames, home-directory paths, raw logs, arbitrary diagnostic text, and persistent installation identifiers.
- The existing explicit user approval requirement remains unchanged: Awtarchy does not submit a pending report until the user chooses Send.
- Worker validation, rate limiting, deduplication, and report fingerprinting are unchanged.
- Automatic report issue #90 identified a separate resume-recovery failure from an earlier v3.3.9 configuration state. This release improves how such reports are presented and submitted; it does not claim to fix that underlying resume-recovery failure.

## Validation

- PR #91 was developed with focused regression coverage for the new user-facing report command and notification behavior.
- The regression suite verified `awtarchy report`, the exact user-facing command in notifications, absence of the internal helper path from notifications, sequential notification deduplication, and concurrent notification deduplication.
- Existing anonymous-reporting privacy, payload validation, send, review, discard, and failure-retention tests remain covered.
- Exact release target `9f83737623913bd4919eab07a7a065b618cb2503` passed `Validate Awtarchy`, `Validate Anonymous Failure Reporting`, `Validate PolicyKit Agent`, and `Validate Theme Picker Workspace Composition` on `main` before publication.
- `Validate Awtarchy` passed Bash syntax, ShellCheck, desktop-entry validation, and the command/updater integration suite on the exact release target.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.4.1._
