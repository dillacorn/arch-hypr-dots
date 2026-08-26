# Awtarchy v3.3.2 Quickshell

Awtarchy v3.3.2 is a focused bug-fix release for Bluetooth state synchronization in Quickshell. It keeps the v3.3.1 update-notification fixes and v3.3.0 terminal PolicyKit changes while fixing a startup condition where Bluetooth could be correctly powered off underneath but still appear enabled in the Awtarchy bar and Bluetooth menu.

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

## Bluetooth state synchronization

- The Bluetooth state helper can now read the actual BlueZ controller power state directly from `bluetoothctl show`.
- Quickshell reconciles its displayed Bluetooth state after startup restore, enable, and disable operations instead of relying only on the cached `BluetoothAdapter.enabled` value.
- The bar and Bluetooth menu now reflect the actual powered state when the saved Awtarchy preference is restored during login.
- Bluetooth enable/disable actions immediately update the reconciled state and then verify it against BlueZ.
- Awtarchy continues to leave Bluetooth rfkill unblocked while powering the controller off, so the adapter remains visible and can be turned back on normally.

## v3.3.1 reliability fixes retained

- Keeps the explicit 30-second login update check introduced in v3.3.1.
- Keeps periodic update checks rate-limited to every six hours.
- Keeps failed notification delivery from consuming a stable release notification target.
- Git-testing mode continues to suppress stable-release notifications as intended.

## v3.3.0 baseline retained

- Keeps the Awtarchy-owned terminal PolicyKit authentication agent introduced in v3.3.0.
- Keeps the headless trusted authentication backend and transient Alacritty TUI behavior.
- Keeps the root-owned PolicyKit runtime, migration safeguards, credential-transport protections, and rollback behavior from v3.3.0.

## Validation

- The Bluetooth bug was reproduced on a real Awtarchy laptop: the saved preference was `disabled` and BlueZ reported `Powered: no`, while the Quickshell bar/menu incorrectly displayed Bluetooth as enabled and could not meaningfully turn it off again.
- The fix was runtime-tested on the same laptop. Saved and actual state matched as `disabled`, then `enabled`, then `disabled` while toggling through the Quickshell Bluetooth UI.
- After restarting Quickshell with Bluetooth disabled, the UI remained correctly displayed as off.
- After a full reboot and login with Bluetooth disabled, the bar/menu still displayed Bluetooth as off, confirming the original startup failure was fixed in real use.
- Permanent Bluetooth regression coverage verifies actual BlueZ power readback, Quickshell synchronization wiring, Bash syntax, ShellCheck, and managed-history registration.
- The full Awtarchy command/updater integration suite, focused Bluetooth validation, update-notification regression, anonymous failure-reporting validation, and PolicyKit contracts all passed on the exact `v3.3.2` release target before publication.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.3.2._
