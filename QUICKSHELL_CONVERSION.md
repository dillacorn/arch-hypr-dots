# Quickshell conversion testing

This branch replaces Awtarchy's Waybar, Fuzzel, Wofi, Mako, and wlogout runtime stack with one Quickshell shell.

## Replaced components

Quickshell now owns:

- Per-monitor bars with top, bottom, left, and right layouts.
- Hyprland workspaces, workspace movement controls, taskbar, scratchpad count, submap display, and active-window title.
- Idle inhibitor status/control.
- CPU, CPU temperature, memory, debounced DDC brightness, battery, PipeWire volume, clock/date, and system tray.
- Application launcher.
- Clipboard history with image thumbnails.
- Notification daemon, notification popups, bounded notification history, actions, dismiss, and popup mute.
- Power/session menu.
- Theme picker.

## Revised shell interactions

- The DDC brightness segment now uses a cogwheel. Scrolling it still adjusts brightness; primary- or secondary-click opens native QML Quick Settings on that display.
- Launcher, Clipboard, Notifications, and Quick Settings have per-display draft sizing and scale controls with an explicit **Save** action. Closing settings discards unsaved changes; reset immediately restores protected defaults.
- Clipboard retains its draggable list scrollbar and adds saved text/image scaling plus copy-to-display settings.
- Primary-clicking the notification bell opens history. Secondary-clicking it mutes or unmutes popups without dismissing stored notifications.
- Quick Settings directly controls DDC brightness, bar placement/visibility, Night Light, vibrance, Hyprland submaps, wallpaper selection, `sched-ext`, NetworkManager Wi-Fi, wired status, and BlueZ Bluetooth devices.
- Only one major flyout is kept open at a time.

### Capture privacy

Screen sharing and recording are never stopped by the shell. Instead, Hyprland `no_screen_share` rules mask only the selected sensitive Quickshell surfaces with black rectangles in captured output.

Launcher, Clipboard, Notifications (both popups and history), and Quick Settings are protected by default. Each surface exposes an **Allow in screenshots and screen recordings** setting; turning it on and saving disables the mask for that surface. Missing or invalid state fails closed and leaves the surface protected.

## Package conversion

The Awtarchy installer now installs the official Arch `quickshell` package.

These packages are no longer selected by Awtarchy:

- `waybar-git`
- `fuzzel`
- `wofi`
- `wlogout`
- `mako`

During a full reinstall/conversion, an obsolete package is removed automatically only when it is recorded in `/var/lib/awtarchy/managed-packages`. If one of these packages was installed independently by the user, Awtarchy leaves it installed.

## Config conversion

Fresh/reinstall config copying now includes:

- `~/.config/hypr`
- `~/.config/quickshell`

The repository no longer ships the old `config/waybar`, `config/fuzzel`, `config/wofi`, `config/mako`, or `config/wlogout` trees.

Awtarchy helper scripts previously stored below `config/waybar/scripts` were moved to `config/hypr/scripts` because they are Awtarchy/Hyprland helpers, not Waybar components.

The first Quickshell launch may still import `~/.cache/waybar/state.json` when it exists. That is migration-only behavior so existing per-monitor bar positions/enabled state survive the conversion; Waybar is not required or launched.

## Themes

Awtarchy theme files are now data-only palettes. They contain native `QS_*` shell colors plus Hyprland/application-theme metadata and no longer mutate legacy launcher, bar, notification, or logout UI configs.

`quickshell_theme_apply.sh` writes Quickshell's native:

```text
~/.config/quickshell/awtarchy/theme.json
```

It also preserves the existing Awtarchy theme behavior for Hyprland borders, Micro, Alacritty, and SpeedCrunch.

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

Quick Settings can also be opened without the bar:

```bash
~/.config/hypr/scripts/quickshell_quick_settings_toggle.sh
```

Check that Awtarchy no longer owns the old packages:

```bash
pacman -Q waybar-git fuzzel wofi wlogout mako 2>/dev/null || true
grep -E '^(waybar-git|fuzzel|wofi|wlogout|mako)$' /var/lib/awtarchy/managed-packages 2>/dev/null || true
```

Watch the Quickshell log:

```bash
tail -f ~/.cache/awtarchy/quickshell.log
```

## Current validation

The conversion branch has passed repository-side checks for:

- `bash -n` on the installer/runtime and Hypr shell scripts.
- Runtime package/default selection: Quickshell present and the legacy shell UI packages absent.
- Runtime config-copy selection: Quickshell present and the legacy shell UI config directories absent.
- Hyprland autostart: Quickshell direct start and no Mako start.
- Quickshell bar helper paths: no dependency on `~/.config/waybar/scripts`.
- Converted themes: no legacy shell-program theme tokens.
- Quickshell QML delimiter/ID structure for the revised components.
- Atomic per-display Launcher, Clipboard, Notifications, and Quick Settings state persistence.
- Fail-closed capture-rule generation, including independent enable/disable state for every protected surface.
- Quick Settings status/action backend fallbacks and persisted `sched-ext` profiles.
- `git diff --check`.

Actual rendering/input behavior still needs testing inside a real Arch + Hyprland + Quickshell session. In particular, verify DDC hardware routing, Wi-Fi password entry, Bluetooth pairing, popup placement, and that protected surfaces become black rectangles while the rest of an active screen recording continues normally. `nm-applet` and `blueman-applet` remain enabled as live-validation fallbacks for now.
