# Quickshell conversion testing

This branch moves Awtarchy's desktop-shell UI from Waybar, Fuzzel, Mako, and wlogout to one Quickshell process while preserving the existing Awtarchy entrypoints during testing.

## Current scope

Quickshell currently owns:

- Per-monitor bars with top, bottom, left, and right layouts.
- Hyprland workspaces, workspace movement controls, taskbar, scratchpad count, submap display, and active-window title.
- Idle inhibitor status/control.
- CPU, CPU temperature, memory, DDC brightness, battery, PipeWire volume, clock/date, and system tray.
- Application launcher.
- Clipboard history with image thumbnails.
- Notification daemon and DND state.
- Power/session menu.
- Theme picker.

The current Awtarchy theme scripts remain the palette source during testing, but Quickshell now reads its own `theme.json`. The theme picker extracts the existing Awtarchy shell color variables into that native Quickshell theme file, so Quickshell no longer depends on Waybar CSS at runtime.

## Compatibility

The existing command paths remain valid during conversion:

- `~/.config/hypr/scripts/waybar.sh`
- `~/.config/hypr/scripts/fuzzel_toggle.sh`
- `~/.config/hypr/scripts/cliphist-fuzzel.sh`
- `~/.config/hypr/scripts/wlogout_toggle.sh`
- `~/.config/hypr/scripts/mako_dismiss.sh`
- `~/.config/hypr/scripts/theme_select.sh`

These now route to Quickshell. This keeps the existing Hyprland keybinds, autostart commands, desktop entries, and hypridle configuration working while the conversion is tested.

The first Quickshell launch imports `~/.cache/waybar/state.json` when available so existing per-monitor bar positions and enabled state are retained.

## Install Quickshell

On Arch Linux:

```bash
sudo pacman -S quickshell
```

## Test

Start the shell:

```bash
~/.config/hypr/scripts/quickshell.sh start
```

Verify IPC and state:

```bash
qs -c awtarchy ipc call control ping
~/.config/hypr/scripts/quickshell.sh status
~/.config/hypr/scripts/quickshell.sh dump-state
```

Exercise the existing entrypoints:

```bash
~/.config/hypr/scripts/fuzzel_toggle.sh
~/.config/hypr/scripts/cliphist-fuzzel.sh
~/.config/hypr/scripts/wlogout_toggle.sh
~/.config/hypr/scripts/theme_select.sh
~/.config/hypr/scripts/waybar_toggle.sh
~/.config/hypr/scripts/waybar_flip.sh
~/.config/hypr/scripts/waybar_rotate.sh
```

Watch the Quickshell log:

```bash
tail -f ~/.cache/awtarchy/quickshell.log
```

Stop the whole Quickshell process manually if needed:

```bash
~/.config/hypr/scripts/quickshell.sh stop
```

## Testing-phase compatibility retained intentionally

The old Waybar/Fuzzel/Mako/wlogout config files and package selections are not removed in this first test commit. They provide rollback/reference data while the Quickshell replacement is visually and behaviorally verified. After parity is confirmed, the conversion can remove the old package dependencies, obsolete configs, and compatibility shims that are no longer needed.

Notification actions are not advertised in the first test build. Basic notification display, timeout, dismiss, DND, images, summary, and body handling are implemented first so notification ownership is predictable during testing.
