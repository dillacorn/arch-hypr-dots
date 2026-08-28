# Visual Theme Browser Design

## Goal

Replace the existing filename-list `ThemePicker.qml` with a visual, searchable theme browser that previews each Awtarchy theme without changing the live desktop until the user explicitly applies a selection.

## Scope

This milestone replaces the current Quickshell theme picker UI and adds a safe theme-catalog reader. It does not implement true live desktop previewing, nested Hyprland, wallpaper changes, theme editing, theme creation, or a second theme-application path.

The existing `config/hypr/scripts/quickshell_theme_apply.sh` remains the only production path that mutates Hyprland borders, Quickshell colors, Micro, Alacritty, SpeedCrunch, active-theme state, PolicyKit appearance, or Hyprland reload state.

## Existing entrypoints

Preserve these existing user entrypoints:

- `config/hypr/scripts/theme_select.sh` starts Quickshell and calls `qs -c awtarchy ipc call themes toggle`.
- `ThemePicker` keeps the existing `themes` IPC target with `toggle`, `open`, and `close`.
- Quick Settings continues to call `ThemePicker.openForScreen(activeScreen)`.
- Existing Hyprland bindings and the `hyprland_themes.desktop` entry do not need a new command.

## Theme catalog

Create `config/hypr/scripts/quickshell_theme_catalog.sh` as a read-only catalog helper.

The helper must:

- inspect `${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes`;
- include regular theme files and ignore `*.backup*` files;
- sort themes deterministically with `LC_ALL=C` filename ordering;
- never `source`, execute, or shell-evaluate theme files;
- parse only literal quoted assignment lines needed by the browser;
- emit one JSON array to stdout;
- return a non-zero status for an unreadable theme directory or malformed required palette data;
- require no new runtime package beyond Python 3, which Awtarchy already requires for Quickshell runtime helpers.

Each catalog entry has this shape:

```json
{
  "name": "crimson_red",
  "display_name": "Crimson Red",
  "palette": {
    "background": "#1e1e2e",
    "foreground": "#f38ba8",
    "hover": "#352630",
    "focus": "#5a3442",
    "active": "#292330",
    "urgent": "#f38ba8",
    "dark": "#1e1e2e",
    "charging": "#fab387",
    "critical": "#f38ba8",
    "muted": "#9f8994"
  },
  "borders": {
    "active": "f38ba8ff",
    "inactive": "00000000"
  },
  "apps": {
    "micro": "zenburn",
    "alacritty": "inferno.toml",
    "speedcrunch": "crimson_red"
  }
}
```

`display_name` is derived from the filename by replacing `_` and `-` with spaces while preserving existing Unicode characters and title-casing normal words. The underlying filename remains the apply key.

## Picker layout

Replace the existing narrow list window with a centered responsive browser.

Target behavior:

- approximate preferred size: 900x600;
- clamp to the active screen with 10px outer safety margins;
- top header contains `Themes`, a search field, and the active theme name;
- center area is a scrollable `GridView` of visual theme cards;
- footer contains selected-theme details, `Cancel`, and `Apply Theme`;
- the picker remains an above-windows layershell surface with exclusion ignored and no wallpaper interaction.

Each theme card previews the theme using only its catalog data:

- card/background uses the theme background;
- a miniature bar strip uses active/focus/foreground colors;
- two miniature window surfaces show active/hover/focus contrast;
- a compact swatch strip shows foreground, focus, urgent, charging, and muted colors;
- the display name is always readable and visually separated from the preview;
- the currently installed theme has an `Active` marker;
- the currently browsed card has a selection border/state independent of the installed-theme marker.

The mock preview must never modify `Theme.qml`, `theme.json`, Hyprland, app configs, active-theme state, or wallpaper state.

## Selection and input

Opening the picker:

- reads the current active-theme name from `${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy/active-theme`;
- loads the catalog;
- clears search text;
- selects the active theme if it exists in the filtered catalog, otherwise selects the first result;
- focuses the search field.

Search:

- filters case-insensitively against filename and display name;
- preserves deterministic catalog order;
- resets selection to the active theme when visible, otherwise the first result.

Keyboard:

- `Escape`: close without changing the live theme;
- `Left` / `Right`: move one card;
- `Up` / `Down`: move one grid row using the current column count;
- `Home` / `End`: jump to first/last visible theme;
- `Enter` / `Return`: apply the selected theme;
- normal text input continues to edit the search query.

Mouse:

- hovering may highlight a card without applying it;
- one click selects a card;
- the explicit `Apply Theme` button commits the selection;
- no single hover or selection action mutates the live theme.

## Apply behavior

Applying a selected theme calls:

```text
quickshell_theme_apply.sh <theme-filename>
```

The picker closes only after launching the apply request. `ThemePicker` must not duplicate any application logic from the helper.

After a successful apply, reopening the picker must identify the newly active theme through the existing active-theme state file.

## Theme model ownership

Do not turn `Theme.qml` into a catalog or persistent preference owner. `Theme.qml` continues to represent the currently applied live Quickshell palette from `theme.json`.

Catalog/browse state belongs to `ThemePicker.qml` and is ephemeral. Theme definitions remain the files under `config/hypr/themes/`. Active applied-theme identity remains `${XDG_STATE_HOME}/awtarchy/active-theme`.

## Updater and managed history

The new catalog helper and modified `ThemePicker.qml` are Awtarchy-managed configuration and must participate in updater/migration behavior.

- append current hashes to `local/share/awtarchy/quickshell-managed-history.sha256` without removing historical hashes;
- verify the updater installs the new helper and recognizes the changed picker as managed stock;
- preserve all existing Bluetooth/Night Light and bar-customization managed-history entries.

## Validation

Add focused regression coverage for:

- catalog JSON structure and deterministic ordering;
- safe literal parsing without executing theme files;
- backup-file exclusion;
- all shipped themes exposing required preview colors;
- picker using the catalog helper rather than its old `find` filename list;
- visual `GridView` contract and explicit Apply action;
- search plus grid keyboard-navigation contracts;
- active-theme readback;
- no preview-time call to the apply helper;
- existing `themes` IPC API remaining intact;
- existing Quick Settings integration remaining intact;
- managed-history registration and updater migration.

Run the existing Quickshell production-readiness, updater migration, theme migration, Quick Settings, and broad Awtarchy validation suites before handoff.

## Follow-up project

True live desktop previewing remains a separate experiment. That later project may run the actual Awtarchy bar and themed application windows inside a disposable nested Hyprland session using the current wallpaper. It must not be required for this browser to work.