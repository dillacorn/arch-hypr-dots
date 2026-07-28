# `awtarchy-shell`

#### See the [Release Page](https://github.com/dillacorn/awtarchy/releases) for install directions.

---

pronounced: **aw-tar-chee**

**awtarchy** is not a Linux distribution. It is an overlay environment for base Arch Linux.

## Install model

1. Install Arch with `archinstall` and select the Minimal profile.
2. Apply the awtarchy overlay on top of that base system.

## Why this approach

* Flexible: works over any clean Arch install.
* Lightweight: no separate ISO or custom repositories required.
* Low maintenance: relies on Arch’s installer and official repositories.
* Transparent: the installer is a single local shell script that can be reviewed before use.

## Workflow expectations

awtarchy targets users who prefer TTY login, direct shell interaction, and manual control over their system. It assumes comfort with the command line and basic Arch Linux maintenance.

> Note on originality
> awtarchy is not an Omarchy clone. All code, scripts, and configurations are original and include features not present in Omarchy or similar projects.

---

**Click the image below to see more previews.**

[![overview](https://github.com/dillacorn/awtarchy/raw/main/previews/overview.png)](https://github.com/dillacorn/awtarchy/tree/main/previews.md)

## 🖥️ System Overview

| Component          | Details                                                                                                                                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Distro**         | [Arch Linux](https://archlinux.org/)                                                                                                                                                                   |
| **Installation**   | [archinstall](https://github.com/archlinux/archinstall)                                                                                                                                                |
| **File System**    | [ext4](https://man.archlinux.org/man/ext4.5.en) and/or [Btrfs](https://wiki.archlinux.org/title/Btrfs)                                                                                                 |
| **Repositories**   | core, extra, multilib, [AUR](https://aur.archlinux.org/), [Flathub](https://flathub.org/)                                                                                                              |
| **Terminal**       | [Alacritty](https://github.com/alacritty/alacritty)                                                                                                                                                    |
| **Bootloader**     | [systemd-boot](https://man.archlinux.org/man/systemd-boot.7) and/or [Limine](https://github.com/limine-bootloader/limine)                                                                              |
| **Window Manager** | [Hyprland](https://github.com/hyprwm/Hyprland) ([config](https://github.com/dillacorn/awtarchy/tree/main/config/hypr))                                                                                 |
| **Kernel**         | [Arch Linux](https://archlinux.org/packages/core/x86_64/linux/) · [Arch Linux LTS](https://archlinux.org/packages/core/x86_64/linux-lts/) · [CachyOS kernel](https://github.com/CachyOS/linux-cachyos) |

## 🚀 Installer

awtarchy now uses one main script:

```bash
awtarchy.sh
```

The script provides a built-in terminal menu without depending on `fzf`, `gum`, `dialog`, or `whiptail`.

It can:

* install the awtarchy overlay
* run a dry-run install plan
* update/reset managed configs from the latest release
* clean old awtarchy backup files

## 📦 Install

Install Arch first with `archinstall` and choose the Minimal profile.

Then install Git:

```bash
sudo pacman -S git --noconfirm
```

Clone the repo and start the installer:

```bash
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
chmod +x awtarchy.sh
sudo ./awtarchy.sh
```

Direct install command:

```bash
sudo ./awtarchy.sh install
```

## 🧪 Dry-run

Dry-run lets you test the installer menu and review the install plan without changing the system:

```bash
./awtarchy.sh dry-run
```

Alternative:

```bash
./awtarchy.sh install --dry-run
```

## 🧭 Main Menu

Running the script without arguments opens the main menu:

```bash
./awtarchy.sh
```

Available actions:

```text
Install Awtarchy
Dry-run Awtarchy install plan
Update/reset Awtarchy configs from latest release
Clean Awtarchy backup files
Exit
```

## ⚙️ Installer Behavior

The installer collects choices at the beginning before making changes.

It lets you choose:

* system type: laptop or desktop
* install sections
* Arch repo package categories
* AUR packages
* Flatpak apps
* shell-file overwrite behavior

Before a live install starts, awtarchy shows a final review screen.

Arch package categories can be edited from the package menu:

```text
Enter/e = edit category
Space = select/clear category
b = back
Up/Down = move
```

## 🔄 Updating awtarchy

awtarchy updates overwrite managed config files. If you modified a managed file, the updater creates a sibling backup next to it ending in `.backup` or `.backup.<timestamp>` if one already exists.

You must manually merge your changes back in.

Update/reset managed configs from the latest release:

```bash
cd ~/awtarchy
chmod +x awtarchy.sh
./awtarchy.sh update-reset-backup
```

Shortcut:

```bash
./awtarchy.sh update-reset
```

Update to a specific release tag:

```bash
./awtarchy.sh update-reset-backup --tag v1.0.0
```

## 🧹 Clean Backup Files

The backup cleaner scans common awtarchy-managed paths under your home directory, lists matching `.backup` files, and lets you mark files as `[KEEP]` before deleting the rest.

Interactive cleaner:

```bash
cd ~/awtarchy
chmod +x awtarchy.sh
./awtarchy.sh update-backup-cleaner
```

Shortcut:

```bash
./awtarchy.sh clean-backups
```

List only, no prompt, no deletes:

```bash
./awtarchy.sh clean-backups --dry-run
```

Delete without prompting:

```bash
./awtarchy.sh clean-backups --yes
```

Only match backups older than 14 days:

```bash
./awtarchy.sh clean-backups --older-than 14
```

Archive matches before deletion:

```bash
./awtarchy.sh clean-backups --archive "$HOME/awtarchy-backups.tar.gz"
```

## 🎨 Wallpaper Collections

* [dharmx/walls](https://github.com/dharmx/walls)
* [Gruvbox Wallpapers](https://github.com/AngelJumbo/gruvbox-wallpapers)
* [Aesthetic Wallpapers](https://github.com/D3Ext/aesthetic-wallpapers)

## 🌐 Browser Notes

* [Firefox + Betterfox](browser_notes/firefox.md)
* [Brave](browser_notes/brave.md)
* [Mullvad](browser_notes/mullvad.md)

## 📦 Optional Packages

* [Optional Packages](extra_notes/optional_packages.md)

## License

This project is licensed under the [MIT License](https://github.com/dillacorn/awtarchy/blob/main/LICENSE).

## Legal Notice

This project is a general-purpose open-source utility that runs locally on the user’s system. It does not provide a hosted service and does not collect user data. Users are responsible for complying with laws and regulations in their own jurisdiction when using this software.

## ☕ Donate

Built and maintained out of passion. Always FOSS. Donations appreciated.
[Donate via PayPal](https://www.paypal.com/donate/?business=XSNV4QP8JFY9Y&no_recurring=0&item_name=Built+and+maintained+out+of+passion.+Always+FOSS.+Donations+appreciated.+%28smtty%2C+MicLockTray%2C+awtarchy%29&currency_code=USD)
