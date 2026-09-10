# Lockscreen Customization Editor and Interactive Effects Design

## Scope

This branch extends Awtarchy's production Quickshell locker from a fixed presentation into a configurable lockscreen scene with a dedicated unlocked-session editor. The security model does not change.

The finished feature provides:

- the existing native Quickshell `WlSessionLock` + PAM lock authority unchanged;
- a reusable lockscreen presentation scene shared by the real locker and the unlocked editor preview;
- normalized, persisted positions for the logo, time, date, username, weather, and password visual anchor;
- an expandable Lockscreen section inside the existing Awtarchy Quick Settings card;
- a dedicated live editor for dragging lockscreen elements with Save, Cancel, and Restore Defaults behavior;
- independent formation, mouse-interaction, and audio-reactive controls;
- optional time, date, username, and cached weather information;
- black background by default with an optional local-wallpaper mode that always fails closed to black;
- explicit-location Open-Meteo weather refresh performed only while the desktop session is unlocked;
- bounded ghost-cursor, pointer-displacement, and CAVA-driven audio effects;
- focused regression coverage, updater/managed-history coverage, and full CI before merge consideration.

This feature must not add another lock authority, another PAM owner, an unlock IPC shortcut, IP-based geolocation, lock-time networking, or remote wallpaper fetching.

## Security ownership

Security ownership is non-negotiable:

- `config/quickshell/awtarchy-lock/shell.qml` owns the sole `WlSessionLock`.
- `config/quickshell/awtarchy-lock/LockAuth.qml` remains the sole PAM conversation owner.
- `LockSurface.qml` remains the secure surface that owns the real password `TextInput` and submits only through `LockAuth.qml`.
- the shared visual scene never receives password text, PAM state, authentication callbacks, or an unlock action;
- the unlocked editor renders only a password placeholder/anchor, never a real password field tied to PAM;
- editor, weather, wallpaper, pointer, and audio failures cannot change `sessionLock.locked`, `sessionLock.secure`, or authentication state;
- the real pointer remains hidden on the secure lock surface with `Qt.BlankCursor`.

The shared scene is a presentation component, not a security component.

## Architecture

### Shared `LockScene`

Extract the reusable presentation from `LockSurface.qml` into:

`config/quickshell/awtarchy-lock/LockScene.qml`

`LockScene` owns presentation only:

- background rendering;
- Awtarchy geometric wordmark and formation animation;
- ghost cursor/trail rendering;
- pointer-driven wordmark displacement;
- audio-reactive wordmark displacement;
- optional time/date/username/weather text;
- normalized element placement;
- a password visual anchor rectangle/geometry that callers can use.

It receives all preference/state values as properties. It does not read PAM state and does not submit authentication.

`LockSurface.qml` remains a `WlSessionLockSurface`. It embeds `LockScene`, keeps the secure full-surface input handlers, keeps `Qt.BlankCursor`, keeps the real password `TextInput`, and positions the real password visual/input block from the password anchor exposed by `LockScene`.

The unlocked editor imports the same `LockScene` component and uses the same normalized layout values. The editor may render a harmless password placeholder at the password anchor. This prevents a visually separate preview implementation from drifting away from the real lockscreen.

### Dedicated unlocked editor

Create a dedicated Awtarchy-shell editor singleton under:

`config/quickshell/awtarchy/LockscreenEditor.qml`

The editor is available only from the normal unlocked Awtarchy shell. It is not loaded by the dedicated secure lock process.

The editor:

- opens on the focused monitor;
- uses an above-windows Quickshell surface consistent with existing Awtarchy editors/pickers;
- previews the real `LockScene` against that monitor's logical dimensions;
- starts from normalized persisted layout state;
- lets the user drag enabled scene elements;
- keeps draft state in memory while open;
- `Save` validates and persists the complete layout atomically through `quickshell_application_state.sh`;
- `Cancel` closes without persisting draft layout changes;
- `Restore Defaults` resets the draft to stock positions and persists only when Save is used;
- closing/reopening without Save reloads persisted state rather than stale draft state.

The editor cannot call lock, unlock, PAM, power, suspend, logout, or session-lock APIs.

## Persisted state model

Continue using the existing shared state file and `quickshell_application_state.sh` as the single write authority. Do not add a second lockscreen settings file.

Existing values remain supported:

```text
lockscreen_animation: random|swarm|edges|center|split|off
lockscreen_audio_reactive: true
lockscreen_mouse_interactive: true
lockscreen_show_time: false
lockscreen_show_date: false
lockscreen_show_username: false
lockscreen_show_weather: false
```

Formation `off` affects only logo formation. It does not silently disable the independently saved Mouse Interaction or Audio Reactive preferences.

Add:

```json
{
  "lockscreen_background": "black",
  "lockscreen_weather_location": "",
  "lockscreen_layout": {
    "logo": { "x": 0.50, "y": 0.34 },
    "time": { "x": 0.50, "y": 0.51 },
    "date": { "x": 0.50, "y": 0.555 },
    "username": { "x": 0.50, "y": 0.595 },
    "weather": { "x": 0.50, "y": 0.635 },
    "password": { "x": 0.50, "y": 0.70 }
  }
}
```

`lockscreen_background` accepts only `black` or `wallpaper`.

`lockscreen_weather_location` is user-entered explicit location text. It must be trimmed, contain no control/newline characters, and be capped at 96 Unicode code points. Empty disables weather refresh even if the Weather display toggle remains saved.

`lockscreen_layout` is written as one complete object by an explicit `save-lockscreen-layout <json>` command. The helper rejects malformed JSON, unknown element keys, missing required elements, non-numeric coordinates, arrays/strings in place of objects, and coordinates outside the allowed normalized bounds. It must never partially persist a malformed layout.

`BarState.qml` exposes normalized readers and returns stock defaults when persisted data is missing or invalid.

The secure lock shell synchronously loads the complete normalized state before rendering surfaces. Quick Settings/editor writes do not need to mutate an already-secure lock session live.

## Normalized layout and safe bounds

Positions are normalized against each target surface so one saved layout works across monitor sizes and scale factors.

Each element uses a normalized center point.

General element bounds:

- `x`: `0.05 .. 0.95`
- `y`: `0.08 .. 0.92`

Password anchor bounds are intentionally tighter because the real input must remain obvious and reachable:

- `x`: `0.15 .. 0.85`
- `y`: `0.20 .. 0.86`

The editor clamps drag motion to these bounds before updating the draft. The persistence helper independently validates the same bounds so UI bugs cannot save unsafe positions.

The real password block keeps its current minimum visual/input size and remains entirely on-screen after applying the normalized password center. The editor shows the same footprint as a non-authenticating placeholder.

Disabled optional metadata retains its saved position so re-enabling it restores the user's layout.

## Quick Settings organization

Keep Lockscreen controls inside the existing Awtarchy Quick Settings card. Do not create a new reorderable top-level Quick Settings card.

Replace the flat lockscreen control cluster with one compact expandable `Lockscreen` section directly after the existing Lockscreen Animation selector. The collapsed state shows only the section title and current summary; expanding reveals:

- `Edit Layout`;
- `Background`: Black / Wallpaper;
- `Mouse Interaction`;
- `Audio Reactive`;
- `Time`;
- `Date`;
- `Username`;
- `Weather`;
- explicit `Weather Location` entry/control;
- `Restore Awtarchy Defaults` for lockscreen presentation preferences/layout, without touching authentication or unrelated Quick Settings state.

All simple toggles continue using the existing application-state command queue.

`Edit Layout` opens `LockscreenEditor` on the active/focused monitor and closes Quick Settings so the editor is not obscured.

## Background behavior

Stock background remains pure black.

Wallpaper mode uses only the current local Awtarchy wallpaper source already available to the desktop shell. Do not download an image and do not infer a remote URL.

Rules:

- `black`: render `#000000` only;
- `wallpaper`: render the current readable local wallpaper with aspect-fill behavior;
- missing, unreadable, unsupported, or empty wallpaper source: render `#000000`;
- the dedicated lock process must not perform network access to obtain a wallpaper;
- background failure must not delay secure lock acquisition.

The editor preview follows the same fallback behavior.

## Weather provider, privacy, and cache

Weather uses Open-Meteo because it does not require an API key. Network activity is owned by the unlocked desktop shell, never the secure lock process.

The user must explicitly enter the location. There is no IP geolocation, GPS lookup, Wi-Fi inference, or silent location derivation.

When Weather is enabled and a non-empty explicit location is configured, an unlocked-session helper may:

1. send the configured location string to Open-Meteo's geocoding endpoint;
2. resolve latitude/longitude for that query;
3. request current weather from Open-Meteo;
4. atomically write a small local cache at `${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/lockscreen-weather.json`.

The cache contains only display-safe data and freshness metadata, for example:

```json
{
  "summary": "72°F · Clear",
  "location": "Pittsburgh, PA",
  "fetched_at": 1788970000,
  "expires_at": 1788971800,
  "provider": "open-meteo"
}
```

Cache policy:

- normal freshness lifetime: 30 minutes;
- unlocked shell may refresh before expiry when the editor/Quick Settings explicitly requests it;
- periodic unlocked refresh must not run more frequently than every 20 minutes;
- the lock process reads the cache only;
- `LockWeatherCache.qml` rejects malformed data, summaries over 96 characters, missing/invalid expiry, and expired entries;
- expired/missing cache means weather text is empty;
- a network error preserves the last still-unexpired cache and never blocks locking.

The Quick Settings Weather Location control must communicate that enabling weather sends the configured location to Open-Meteo.

## Ghost cursor and pointer interaction

The system cursor is never shown on the secure lockscreen.

The shared scene keeps the bounded replacement visual:

- one soft circular head;
- six fixed trail samples;
- no pointer-shaped glyph;
- no persistent visual while stationary;
- fade begins around 180 ms after movement stops and completes around 500 ms total;
- movement samples are thresholded;
- physics processing is capped near one update per 16 ms;
- no permanent idle pointer loop.

Mouse Interaction is independently persisted. Disabling it removes the ghost trail and pointer-driven wordmark displacement without changing logo formation or Audio Reactive.

Pointer displacement remains local to nearby geometric wordmark cells:

- approximately 72 logical-pixel influence radius at `uiScale == 1`;
- approximately 24 logical-pixel displacement cap;
- speed-weighted bounded impulse;
- approximately 450 ms spring-like return;
- no pointer interaction until formation is nearly complete;
- only affected row/column ranges are examined.

## Audio-reactive wordmark

Audio response continues to use real system output energy from the dedicated short-lived CAVA analyzer.

Requirements remain:

- PipeWire automatic/default output monitor source;
- mono/averaged spectrum;
- eight bands;
- approximately 30 FPS;
- raw ASCII stdout;
- no microphone selection;
- no synthetic fake audio movement;
- missing/failed CAVA resolves to zero activity;
- one analyzer per lock process, shared across all monitor surfaces;
- audio displacement remains capped near 6 logical pixels per cell at `uiScale == 1` and weaker than pointer displacement.

Audio Reactive is independent of formation mode. `lockscreen_animation=off` skips only formation; if Audio Reactive is enabled, the already-assembled logo may still react to audio.

The editor may preview scene geometry without starting a duplicate permanent analyzer. Any editor-owned analyzer must exist only while the editor is open and must stop when it closes.

## Metadata behavior

Time, Date, Username, and Weather are independent optional elements rather than one forced vertical metadata stack.

- Time uses local system time, minute precision.
- Date uses local system locale/date facilities.
- Username reads only `Quickshell.env("USER")`; it never changes PAM user selection or enumerates users.
- Weather renders only a valid unexpired local cache summary.
- each optional element consumes no visible interaction target on the secure surface when disabled;
- each keeps its persisted normalized position while disabled.

## Multi-monitor behavior

Every secure `WlSessionLockSurface` uses the same persisted presentation preferences and normalized layout.

- normalized positions are resolved independently against each monitor's logical geometry;
- pointer/ghost state remains surface-local;
- moving on one lock surface cannot displace another monitor's logo;
- one lock-root audio analyzer feeds all surfaces;
- one lock-root weather cache reader feeds all surfaces;
- the editor opens on one selected monitor at a time and edits the global normalized layout;
- no editor window exists inside the secure lock process.

## Performance and lifecycle

Idle behavior must remain cheap:

- ghost-trail timers stop when fully transparent;
- pointer displacement has no permanent frame loop;
- CAVA remains bounded to eight bands near 30 FPS and terminates with its owning process;
- no analyzer starts when Audio Reactive is disabled;
- time/date use a low-frequency timer;
- weather network refresh occurs only in the unlocked shell and no more often than the cache policy allows;
- wallpaper loading is local and falls back immediately to black;
- the editor creates no persistent background service;
- no full-screen continuously running shader is introduced.

## TDD and regression coverage

Production changes for the editor architecture must follow RED -> GREEN.

Add a focused regression such as `tests/test-quickshell-lockscreen-editor.sh` before creating the production editor/scene implementation. It must initially fail because `LockScene.qml`, `LockscreenEditor.qml`, and the new persisted layout/background/location commands do not exist.

Focused coverage must assert at least:

- `LockScene.qml` exists and does not import/use `Quickshell.Wayland`, `WlSessionLock`, PAM, or authentication submission;
- `LockSurface.qml` remains the `WlSessionLockSurface`, keeps `Qt.BlankCursor`, keeps the real password `TextInput`, and embeds the shared `LockScene`;
- the editor imports/uses the exact same `LockScene`;
- the editor has Save, Cancel, and Restore Defaults semantics and no lock/unlock/PAM API;
- stock normalized positions exist for logo/time/date/username/weather/password;
- persistence rejects malformed/partial layout JSON and unsafe password coordinates;
- background accepts only `black|wallpaper`;
- explicit weather location validation is bounded and rejects control/newline input;
- Quick Settings exposes one expandable Lockscreen section and `Edit Layout`;
- wallpaper mode has an explicit black fallback;
- weather fetch code exists only in the unlocked shell/helper, uses Open-Meteo, has bounded timeouts/frequency, and never appears in `awtarchy-lock/shell.qml` or `LockWeatherCache.qml`;
- lock weather cache rejects expired entries;
- `LockAuth.qml` remains free of editor/layout/weather/audio presentation state;
- managed-history is refreshed only after final managed file contents are known.

Existing interactive-effects, lockscreen foundation, runtime-regression, animation-preference, lifecycle, updater, managed-history, Screen Share Guard, and full Awtarchy integration tests remain required.

## Validation

Automated evidence must include:

- the new focused editor regression observed RED before production implementation;
- focused editor regression GREEN after implementation;
- existing interactive-effects and interactive-physics regressions;
- lockscreen foundation/runtime/animation/cutover regressions;
- Bash syntax and ShellCheck for every changed/new shell helper;
- managed-history/updater validation after final hashes are registered;
- `git diff --check` equivalent hygiene;
- all PR-triggered GitHub Actions successful on the exact final candidate before merge consideration.

Static tests and CI may prove structure, state validation, lifecycle contracts, and security separation. They cannot prove final visual placement, drag feel, wallpaper appearance, pointer/audio motion quality, multi-monitor appearance, or real unlock behavior.

Real Hyprland runtime validation by the user remains mandatory before those runtime/visual behaviors are called verified. The runtime pass must include wrong-password retry and successful unlock so presentation refactoring does not mask an authentication regression.
