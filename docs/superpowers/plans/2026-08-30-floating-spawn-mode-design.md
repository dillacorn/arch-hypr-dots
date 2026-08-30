# Floating Spawn Mode Design

## Goal

Make Awtarchy's global "new windows spawn floating" mode easy to toggle, impossible to forget visually, and consistent between Quick Settings, keyboard control, and the bar.

## Approved behavior

- `SUPER+ALT+F` toggles the global floating-spawn mode.
- `SUPER+F` remains unchanged and only toggles the focused window between tiled and floating.
- Toggling global floating-spawn mode from the keyboard emits a short Awtarchy notification stating whether it is enabled or disabled.
- While global floating-spawn mode is enabled, every visible Awtarchy bar shows a persistent `Floating` indicator.
- Left-clicking the `Floating` indicator disables global floating-spawn mode.
- The indicator is absent when global floating-spawn mode is disabled.
- Quick Settings continues to expose the existing Floating Windows control, but it and the bar must consume the same shared state instead of polling independently.
- Existing game exceptions and the current `hyprland.lua` marker/rule behavior remain unchanged.

## Architecture

`quickshell_floating_windows.sh` remains the only component that edits `hyprland.lua`. It gains a `toggle` action and publishes the resolved state to a small runtime state file after `status`, `set`, or `toggle`. Keyboard toggles request a notification through the same helper.

A new `FloatingWindowsState.qml` singleton owns Quickshell-side state. It reads/watches the runtime state file, performs one initial status refresh, and exposes `enabled`, `state`, `setEnabled()`, and `toggle()` for UI consumers. `FloatingWindowsCard.qml` and `Bar.qml` consume this singleton so there is no per-card or per-monitor status polling.

The bar indicator is rendered in both horizontal and vertical layouts. It is deliberately plain text and persistent because the purpose is warning/visibility, not decoration.

## Constraints

- Preserve `SUPER+F` focused-window behavior.
- Preserve current game tiling exceptions.
- Do not add polling per monitor.
- Do not overwrite user `hyprland.lua` beyond the existing floating-mode marker/rule mechanism.
- Update managed Quickshell history hashes for every managed QML file changed or added.
- Validate `hyprland.lua` bind coverage for both default and `noalt` submap modes.
