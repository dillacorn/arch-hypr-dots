# Bar Icon Customization Design

## Status

Approved design for customizable Awtarchy bar workspace labels and application-launcher icon. This feature is intentionally isolated from the theme-revamp and nested-Hyprland preview work so it can be implemented, tested, and reviewed independently.

## Goal

Allow users to customize how workspaces and the application-launcher entry appear on the Awtarchy bar without editing `Bar.qml` or other source files manually.

The existing Awtarchy workspace labels and launcher glyph remain the default after upgrade.

## Scope

This branch owns:

- workspace presentation presets;
- optional per-workspace label overrides for workspaces 1 through 10;
- application-launcher glyph customization;
- persistence and reset behavior for those choices;
- Quick Settings controls for the feature;
- horizontal and vertical bar rendering of the configured labels.

This branch does not own:

- theme colors;
- named theme presets;
- wallpaper behavior;
- nested Hyprland theme previews;
- image-file launcher icons;
- per-monitor workspace identities.

## Current implementation

`config/quickshell/awtarchy/Bar.qml` currently owns the visible defaults directly:

- `workspaceIcon(id)` maps workspaces 1 through 10 to the current number-plus-icon labels;
- the application launcher uses the hardcoded `` label;
- horizontal workspaces render the returned label directly;
- vertical workspaces currently transform the narrow no-break-space separator in the stock number-plus-icon label into a newline.

Persistent Quickshell state already lives in `$XDG_CACHE_HOME/awtarchy/quickshell-state.json` or the `~/.cache` fallback. `BarState.qml` is the existing reader/state owner and `config/hypr/scripts/quickshell_application_state.sh` is the existing serialized writer.

This feature extends those existing owners rather than introducing another state file or competing source of truth.

## Workspace presentation model

The user chooses one global workspace style. Supported styles are:

- `awtarchy`: current Awtarchy number plus icon presentation;
- `numbers`: workspace numbers only;
- `icons`: current Awtarchy icons without workspace numbers;
- `dots`: a dot glyph for each workspace;
- `diamonds`: a diamond glyph for each workspace;
- `custom`: use configured workspace overrides where present and otherwise fall back to the stock Awtarchy label for that workspace.

The initial/default style is `awtarchy`.

The exact built-in glyphs for `dots` and `diamonds` must be chosen from glyphs already renderable by Awtarchy's configured Nerd Font stack and must be tested on both horizontal and vertical bars before merge.

## Per-workspace overrides

Workspaces 1 through 10 may each have an optional custom label.

A per-workspace override takes precedence over the selected global style for that workspace. Clearing the override returns that workspace to the global style.

Overrides are global to the workspace number, not monitor-specific. A workspace can move between monitors, and its visual identity should move with it.

The UI accepts short Unicode/Nerd Font text rather than forcing a single Unicode code point. This avoids breaking valid multi-codepoint graphemes or Nerd Font sequences while still keeping the bar label bounded.

The implementation must enforce a conservative maximum input length suitable for a bar label and reject embedded newlines/control characters. The exact maximum may be chosen during implementation based on the existing bar geometry, but it must be covered by tests and must not permit arbitrary multi-line content from the input field.

## Launcher icon model

The application-launcher label becomes user-configurable.

The Quick Settings control provides:

- the current Awtarchy `` glyph as the default;
- a small set of built-in glyph presets suitable for an application/menu launcher;
- a custom Unicode/Nerd Font text field;
- a Reset action that restores the stock Awtarchy launcher glyph.

Image files such as PNG or SVG are intentionally out of scope. Supporting image-backed launcher identity would add path persistence, file availability, scaling, updater behavior, and rendering concerns unrelated to the core requirement.

## Persistence

The feature extends the existing Quickshell state object with a `bar_appearance` object.

Conceptual schema:

```json
{
  "bar_appearance": {
    "workspace_style": "awtarchy",
    "launcher_icon": "",
    "workspace_overrides": {
      "1": "󰞷",
      "4": ""
    }
  }
}
```

Implementation requirements:

- missing `bar_appearance` state behaves exactly like current Awtarchy;
- malformed or wrong-type fields fall back independently rather than invalidating the entire Quickshell state;
- valid unrelated state must survive all appearance writes;
- state writes continue to use the existing lock-and-temporary-file pattern in `quickshell_application_state.sh`;
- `BarState.qml` remains the single QML reader/state owner;
- no direct ad-hoc JSON writes are added to `Bar.qml` or Quick Settings QML.

## State API

`BarState.qml` should expose read helpers whose consumers do not need to understand the JSON schema directly.

Expected responsibilities include equivalents of:

- selected workspace style;
- workspace override lookup;
- resolved launcher icon;
- resolved workspace label or enough primitive state for one shared resolver.

The workspace label resolver should have one source of truth used by horizontal and vertical bars.

`quickshell_application_state.sh` should expose explicit appearance write/reset operations rather than a generic arbitrary-JSON mutation interface.

Expected operations include:

- set workspace style;
- set one workspace override;
- clear one workspace override;
- clear all workspace overrides;
- set launcher icon;
- reset launcher icon;
- reset all bar appearance state to stock defaults.

All workspace IDs accepted by the writer must be constrained to 1 through 10.

## Quick Settings UX

Quick Settings receives a `Bar Appearance` section or equivalent clearly named subsection within the existing bar-related settings surface.

The workspace controls contain:

- a global style selector for Awtarchy, Numbers, Icons, Dots, Diamonds, and Custom;
- a workspace override editor for workspaces 1 through 10;
- an individual Reset action for each workspace override;
- a Reset All action that clears all workspace overrides and restores the global workspace style to `awtarchy`.

The launcher controls contain:

- a visible current launcher glyph;
- built-in preset choices;
- a custom glyph/text entry;
- a Reset action that restores ``.

Appearance changes should update the active Quickshell session immediately after persistence, following the existing state-refresh mechanism. The user should not need to restart Quickshell manually.

## Rendering behavior

The current `workspaceIcon(id)` behavior is replaced by a style-aware workspace-label resolver.

Resolution order for each workspace is:

1. valid per-workspace override, when present;
2. selected global workspace style;
3. stock Awtarchy label as the final fallback.

For the `custom` global style, a workspace without an override resolves to its stock Awtarchy label. This prevents blank or unusable workspace buttons when only some workspaces are customized.

Horizontal and vertical bar paths consume the same resolved logical label.

Vertical rendering must not blindly replace separator characters in arbitrary user input. Stock Awtarchy number-plus-icon labels may retain their existing stacked presentation, while other presets/custom labels should render according to explicit style-aware rules. Custom labels must remain bounded within the vertical bar control rather than being silently rewritten into unintended multi-line content.

Existing urgent, active, hover, click, wheel, tooltip, and workspace-focus behavior remains unchanged.

The launcher button continues to open the existing launcher and preserves its current hover/click behavior; only its visible label becomes state-driven.

## Interaction with themes

Bar appearance customization is independent user state and must not be overwritten by later theme changes.

A future theme may change color, foreground/background, terminal palette, and other theme-owned visual properties, but it must not replace:

- workspace style;
- workspace overrides;
- launcher icon.

This allows combinations such as a Catppuccin-style color theme with numbers-only workspaces or a custom launcher glyph.

## Reset semantics

Reset behavior must be explicit and unsurprising:

- workspace row Reset: remove only that workspace override;
- workspace Reset All: remove every workspace override and set workspace style to `awtarchy`;
- launcher Reset: restore the stock `` launcher glyph;
- full Bar Appearance reset, if exposed: restore all workspace and launcher appearance values to stock Awtarchy defaults while preserving unrelated Quickshell state.

Reset does not change bar position, bar size, icon scale, flyout layout, theme colors, or any unrelated setting.

## Error handling

Invalid persistent appearance data must fail soft to stock values.

The writer must reject:

- workspace IDs outside 1 through 10;
- invalid workspace style names;
- empty values where the operation requires a concrete custom label;
- embedded newline/control-character content that could break layout or state handling;
- values exceeding the selected safe label-length limit.

A failed write must not damage the existing state file. Existing temporary-file and file-lock behavior remains mandatory.

## Tests

Automated coverage should verify at minimum:

- absent appearance state preserves current Awtarchy labels and `` launcher glyph;
- each built-in workspace style resolves correctly for workspaces 1 through 10;
- per-workspace override wins over every global style;
- clearing an override returns to the global style;
- `custom` style without an override falls back to the stock Awtarchy label;
- launcher customization and reset work;
- individual workspace reset works;
- Reset All restores stock workspace presentation;
- appearance writes preserve unrelated Quickshell state;
- malformed appearance JSON fields fail soft;
- writer rejects invalid workspace IDs, styles, control characters, and oversized labels;
- horizontal and vertical rendering use the shared resolved state rather than separate hardcoded mappings;
- existing bar position, bar sizing, icon scaling, workspace focus, urgent/active state, click behavior, wheel behavior, and launcher-open behavior remain intact.

## Live validation

Before merge, test in a real Hyprland/Quickshell session:

1. Confirm a fresh/default state looks the same as current Awtarchy.
2. Cycle through every workspace preset on a horizontal bar.
3. Repeat on a vertical bar.
4. Set distinct overrides for several workspaces and move at least one workspace to another monitor.
5. Confirm its override follows the workspace number rather than the monitor.
6. Set and reset a custom launcher glyph.
7. Restart Quickshell and confirm persistence.
8. Log out/in and confirm persistence.
9. Use per-workspace Reset, workspace Reset All, and launcher Reset.
10. Confirm existing bar-size/icon-scale controls still work before and after appearance changes.

## Branch isolation

Implementation belongs only on `feature/bar-icon-customization`.

The separate `feature/theme-revamp` branch may consume theme-independent appearance behavior after this feature is merged or otherwise deliberately integrated, but it must not absorb the implementation while this branch is under test.

The separate `experiment/live-theme-preview` branch remains disposable and has no dependency on bar-icon customization unless that dependency is explicitly introduced later.
