# Bar Icon Customization Design

## Status

Approved design for customizable Awtarchy bar workspace labels and application-launcher icon. This feature is intentionally isolated from the theme-revamp and nested-Hyprland preview work so it can be implemented, tested, and reviewed independently.

## Goal

Allow users to customize how workspaces and the application-launcher entry appear on the Awtarchy bar without editing `Bar.qml` or other source files manually.

The existing Awtarchy workspace labels and launcher glyph remain the default after upgrade.

## Scope

This branch owns:

- workspace presentation presets;
- one optional global custom workspace symbol;
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
- `dots`: `●` for every workspace;
- `diamonds`: `◆` for every workspace;
- `custom-symbol`: one user-supplied label shown for every workspace that does not have an individual override.

The initial/default style is `awtarchy`.

The `●` and `◆` presets use normal Unicode geometric symbols rather than private-use glyphs so they are not dependent on a particular Nerd Font codepoint mapping.

## Global custom workspace symbol

The `custom-symbol` style lets the user define one label that is reused across all workspaces unless a per-workspace override exists.

This is distinct from per-workspace overrides and covers the use case where a user wants every workspace rendered as the same custom dot, diamond, icon, or other glyph.

If persistent state says `custom-symbol` but the saved global custom label is missing or invalid, the resolver falls back to the stock Awtarchy label for each workspace instead of rendering blank buttons.

## Per-workspace overrides

Workspaces 1 through 10 may each have an optional custom label.

A valid per-workspace override takes precedence over the selected global style for that workspace. Clearing the override returns that workspace to the global style.

Overrides are global to the workspace number, not monitor-specific. A workspace can move between monitors, and its visual identity should move with it.

The UI accepts short Unicode/Nerd Font text rather than forcing a single Unicode code point. This permits useful combinations such as a number plus glyph while still keeping the bar label bounded.

Workspace overrides, the global custom workspace symbol, and the custom launcher label all use the same input contract:

- 1 through 8 Unicode code points;
- the value must contain at least one non-whitespace code point;
- embedded line breaks are rejected;
- Unicode C0/C1 control characters (`U+0000` through `U+001F` and `U+007F` through `U+009F`) are rejected;
- normal spaces, narrow spaces, Nerd Font private-use characters, symbols, and multi-codepoint graphemes are otherwise allowed within the 8-code-point limit.

The writer must enforce this contract as well as the QML input surface so invalid state cannot be introduced by calling the persistence script directly.

## Launcher icon model

The application-launcher label becomes user-configurable.

The Quick Settings control provides:

- the current Awtarchy `` glyph as the default and always-available preset;
- a small curated set of additional launcher/menu glyph presets that are verified against Awtarchy's configured font before merge;
- a custom Unicode/Nerd Font text field using the shared 1-to-8-code-point contract;
- a Reset action that restores the stock Awtarchy launcher glyph.

Image files such as PNG or SVG are intentionally out of scope. Supporting image-backed launcher identity would add path persistence, file availability, scaling, updater behavior, and rendering concerns unrelated to the core requirement.

## Persistence

The feature extends the existing Quickshell state object with a `bar_appearance` object.

Conceptual schema:

```json
{
  "bar_appearance": {
    "workspace_style": "awtarchy",
    "workspace_custom_label": "●",
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
- global custom workspace label;
- workspace override lookup;
- resolved launcher icon;
- resolved workspace label or enough primitive state for one shared resolver.

The workspace label resolver has one source of truth used by horizontal and vertical bars.

`quickshell_application_state.sh` exposes explicit appearance write/reset operations rather than a generic arbitrary-JSON mutation interface.

Required operations are:

- set workspace style;
- set global custom workspace label;
- clear global custom workspace label;
- set one workspace override;
- clear one workspace override;
- clear all workspace overrides;
- set launcher icon;
- reset launcher icon;
- reset all bar appearance state to stock defaults.

All workspace IDs accepted by the writer are constrained to 1 through 10.

## Quick Settings UX

Quick Settings receives a `Bar Appearance` section or clearly named subsection within the existing bar-related settings surface.

The workspace controls contain:

- a global style selector for Awtarchy, Numbers, Icons, Dots, Diamonds, and Custom Symbol;
- a global custom-symbol field associated with the Custom Symbol style;
- a workspace override editor for workspaces 1 through 10;
- an individual Reset action for each workspace override;
- a workspace Reset All action that clears the global custom label, clears all workspace overrides, and restores the global workspace style to `awtarchy`.

The launcher controls contain:

- a visible current launcher glyph;
- built-in preset choices;
- a custom glyph/text entry;
- a Reset action that restores ``.

The section also exposes one `Reset Bar Appearance` action that restores all workspace and launcher appearance state to stock Awtarchy defaults while preserving unrelated Quickshell settings.

Appearance changes update the active Quickshell session immediately after persistence, following the existing state-refresh mechanism. The user does not need to restart Quickshell manually.

## Rendering behavior

The current `workspaceIcon(id)` behavior is replaced by a style-aware workspace-label resolver.

Resolution order for each workspace is:

1. valid per-workspace override, when present;
2. selected global workspace style;
3. stock Awtarchy label as the final fallback.

Global style behavior is:

- `awtarchy`: stock number plus icon;
- `numbers`: workspace number only;
- `icons`: stock icon only;
- `dots`: `●`;
- `diamonds`: `◆`;
- `custom-symbol`: valid saved global custom label, otherwise the stock Awtarchy label for that workspace.

Horizontal and vertical bar paths consume the same resolved logical label.

Vertical rendering must not blindly replace separator characters in arbitrary user input. Only stock Awtarchy number-plus-icon labels use the existing stacked number/icon presentation. Numbers, icons, dots, diamonds, the global custom symbol, and per-workspace overrides render as their resolved label without automatic separator rewriting.

Custom labels remain bounded by the existing bar control geometry; they are not converted into unintended multi-line content.

Existing urgent, active, hover, click, wheel, tooltip, and workspace-focus behavior remains unchanged.

The launcher button continues to open the existing launcher and preserves its current hover/click behavior; only its visible label becomes state-driven.

## Interaction with themes

Bar appearance customization is independent user state and must not be overwritten by later theme changes.

A future theme may change color, foreground/background, terminal palette, and other theme-owned visual properties, but it must not replace:

- workspace style;
- global custom workspace label;
- workspace overrides;
- launcher icon.

This allows combinations such as a Catppuccin-style color theme with numbers-only workspaces, one custom symbol on every workspace, or a custom launcher glyph.

## Reset semantics

Reset behavior is explicit:

- workspace row Reset: remove only that workspace override;
- workspace Reset All: remove the global custom workspace label, remove every workspace override, and set workspace style to `awtarchy`;
- launcher Reset: restore the stock `` launcher glyph;
- Reset Bar Appearance: perform the workspace Reset All behavior and launcher Reset together.

Reset does not change bar position, bar size, icon scale, flyout layout, theme colors, or any unrelated setting.

## Error handling

Invalid persistent appearance data fails soft to stock values.

The writer rejects:

- workspace IDs outside 1 through 10;
- workspace style names outside the six supported values;
- empty or whitespace-only custom labels;
- custom labels longer than 8 Unicode code points;
- embedded line breaks;
- C0/C1 control characters.

A failed write must not damage the existing state file. Existing temporary-file and file-lock behavior remains mandatory.

## Tests

Automated coverage verifies at minimum:

- absent appearance state preserves current Awtarchy labels and `` launcher glyph;
- each built-in workspace style resolves correctly for workspaces 1 through 10;
- `dots` resolves to `●` and `diamonds` resolves to `◆`;
- `custom-symbol` uses the global custom label;
- `custom-symbol` with missing/invalid global label falls back to the stock Awtarchy labels;
- per-workspace override wins over every global style including `custom-symbol`;
- clearing an override returns to the global style;
- launcher customization and reset work;
- individual workspace reset works;
- workspace Reset All restores stock workspace presentation and clears global/per-workspace custom values;
- Reset Bar Appearance restores both workspace and launcher defaults without touching unrelated state;
- appearance writes preserve unrelated Quickshell state;
- malformed appearance JSON fields fail soft;
- writer rejects invalid workspace IDs, styles, whitespace-only values, control characters, line breaks, and labels above 8 Unicode code points;
- horizontal and vertical rendering use the shared resolved state rather than separate hardcoded mappings;
- only stock Awtarchy number-plus-icon labels receive the vertical stacked transformation;
- existing bar position, bar sizing, icon scaling, workspace focus, urgent/active state, click behavior, wheel behavior, and launcher-open behavior remain intact.

## Live validation

Before merge, test in a real Hyprland/Quickshell session:

1. Confirm a fresh/default state looks the same as current Awtarchy.
2. Cycle through Awtarchy, Numbers, Icons, Dots, Diamonds, and Custom Symbol on a horizontal bar.
3. Repeat on a vertical bar.
4. Test a single global custom workspace symbol.
5. Set distinct overrides for several workspaces and move at least one workspace to another monitor.
6. Confirm its override follows the workspace number rather than the monitor.
7. Set and reset a custom launcher glyph.
8. Restart Quickshell and confirm persistence.
9. Log out/in and confirm persistence.
10. Exercise individual Reset, workspace Reset All, launcher Reset, and Reset Bar Appearance.
11. Confirm existing bar-size/icon-scale controls still work before and after appearance changes.

## Branch isolation

Implementation belongs only on `feature/bar-icon-customization`.

The separate `feature/theme-revamp` branch may consume theme-independent appearance behavior after this feature is merged or otherwise deliberately integrated, but it must not absorb the implementation while this branch is under test.

The separate `experiment/live-theme-preview` branch remains disposable and has no dependency on bar-icon customization unless that dependency is explicitly introduced later.
