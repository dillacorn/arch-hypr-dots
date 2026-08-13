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
* Transparent: the local installer and maintenance scripts can be reviewed before use.

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

## 🚀 Installer and Maintenance Command

Awtarchy uses two user-facing entrypoints:

```text
awtarchy-install.sh    Initial installation only
awtarchy               Updates, config maintenance, version checks, and backup cleanup
```

The installer deploys the permanent command to:

```text
~/.local/bin/awtarchy
```

Its internal runtime is stored at:

```text
~/.local/share/awtarchy/awtarchy-runtime.sh
```

The installer and maintenance command use built-in terminal menus without depending on `fzf`, `gum`, `dialog`, or `whiptail`.

## 📦 Install

Install Arch first with `archinstall` and choose the Minimal profile.

Then install Git:

```bash
sudo pacman -S git --noconfirm
```

Clone the repo and start the install-only entrypoint:

```bash
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

After installation, open a new shell and run:

```bash
awtarchy
```

### Existing-install detection

When `awtarchy-install.sh` finds the installed command, it stops before rerunning the installer and prints the maintenance commands.

When it detects a legacy Awtarchy installation without the command, it installs only `~/.local/bin/awtarchy`, the internal runtime, and version state. It does not reinstall packages or replace managed configs.

To intentionally run the complete installer again:

```bash
sudo ./awtarchy-install.sh --reinstall
```

## 🧪 Installer Dry-run

Dry-run lets you test the installer questionnaire and review the install plan without changing the system:

```bash
./awtarchy-install.sh --dry-run
```

For a detected legacy installation, dry-run reports the command migration without installing it.

## 🧭 Maintenance Menu

Running the installed command without arguments opens the maintenance menu:

```bash
awtarchy
```

Available actions:

```text
Refresh Awtarchy updater from main
Update configs (preserve personal modifications)
Reset configs (clean-slate managed files)
Review config changes without applying
Clean Awtarchy backup files
Version information
Exit
```

Installation is deliberately excluded from this menu. Use `awtarchy-install.sh` only when performing an initial installation or intentional full reinstall.

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

## 🔄 Updating Awtarchy

The installed command refreshes its launcher and runtime from the current `main`
head before update, reset, and review operations. Managed configs update only
from the latest published release unless an explicit release tag is selected.

Update only the installed command and runtime:

```bash
awtarchy self-update
```

Show the installed command release, installed config release, and latest release:

```bash
awtarchy version
```

Update configs while preserving personal modifications:

```bash
awtarchy update
```

Reset managed configs to the release defaults:

```bash
awtarchy reset
```

Preview config changes without applying them:

```bash
awtarchy review
```

Use a specific release tag:

```bash
awtarchy update --tag v1.0.0
```

### Existing installation migration

Existing users need one final repository-based migration to install the new command:

```bash
cd ~/awtarchy
git pull --ff-only
sudo ./awtarchy-install.sh
```

The installer detects the legacy Awtarchy state and performs a command-only migration. Existing packages and managed configs are left untouched. After migration, rerunning `awtarchy-install.sh` prints the maintenance commands and exits unless `--reinstall` is supplied.

## 🧹 Clean Backup Files

The backup cleaner scans common awtarchy-managed paths under your home directory, lists matching `.backup` files, and lets you mark files as `[KEEP]` before deleting the rest.

Interactive cleaner:

```bash
awtarchy clean-backups
```

List only, no prompt, no deletes:

```bash
awtarchy clean-backups --dry-run
```

Delete without prompting:

```bash
awtarchy clean-backups --yes
```

Only match backups older than 14 days:

```bash
awtarchy clean-backups --older-than 14
```

Archive matches before deletion:

```bash
awtarchy clean-backups --archive "$HOME/awtarchy-backups.tar.gz"
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
