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
awtarchy-install.sh    Initial installation or intentional full reinstall
awtarchy               Updates and maintenance after installation
```

The installed command lives at `~/.local/bin/awtarchy`. Run `awtarchy help` for the full command and option list.

The installer and maintenance command use built-in terminal menus without depending on `fzf`, `gum`, `dialog`, or `whiptail`.

## 📦 Install

Install Arch first with `archinstall` and choose the Minimal profile.

Then install Git:

```bash
sudo pacman -S git --noconfirm
```

Clone the repo and run the installer:

```bash
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

After installation:

```bash
awtarchy
```

### Existing installations

If the installer finds an existing Awtarchy installation, it installs or refreshes the maintenance command without reinstalling packages or replacing managed configs.

To intentionally run the complete installer again:

```bash
sudo ./awtarchy-install.sh --reinstall
```

Existing users migrating from the older repository-only updater can run:

```bash
cd ~/awtarchy
git pull --ff-only
sudo ./awtarchy-install.sh
```

### Dry-run

Review the installer questionnaire and install plan without changing the system:

```bash
./awtarchy-install.sh --dry-run
```

## ⚙️ Installer Behavior

The installer collects choices before making changes. It lets you choose the system type, install sections, Arch package categories, AUR packages, Flatpak apps, and shell-file overwrite behavior, then shows a final review screen before a live install starts.

## 🧭 Maintenance

Run `awtarchy` with no arguments for the interactive maintenance menu.

Common commands:

```text
awtarchy update          Update configs and preserve personal modifications
awtarchy reset           Reset managed configs to release defaults
awtarchy review          Preview managed config changes without applying them
awtarchy version         Show updater and config release status
awtarchy clean-backups   Review and clean Awtarchy backup files
awtarchy help            Show all commands and options
```

The `awtarchy` launcher/runtime refreshes from the current `main` head. Managed configs update from published releases so the updater and config release remain separate.

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
