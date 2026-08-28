# Bar Icon Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent workspace/launcher icon customization to the existing Bar Appearance UI, including the approved Unicode preset families and compact single-row vertical workspace labels.

**Architecture:** Extend the existing `quickshell-state.json` through `quickshell_application_state.sh`, normalize/read it through `BarState.qml`, render it through `Bar.qml`, and expose controls through the existing `BarSettingsSection.qml`. Keep identity state global while preserving the existing monitor-targeted geometry/scale controls.

**Tech Stack:** Bash, jq, QML/QtQuick, Quickshell, Hyprland, shell regression tests.

**Spec:** `docs/superpowers/specs/2026-08-28-bar-icon-customization-design.md`

## Global Constraints

- Work only on `feature/bar-icon-customization`.
- Preserve the existing horizontal Awtarchy number+icon appearance by default.
- Vertical stock number+icon labels must be one row, e.g. `1󰞷`, never stacked.
- Workspace IDs are 1 through 10 only.
- Custom labels are 1 through 8 Unicode code points, contain at least one non-whitespace code point, contain no line breaks, and contain no C0/C1 control characters.
- Workspace/launcher identity state is global, not per-monitor.
- Theme changes must not overwrite workspace or launcher identity state.
- Existing monitor-targeted Bar Appearance Reset must keep its existing geometry/scale scope.
- State writes must preserve unrelated JSON and keep the existing lock + temporary-file + atomic-move behavior.

---

### Task 1: Add persistence commands and regression tests

**Files:**
- Create: `tests/test-bar-icon-customization.sh`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`

**Interfaces:**
- Consumes: existing `$XDG_CACHE_HOME/awtarchy/quickshell-state.json` and locked writer flow.
- Produces commands:
  - `set-workspace-style <style>`
  - `set-workspace-custom-label <label>`
  - `clear-workspace-custom-label`
  - `set-workspace-override <1-10> <label>`
  - `clear-workspace-override <1-10>`
  - `clear-workspace-overrides`
  - `set-launcher-icon <label>`
  - `reset-launcher-icon`
  - `reset-workspace-icons`
  - `reset-bar-icons`

- [ ] **Step 1: Write the failing persistence test**

Create `tests/test-bar-icon-customization.sh` with a temporary `XDG_CACHE_HOME`, seed unrelated state, and assert all commands above preserve unrelated keys. Include invalid cases for workspace `0`, `11`, unknown style, blank/whitespace-only labels, embedded newline, C0 control input, and a 9-code-point label. Assert rejected operations leave the state file byte-identical to a saved pre-command copy.

The test must also grep the writer usage/case dispatch for all public commands so command names cannot silently drift.

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bash tests/test-bar-icon-customization.sh
```

Expected: failure because the new persistence commands do not exist.

- [ ] **Step 3: Add validation and state mutations**

Add to `quickshell_application_state.sh`:

```bash
WORKSPACE_STYLES_JSON='["awtarchy","numbers","icons","filled-dot","phases","filled-diamond","center-diamond","filled-square","small-square","filled-triangle","spark","minimal-bar","custom-symbol"]'
```

Add one shared label validator that uses Python 3 for Unicode-code-point/control validation rather than byte-counting Bash tools. It must return failure without modifying state when the value is invalid.

Normalize `.bar_appearance` and `.bar_appearance.workspace_overrides` to objects before mutation. `reset-workspace-icons` removes workspace style/custom-label/overrides or restores them to their stock-equivalent absence. `reset-launcher-icon` removes the launcher override. `reset-bar-icons` removes the full `bar_appearance` object when no other identity fields remain.

- [ ] **Step 4: Run persistence validation**

Run:

```bash
bash -n config/hypr/scripts/quickshell_application_state.sh
bash tests/test-bar-icon-customization.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/hypr/scripts/quickshell_application_state.sh tests/test-bar-icon-customization.sh
git commit -m "Add bar icon customization state"
```

---

### Task 2: Add the normalized BarState identity API

**Files:**
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `tests/test-bar-icon-customization.sh`

**Interfaces:**
- Consumes: `.bar_appearance` written by Task 1.
- Produces:
  - `workspaceStyle()`
  - `workspaceCustomLabel()`
  - `workspaceOverrideFor(id)`
  - `workspaceLabelFor(id)`
  - `workspaceVerticalLabelFor(id)`
  - `launcherIcon()`
  - `workspaceStylePresets`
  - `launcherIconPresets`

- [ ] **Step 1: Extend the failing test with BarState contracts**

Assert `BarState.qml` contains the approved style keys and exact representative Unicode symbols:

```text
● ◐ ◑ ◒ ◓ ◔ ◕ ○ ◉ ◎ ◆ ◈ ■ ▪ ▲ ✦ ━
```

The `phases` preset is one sequential workspace style: workspaces 1–10 map to `◐ ◑ ◒ ◓ ◔ ◕ ○ ● ◉ ◎`. The circle variants used at positions 7–10 are part of that sequence, not separate global presets.

Assert stock launcher fallback remains ``.

- [ ] **Step 2: Run the test and verify it fails**

```bash
bash tests/test-bar-icon-customization.sh
```

Expected: failure because BarState does not expose the identity API.

- [ ] **Step 3: Implement normalized state helpers**

Extend `emptyData()` with `bar_appearance: {}` and normalize malformed `.bar_appearance` and `.bar_appearance.workspace_overrides` inside `data()`.

Keep one stock icon map and one preset catalog in `BarState.qml`. `workspaceLabelFor(id)` resolves in this order:

1. valid per-workspace override;
2. selected global style;
3. stock Awtarchy horizontal label.

`workspaceVerticalLabelFor(id)` uses the same override/global resolution, except stock Awtarchy fallback/style returns compact number+icon with no separator, e.g. `1󰞷`.

`launcherIcon()` returns a valid saved launcher label or ``.

- [ ] **Step 4: Run focused tests**

```bash
bash tests/test-bar-icon-customization.sh
```

Expected: PASS for state/resolver static contracts.

- [ ] **Step 5: Commit**

```bash
git add config/quickshell/awtarchy/BarState.qml tests/test-bar-icon-customization.sh
git commit -m "Resolve customizable workspace labels"
```

---

### Task 3: Render identity state in the bar and remove vertical stacking

**Files:**
- Modify: `config/quickshell/awtarchy/Bar.qml`
- Modify: `tests/test-bar-icon-customization.sh`

**Interfaces:**
- Consumes: `BarState.workspaceLabelFor(id)`, `BarState.workspaceVerticalLabelFor(id)`, and `BarState.launcherIcon()`.
- Produces: identical workspace interaction behavior with state-driven labels.

- [ ] **Step 1: Add failing rendering assertions**

Assert `Bar.qml` no longer contains the hardcoded `workspaceIcon(id)` map and no longer performs the narrow-space-to-newline transformation. Assert horizontal workspace text uses `BarState.workspaceLabelFor(...)`, vertical workspace text uses `BarState.workspaceVerticalLabelFor(...)`, and both launcher buttons/orientations use `BarState.launcherIcon()`.

- [ ] **Step 2: Run the test and verify it fails**

```bash
bash tests/test-bar-icon-customization.sh
```

Expected: failure on current hardcoded rendering.

- [ ] **Step 3: Replace only label ownership**

Remove `workspaceIcon(id)` from `Bar.qml`. Do not alter workspace focus, urgent state, click, wheel, hover, tooltip, fullscreen visibility, or geometry behavior.

Horizontal delegates bind their label to `BarState.workspaceLabelFor(id)`. Vertical delegates bind to `BarState.workspaceVerticalLabelFor(id)` without `.replace(" ", "\n")` or any equivalent newline rewrite.

Replace the hardcoded launcher `` label in both orientations with `BarState.launcherIcon()`.

- [ ] **Step 4: Run focused bar tests**

```bash
bash tests/test-bar-icon-customization.sh
bash tests/test-bar-control-actions.sh
bash tests/test-bar-wheel-input.sh
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add config/quickshell/awtarchy/Bar.qml tests/test-bar-icon-customization.sh
git commit -m "Render customizable bar icons"
```

---

### Task 4: Add visual controls to the existing Bar Appearance section

**Files:**
- Modify: `config/quickshell/awtarchy/BarSettingsSection.qml`
- Modify: `tests/test-bar-icon-customization.sh`

**Interfaces:**
- Consumes: BarState preset catalogs and Task 1 writer commands.
- Produces: visual preset selection, global custom label, per-workspace overrides, launcher presets/custom label, and explicit identity resets.

- [ ] **Step 1: Add failing UI contract assertions**

Assert `BarSettingsSection.qml` references `BarState.workspaceStylePresets`, `BarState.launcherIconPresets`, and the Task 1 writer commands. Assert the existing `resetAppearance()` geometry function remains present and does not call `reset-bar-icons`.

- [ ] **Step 2: Run the test and verify it fails**

```bash
bash tests/test-bar-icon-customization.sh
```

Expected: failure because the controls are not implemented.

- [ ] **Step 3: Implement identity command queueing**

Reuse the component's existing serialized `Process` pattern. Add a global identity command path that calls `quickshell_application_state.sh` directly and refreshes `BarState` on completion. Do not route global identity through the monitor-targeted `quickshell.sh` geometry commands.

- [ ] **Step 4: Implement the visual preset UI**

Add a compact visual selector under the existing Bar Appearance header. Each preset button shows its sample glyph and has a tooltip/text label. The selector must be scrollable or wrap cleanly within the existing panel width rather than forcing Quick Settings wider.

Custom Symbol exposes a bounded `TextInput` and Apply action. Per-workspace overrides expose workspace 1-10 rows with current resolved preview, editable label, Apply, and Reset. Launcher identity exposes a preset row, custom input, launcher Reset, plus `Reset Workspace Icons` and `Reset Bar Icons` actions.

Existing display target, display scale, thickness, icon scale, text scale, Themes, and monitor-targeted Reset behavior remain functional.

- [ ] **Step 5: Run focused UI contracts**

```bash
bash tests/test-bar-icon-customization.sh
bash tests/test-quick-settings-layout.sh
bash tests/test-flyout-edge-layout.sh
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add config/quickshell/awtarchy/BarSettingsSection.qml tests/test-bar-icon-customization.sh
git commit -m "Add bar icon appearance controls"
```

---

### Task 5: Add updater history and CI coverage, then run the strongest available validation

**Files:**
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify: `.github/workflows/validate-awtarchy.yml`
- Modify: `tests/test-bar-icon-customization.sh`

**Interfaces:**
- Consumes: final changed managed Quickshell files.
- Produces: updater recognition and permanent CI execution.

- [ ] **Step 1: Extend the test with managed-history checks**

Require current hashes for:

```text
.config/hypr/scripts/quickshell_application_state.sh
.config/quickshell/awtarchy/BarState.qml
.config/quickshell/awtarchy/Bar.qml
.config/quickshell/awtarchy/BarSettingsSection.qml
```

- [ ] **Step 2: Add the new test to CI**

Add `bash -n tests/test-bar-icon-customization.sh` to Bash syntax validation, add it to ShellCheck, and run `bash tests/test-bar-icon-customization.sh` in the integration-test step.

- [ ] **Step 3: Refresh only the managed-history entries required by this feature**

Append the current SHA-256 plus home-relative path for each changed managed file following the existing history format. Do not delete historical hashes.

- [ ] **Step 4: Run focused and broad validation**

Run:

```bash
bash -n config/hypr/scripts/quickshell_application_state.sh
bash -n tests/test-bar-icon-customization.sh
shellcheck config/hypr/scripts/quickshell_application_state.sh tests/test-bar-icon-customization.sh
bash tests/test-bar-icon-customization.sh
bash tests/test-bar-control-actions.sh
bash tests/test-bar-wheel-input.sh
bash tests/test-quick-settings-layout.sh
bash tests/test-flyout-edge-layout.sh
bash tests/test-quickshell-production-readiness.sh
bash tests/test-quickshell-updater-migration.sh
git diff --check
```

Expected: all commands PASS.

- [ ] **Step 5: Live-session validation before merge**

Use the exact checklist in the design spec. Automated/static validation is not evidence that Quickshell renders every glyph correctly in a real session, so merge readiness remains blocked until the real-session checks are completed.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/validate-awtarchy.yml local/share/awtarchy/quickshell-managed-history.sha256 tests/test-bar-icon-customization.sh
git commit -m "Validate bar icon customization"
```
