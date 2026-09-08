# Lockscreen Interactive Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded ghost-cursor/logo interaction, real CAVA-driven audio motion, and optional local time/date/username lockscreen information without changing Awtarchy's session-lock or PAM security model.

**Architecture:** Extend the existing shared Quickshell state path and dedicated `awtarchy-lock` process. Keep `LockSurface.qml` as the geometric wordmark renderer, add one shell-owned audio analyzer feeding every lock surface, and keep pointer/trail state local to each surface. Reuse the existing `lockscreen_animation=off` preference as the animation master switch.

**Tech Stack:** Bash, jq/flock, QML/Qt Quick, Quickshell Io, CAVA/PipeWire, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-lockscreen-interactive-effects-design.md`

## Global Constraints

- Preserve `WlSessionLock` as the only lock authority.
- Preserve `LockAuth.qml` as the only PAM conversation owner.
- Never pass authentication data to audio, pointer, shell-helper, file, environment, argv, or IPC paths.
- `lockscreen_animation=off` disables formation, ghost cursor, pointer displacement, and audio displacement but not optional informational metadata.
- `lockscreen_audio_reactive` defaults `true`; `lockscreen_show_time`, `lockscreen_show_date`, and `lockscreen_show_username` default `false`.
- Weather is not implemented in this slice.
- No release/tag modification.

---

### Task 1: Define focused regression contracts

**Files:**
- Create: `tests/test-quickshell-lockscreen-interactive-effects.sh`
- Create: `.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml`

**Interfaces:**
- Consumes: current `BarState.qml`, `QuickSettings.qml`, `quickshell_application_state.sh`, `awtarchy-lock/shell.qml`, `LockSurface.qml`.
- Produces: a focused red/green contract for state defaults, state mutation, master suppression, ghost cursor bounds, audio analyzer lifecycle, and Quick Settings controls.

- [ ] **Step 1: Write the failing regression**

Assert the new persisted booleans, explicit state commands, UI controls, lock-shell preference loading, one shell-owned analyzer, fixed-size ghost trail, bounded pointer/audio offsets, real CAVA raw PipeWire configuration, and the unchanged blank real cursor.

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-interactive-effects.sh
```

Expected: FAIL because the first new state command/default or analyzer file does not exist yet.

- [ ] **Step 3: Commit the red regression**

```bash
git add tests/test-quickshell-lockscreen-interactive-effects.sh .github/workflows/validate-quickshell-lockscreen-interactive-effects.yml
git commit -m "Test lockscreen interactive effects"
```

### Task 2: Persist and surface lockscreen options

**Files:**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Test: `tests/test-quickshell-lockscreen-interactive-effects.sh`
- Test: `tests/test-quickshell-lockscreen-animation-preference.sh`

**Interfaces:**
- Produces state keys `lockscreen_audio_reactive`, `lockscreen_show_time`, `lockscreen_show_date`, `lockscreen_show_username` and corresponding normalized QML properties passed into every lock surface.

- [ ] **Step 1: Add explicit boolean setters to the state helper**

Use existing `parse_bool()` and one generic private `set_lockscreen_option(field, value, label)` helper restricted to four hard-coded commands. Do not add arbitrary field mutation.

- [ ] **Step 2: Add normalized defaults/readers to `BarState.qml`**

Return stock defaults when keys are missing or malformed.

- [ ] **Step 3: Add compact Quick Settings controls under `Lockscreen Animation`**

Audio Reactive preserves its saved value but is visually inactive when animation is Off. Time, Date, and Username remain independent.

- [ ] **Step 4: Load preferences synchronously in the dedicated lock shell**

Pass read-only booleans into surfaces and use one root-level analyzer enable expression.

- [ ] **Step 5: Run focused preference tests**

```bash
bash tests/test-quickshell-lockscreen-interactive-effects.sh
bash tests/test-quickshell-lockscreen-animation-preference.sh
```

### Task 3: Add real audio analyzer

**Files:**
- Create: `config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml`
- Create: `config/quickshell/awtarchy-lock/cava.conf`
- Create: `config/hypr/scripts/quickshell_lockscreen_audio.sh`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Test: `tests/test-quickshell-lockscreen-interactive-effects.sh`

**Interfaces:**
- `LockAudioAnalyzer.qml` exposes `low`, `mid`, `high`, `overall` normalized `0..1` properties.
- The helper writes only CAVA raw frames to stdout and exits successfully when CAVA is unavailable.
- `shell.qml` owns exactly one analyzer and passes the four values to every surface.

- [ ] **Step 1: Configure CAVA for PipeWire output monitoring**

Use eight bands, about 30 FPS, raw ASCII stdout, bounded integer range, and silence sleep.

- [ ] **Step 2: Add safe analyzer launcher**

```bash
#!/usr/bin/env bash
set -euo pipefail
command -v cava >/dev/null 2>&1 || exit 0
exec cava -p "$CONFIG"
```

Resolve `CONFIG` from the managed Quickshell lock config path with `XDG_CONFIG_HOME` fallback; do not select microphone sources.

- [ ] **Step 3: Parse and smooth frames in QML**

Split eight numeric bands, clamp to `0..1`, derive low/mid/high/overall groups, use faster attack than release, and decay to zero when the process stops.

- [ ] **Step 4: Run syntax/static checks**

```bash
bash -n config/hypr/scripts/quickshell_lockscreen_audio.sh
shellcheck config/hypr/scripts/quickshell_lockscreen_audio.sh
bash tests/test-quickshell-lockscreen-interactive-effects.sh
```

### Task 4: Add ghost cursor and bounded logo physics

**Files:**
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Test: `tests/test-quickshell-lockscreen-interactive-effects.sh`
- Test: `tests/test-quickshell-lockscreen-runtime-regressions.sh`

**Interfaces:**
- Surface-local pointer state: head plus six fixed trail samples.
- Per-cell additive offsets: `pointerOffsetX/Y` and computed `audioOffsetX/Y` added after formation geometry.

- [ ] **Step 1: Replace click-only `MouseArea` handling with movement capture while retaining `Qt.BlankCursor`**

Throttle physics updates to about 16 ms and ignore sub-threshold movement.

- [ ] **Step 2: Render one soft head plus six fading trail samples**

Start fade around 180 ms idle and reach zero around 500 ms; stop decay activity when invisible.

- [ ] **Step 3: Apply local pointer impulses only to nearby assembled cells**

Use approximately 72 px influence radius, approximately 24 px pointer displacement cap, and approximately 450 ms return-to-rest behavior.

- [ ] **Step 4: Add subtle audio offsets**

Use per-cell existing random seeds, edge weighting, a maximum near 6 px, and combined displacement clamping. Silence must resolve to exact rest.

- [ ] **Step 5: Run focused and existing runtime-regression tests**

```bash
bash tests/test-quickshell-lockscreen-interactive-effects.sh
bash tests/test-quickshell-lockscreen-runtime-regressions.sh
```

### Task 5: Add optional local metadata and update historical guards

**Files:**
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `tests/test-quickshell-lockscreen-runtime-regressions.sh`
- Modify: `tests/test-quickshell-lockscreen-animation-preference.sh`

**Interfaces:**
- Surface properties: `showTime`, `showDate`, `showUsername`.
- Metadata stack has zero visible height when all three are off.

- [ ] **Step 1: Add local-only metadata stack**

Use a low-frequency QML timer for time/date and `Quickshell.env("USER")` only for the optional username display. Do not enumerate users or touch PAM targeting.

- [ ] **Step 2: Replace obsolete regressions that prohibit metadata**

Assert instead that all metadata is optional and stock-disabled.

- [ ] **Step 3: Verify animation Off remains independent from metadata**

```bash
bash tests/test-quickshell-lockscreen-animation-preference.sh
bash tests/test-quickshell-lockscreen-runtime-regressions.sh
```

### Task 6: Managed history and complete validation

**Files:**
- Modify after final stock content only: `local/share/awtarchy/quickshell-managed-history.sha256`

**Interfaces:**
- Registers the final managed Quickshell stock hashes without replacing historical entries.

- [ ] **Step 1: Compute final hashes for every changed managed Quickshell file and append only missing current entries**

- [ ] **Step 2: Run focused lockscreen validation and updater/migration validation**

Use all tests invoked by the lockscreen workflows plus affected managed-history/updater tests.

- [ ] **Step 3: Run diff hygiene**

```bash
git diff --check
```

- [ ] **Step 4: Require all PR-triggered GitHub Actions checks to complete successfully before merge consideration**

- [ ] **Step 5: Leave runtime-only visual claims unverified until real Hyprland testing**

The runtime candidate must be tested for cursor fade, pointer/logo response, audio response/silence, toggles, multi-monitor behavior, wrong-password retry, and successful unlock before declaring those visual behaviors complete.
