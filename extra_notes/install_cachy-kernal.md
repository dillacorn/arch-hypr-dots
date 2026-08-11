# CachyOS kernel on Arch (systemd-boot) quick guide

For a normal Arch installation, use the automated repository setup documented by the official `CachyOS/linux-cachyos` project.

## 1. Add the CachyOS repositories

```sh
curl -O https://mirror.cachyos.org/cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz
cd cachyos-repo
sudo ./cachyos-repo.sh
```

The installer detects the supported CPU repository tier and configures the CachyOS repositories for pacman.

## 2. Install the kernel

```sh
sudo pacman -Syu
sudo pacman -S --needed linux-cachyos linux-cachyos-headers
```

Awtarchy's current kernel/GPU handling recognizes `linux-cachyos` kernels. The old standalone `install_GPU_dependencies.sh` workflow is obsolete and should not be used.

## 3. Add a systemd-boot entry if your setup uses manual loader entries

First inspect the entries that already boot correctly:

```sh
bootctl list
ls /boot/loader/entries
```

Copy your working Arch entry and edit the copy rather than inventing a new `options` line:

```sh
cd /boot/loader/entries
sudo cp -a <existing-arch-entry>.conf linux-cachyos.conf
sudo nano linux-cachyos.conf
```

The kernel/initramfs portion should point at the CachyOS files while preserving your existing root/options line:

```ini
title   Linux CachyOS
linux   /vmlinuz-linux-cachyos
initrd  /amd-ucode.img
initrd  /initramfs-linux-cachyos.img
options <keep the working options line from your existing Arch entry>
```

Intel systems should use the existing Intel microcode line instead of `/amd-ucode.img`.

Verify the entry is detected:

```sh
bootctl list
```

No separate bootloader regeneration command is required for a normal systemd-boot loader entry. systemd-boot reads the entry files from the loader entries directory at boot.

Official kernel/repository documentation:
https://github.com/CachyOS/linux-cachyos
