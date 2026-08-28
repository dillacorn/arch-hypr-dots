# Awtarchy v3.4.0 Quickshell

Awtarchy v3.4.0 is a Quickshell customization and polish release focused on the bar, workspace presentation, theme browser behavior, flyout placement, and Quick Settings usability. It expands per-display bar controls, improves fullscreen-aware flyouts, makes workspace labels far more configurable, and tightens the visual theme workflow without changing the existing Awtarchy installation model.

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

## Workspace and launcher customization

- Workspace numbers and workspace icons are now independent controls instead of one mutually exclusive style setting.
- The stock default remains Numbers On + Awtarchy icons, preserving the normal Awtarchy workspace appearance for fresh/default setups.
- Built-in workspace packs are intentionally curated around Awtarchy, Workflow, Phases, Custom, and Off instead of filling the selector with repetitive geometric presets.
- The Workflow pack provides distinct role-style examples across workspaces, while Phases keeps its sequential visual identity.
- Workspace glyph sizing and optical vertical offsets are handled independently from workspace numbers so icons sit more naturally beside the numeric label.
- Existing saved workspace styles are normalized through compatibility mappings instead of being discarded.
- Per-workspace custom overrides continue to take precedence over the global workspace presentation.
- Workspace pack symbols and application-launcher symbols can be copied directly, with visible copy feedback.
- Copy All now copies the full workspace pack through a managed clipboard process and reports success only after the copy command succeeds.
- Nerd Fonts and Unicode resource links are available from the customization UI for users building their own workspace or launcher labels.

## Theme browser refinements

- The visual Theme Picker now uses square corners throughout to match the requested Awtarchy presentation.
- Clicking a different theme selects it; clicking the already-selected theme again applies it through the existing theme-apply path.
- The Apply Theme button and Enter-key apply behavior remain available.
- Theme browsing remains non-destructive until an apply action occurs.

## Bar controls and flyout placement

- Internal Awtarchy Quickshell flyouts are filtered out of the running-application task strip while normal application and tray icon coloring remains intact.
- CPU usage, CPU temperature, and RAM usage can be toggled per display from Quick Settings and remain visible by default.
- Launcher, Clipboard, Notifications, Network, and Bluetooth now respect effective per-monitor bar visibility when deciding whether to anchor to a bar edge or open centered.
- Keyboard-opened Notifications stay centered along the active visible bar edge while bar-click opens remain anchored to the clicked bar item.
- `SUPER+N` toggles the notification center in the default and `noalt` modes without changing the mouse or VM submaps.
- Fullscreen/hidden-bar flyout behavior is preserved so menus do not incorrectly position against a bar that is not currently visible.

## Quick Settings layout usability

- The Customize Layout editor now has a visible scrollbar when its section list exceeds the available height.
- The layout header, monitor name, Stock Layout control, and explanatory text remain fixed while only the section list scrolls.
- Mouse wheel, touchpad scrolling, scrollbar dragging, and track clicking reuse Awtarchy's existing `ListScrollBar` behavior.
- The row layout reserves scrollbar space only when needed so visibility and reorder controls are not covered.
- Existing per-display ordering, hiding, saving, reset, and copy-to-display behavior is unchanged.

## Validation

- PR #86 and PR #88 were runtime-tested and approved in a real Awtarchy/Hyprland session before release integration.
- Focused regressions cover workspace composition, workspace icon packs, Theme Picker behavior, bar icon customization, bar task filtering, module visibility, flyout placement, Quick Settings layout scrolling, and updater managed-history migration.
- Bash syntax and ShellCheck passed for the changed state helper and related focused test scripts.
- Exact post-merge release target `76f8e63272c5af7c157e151d34744f7fce249a43` passed `Validate Awtarchy`, `Validate Bluetooth State`, `Validate PolicyKit Agent`, `Validate Update Notification Login Regression`, `Validate Theme Picker Workspace Composition`, and `Validate Anonymous Failure Reporting` on `main` before publication.
- The release target preserves the updater-managed Quickshell history required for stable migration from previously shipped Awtarchy configurations.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.4.0._
