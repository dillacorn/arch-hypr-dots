# Awtarchy v3.2.2 Quickshell

Awtarchy v3.2.2 adds quiet, actionable update notifications to the normal Quickshell notification experience. It clearly separates new stable releases from meaningful same-release maintenance refreshes while avoiding repeat alerts.

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

## Stable update notifications

- Awtarchy now checks for newer published stable releases and notifies through its normal Quickshell notification server and history.
- The notice clearly shows the installed and target versions, such as `v3.2.1 → v3.2.2`, and reminds users that they can run `awtarchy update`.
- Draft releases, prereleases, unknown or unreleased installs, and Git-testing state do not generate normal stable-release notices.
- A GitHub icon identifies the update source, with visible **Update ↑** and **Release Notes ↗** actions.
- **Release Notes ↗** opens the exact GitHub release page without dismissing the notification or disabling its remaining update action.
- **Update ↑** opens Awtarchy's existing terminal helper and starts the updater. The notice closes only when the command succeeds and the installed config reaches the advertised release or a newer one.

## Calm by default

- Stable targets are remembered across sessions, so the same update is not announced again at every login.
- Update notices can be disabled from the Notifications cog-wheel settings.
- When notices are disabled, checks are reduced to weekly. Only a proven gap of five or more stable releases may produce an occasional normal-urgency catch-up notice, with a 30-day cooldown across targets.
- Network failures remain silent and checks are rate-limited.

## Same-release maintenance refreshes

- Awtarchy can distinguish a stable config release from a newer maintenance command/runtime on `main` without pretending that the version string changed.
- A maintenance notice appears only when `command-version` is behind `main` and the installed launcher or runtime payload actually differs from the corresponding Git blob on `main`.
- Meaningful same-release fixes are labeled **Awtarchy Maintenance Refresh** and use `awtarchy self-update`; commit-only changes with identical installed payloads stay silent.
- Maintenance notices do not show a misleading stable-release notes action.

## Notification and terminal polish

- Update actions use a clean non-login shell, avoiding Fastfetch and other login-profile output.
- Held terminal commands now report the real exit status without the prior stray `status=0` text.
- The update-notification setting and popup controls use a cleaner Notifications layout.

## Validation

- Added focused integration coverage for stable, prerelease, Git-testing, offline, suppression, catch-up, deduplication, resident actions, successful and failed updates, newer-target races, and maintenance payload identity.
- Bash syntax, ShellCheck, desktop validation, command/updater integration, Quickshell production-readiness, managed-history migration, anonymous failure-reporting, anti-spam, and the complete repository workflow passed before release.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.2.2._
