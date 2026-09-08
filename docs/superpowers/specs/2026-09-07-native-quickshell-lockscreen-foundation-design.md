# Native Quickshell Lockscreen Foundation Design

## Scope

This first implementation slice builds and proves Awtarchy's own native Quickshell session locker while leaving Hyprlock as the active production fallback until the new locker passes real Hyprland runtime validation.

This slice does not yet remove Hyprlock from the package catalog, delete `hyprlock.conf`, replace every lock entrypoint, or add qylock theme selection. Those are follow-up migration steps after the new locker itself is secure and stable.

## Goal

Create a dedicated Awtarchy Quickshell lock process that:

- uses the Wayland session-lock protocol through Quickshell `WlSessionLock`;
- authenticates the current user through Quickshell `PamContext`;
- covers every active monitor with a real lock surface;
- keeps authentication secrets in process memory only;
- has a minimal black Awtarchy visual design using the existing Fastfetch ASCII mark and Awtarchy theme colors;
- exposes a narrow launcher/manager interface for manual testing before production lock paths are switched;
- can later become the single lock authority for `SUPER + L`, Hypridle, Power Menu, suspend, and hibernate.

## Security model

The locker must be a real compositor session lock, not a fullscreen overlay.

`WlSessionLock.locked` is set true when the dedicated lock process starts. The lock is considered secure only when `WlSessionLock.secure` becomes true, meaning the compositor has confirmed all outputs are covered.

Unlock occurs only after PAM reports successful authentication. A successful PAM result sets `WlSessionLock.locked = false`; the process exits only after that unlock transition is requested. Failed or cancelled authentication must never change the session-lock state.

If the lock process crashes after the compositor has accepted the session lock, the compositor remains locked. The first slice should not silently unlock or fall back to an insecure overlay. Hyprland session-lock restoration support will be enabled only when the later production migration adds supervised crash recovery.

## Process isolation

The lock runs as a separate Quickshell configuration from Awtarchy's normal `awtarchy` shell.

Create:

- `config/quickshell/awtarchy-lock/shell.qml`: lock root, `WlSessionLock`, shared authentication state and lock IPC;
- `config/quickshell/awtarchy-lock/LockSurface.qml`: one visual/input surface instantiated for each locked output;
- `config/quickshell/awtarchy-lock/LockAuth.qml`: PAM conversation owner and password submission interface;
- `config/quickshell/awtarchy-lock/LockTheme.qml`: read-only bridge to Awtarchy theme colors plus safe fallbacks;
- `config/quickshell/awtarchy-lock/qmldir`: singleton/module declarations where required;
- `config/hypr/scripts/awtarchy_lock.sh`: authoritative launcher/status/test manager for the dedicated lock process.

The normal `config/quickshell/awtarchy/shell.qml` must not own the security lock. Restarting the desktop shell must not terminate the lock process.

## Lock manager interface

`config/hypr/scripts/awtarchy_lock.sh` is the only shell entrypoint introduced in this slice.

Supported commands:

- `lock`: start the dedicated lock configuration if not already running;
- `status`: report `unlocked`, `starting`, or `secure` based on the dedicated process and its IPC state;
- `wait-secure [timeout-seconds]`: wait until the lock IPC reports compositor-secure state, returning nonzero on timeout;
- `stop-test`: test-only/manual-development escape path that is permitted only when the compositor is not secure; it must refuse to terminate a secure lock process.

The manager must target only the dedicated Quickshell config name `awtarchy-lock` and must never broadly kill all Quickshell processes.

This first slice does not replace `loginctl lock-session`, Hypridle, `SUPER + L`, or Power Menu yet.

## Authentication

`LockAuth.qml` owns a single `PamContext` for the current user.

Requirements:

- leave `PamContext.user` unset so Quickshell authenticates the current user;
- use the standard PAM `login` configuration initially unless real Arch testing proves a dedicated Awtarchy PAM profile is required;
- store the pending password only in a QML property long enough to answer a PAM response request;
- clear the password property immediately after `pam.respond()`;
- never pass the password to a shell `Process`, environment variable, argument list, IPC call, file, log, notification or journal message;
- surface PAM informational/error text only as sanitized UI status text;
- failed authentication clears the password field, displays an error and returns focus to input;
- success emits one internal `authenticated()` signal to the lock root.

The implementation must not use qylock's SDDM compatibility shim. Awtarchy only needs current-session authentication, not SDDM user/session enumeration.

## Multi-monitor behavior

`WlSessionLock` creates one `WlSessionLockSurface` per screen. Every surface renders the same lock layout and shares the single authentication owner.

Each surface must:

- fill its assigned output;
- use an opaque black backing color;
- consume pointer/wheel input that is not handled by controls;
- scale its visual content from available surface width/height without fixed monitor assumptions;
- allow password focus on whichever monitor receives keyboard focus;
- reflect authentication status shared by the root.

No monitor may use an ordinary `PanelWindow`, `Window`, layer surface or fullscreen window as a substitute for the session-lock surface.

## Default visual design

The stock Awtarchy lockscreen is intentionally simple and terminal-like.

Default background: solid black.

Primary visual stack:

1. Existing Awtarchy ASCII mark from `config/fastfetch/ascii/awtarchy.txt` rendered in the configured Awtarchy foreground/accent treatment.
2. Large local time.
3. Small weekday/date line.
4. Current username.
5. Minimal password field using an underline/border treatment rather than a rounded card.
6. Small authentication status/error line.

No rounded container panels, glass cards, blur, screenshot background, weather request or network dependency.

The lock reads current Awtarchy colors from `~/.config/quickshell/awtarchy/theme.json` through `LockTheme.qml`, with hardcoded safe dark/foreground/error fallbacks if the file is missing or invalid.

The Fastfetch ASCII source must be read locally. It must not invoke `fastfetch` just to render the logo.

## Input behavior

- Password input receives initial focus when a surface becomes visible.
- Enter submits authentication when PAM is not already active.
- Escape clears current password/status input but never unlocks or closes the lock.
- Pointer clicks on the password area restore focus.
- Authentication cannot be submitted concurrently; additional Enter presses are ignored while PAM is active.
- Password text is masked unless PAM explicitly requests a visible response.

## Testability

The lock QML may support a non-locking preview/test mode only when an explicit environment variable such as `AWTARCHY_LOCK_PREVIEW=1` is set.

Preview mode exists only for static/QML UI validation and must not masquerade as a security test. Production `lock` mode must always use `WlSessionLock`.

The manager must refuse to call preview mode from its normal `lock` command.

## TDD coverage

Add `tests/test-quickshell-lockscreen-foundation.sh` before production implementation.

The regression should statically and behaviorally assert at least:

- the dedicated `awtarchy-lock` configuration exists separately from normal Awtarchy Quickshell;
- production lock QML imports `Quickshell.Wayland` and uses `WlSessionLock` plus `WlSessionLockSurface`;
- PAM uses `Quickshell.Services.Pam` and no password value is sent to shell commands, environment, argv, files or logs;
- the manager targets only the dedicated config name and has no `killall`, broad `pkill`, or generic Quickshell termination;
- `wait-secure` succeeds only when the lock IPC reports secure state;
- `stop-test` refuses when secure state is reported;
- the default design references the Awtarchy ASCII source and an opaque black fallback;
- existing Hyprlock production entrypoints remain unchanged during this foundation slice.

The test must fail before implementation and pass after the minimal implementation is added.

## Validation

Automated validation for this slice:

- `bash -n config/hypr/scripts/awtarchy_lock.sh`;
- `shellcheck config/hypr/scripts/awtarchy_lock.sh` when available;
- `bash tests/test-quickshell-lockscreen-foundation.sh`;
- relevant existing Quickshell production/lifecycle tests;
- `git diff --check`;
- full Awtarchy CI before merging any later production migration.

Real runtime validation is mandatory before this foundation may replace Hyprlock:

- manual lock and successful unlock;
- wrong password and retry;
- multiple monitors;
- differing monitor scale values;
- DPMS off/on while locked;
- suspend/resume while locked;
- confirmation that killing the locker after secure acquisition does not expose the desktop;
- confirmation that a TTY remains the recovery path during early testing.

Passing static tests does not prove the lock is production-ready.

## Migration boundary

During this foundation slice, Hyprlock remains installed and all existing production lock entrypoints remain on Hyprlock.

After real runtime validation succeeds, a separate migration plan will:

- enable Hyprland `misc.allow_session_lock_restore` and supervised lock recovery;
- redirect `SUPER + L`, Hypridle, Power Menu, `hypridle_action.sh`, protected-idle safety and lock-before-suspend/hibernate paths to the Awtarchy lock manager;
- require secure compositor confirmation before suspend/hibernate where Awtarchy initiates the transition;
- remove active Hyprlock permission/config/process references;
- remove Hyprlock from Awtarchy's package catalog only after ownership-safe package migration is designed and tested;
- retire the managed `hyprlock.conf` without deleting user-modified content;
- add Quick Settings lockscreen background/layout controls;
- investigate optional locally installed qylock layout compatibility without making qylock the security authority.

This separation keeps the first runtime test recoverable and prevents an unproven lock implementation from replacing the known-good Hyprlock path prematurely.
