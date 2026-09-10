# Lockscreen Customization Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing interactive Awtarchy Quickshell lockscreen into a reusable configurable scene with an unlocked live editor, normalized persisted layout, local-wallpaper background option, and explicit-location cached weather without changing lock or PAM ownership.

**Architecture:** Extract presentation into `awtarchy-lock/LockScene.qml`. `LockSurface.qml` remains the secure `WlSessionLockSurface` and keeps the real password input/authentication path, while `awtarchy/LockscreenEditor.qml` imports the same scene and renders only a harmless password placeholder. Persist all presentation state through the existing `quickshell_application_state.sh` state writer; perform weather network refresh only from the unlocked shell and let the lock process read an expiring local cache.

**Tech Stack:** Bash, jq/flock, QML/Qt Quick, Quickshell Io/Wayland, CAVA/PipeWire, curl/Open-Meteo, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-lockscreen-interactive-effects-design.md`

## Global Constraints

- `WlSessionLock` remains the only lock authority.
- `LockAuth.qml` remains the only PAM conversation owner.
- `LockSurface.qml` retains the real password `TextInput` and authentication submission.
- Shared/editor scene code never receives password text or an unlock method.
- No release/tag modification and no merge of PR #181.
- `quickshell_application_state.sh` remains the sole persistent write authority.
- Layout uses normalized coordinates and independently validates safe password bounds.
- Weather uses explicit user-entered location only; no IP/device geolocation.
- Weather networking occurs only in the unlocked shell/helper; the lock process is cache-only.
- Background defaults to black and local-wallpaper failure falls back to black.
- Runtime/visual behavior is not called verified until the user tests it on Hyprland.

---

### Task 1: Define editor architecture regressions

**Files:**
- Create: `tests/test-quickshell-lockscreen-editor.sh`
- Modify: `.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml`

**Interfaces:**
- Consumes current lockscreen state/QML and future `LockScene.qml`/`LockscreenEditor.qml`.
- Produces the RED contract for shared scene ownership, normalized layout persistence, editor safety, background validation, and weather separation.

- [ ] **Step 1: Write the failing focused test**

The test must require:

```text
config/quickshell/awtarchy-lock/LockScene.qml
config/quickshell/awtarchy/LockscreenEditor.qml
```

It must assert shared-scene use in both real lock and editor, reject lock/PAM APIs in editor/scene, exercise `save-lockscreen-layout`, reject malformed and unsafe password coordinates, exercise `set-lockscreen-background`, validate weather-location input, require the expandable Quick Settings Lockscreen section, and require cache expiry handling.

- [ ] **Step 2: Add the focused test to permanent lockscreen CI**

Add syntax/ShellCheck invocation and `bash tests/test-quickshell-lockscreen-editor.sh` to the existing interactive-effects workflow.

- [ ] **Step 3: Verify RED through GitHub Actions**

Expected focused failure: missing `LockScene.qml` or `LockscreenEditor.qml`; existing unrelated tests must not be edited to manufacture the failure.

- [ ] **Step 4: Commit only regression/workflow changes before production code**

Commit message:

```text
Test lockscreen customization editor
```

### Task 2: Add validated presentation state

**Files:**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Test: `tests/test-quickshell-lockscreen-editor.sh`

**Interfaces:**
- Produces `lockscreen_background`, `lockscreen_weather_location`, and complete `lockscreen_layout` object.
- Commands:
  - `set-lockscreen-background <black|wallpaper>`
  - `set-lockscreen-weather-location <text>`
  - `save-lockscreen-layout <json>`
  - `reset-lockscreen-presentation`

- [ ] **Step 1: Add stock defaults to state normalization**

Use these exact default centers:

```json
{
  "logo":{"x":0.50,"y":0.34},
  "time":{"x":0.50,"y":0.51},
  "date":{"x":0.50,"y":0.555},
  "username":{"x":0.50,"y":0.595},
  "weather":{"x":0.50,"y":0.635},
  "password":{"x":0.50,"y":0.70}
}
```

- [ ] **Step 2: Add strict background setter**

Only `black` and `wallpaper` succeed. Invalid values exit nonzero without modifying state.

- [ ] **Step 3: Add strict location setter**

Trim outer whitespace, permit empty string, reject newline/control characters, and reject more than 96 Unicode code points.

- [ ] **Step 4: Add atomic layout validator/writer**

Require exactly the six known elements, object values with numeric `x/y`, general bounds `x 0.05..0.95`, `y 0.08..0.92`, and password bounds `x 0.15..0.85`, `y 0.20..0.86`. Validate the complete candidate before calling the existing atomic commit path.

- [ ] **Step 5: Add normalized `BarState.qml` readers**

Expose stock-safe functions for background, weather location, full layout, and per-element position.

- [ ] **Step 6: Run the focused regression**

Expected at this point: state validation assertions pass; test still fails because shared scene/editor files are missing.

### Task 3: Extract presentation into `LockScene`

**Files:**
- Create: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Test: `tests/test-quickshell-lockscreen-editor.sh`
- Test: `tests/test-quickshell-lockscreen-interactive-effects.sh`
- Test: `tests/test-quickshell-lockscreen-interactive-physics-regressions.sh`
- Test: `tests/test-quickshell-lockscreen-runtime-regressions.sh`

**Interfaces:**
- `LockScene` inputs: theme, animation preference/mode, audio levels, effect toggles, detail toggles/text, background source/mode, layout object, `previewMode`.
- `LockScene` outputs: password anchor center/size geometry and pointer-motion method used by the secure surface/editor.

- [ ] **Step 1: Move only presentation into `LockScene.qml`**

Move black/background layer, wordmark geometry/formation, pointer/audio displacement, ghost trail, time/date/username/weather rendering, and normalized positioning. Do not move `WlSessionLockSurface`, `TextInput`, `auth`, submit logic, or unlock transitions.

- [ ] **Step 2: Make normalized placement authoritative**

Each scene element centers at `layout[element].x * width`, `layout[element].y * height`; disabled metadata remains non-visible but retains state.

- [ ] **Step 3: Expose password anchor geometry**

Use the same current password footprint sizing and return its center/width/height so `LockSurface.qml` can position the real secure password block there.

- [ ] **Step 4: Rewire `LockSurface.qml`**

Keep `WlSessionLockSurface`, `Qt.BlankCursor`, real password `TextInput`, `submitPassword()`, focus handling, fade/unlock behavior, and wheel/pinch consumption. Feed pointer motion into the embedded scene.

- [ ] **Step 5: Rewire lock-root preferences**

Load normalized layout/background along with existing booleans and pass them into every surface. Keep one audio analyzer and one weather cache reader at lock root.

- [ ] **Step 6: Run focused/existing tests**

Editor-focused test is expected to remain RED only on the not-yet-created editor/Quick Settings parts. Existing interactive effects/physics/security contracts must remain green.

### Task 4: Add unlocked live layout editor

**Files:**
- Create: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy/shell.qml`
- Test: `tests/test-quickshell-lockscreen-editor.sh`

**Interfaces:**
- Singleton API: `openForScreen(screen)`, `openFocused()`, `close()`, `save()`, `resetDraft()`.
- Draft layout is in memory until Save invokes `save-lockscreen-layout`.

- [ ] **Step 1: Build editor surface following existing picker/editor patterns**

Use an above-windows Quickshell surface on the focused screen with exclusive keyboard focus while open and no session-lock/PAM imports.

- [ ] **Step 2: Import and render the shared scene**

The editor must import the exact `awtarchy-lock/LockScene.qml` component, pass current presentation preferences, and set preview mode so the password anchor is a harmless placeholder.

- [ ] **Step 3: Add draggable handles for enabled elements**

Convert pointer positions to normalized coordinates and clamp general/password coordinates before updating draft state.

- [ ] **Step 4: Add Save / Cancel / Restore Defaults**

Save serializes all six normalized positions and invokes the explicit state helper command. Cancel discards draft. Restore Defaults changes draft only until Save.

- [ ] **Step 5: Construct editor singleton from `awtarchy/shell.qml`**

Force singleton readiness consistently with existing Awtarchy surfaces and ensure Escape can close the editor before lower-priority flyouts.

- [ ] **Step 6: Run focused regression**

Expected remaining RED assertions should be limited to Quick Settings/background/weather pieces not yet implemented.

### Task 5: Reorganize Quick Settings lockscreen controls

**Files:**
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Test: `tests/test-quickshell-lockscreen-editor.sh`
- Test: `tests/test-quickshell-lockscreen-interactive-effects.sh`
- Test: `tests/test-quickshell-quick-settings-layout.sh`

**Interfaces:**
- One inline expandable Lockscreen section inside the existing Awtarchy card.
- `Edit Layout` opens `LockscreenEditor` on the active monitor.

- [ ] **Step 1: Replace flat Effects/Details headings with one expandable Lockscreen section**

Preserve existing animation, mouse, audio, time, date, username, and weather behavior.

- [ ] **Step 2: Add `Edit Layout` and background selector**

Editor launch closes Quick Settings before opening the editor. Background selection persists through `set-lockscreen-background`.

- [ ] **Step 3: Add bounded Weather Location editor**

Persist through `set-lockscreen-weather-location`; show explicit text that the configured location is sent to Open-Meteo when Weather is enabled/refreshed.

- [ ] **Step 4: Add Restore Awtarchy Defaults**

Invoke only the lockscreen presentation reset path; do not reset authentication, unrelated application state, or Quick Settings layout.

- [ ] **Step 5: Run Quick Settings and focused tests**

Keep existing Awtarchy card/reorder structure unchanged.

### Task 6: Add local wallpaper background path

**Files:**
- Modify only the existing Awtarchy wallpaper state/helper proven by current repository inspection.
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Test: `tests/test-quickshell-lockscreen-editor.sh`

**Interfaces:**
- Scene receives a local file URL/path or empty string.
- Empty/unreadable source renders black.

- [ ] **Step 1: Inspect and reuse the current wallpaper source of truth**

Do not create a parallel wallpaper state path and do not guess a package/API.

- [ ] **Step 2: Feed the current local wallpaper source into editor and secure lock startup state**

No remote/network wallpaper source is accepted.

- [ ] **Step 3: Add aspect-fill wallpaper rendering with black fallback**

The base rectangle stays black underneath the image so decode/read failures are safe and immediate.

- [ ] **Step 4: Run focused regression**

Static tests prove source/fallback structure only; appearance remains runtime-gated.

### Task 7: Implement unlocked Open-Meteo refresh and strict cache expiry

**Files:**
- Create: `config/hypr/scripts/quickshell_lockscreen_weather.sh`
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Modify: `config/quickshell/awtarchy/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockWeatherCache.qml`
- Test: `tests/test-quickshell-lockscreen-editor.sh`

**Interfaces:**
- Helper mode `refresh <location>` writes `${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/lockscreen-weather.json` atomically.
- Cache fields: `summary`, `location`, `fetched_at`, `expires_at`, `provider`.

- [ ] **Step 1: Write helper tests before helper implementation**

Use a fake `curl` earlier in `PATH` to prove the helper calls only Open-Meteo geocoding/current-weather URLs, passes explicit location, uses bounded timeouts, and writes a 30-minute expiry without external network access in tests.

- [ ] **Step 2: Implement narrow weather helper**

Require `curl` and `jq`, use connect/overall timeouts, URL-encode the explicit location, fail without destroying a still-valid prior cache, and atomically replace cache only after validating provider JSON.

- [ ] **Step 3: Add unlocked refresh ownership**

Only `awtarchy/shell.qml`/Quick Settings may run the helper. Normal periodic refresh must be at least 20 minutes apart and only while Weather is enabled with a non-empty location.

- [ ] **Step 4: Enforce expiry in `LockWeatherCache.qml`**

Reject malformed/missing `expires_at`, expired cache, overlong summary, and non-Open-Meteo provider value. Keep all HTTP/network tokens absent from the secure lock process.

- [ ] **Step 5: Run syntax/ShellCheck/focused tests**

The focused test must prove the lock side remains cache-only.

### Task 8: Final managed history and validation

**Files:**
- Modify after final managed stock content only: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify PR #181 description after exact final state is known.

**Interfaces:**
- Registers final managed hashes without deleting historical valid entries.

- [ ] **Step 1: Refresh managed history only for finalized managed files**

Use the repository's existing history-generation/update pattern and preserve history required for user migrations.

- [ ] **Step 2: Run all focused lockscreen tests**

```bash
bash tests/test-quickshell-lockscreen-editor.sh
bash tests/test-quickshell-lockscreen-interactive-effects.sh
bash tests/test-quickshell-lockscreen-interactive-physics-regressions.sh
bash tests/test-quickshell-lockscreen-animation-preference.sh
bash tests/test-quickshell-lockscreen-runtime-regressions.sh
```

- [ ] **Step 3: Run affected broader validation**

Run lockscreen foundation/cutover, Quick Settings layout, lifecycle/production, managed-history/updater tests, Bash syntax/ShellCheck, and full Awtarchy integration coverage used by the relevant workflows.

- [ ] **Step 4: Verify exact GitHub branch/CI state**

Require all PR-triggered workflows on the exact final head to complete successfully. Keep PR #181 draft/unmerged.

- [ ] **Step 5: Update PR #181 body to match proven scope/status**

Do not claim wallpaper/editor/effect/weather visual behavior or successful real unlock as runtime-verified until the user's Hyprland test supplies that evidence.

- [ ] **Step 6: Provide one consolidated Hyprland runtime test**

Cover editor drag/save/cancel/reset, multi-monitor normalized placement, black/wallpaper fallback, weather fresh/expired behavior, pointer/audio effects, wrong-password retry, successful unlock, and unchanged secure handoff.
