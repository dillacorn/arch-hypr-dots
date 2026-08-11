# Safe Orphaned Arch-Repo Package Cleanup for Arch Linux (With Confirmation)

This script finds orphaned packages but excludes important kernels and essential system packages to avoid accidental removal.

---

## View Orphaned Packages

To see orphaned packages before removal, run:

```sh
pacman -Qtdq
```

---

## Usage

Run this command in your terminal:

```sh
orphans=$(pacman -Qtdq | grep -v -E "^(grub|linux.*|systemd|bash|coreutils|glibc|filesystem|util-linux|pacman|binutils|sudo|e2fsprogs|shadow|iproute2|inetutils|netctl|networkmanager|dhcpcd|nss|openssl|gnutls|ca-certificates|libx11|libxcb|xf86-input-libinput|xcb|xorg-server|xorg-xinit|mesa|wayland|wayland-protocols|kbd|mkinitcpio|nano|vim|vi|less|man-db|man-pages|base|base-devel|dbus|udev|zstd|pcre2|gcc-libs|libxkbcommon|seatd|pam|elogind|xdg-utils|xdg-desktop-portal|pipewire|wireplumber|hyprland|swaybg|xdg-desktop-portal-hyprland|accountsservice)$")

if [ -z "$orphans" ]; then 
  echo "No orphaned packages found"
else 
  echo "The following orphaned packages will be removed:"
  echo "$orphans"
  read -p "Do you want to proceed? [y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "$orphans" | xargs sudo pacman -Rns
  else
    echo "Aborted removal."
  fi
fi
```
