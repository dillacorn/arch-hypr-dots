# Awtarchy v3.0.0 Quickshell

## Patch notes for v3.0.0

- Awtarchy's desktop shell has been rebuilt around [Quickshell](https://github.com/quickshell-mirror/quickshell), replacing the previous Waybar/Fuzzel-era shell stack.
- The Quickshell shell now owns the bar, application launcher, notifications, Quick Settings, network and Bluetooth controls, power controls, clipboard UI, display controls, and other shell surfaces that were previously split across several programs and helper scripts.
- Existing Awtarchy installations can migrate through the normal `awtarchy update` flow. Preserve mode keeps personalized managed files where possible, creates backups when required, and migrates supported Hyprland customizations.
- The updater now tracks the command/runtime separately from published config releases, supports explicit Git branch testing, validates migrations before applying them, and can reconcile older preserved Quickshell UI files without replacing `hyprland.lua`.
- Awtarchy's Quickshell configuration includes multi-monitor behavior, per-display shell settings, capture-privacy controls, notification controls, audio limits, display brightness controls, and shell recovery handling.

## Start Here

Awtarchy is not a Linux distribution. It is an overlay built to run on top of a fresh, vanilla Arch Linux installation.

1. Download the latest [Arch Linux ISO](https://archlinux.org/download/).
2. Put the ISO on a bootable USB. [Ventoy](https://www.ventoy.net/en/download.html) is recommended because you can copy ISOs directly to the drive and reuse it without reflashing each time.
3. Boot the Arch ISO and install Arch manually, or use `archinstall`.

`archinstall` is included on the Arch ISO. To refresh it before starting the installer:

```bash
pacman -Sy archinstall
archinstall
```

Choose the **Minimal** profile. Complete the Arch installation, reboot, and log into the new system before installing Awtarchy.

## Install Awtarchy

Install Git:

```bash
sudo pacman -S git --noconfirm
```

Clone the repository and run the installer:

```bash
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

The installer collects your choices before making changes and shows a final review before installation begins.

## After Installation

Reboot after the installer completes.

If Ly was enabled during installation, log in through Ly. Otherwise, log in from the TTY and start Hyprland with:

```bash
hypr
```

For future updates and system maintenance, run:

```bash
awtarchy
```

The `awtarchy` menu handles command updates, configuration maintenance, version checks, Git testing, and backup cleanup.

## Existing Awtarchy Users

If the installed `awtarchy` command is already available, migrate to v3.0.0 with:

```bash
awtarchy update
```

The updater preserves personalized managed files where possible and creates backups before replacing files that require migration.

If the installation still uses the old repository-only updater, perform the command migration first:

```bash
cd ~/awtarchy
git pull --ff-only
sudo ./awtarchy-install.sh
```

That step installs the current maintenance command without broadly replacing managed configs. Then run:

```bash
awtarchy update
```

## Retired shell programs

The v3.0.0 migration retires these programs from the Awtarchy-managed shell stack when installed:

- Waybar / `waybar-git`
- Fuzzel
- Mako
- Wlogout
- Wofi
- `network-manager-applet`
- Blueman

NetworkManager and BlueZ remain part of the system. Only the retired GUI applets are removed because their shell-facing controls are now provided by Awtarchy's Quickshell implementation.

## Retired managed configuration

The updater removes Awtarchy-managed configuration and cache directories that belonged to the old shell stack:

```text
~/.config/waybar/
~/.config/fuzzel/
~/.config/mako/
~/.config/wlogout/
~/.config/wofi/
~/.cache/waybar/
~/.cache/fuzzel/
~/.cache/wofi/
```

It also retires the old Awtarchy shell helper scripts and desktop entries, including:

```text
~/.config/hypr/scripts/cliphist-fuzzel.sh
~/.config/hypr/scripts/cliphist-wofi.sh
~/.config/hypr/scripts/fuzzel_toggle.sh
~/.config/hypr/scripts/mako_dismiss.sh
~/.config/hypr/scripts/waybar.sh
~/.config/hypr/scripts/waybar_flip.sh
~/.config/hypr/scripts/waybar_ready_sound.sh
~/.config/hypr/scripts/waybar_restore_resume.sh
~/.config/hypr/scripts/waybar_rotate.sh
~/.config/hypr/scripts/waybar_toggle.sh
~/.config/hypr/scripts/waybar_toggle_idle.sh
~/.config/hypr/scripts/wlogout_toggle.sh
~/.local/share/applications/hypr_quicksettings.desktop
~/.local/share/applications/waybar_flip.desktop
~/.local/share/applications/waybar_rotate.desktop
~/.local/share/applications/waybar_toggle.desktop
```

## What Changed in v3.0.0

- Replaced the previous collection of shell programs with a unified Quickshell implementation.
- Added a Quickshell bar, launcher, notifications, Quick Settings, network/Bluetooth interfaces, power controls, clipboard UI, and display-oriented shell controls.
- Added per-display shell configuration and multi-monitor handling.
- Added capture-privacy controls for sensitive shell surfaces.
- Added stronger Quickshell startup, restart, resume, and migration recovery behavior.
- Added a safer production updater with preserve, reset, review, and explicit Git-testing modes.
- Added migration handling for retired Waybar/Fuzzel-era packages, configuration, helper scripts, and desktop entries.
- Added expanded updater, migration, shell, security-boundary, and regression validation in GitHub Actions.
