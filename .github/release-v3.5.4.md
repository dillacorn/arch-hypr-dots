# Awtarchy v3.5.4 Quickshell

Awtarchy v3.5.4 is a stability and usability update that rolls the tested v3.5.3 post-release updater work into a stable configuration release and fixes Bluetooth startup-state presentation plus idle-eye Always Awake placement and ownership.

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

## Existing Awtarchy users

```bash
awtarchy update
```

## Bluetooth startup-state synchronization

- The Quickshell Bluetooth bar indicator now follows the authoritative BlueZ adapter power state across login/startup races instead of temporarily presenting an enabled color from stale state.
- If an authoritative adapter-power probe is already running, later refresh requests are queued and replayed after it exits rather than being dropped.
- The fix was verified in a real reboot/login session with Bluetooth powered off: the bar icon was already faded/off before the Bluetooth flyout was opened, and opening the flyout confirmed Bluetooth remained off without correcting the icon afterward.

## Idle-eye and Always Awake polish

- Always Awake is now owned by the idle-inhibitor eye flyout; the duplicate Always Awake row has been removed from Quick Settings.
- With a top bar, normal Keep Awake stays nearest the bar while the stronger red Always Awake section is placed farther below it.
- Bottom, left, and right bar flyout ordering remains unchanged.
- Stale backend/config wording no longer instructs users to use Quick Settings for Always Awake.
- Normal Keep Awake remains the recommended mode and preserves Awtarchy's four-hour protected-idle safety action; Always Awake remains the stronger warned option.

## Updater reliability and package recovery

The tested v3.5.3 post-release maintenance changes are carried forward into the v3.5.4 stable release:

- Notification-launched updates run their held terminal in an independent waited session so stopping or restarting Quickshell cannot tear down the updater terminal.
- Package reconciliation does not pre-authenticate or keep an Awtarchy-managed reusable sudo ticket alive for an AUR-only plan. Privileged Awtarchy work authenticates only when the actual root operation runs.
- Awtarchy invalidates sudo before each upstream `aur-scan install` so a previous package cannot leave reusable authorization exposed while the next PKGBUILD begins. Stock `aur-scanner` / `makepkg -si` may request sudo independently during dependency and package installation.
- Updates check root-filesystem headroom and can conservatively prune stale pacman cache entries with `paccache -rk2` before refusing to continue below the hard free-space minimum.
- Real-machine validation completed Git-testing update and package reconciliation for `obs-pipewire-audio-capture-bin`; the AUR-only plan added no Awtarchy pre-authentication prompt, upstream makepkg prompts occurred as expected, the package installed, and reconciliation completed.
- PR #138 merged the updater-session, disk-recovery, and sudo-boundary changes after all 22 PR workflows passed on exact tested head `34569609ede7225ed6bfe4ae0f4f1bcc0072af48`.
- PR #139 added the v3.5.3 tag-scoped notifier delivery repair after all 14 PR workflows passed on exact tested head `bf9f48629276f801c692ca0b9773b62fea5e8b22`. All eight push workflows then passed on exact maintenance `main` commit `7f96e7141dda9ea9d14fa255c9e18ba48143c049`.
- The published `v3.5.3` tag remains unchanged at `89f8ac995bcaa29835bf5fa9c9164a2712eb1e00`; v3.5.4 publishes the current tested stable state from the new release target.

## Managed update safety

- Current stock hashes for the changed Bluetooth and idle-eye Quickshell surfaces are recorded in Awtarchy's managed-history data so future stable updates can recognize the v3.5.4 shipped state.
- Regression coverage protects Bluetooth power-state refresh queuing, top-bar edge ordering, Quick Settings ownership, the four-hour idle-safety behavior, and managed-history entries.

## Validation

- Exact release target: `4a7cb022c7001650cfe77467ba94d548e6d0e34a`.
- PR #141 passed all 21 pull-request workflows on exact tested head `762f04739301628f6cd2de6e16f7f1df2ace3f1a`.
- The focused Bluetooth-state workflow passed on that exact PR head and again on merged `main`.
- Real-session reboot/login testing with `Powered: no` confirmed the Bluetooth bar icon rendered the faded/off state before the flyout was opened, and the flyout then confirmed Bluetooth remained off.
- All ten push workflows completed successfully on exact merged release target `4a7cb022c7001650cfe77467ba94d548e6d0e34a`, including `Validate Awtarchy` with Bash syntax, ShellCheck, Quickshell desktop-entry validation, and command/updater integration tests.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.5.4._
