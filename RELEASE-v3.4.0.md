# Awtarchy v3.4.0 Quickshell

Awtarchy v3.4.0 focuses on a cleaner, more configurable Quickshell bar and more predictable flyout behavior. Awtarchy's own flyouts no longer leak into the running-application strip, CPU/temperature/RAM readouts can be hidden per display, and launcher/notification-style surfaces now center correctly when the bar is not actually visible.

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

## Cleaner running-application strip

- Awtarchy's internal Quickshell flyouts no longer appear as running applications in the bar.
- Application icons keep their native icon-theme colors.
- Tray icons keep their native rendering.
- Existing task-strip mouse actions are preserved, including activation, minimize/restore behavior, and middle-click close.

## Optional system statistics

- CPU usage, CPU temperature, and RAM usage can now be shown or hidden independently in Quick Settings → Bar Appearance.
- The controls apply per display and use the existing display-target selector.
- All three readouts remain visible by default, preserving the stock Awtarchy bar for existing and new displays.
- Reset Bar Appearance restores all three statistics to visible.
- The state continues to use Awtarchy's existing shared per-monitor Quickshell state rather than a parallel settings store.

## Bar-aware flyout placement

- Launcher, Clipboard History, Notifications, Network, and Bluetooth now use the bar's effective runtime visibility instead of only its saved enabled state.
- If fullscreen content or another runtime condition hides the bar, those flyouts open centered on the screen instead of positioning themselves against an invisible bar.
- Keyboard-opened Notifications remain attached to a visible bar edge but center along that edge.
- Clicking the notification control in the bar still anchors Notifications to the exact clicked item.
- `SUPER+N` now toggles the notification center in both the normal and `noalt` input modes; mouse and VM submaps are unchanged.

## Validation

- PR #86 passed all 12 pull-request workflows on exact feature head `499dc55d9171249aab0c45bcbb7a11939cf3ef07`, including repository-wide validation, Quick Settings layout, display scale, floating windows, clock/date persistence, fullscreen/spacing, notification history, PolicyKit, Bluetooth, update-notification, and anonymous-reporting checks.
- Exact release target `75ac399cb2d9142714c4184d41b75fc47062a8d1` passed all five post-merge `main` workflows, including repository-wide `Validate Awtarchy`, Bluetooth state, PolicyKit, update-notification, and anonymous-failure-reporting checks.
- The maintainer completed the requested real-session review of the integrated branch and approved it for merge and release.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.4.0._
