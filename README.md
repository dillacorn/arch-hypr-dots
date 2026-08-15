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

Awtarchy-authored code and configuration is licensed under MIT unless otherwise noted. Third-party material retains its respective copyright and license. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for redistributed or adapted third-party material that warrants attribution.

---

**Click the image below to see more previews.**

[![overview](https://github.com/dillacorn/awtarchy/raw/main/previews/overview.png)](https://github.com/dillacorn/awtarchy/tree/main/previews.md)

## System Overview

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

## Install

Awtarchy expects a minimal vanilla Arch installation. `archinstall` with the Minimal profile is the recommended starting point.

```bash
sudo pacman -S git --noconfirm
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

After installation, use:

```bash
awtarchy
```

The installed maintenance command lives at `~/.local/bin/awtarchy`.

If Awtarchy is already installed, running the installer refreshes the maintenance command without reinstalling packages or replacing managed configs. Use `sudo ./awtarchy-install.sh --reinstall` only when you intentionally want the full installer again.

## Maintenance

Run `awtarchy` with no arguments for the interactive maintenance menu.

Common commands:

```text
awtarchy update          Update from the latest published release while preserving personal modifications
awtarchy reset           Reset managed configs to published release defaults
awtarchy review          Preview managed config changes without applying them
awtarchy version         Show updater, config release, and git-testing status
awtarchy git             Test an unreleased remote branch or exact branch commit
awtarchy clean-backups   Review and clean Awtarchy backup files
awtarchy help            Show the full command list
```

`awtarchy update`, `reset`, and `review` remain release-based; `--tag` accepts only an exact published release tag. The launcher/runtime can refresh from `main` independently so updater fixes do not require a config release.

`awtarchy git` is an explicit unreleased-testing mode. It shows the selected remote branch and exact commit and keeps git-testing state separate from stable release state.

## Existing installations and Quickshell migration

Existing Awtarchy users can update through the normal `awtarchy update` flow once the Quickshell release is published. The updater preserves personalized managed files where possible, creates backups when required, and migrates retired Waybar/Fuzzel-era managed files to the Quickshell shell.

For installations still using the old repository-only updater:

```bash
cd ~/awtarchy
git pull --ff-only
sudo ./awtarchy-install.sh
```

This installs the current maintenance command without broadly replacing managed configs.

## Dry-run

Review the installer questionnaire and install plan without changing the system:

```bash
./awtarchy-install.sh --dry-run
```

## Wallpaper Collections

* [dharmx/walls](https://github.com/dharmx/walls)
* [Gruvbox Wallpapers](https://github.com/AngelJumbo/gruvbox-wallpapers)
* [Aesthetic Wallpapers](https://github.com/D3Ext/aesthetic-wallpapers)

## Browser Notes

* [Firefox + Betterfox](browser_notes/firefox.md)
* [Brave](browser_notes/brave.md)
* [Mullvad](browser_notes/mullvad.md)

## Optional Packages

* [Optional Packages](extra_notes/optional_packages.md)

## License

Awtarchy-authored code and configuration is licensed under the [MIT License](https://github.com/dillacorn/awtarchy/blob/main/LICENSE) unless otherwise noted. Third-party material retains its original copyright and licensing terms.

## Legal Notice

This project is a general-purpose open-source utility that runs locally on the user’s system. It does not provide a hosted service and does not collect user data. Users are responsible for complying with laws and regulations in their own jurisdiction when using this software.

## Donate

Built and maintained out of passion. Always FOSS. Donations appreciated.
[Donate via PayPal](https://www.paypal.com/donate/?business=XSNV4QP8JFY9Y&no_recurring=0&item_name=Built+and+maintained+out+of+passion.+Always+FOSS.+Donations+appreciated.+%28smtty%2C+MicLockTray%2C+awtarchy%29&currency_code=USD)
