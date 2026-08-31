# Floating Spawn Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a keyboard-toggleable global floating-spawn mode with a persistent clickable bar indicator and one shared Quickshell state owner.

**Architecture:** Keep `quickshell_floating_windows.sh` as the only `hyprland.lua` writer. Add a runtime state publication contract and a `FloatingWindowsState.qml` singleton so Quick Settings and all bar instances consume one state source without duplicate polling.

**Tech Stack:** Bash, Hyprland Lua config, QML/Quickshell, GitHub Actions shell validation.

**Spec:** `docs/superpowers/plans/2026-08-30-floating-spawn-mode-design.md`

## Global Constraints

- `SUPER+ALT+F` toggles global floating-spawn mode; `SUPER+F` remains focused-window float/tile.
- Keyboard toggles produce a short Awtarchy notification.
- `Floating` is visible on every active bar only while global floating-spawn mode is enabled; clicking it disables the mode.
- Existing game tiling exceptions and `hyprland.lua` marker/rule behavior remain unchanged.
- No per-monitor status polling.
- Managed Quickshell history hashes must be updated for changed/added managed QML.

---

### Task 1: Define the regression contract

**Files:**
- Create: `tests/test-floating-windows-global-mode.sh`

**Interfaces:**
- Consumes: existing `quickshell_floating_windows.sh`, `hyprland.lua`, `FloatingWindowsCard.qml`, `Bar.qml`.
- Produces: a failing contract requiring helper toggle/state publication, both keybind contexts, shared QML state, and horizontal/vertical indicators.

- [ ] **Step 1: Write the failing test**

The test must assert:

```bash
grep -Fq 'toggle)' config/hypr/scripts/quickshell_floating_windows.sh
grep -Fq 'SUPER + ALT + F' config/hypr/hyprland.lua
grep -Fq 'FloatingWindowsState.enabled' config/quickshell/awtarchy/Bar.qml
grep -Fq 'label: "Floating"' config/quickshell/awtarchy/Bar.qml
grep -Fq 'FloatingWindowsState' config/quickshell/awtarchy/FloatingWindowsCard.qml
test -f config/quickshell/awtarchy/FloatingWindowsState.qml
```

It must also use a temporary `hyprland.lua`, fake `hyprctl`, fake runtime directory, and fake `notify-send` to verify `status`, `set`, and `toggle --notify` publish the exact `enabled`/`disabled` state without corrupting the Lua marker.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash -n tests/test-floating-windows-global-mode.sh
shellcheck tests/test-floating-windows-global-mode.sh
bash tests/test-floating-windows-global-mode.sh
```

Expected: FAIL because the helper has no `toggle`, the shared singleton does not exist, and the global bind/bar indicator are absent.

### Task 2: Extend the floating helper and keyboard bind

**Files:**
- Modify: `config/hypr/scripts/quickshell_floating_windows.sh`
- Modify: `config/hypr/hyprland.lua`

**Interfaces:**
- Produces: `status`, `set on|off`, `toggle`, optional `--notify`, and runtime publication to `${AWTARCHY_FLOATING_STATE_FILE:-${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/awtarchy-floating-windows-state}`.

- [ ] **Step 1: Implement runtime publication and toggle**

Add a publication helper that writes exactly `enabled` or `disabled` plus a newline. Make CLI actions resolve the final state, publish it, print it, and optionally notify with `notify-send -a Awtarchy -t 1500 "Floating windows" "enabled|disabled"`.

- [ ] **Step 2: Add the bind in both contexts**

Define:

```lua
local floating_windows_toggle = "~/.config/hypr/scripts/quickshell_floating_windows.sh toggle --notify"
```

Add `SUPER + ALT + F` to the default mode and the `noalt` submap, both dispatching the same command.

- [ ] **Step 3: Run helper regression**

Run the new test and existing floating-window test. Expected: helper/bind assertions pass; QML assertions still fail until Task 3.

### Task 3: Add one shared Quickshell state owner

**Files:**
- Create: `config/quickshell/awtarchy/FloatingWindowsState.qml`
- Modify: `config/quickshell/awtarchy/FloatingWindowsCard.qml`

**Interfaces:**
- Produces singleton properties `state`, `enabled`, `available`, `busy`, `message`, `errorMessage`; functions `refresh()`, `setEnabled(bool)`, `toggle()`.
- Consumes helper runtime state file and helper CLI.

- [ ] **Step 1: Implement singleton**

The singleton must:

```qml
pragma Singleton
```

Watch the runtime state file with `FileView`, perform one initial `status` invocation, parse only `enabled`/`disabled`, and use one action process for `set`/`toggle`. Do not add a repeating timer.

- [ ] **Step 2: Refactor Quick Settings card**

Remove its local status/action polling processes and 3-second timer. Bind labels/status/busy/error/message to `FloatingWindowsState` and call `FloatingWindowsState.toggle()` from the existing button.

### Task 4: Add the persistent bar escape hatch

**Files:**
- Modify: `config/quickshell/awtarchy/Bar.qml`

**Interfaces:**
- Consumes: `FloatingWindowsState.enabled`, `FloatingWindowsState.setEnabled(false)`.

- [ ] **Step 1: Add horizontal indicator**

Add a `BarControl` in the left-side status area after transient mode indicators:

```qml
BarControl {
    visible: FloatingWindowsState.enabled
    label: "Floating"
    tooltip: "New windows open floating by default\nClick to restore normal tiling"
    foreground: Theme.urgent
    onClicked: FloatingWindowsState.setEnabled(false)
    onRightClicked: FloatingWindowsState.setEnabled(false)
}
```

- [ ] **Step 2: Add vertical indicator**

Add the equivalent vertical `BarControl` in the top-side status area so vertical bars expose the same escape hatch.

### Task 5: Managed history and verification

**Files:**
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`

**Interfaces:**
- Consumes final managed QML bytes.

- [ ] **Step 1: Update managed hashes**

Append SHA-256 entries for changed/added managed QML paths if the exact digest/path pair is not already present.

- [ ] **Step 2: Run full focused verification**

Run:

```bash
git diff --check
bash -n config/hypr/scripts/quickshell_floating_windows.sh
shellcheck config/hypr/scripts/quickshell_floating_windows.sh tests/test-floating-windows-global-mode.sh
bash tests/test-floating-windows-global-mode.sh
bash tests/test-floating-windows-quicksettings.sh
bash tests/test-quick-settings-bar-customize-flow.sh
bash tests/test-quick-settings-settings-mode.sh
bash tests/test-quick-settings-ux-flow.sh
bash tests/test-bar-transparency.sh
bash tests/test-bar-module-visibility.sh
bash tests/test-bar-icon-display-options.sh
bash tests/test-bar-icon-customization.sh
```

Expected: all PASS.

- [ ] **Step 3: Commit production changes**

Commit production files, permanent regression test, design, and plan. Temporary branch-only CI/apply helpers must be removed after GREEN validation.
