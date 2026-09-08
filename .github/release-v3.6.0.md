# Awtarchy v3.6.0 Quickshell

Awtarchy v3.6.0 moves locking fully into Quickshell and adds new privacy and bar controls that were runtime-tested together before release. It also tightens workspace behavior and fixes a few desktop input/indicator regressions.

## Install and update

Fresh installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)

Existing Awtarchy installations and stable updates: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md)

Quick update:

```bash
awtarchy update
```

## Native Quickshell lockscreen

- Replaces Hyprlock with Awtarchy's native Quickshell `WlSessionLock` + PAM lockscreen.
- `SUPER+L`, Hypridle, and the Power Menu now use the same Awtarchy lock path.
- Multi-monitor locking, theme/cursor behavior, and lockscreen power actions are integrated into the Quickshell implementation.
- Existing Awtarchy installations migrate to the new lockscreen through the normal managed update path.

## Privacy and Quick Settings

- Screen Share Guard can now be controlled from Quick Settings per app/group without editing `hyprland.lua`.
- Capture allowances can be session-only or persisted by locking the current choice, and **Restore Awtarchy Defaults** returns the guard policy to stock behavior.
- Adds an Awtarchy Tips `?` shortcut to Quick Settings.
- Adds optional per-workspace bar hiding for workspaces 1-10 while preserving existing global, per-monitor, fullscreen, and idle visibility behavior.

## Desktop polish

- Regular workspace-switch animations are disabled by default while special-workspace and unrelated animations remain enabled.
- Brightness wheel input now responds on the first valid scroll step instead of waiting through the previous brightness-only delay.
- Empty workspace placeholders disappear after focus moves away instead of leaving phantom workspace indicators.

## Release and documentation maintenance

- `INSTALL.md` and `UPDATING.md` are now the canonical installation and update guides linked by stable releases.
- Stable release notes now pass a permanent structure validator before and after publication.

## Known issue

- Bluetooth suspend/resume issue #146 remains evidence-gated and unresolved. v3.6.0 does not claim to fix that intermittent behavior; the diagnostic capture remains available for the next real reproduction.

## Validation

- Exact release target: `271595d1e78d1cd48f68795e6c1f3fcc060c4471`.
- The native lockscreen, Screen Share Guard, Quick Settings Tips shortcut, per-workspace bar visibility, brightness-wheel fix, and workspace-indicator fix were runtime-tested before merge.
- All merged-main push workflows returned for the exact release target completed successfully, including the full `Validate Awtarchy` integration suite and focused lockscreen, Screen Share Guard, workspace, and runtime checks.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.6.0._
