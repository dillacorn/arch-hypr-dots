# Lockscreen Interactive Effects and Local Info Design

## Scope

This implementation slice extends the current production Awtarchy Quickshell locker with interactive visual effects and optional local lockscreen information while preserving the existing session-lock and PAM security architecture.

This slice adds:

- a temporary ghost-cursor circle and short comet trail while the pointer is moving;
- localized Awtarchy wordmark displacement when the ghost cursor passes through the logo;
- subtle audio-reactive wordmark motion driven by real output-audio spectrum data when CAVA is available;
- independent Quick Settings toggles for time, date, and username, all disabled by default;
- an Audio Reactive toggle enabled by default;
- focused regression coverage and permanent CI validation for the new behavior.

This slice does not change `WlSessionLock`, PAM authentication, password handling, the lock manager, suspend/hibernate security ordering, or the black lockscreen background.

Weather is intentionally outside this slice. It requires a separate provider/location/privacy decision because the current lockscreen has no network dependency and Awtarchy must not silently derive location or contact a weather service. Weather should receive its own design before any network access is added.

## Current implementation constraints

The current production lock lives under `config/quickshell/awtarchy-lock/` and already provides the correct foundation for this work:

- `shell.qml` owns `WlSessionLock`, shared authentication, and the persisted lockscreen animation preference.
- `LockSurface.qml` renders the geometric seven-row Awtarchy wordmark as individually addressable filled cells.
- `LockSurface.qml` already hides the real pointer with `cursorShape: Qt.BlankCursor`.
- the wordmark already has per-cell randomized formation state and one exact resting position per filled cell.
- `BarState.qml`, `QuickSettings.qml`, and `quickshell_application_state.sh` already own the global lockscreen animation preference in the shared Quickshell state file.

The implementation must extend those owners instead of creating a parallel preference store or a second lock authority.

## Preference model

Keep the existing `lockscreen_animation` preference and its values unchanged:

- `random`
- `swarm`
- `edges`
- `center`
- `split`
- `off`

`off` is the animation master switch. When it is selected:

- logo formation remains skipped as it is today;
- the ghost cursor/comet effect is disabled;
- pointer-driven logo displacement is disabled;
- audio-reactive logo displacement is disabled.

The real pointer remains hidden even when animation is off.

Add these global persisted values to the existing Quickshell state file:

```text
lockscreen_audio_reactive: true
lockscreen_show_time: false
lockscreen_show_date: false
lockscreen_show_username: false
```

Time, date, and username are informational preferences and remain independent of the animation master switch.

`quickshell_application_state.sh` must remain the write authority. Add narrowly validated explicit setters for the four new booleans rather than introducing an unrestricted arbitrary-state mutation command.

`BarState.qml` exposes normalized read access with the stock defaults above. The dedicated lock process reads the state synchronously at startup, just as it already does for `lockscreen_animation`. Quick Settings cannot be changed while the desktop is securely locked, so live preference mutation inside an existing lock session is unnecessary.

## Ghost cursor and comet trail

The system cursor is never shown on the lockscreen.

Pointer movement instead creates a temporary lockscreen-owned visual:

- a small soft circular head at the current pointer position;
- a short comet trail made from a fixed small number of prior positions;
- no pointer-shaped glyph or arrow;
- no persistent cursor while the mouse is stationary.

Use a fixed-size trail rather than dynamically creating arbitrary QML objects. Six trail samples plus one head is sufficient. New samples are accepted only after a small movement threshold so high-polling-rate mice do not create unnecessary work.

Target timing:

- movement makes the head/trail visible immediately;
- after roughly 180 ms without movement, opacity begins dropping rapidly;
- the complete cursor effect is gone by roughly 500 ms after the final movement;
- the decay timer stops when the effect is fully invisible.

Clicks continue to restore password focus exactly as they do now. Wheel and pinch input remain consumed by the lock surface.

## Pointer-driven wordmark displacement

Reuse the existing geometric wordmark cells as the physical fragments. Do not replace the wordmark with a shader-only image, text renderer, or second duplicate logo.

Each filled wordmark cell gains transient displacement state in addition to its existing formation position:

```text
final/rest position
+ formation offset
+ pointer offset
+ audio offset
= rendered position
```

Pointer interaction is local, not global. When the ghost cursor passes through the assembled wordmark:

- only cells inside a bounded influence radius react;
- cells are pushed away from the cursor contact point;
- cursor speed scales the impulse within a strict cap;
- brushing an edge produces a small ripple;
- a faster pass through the center produces a stronger but still localized separation;
- cells return to their exact original rest positions automatically.

Target bounds at `uiScale == 1`:

- influence radius: approximately 72 logical pixels;
- pointer displacement cap per cell: approximately 24 logical pixels;
- pointer decay: approximately 450 ms;
- use an easing curve with a small overshoot on the return so the motion reads as spring-like without a long oscillation.

Pointer interaction should not fight the initial formation animation. A cell becomes interactive only when its formation is nearly complete.

Do not scan the entire wordmark on every raw mouse event. Convert the cursor into wordmark-local coordinates, derive the affected row/column range from the known cell geometry, and evaluate only nearby cells. Cap interaction processing at approximately one update per 16 ms.

When pointer input stops and all displacement decays to zero, there must be no continuously running pointer-physics loop.

## Audio-reactive wordmark

Audio response must use real system output energy. Do not infer animation strength from Spotify/MPRIS playback state, active PipeWire links, configured volume, or a synthetic random animation.

Quickshell's PipeWire service is still useful for normal audio controls, but it does not expose a live PCM/spectrum level suitable for this effect. Use CAVA as a short-lived analyzer when available because Awtarchy already carries CAVA as an existing terminal-app package and CAVA can consume PipeWire output and emit raw spectrum frames.

Add a dedicated lockscreen CAVA configuration under `config/quickshell/awtarchy-lock/` with these properties:

- PipeWire input;
- automatic/default output-monitor source;
- mono/averaged spectrum;
- eight bands;
- approximately 30 frames per second;
- raw ASCII output to stdout;
- normalized integer range suitable for simple QML parsing;
- a short silence sleep timer so CAVA reduces work when no audio is present.

Add a narrow launcher helper under `config/hypr/scripts/` that:

- exits quietly when `cava` is unavailable;
- otherwise `exec`s CAVA with only the dedicated lockscreen configuration;
- never reads microphone input intentionally;
- creates no persistent daemon/service;
- terminates with the lock process.

Isolate parsing and smoothing in a small lockscreen QML component rather than expanding authentication code. It exposes normalized low, mid, high, and overall activity values. Parse each frame, clamp values to `0..1`, apply a small silence threshold, and smooth attack/release so raw band changes do not make the logo jitter.

The audio analyzer runs only when all of these are true:

- `lockscreen_audio_reactive` is enabled;
- `lockscreen_animation` is not `off`;
- the lock process is active.

If CAVA is not installed or cannot start, the analyzer produces zero activity and the lockscreen remains fully functional and static. Do not synthesize fake movement and do not make authentication depend on analyzer availability.

### Audio motion language

The wordmark itself is the visualizer. Do not add bars, waveforms, equalizer graphics, RGB effects, album art, or player controls.

Audio displacement is weaker than pointer displacement and biased toward the outer edges of the logo:

- silence: exact resting wordmark;
- quiet audio: nearly imperceptible edge motion;
- normal audio: gentle edge separation/vibration;
- louder transients/bass: slightly stronger outward movement and quick return;
- the center of the wordmark stays comparatively stable.

Target maximum audio displacement at `uiScale == 1`: approximately 6 logical pixels per cell.

Use the existing per-cell deterministic random seeds plus the smoothed low/mid/high values to vary direction and frequency response between cells. This keeps motion organic without adding a separate particle population.

Pointer and audio offsets are additive but the final combined displacement is clamped. A pointer pass therefore temporarily dominates local motion while the rest of the logo can continue its subtle audio vibration.

## Optional local information

Add a small collapsible metadata stack between the wordmark and password blocks.

When all local information toggles are off, the stack consumes no visible height and the existing minimal layout remains effectively unchanged.

### Time

- disabled by default;
- centered and visually prominent relative to the other metadata, but still secondary to the wordmark;
- use local system time with no network dependency;
- minute precision is sufficient; no seconds display is required.

### Date

- disabled by default;
- centered beneath time when both are enabled;
- use the system locale/date facilities only.

### Username

- disabled by default;
- centered and visually subtle;
- read the current local session username only when the option is enabled;
- do not perform user enumeration or change PAM user selection.

A lightweight local timer may update time/date while locked. It must not participate in authentication or delay secure lock acquisition.

## Quick Settings layout

Keep all controls inside the existing Awtarchy Quick Settings card. Do not add another reorderable top-level card.

Directly below the existing `Lockscreen Animation` selector, add a compact lockscreen-options group containing:

- `Audio Reactive` — On by default;
- `Time` — Off by default;
- `Date` — Off by default;
- `Username` — Off by default.

The controls persist immediately through the existing application-state command queue.

When `Lockscreen Animation` is `Off`, `Audio Reactive` should look inactive/disabled because the master animation setting suppresses it, but its saved boolean value is preserved so turning animations back on restores the user's previous preference.

Time, Date, and Username remain usable regardless of animation mode.

There is no separate Ghost Cursor toggle in this slice. The ghost cursor and pointer physics are part of the lockscreen animation system and follow the existing `Off` master setting.

## Multi-monitor behavior

Every `WlSessionLockSurface` renders the same saved preferences and receives the same global audio spectrum values.

Pointer/comet state remains surface-local because each monitor has its own pointer coordinates and wordmark geometry. Moving the pointer on one surface must not displace the wordmark on another monitor.

The one lock process owns one audio analyzer so multiple monitors do not spawn duplicate CAVA processes.

The existing shared random formation family remains one choice per lock across all monitors.

## Performance and lifecycle

This feature must remain cheap when idle.

- ghost-trail decay timers stop when fully transparent;
- pointer displacement has no permanent frame loop;
- audio analysis is capped near 30 FPS and uses only eight bands;
- CAVA's silence sleep behavior should be enabled;
- no analyzer process starts when Audio Reactive is disabled or animations are Off;
- the analyzer ends with the dedicated lock process;
- local time/date refresh uses a low-frequency timer;
- no new long-running service is introduced.

The implementation should preserve the existing wordmark geometry and use small additive state rather than replacing it with a continuously rendered full-screen shader.

## Security boundaries

The feature must not weaken the existing lockscreen security model.

- `WlSessionLock` remains the only lock authority.
- `LockAuth.qml` remains the only PAM conversation owner.
- password values remain confined to the existing authentication path.
- audio processing never receives password/authentication data.
- pointer effects cannot unlock, dismiss, or terminate a secure lock.
- CAVA failure cannot affect authentication or `sessionLock.locked`.
- no new IPC method may expose an unlock path.
- informational metadata must not change PAM's target user.

## TDD and regression coverage

Create a focused regression test before production implementation, for example `tests/test-quickshell-lockscreen-interactive-effects.sh`.

The focused test must cover at least:

- the real cursor remains `Qt.BlankCursor`;
- ghost cursor/trail state exists only as a lockscreen visual and has bounded fixed sample count;
- pointer displacement has explicit radius/displacement caps and a return-to-rest animation;
- pointer processing is throttled/bounded rather than scanning continuously while idle;
- audio-reactive default is enabled;
- time/date/username defaults are disabled;
- `lockscreen_animation == off` suppresses pointer and audio effects while leaving information preferences independent;
- application-state setters accept only valid boolean values and persist the intended JSON fields;
- the lock shell synchronously loads and distributes the new preferences;
- exactly one audio analyzer is owned by the lock root, not one per monitor;
- the audio helper exits safely when CAVA is missing;
- the dedicated CAVA config uses PipeWire output monitoring/raw output and a bounded low bar/frame count;
- authentication files are not given analyzer state or password-adjacent changes;
- Quick Settings places the controls directly under the existing Lockscreen Animation section.

Update `tests/test-quickshell-lockscreen-runtime-regressions.sh` intentionally. Its current assertions that reject time/date/username are historical guards for the current minimalist default; replace them with assertions that those elements are optional and default off rather than deleting the coverage entirely.

Update `tests/test-quickshell-lockscreen-animation-preference.sh` so the existing `off` preference is also verified as the master suppression state for interactive/audio animations.

Add a dedicated GitHub Actions validation workflow for the focused test, following the existing lockscreen validation style.

Because this changes managed Quickshell files, refresh `local/share/awtarchy/quickshell-managed-history.sha256` only after the final intended stock file contents are known, and include the resulting migration/updater validation in the final branch checks.

## Validation

Automated validation must include:

- syntax and ShellCheck for any changed/new shell helper;
- the new focused interactive-effects regression;
- existing lockscreen foundation, runtime-regression, animation-preference, and production-cutover tests;
- Quickshell production/lifecycle regressions affected by the changed files;
- updater/managed-history validation after final stock hashes are registered;
- `git diff --check` or equivalent diff hygiene;
- full GitHub CI before merge consideration.

Real Hyprland runtime validation remains mandatory for visual/interactive claims. The consolidated runtime test should cover:

- ghost head/trail appears on movement and disappears quickly after movement stops;
- no normal pointer becomes visible while idle or moving;
- slow edge brush versus fast center pass produces visibly different but bounded logo displacement;
- the logo returns exactly to rest after interaction;
- music/browser/game audio produces subtle real audio-reactive movement;
- silence returns the logo fully to rest;
- disabling Audio Reactive stops audio motion;
- selecting Lockscreen Animation Off suppresses formation, cursor effects, and audio effects;
- time/date/username each independently appear and disappear according to saved Quick Settings state;
- wrong-password retry and successful unlock remain unchanged;
- multi-monitor lock surfaces remain secure and do not duplicate the audio analyzer.

Static tests and CI can prove preference, parsing, lifecycle, and security contracts, but they cannot prove that the final motion is attractive or sufficiently subtle. Visual tuning remains runtime-evidence gated.

## Follow-up boundary: weather

Weather is a separate follow-up design, not an unfinished part of this implementation slice.

That later design must explicitly decide:

- weather provider/data source;
- user-entered location representation;
- cache lifetime and failure behavior;
- when network requests are permitted;
- how the UI communicates that enabling weather sends the configured location to an external service;
- how to guarantee that locking the screen never blocks on a fresh network request.

Until that design is approved, this branch must not introduce geolocation, IP-based location lookup, weather HTTP requests, API keys, or a Weather toggle that pretends to work without a defined data source.
