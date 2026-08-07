# Quickshell conversion testing

This branch replaces Awtarchy's Waybar, Fuzzel, Mako, and wlogout runtime stack with one Quickshell shell.

## Replaced components

Quickshell now owns:

- Per-monitor bars with top, bottom, left, and right layouts.
- Hyprland workspaces, workspace movement controls, taskbar, scratchpad count, submap display, and active-window title.
- Idle inhibitor status/control.
- CPU, CPU temperature, memory, debounced DDC brightness, battery, PipeWire volume, clock/date, and system tray.
- Application launcher.
- Clipboard history with image thumbnails.
- Notification daemon, notification popups, dismiss, and DND state.
- Power/session menu.
- Theme picker.

## Package conversion

The Awtarchy installer now installs the official Arch `quickshell` package.

These packages are no longer selected by Awtarchy:

- `waybar-git`
- `fuzzel`
- `wlogout`
- `mako`

During a full reinstall/conversion, an obsolete package is removed automatically only when it is recorded in `/var/lib/awtarchy/managed-packages`. If one of these packages was installed independently by the user, Awtarchy leaves it installed.

## Config conversion

Fresh/reinstall config copying now includes:

- `~/.config/hypr`
- `~/.config/quickshell`

The repository no longer ships the old `config/waybar`, `config/fuzzel`, `config/mako`, or `config/wlogout` trees.

Awtarchy helper scripts previously stored below `config/waybar/scripts` were moved to `config/hypr/scripts` because they are Awtarchy/Hyprland helpers, not Waybar components.

The first Quickshell launch may still import `~/.cache/waybar/state.json` when it exists. That is migration-only behavior so existing per-monitor bar positions/enabled state survive the conversion; Waybar is not required or launched.

## Themes

Awtarchy theme files are now data-only palettes. They contain `QS_*` colors plus Hyprland/Wofi/application-theme metadata and no longer mutate Waybar, Fuzzel, Mako, or wlogout configs.

`quickshell_theme_apply.sh` writes Quickshell's native:

```text
~/.config/quickshell/awtarchy/theme.json
```

It also preserves the existing Awtarchy theme behavior for Hyprland borders, Wofi, Micro, Alacritty, and SpeedCrunch.

## Testing branch installer behavior

The testing installer deliberately keeps the unreleased branch runtime instead of immediately replacing it with the latest stable GitHub release. An explicit later `awtarchy self-update` will return the command/runtime to the published release channel.

For an existing Awtarchy machine, use the full reinstall path so package/config conversion actually runs:

```bash
cd ~/awtarchy
git fetch origin
git switch quickshell-conversion-testing
git pull --ff-only
sudo ./awtarchy-install.sh --reinstall --no-reboot
```

Then start or restart the Hyprland session. Quickshell is started directly by `hyprland.lua`.

Verify the shell:

```bash
pacman -Q quickshell
~/.config/hypr/scripts/quickshell.sh status
qs -c awtarchy ipc call control ping
~/.config/hypr/scripts/quickshell.sh dump-state
```

Expected IPC result:

```text
ok
```

Check that Awtarchy no longer owns the old packages:

```bash
pacman -Q waybar-git fuzzel wlogout mako 2>/dev/null || true
grep -E '^(waybar-git|fuzzel|wlogout|mako)$' /var/lib/awtarchy/managed-packages 2>/dev/null || true
```

Watch the Quickshell log:

```bash
tail -f ~/.cache/awtarchy/quickshell.log
```

## Current validation

The conversion branch has passed repository-side checks for:

- `bash -n` on the installer/runtime and Hypr shell scripts.
- Runtime package/default selection: Quickshell present and the four legacy packages absent.
- Runtime config-copy selection: Quickshell present and the four legacy config directories absent.
- Hyprland autostart: Quickshell direct start and no Mako start.
- Quickshell bar helper paths: no dependency on `~/.config/waybar/scripts`.
- Converted themes: no legacy shell-program theme tokens.
- `git diff --check`.

Actual rendering/input behavior still needs testing inside a real Arch + Hyprland + Quickshell session.
