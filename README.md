# `arch dilla.hypr.files`

**Click the image below to see more previews!**

[![overview](https://github.com/dillacorn/arch-hypr-dots/raw/main/previews/overview.png)](https://github.com/dillacorn/arch-hypr-dots/tree/main/previews.md)

## 🚀 Quick Start
ℹ️ Note: Before running `archinstall`, update the package database to ensure you're using the latest version:
```bash
pacman -Syyu
```

### Installation (after `archinstall`):
```bash
git clone https://github.com/dillacorn/arch-hypr-dots
cd arch-hypr-dots
chmod +x setup_installer.sh
sudo ./setup_installer.sh
```
> ⚠️ Caution: Always review scripts from the internet before running them.

## 🖥️ System Overview

| Component          | Details |
|--------------------|---------|
| **Distro**         | [Arch Linux](https://archlinux.org/) |
| **Installation**   | [archinstall](https://github.com/archlinux/archinstall) |
| **File System**    | [ext4 (separate root/home partitions)](https://man.archlinux.org/man/ext4.5.en) and/or [BTRFS](https://wiki.archlinux.org/title/Btrfs) |
| **Repositories**   | core, extra, multilib, [AUR](https://aur.archlinux.org/), [Flathub](https://flathub.org/) |
| **Terminal**       | [Alacritty](https://github.com/alacritty/alacritty) |
| **Bootloader**     | [systemd-boot](https://man.archlinux.org/man/systemd-boot.7) |
| **Window Manager** | [Hyprland](https://github.com/hyprwm/Hyprland) ([config](https://github.com/dillacorn/arch-hypr-dots/tree/main/config/hypr)) |
| **Kernel**         | [linux-tkg](https://github.com/Frogging-Family/linux-tkg) with BORE scheduler |

## 🎨 Wallpaper Collections
- [dharmx/walls](https://github.com/dharmx/walls)
- [Gruvbox Wallpapers](https://github.com/AngelJumbo/gruvbox-wallpapers)
- [Aesthetic Wallpapers](https://github.com/D3Ext/aesthetic-wallpapers)

---

# ⌨️ Hyprland Keybindings

## 🛠️ Custom Scripts & Commands
| Keybind               | Action                          |
|-----------------------|---------------------------------|
| `SUPER + r`          | Rotate navigation keys (SUPER/ALT toggle) |
| `SUPER + t`          | Run theme scripts               |
| `SUPER + w`          | Change wallpaper (Waypaper GUI) |
| `SUPER + SHIFT + c`  | Open SpeedCrunch (Calculator)   |
| `SUPER + SHIFT + g`  | Record cropped GIF              |
| `SUPER + SHIFT + s`  | Take cropped screenshot         |
| `SUPER + SHIFT + f`  | Take fullscreen screenshot      |
| `SUPER + q`          | Scan QR code                    |

## 🖱️ Navigation & Windows
| Keybind                     | Action                      |
|-----------------------------|-----------------------------|
| `SUPER + SHIFT + Enter`     | Open terminal (Alacritty)   |
| `SUPER + p`                 | Application launcher (Wofi) |
| `SUPER + SHIFT + q`         | Close focused window        |
| `SUPER + f`                 | Toggle floating/tiling      |
| `SUPER + arrow keys`        | Change window focus         |
| `SUPER + mouse1/2`          | Move/resize floating window |

## 🗂️ Workspaces
| Keybind                     | Action                      |
|-----------------------------|-----------------------------|
| `SUPER + 1-9`              | Switch workspace           |
| `SUPER + SHIFT + 1-9`      | Move window to workspace   |
| `SUPER + CTRL + SHIFT + arrows` | Move workspace to monitor |

---

## ⚡ Installation Scripts
- [Arch Repo Apps](scripts/install_arch_repo_apps.sh)
- [AUR Apps](scripts/install_aur_repo_apps.sh)  
- [Flatpak Apps](scripts/install_flatpak_apps.sh)

> ℹ️ Modify scripts to suit your preferences

## 🌐 Browser Notes
- [Brave](browser_notes/brave.md)
- [Ungoogled-Chromium](browser_notes/ungoogled-chromium.md)
- [Firefox Privacy Forks](browser_notes/firefox_privacy_focused_forks.md)
- [Cromite](browser_notes/cromite.md)

---

## 📜 License
All code and notes are unlicensed - use freely!  
[See UNLICENSED file](https://github.com/dillacorn/arch-hypr-dots/blob/main/UNLICENSED)
