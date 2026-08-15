# Safe Orphaned AUR Package Cleanup for Arch Linux (With Confirmation)

This script finds orphaned packages, excludes important ones, and asks for confirmation before removal.

---

## View Orphaned Packages

To see orphaned packages before removal, run:

```sh
yay -Qtdq
```

---

## Usage

Run this command in your terminal:

```sh
orphans=$(yay -Qtdq | grep -v -E "^(grub|linux.*|systemd|bash|coreutils|glibc|filesystem|util-linux|pacman|binutils|sudo|e2fsprogs|shadow|iproute2|inetutils|netctl|networkmanager|dhcpcd|nss|openssl|gnutls|ca-certificates|libx11|libxcb|xf86-input-libinput|xcb|xorg-server|xorg-xinit|mesa|wayland|wayland-protocols|kbd|mkinitcpio|nano|vim|vi|less|man-db|man-pages|base|base-devel|dbus|udev|zstd|pcre2|gcc-libs|libxkbcommon|seatd|pam|elogind|xdg-utils|xdg-desktop-portal|pipewire|wireplumber|hyprland|swaybg|xdg-desktop-portal-hyprland|accountsservice)$");

if [ -z "$orphans" ]; then
  echo "No orphaned AUR packages found";
else
  echo "The following orphaned AUR packages will be removed:"
  echo "$orphans"
  read -p "Do you want to proceed? [y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "$orphans" | xargs yay -Rns
  else
    echo "Aborted removal."
  fi
fi
```
