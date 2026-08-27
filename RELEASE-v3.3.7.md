# Awtarchy v3.3.7 Quickshell

Awtarchy v3.3.7 is a Quickshell-focused feature, polish, and reliability release. It improves Clipboard History responsiveness, adds per-display display and Quick Settings controls, adds an optional floating-window default, preserves more UI state, refines notification behavior, fixes fullscreen bar restoration, and removes the Quick Settings startup/grid issues found during real-session testing.

## Getting started

Awtarchy is an Arch Linux overlay/environment, not a Linux distribution or an Arch Linux installer. Install it onto a working minimal Arch Linux system.

If you are starting from zero:

1. Download the official Arch Linux ISO from the [Arch Linux download page](https://archlinux.org/download/).
2. Boot the Arch Linux ISO.
3. Install a working minimal Arch Linux system first.
   - For most users, Awtarchy recommends the official `archinstall` guided installer included with the Arch ISO as the easiest path. Run `archinstall` from the live environment and complete a minimal Arch installation.
   - A normal manual Arch installation using the [ArchWiki Installation Guide](https://wiki.archlinux.org/title/Installation_guide) is also fine.
4. Boot into the installed Arch system.

Once you have a working minimal Arch installation, install Awtarchy:

```bash
sudo pacman -S git --noconfirm
git clone https://github.com/dillacorn/awtarchy
cd awtarchy
sudo ./awtarchy-install.sh
```

Existing Awtarchy users:

```bash
awtarchy update
```

## Faster Clipboard History

- Clipboard History now streams entries newest-first instead of waiting for the full list before showing content.
- Metadata loading is capped to 60 entries for fast menu startup while delegates are reused as the list scrolls.
- Image thumbnails are generated lazily for visible rows rather than blocking the initial menu.
- Loading, empty, no-match, and backend-error states are handled explicitly.
- Clipboard producer processes are serialized and cleaned up across close/reopen and monitor handoff.
- Search keeps normal fuzzy matching while supporting intuitive `*` wildcard matching.
- Individual history entries can be permanently deleted without reloading the whole list or losing the current viewport.

## Focused display scaling

- Quick Settings → Bar Appearance can now adjust the focused display's Hyprland scale.
- Presets are available for `1`, `1.25`, `1.5`, and `2`, with a custom editor from `1.0` through `4.0`.
- Scale values are validated against the focused monitor resolution so the resulting logical dimensions remain whole pixels.
- Valid custom values show the resulting logical resolution before applying.
- Scale changes persist in `hyprland.lua` without changing the monitor's existing mode, position, or VRR fields.
- Failed reload/config validation restores the exact prior monitor configuration.

## Per-display Quick Settings layout

- Quick Settings now includes a per-display layout editor for the 11 real configurable sections.
- Sections can be shown, hidden, and reordered with live preview before saving.
- Layout state persists per display and can be copied to other displays or reset to the stock order.
- Invalid, duplicate, unknown, and all-hidden layouts are rejected or normalized safely.
- Top- and bottom-edge ordering remains consistent while hidden sections are removed from row calculations.
- The old inert Power Mode compatibility host no longer reserves a visible row, fixing the oversized Maximum output volume → Bar gap.
- Startup now falls back to the stock section order until the saved per-monitor draft loads, eliminating the row-0 GridLayout collisions found during real-session testing.

## Window behavior

- Quick Settings now includes an optional Floating Windows preference below Title Bars.
- Normal Awtarchy tiling remains the stock default.
- When enabled, newly opened normal windows float by default while explicit game, force-tile, and manual per-window behavior remain authoritative.
- The preference persists in `hyprland.lua` and supports customized existing configs through the updater's preserve-mode bootstrap path.
- Reload/config validation uses exact rollback on failure.

## Persistent clock/date state

- Each display now remembers whether its bar clock is showing time or date.
- Horizontal and vertical clock controls use the same persistent per-monitor state.
- Rapid toggles are coalesced so the final user choice wins.
- Existing unrelated monitor and application state is preserved.

## Notification behavior

- Space-family popup hiding now preserves notification history instead of permanently dismissing the entry.
- Normal notification body clicks invoke the default action when present and then hide only the popup.
- Explicit card X/swipe dismissal remains permanent.
- Clear remains permanent, with a short bounded staircase animation for visible history cards.
- Clear animation work is capped so large histories remain responsive, and notifications arriving during the animation are left untouched.

## Fullscreen bar and Quick Settings polish

- Each monitor's bar now explicitly follows that monitor's active Hyprland workspace fullscreen state.
- Fullscreen apps, including video and games, suppress only the bar on the affected monitor.
- Lock/unlock or resume can no longer restore the bar above an already-fullscreen workspace just because the layer surface was recreated.
- Leaving fullscreen restores the bar normally without changing the user's saved bar-enabled state.
- Quick Settings section spacing is now consistent, including Maximum output volume → Bar.

## Validation

- The combined Quickshell integration tree passed all 12 pull-request workflows before merge, including repository-wide `Validate Awtarchy`, Quick Settings layout, display scale, floating windows, clock/date persistence, fullscreen/spacing, notification history, PolicyKit, Bluetooth, update-notification, and anonymous-reporting checks.
- The final Quick Settings startup-row follow-up passed its focused regression and repository-wide `Validate Awtarchy`, then passed post-merge `Validate Awtarchy` on exact release target `d599be7966e934f6ccf717b72e4852ca8090e29b`.
- Real-machine testing confirmed the progressive Clipboard History behavior, focused display scaling, per-display Quick Settings customization, Floating Windows behavior, clock/date persistence, notification history behavior, corrected Quick Settings spacing, and fullscreen-video bar suppression.
- After the final Quick Settings startup fix, a fresh real-session check reported no Hyprland config errors, no new QML errors, and no new `QGridLayoutEngine ... cell (0, 0)` warnings. The only matching Quickshell warning was the unrelated unavailable `org.freedesktop.UPower.PowerProfiles` service on the desktop.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.3.7._
