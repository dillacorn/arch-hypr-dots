# Bar Icon Customization Design

## Status

Approved design for customizable Awtarchy bar workspace labels and application-launcher icon. This feature is intentionally isolated from the theme-revamp and nested-Hyprland preview work so it can be implemented, tested, and reviewed independently.

## Goal

Allow users to customize how workspaces and the application-launcher entry appear on the Awtarchy bar without editing `Bar.qml` or other source files manually.

The existing Awtarchy workspace labels and launcher glyph remain the default after upgrade, except that vertical bars intentionally stop stacking the workspace number above its icon. Stock number-plus-icon labels render on one row in vertical mode, for example `1󰞷` rather than `1` above `󰞷`.

## Scope

This branch owns:

- workspace presentation presets;
- one optional global custom workspace symbol;
- optional per-workspace label overrides for workspaces 1 through 10;
- application-launcher glyph customization;
- persistence and reset behavior for those choices;
- Quick Settings / Bar Appearance controls for the feature;
- horizontal and vertical bar rendering of the configured labels;
- removal of the existing vertical number/icon stacking behavior.

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

`config/quickshell/awtarchy/BarSettingsSection.qml` already owns the Bar Appearance controls surfaced through Quick Settings, including thickness, icon/text scale, display scale, theme access, and reset behavior. Workspace/launcher identity controls belong in this component rather than creating a second competing Bar Appearance surface.

Persistent Quickshell state already lives in `$XDG_CACHE_HOME/awtarchy/quickshell-state.json` or the `~/.cache` fallback. `BarState.qml` is the existing reader/state owner and `config/hypr/scripts/quickshell_application_state.sh` is the existing serialized writer.

This feature extends those existing owners rather than introducing another state file or competing source of truth.

## Workspace presentation model

The user chooses one global workspace style. The initial/default style is `awtarchy`.

Built-in styles are:

| State key | Quick Settings label | Workspace appearance |
| --- | --- | --- |
| `awtarchy` | Awtarchy | current number plus icon mapping |
| `numbers` | Numbers | `1 2 3 …` |
| `icons` | Icons | current Awtarchy icons without numbers |
| `filled-dot` | Filled Dot | `●` |
| `phases` | Phases | workspace 1–10 use `◐ ◑ ◒ ◓ ◔ ◕ ○ ● ◉ ◎` |
| `filled-diamond` | Filled Diamond | `◆` |
| `center-diamond` | Center Diamond | `◈` |
| `filled-square` | Filled Square | `■` |
| `small-square` | Small Square | `▪` |
| `filled-triangle` | Filled Triangle | `▲` |
| `spark` | Spark | `✦` |
| `minimal-bar` | Minimal Bar | `━` |
| `custom-symbol` | Custom | one user-supplied label for every workspace |

The `phases` preset is sequential rather than a repeated-symbol style. Workspaces 1 through 10 map exactly to `◐`, `◑`, `◒`, `◓`, `◔`, `◕`, `○`, `●`, `◉`, and `◎` respectively.

The geometric presets use normal Unicode symbols rather than Nerd Font private-use mappings. This makes the built-in styles stable even if Nerd Font icon mappings change. The custom fields remain available for users who explicitly want Nerd Font/private-use glyphs.

The preset selector is visual. Each preset exposes its representative glyph or sample directly rather than requiring the user to infer the style from a text-only dropdown.

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

The Bar Appearance control provides:

- the current Awtarchy `` glyph as the default and always-available preset;
- curated launcher presets for Awtarchy ``, Menu `☰`, Tux/Linux ``, Arch ``, Diamond `◆`, and Circle `●`;
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

- missing `bar_appearance` state behaves like stock Awtarchy apart from the intentional vertical inline-label change;
- malformed or wrong-type fields fall back independently rather than invalidating the entire Quickshell state;
- valid unrelated state must survive all appearance writes;
- state writes continue to use the existing lock-and-temporary-file pattern in `quickshell_application_state.sh`;
- `BarState.qml` remains the single QML reader/state owner;
- no direct ad-hoc JSON writes are added to `Bar.qml`, `BarSettingsSection.qml`, or `QuickSettings.qml`.

## State API

`BarState.qml` exposes normalized read helpers whose consumers do not need to understand the JSON schema directly.

Required responsibilities include equivalents of:

- `workspaceStyle()`;
- `workspaceCustomLabel()`;
- `workspaceOverrideFor(id)`;
- `workspaceLabelFor(id)`;
- `launcherIcon()`;
- helper data for visual preset presentation where keeping the preset catalog in the state owner avoids duplication.

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
- reset workspace appearance;
- reset all bar identity appearance state to stock defaults.

All workspace IDs accepted by the writer are constrained to 1 through 10.

## Bar Appearance UX

The existing `BarSettingsSection.qml` remains the Bar Appearance surface.

Its existing monitor-targeted geometry controls remain monitor-targeted. Workspace identity and launcher identity are global preferences, because workspace numbers move between monitors and the application launcher should not unexpectedly change identity when focus moves to another display.

The new workspace controls contain:

- a visual preset grid containing every built-in workspace style;
- a global custom-symbol field associated with the Custom style;
- a workspace override editor for workspaces 1 through 10;
- an individual Reset action for each workspace override;
- a workspace Reset All action that clears the global custom label, clears all workspace overrides, and restores the global workspace style to `awtarchy`.

The launcher controls contain:

- a visible current launcher glyph;
- built-in preset choices;
- a custom glyph/text entry;
- a Reset action that restores ``.

The existing Bar Appearance Reset must not silently gain destructive global identity behavior if it is operating on a monitor target. Global identity reset is exposed separately and clearly as `Reset Workspace Icons`, `Reset Launcher Icon`, or a combined `Reset Bar Icons` action.

Appearance changes update the active Quickshell session immediately after persistence, following the existing `BarState.refresh()` state-refresh mechanism. The user does not need to restart Quickshell manually.

## Rendering behavior

The current hardcoded workspace label path becomes a style-aware workspace-label resolver.

Resolution order for each workspace is:

1. valid per-workspace override, when present;
2. selected global workspace style;
3. stock Awtarchy label as the final fallback.

Global style behavior is defined by the preset table above. `phases` maps workspace IDs 1 through 10 to `◐ ◑ ◒ ◓ ◔ ◕ ○ ● ◉ ◎`. `custom-symbol` uses the valid saved global custom label; otherwise it falls back to the stock Awtarchy label for that workspace.

### Horizontal bar

Stock Awtarchy labels preserve the current readable number/icon spacing used by the horizontal bar. All other presets and custom labels render as their resolved label without transformation.

### Vertical bar

Workspace labels never stack number and icon onto separate lines.

For the stock Awtarchy style, the vertical bar renders number plus icon as a compact single-row label with no forced separator, for example:

- workspace 1: `1󰞷`;
- workspace 2: `2`;
- workspace 3: `3`.

The previous separator-to-newline transformation is removed.

Numbers, icons, the phases sequence, geometric presets, the global custom symbol, and per-workspace overrides also render on one row. Custom input is not rewritten to introduce line breaks.

Custom labels remain bounded by the existing bar control geometry; they are not converted into unintended multi-line content.

Existing urgent, active, hover, click, wheel, tooltip, and workspace-focus behavior remains unchanged.

The launcher button continues to open the existing launcher and preserves its current hover/click behavior; only its visible label becomes state-driven.

## Interaction with themes

Bar identity customization is independent user state and must not be overwritten by later theme changes.

A future theme may change color, foreground/background, terminal palette, and other theme-owned visual properties, but it must not replace:

- workspace style;
- global custom workspace label;
- workspace overrides;
- launcher icon.

This allows combinations such as a Catppuccin-style color theme with numbers-only workspaces, `◐` workspaces, or a custom launcher glyph.

## Reset semantics

Reset behavior is explicit:

- workspace row Reset: remove only that workspace override;
- workspace Reset All: remove the global custom workspace label, remove every workspace override, and set workspace style to `awtarchy`;
- launcher Reset: restore the stock `` launcher glyph;
- Reset Bar Icons: perform workspace Reset All and launcher Reset together;
- existing monitor-targeted bar geometry Reset: continue resetting only the geometry/scale values it already owns.

Reset does not change wallpaper, theme colors, flyout layout, bar position, or unrelated state unless the existing geometry Reset is explicitly invoked for those existing bar geometry values.

## Error handling

Invalid persistent appearance data fails soft to stock values.

The writer rejects:

- workspace IDs outside 1 through 10;
- workspace style names outside the supported preset state keys;
- empty or whitespace-only custom labels;
- custom labels longer than 8 Unicode code points;
- embedded line breaks;
- C0/C1 control characters.

A failed write must not damage the existing state file. Existing temporary-file and file-lock behavior remains mandatory.

## Tests

Automated coverage verifies at minimum:

- absent appearance state preserves stock horizontal Awtarchy labels and `` launcher glyph;
- absent appearance state uses the new compact single-row stock Awtarchy label on vertical bars;
- every retained built-in workspace preset resolves correctly for workspaces 1 through 10;
- `phases` resolves workspaces 1 through 10 exactly to `◐ ◑ ◒ ◓ ◔ ◕ ○ ● ◉ ◎`;
- removed exploratory workspace styles are rejected by the writer and are absent from the preset catalog;
- filled-dot, diamond, square, triangle, spark, and minimal-bar presets resolve to their declared symbols;
- `custom-symbol` uses the global custom label;
- `custom-symbol` with missing/invalid global label falls back to stock Awtarchy labels;
- per-workspace override wins over every global style including `custom-symbol`;
- clearing an override returns to the global style;
- launcher customization and reset work;
- individual workspace reset works;
- workspace Reset All restores stock workspace presentation and clears global/per-workspace custom values;
- Reset Bar Icons restores both workspace and launcher identity defaults without touching unrelated state;
- appearance writes preserve unrelated Quickshell state;
- malformed appearance JSON fields fail soft;
- writer rejects invalid workspace IDs, styles, whitespace-only values, control characters, line breaks, and labels above 8 Unicode code points;
- horizontal and vertical rendering use the shared resolved state rather than separate hardcoded mappings;
- vertical workspace labels contain no newline-producing stock transformation;
- stock vertical number-plus-icon output is inline, e.g. `1󰞷`, not stacked;
- existing bar position, bar sizing, icon scaling, text scaling, display scaling, workspace focus, urgent/active state, click behavior, wheel behavior, launcher-open behavior, and theme access remain intact.

## Live validation

Before merge, test in a real Hyprland/Quickshell session:

1. Confirm a fresh/default horizontal bar looks the same as current Awtarchy.
2. Confirm a fresh/default vertical bar renders stock workspace number+icon labels inline on one row.
3. Cycle through every retained built-in workspace preset on a horizontal bar.
4. Repeat on a vertical bar and confirm every workspace label remains single-row.
5. Select Phases and confirm workspaces 1–10 display `◐ ◑ ◒ ◓ ◔ ◕ ○ ● ◉ ◎` in that order.
6. Test a single global custom workspace symbol.
7. Set distinct overrides for several workspaces and move at least one workspace to another monitor.
8. Confirm its override follows the workspace number rather than the monitor.
9. Test the Awtarchy, Menu, Tux/Linux, Arch, Diamond, and Circle launcher presets plus a custom launcher glyph.
10. Restart Quickshell and confirm persistence.
11. Log out/in and confirm persistence.
12. Exercise individual Reset, workspace Reset All, launcher Reset, and Reset Bar Icons.
13. Confirm existing bar thickness/icon-scale/text-scale/display-scale controls still work before and after identity changes.
14. Confirm the existing monitor-targeted Reset still affects only its existing geometry/scale scope.

## Branch isolation

Implementation belongs only on `feature/bar-icon-customization`.

The separate `feature/theme-revamp` branch may consume theme-independent appearance behavior after this feature is merged or otherwise deliberately integrated, but it must not absorb the implementation while this branch is under test.

The separate `experiment/live-theme-preview` branch remains disposable and has no dependency on bar-icon customization unless that dependency is explicitly introduced later.
